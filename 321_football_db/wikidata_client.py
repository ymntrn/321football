"""
A well-behaved Wikidata client.

Handles the things that will otherwise ruin a long scrape:
  - retries with exponential backoff on 429 / 5xx / timeouts
  - on-disk response caching so a crash doesn't cost you completed queries
  - automatic chunk-halving when a query is too big and times out
  - a real User-Agent (WDQS blocks anonymous clients)
  - polite pacing between requests
"""

from __future__ import annotations

import hashlib
import json
import os
import time
from typing import Any, Callable, Iterable

import requests

import config


class WikidataError(RuntimeError):
    pass


class QueryTooBig(WikidataError):
    """Raised when a query times out in a way that suggests it asked for too much."""


def _cache_path(query: str) -> str:
    digest = hashlib.sha256(query.encode("utf-8")).hexdigest()[:32]
    return os.path.join(config.CACHE_DIR, f"{digest}.json")


def _read_cache(query: str) -> list[dict] | None:
    if not config.ENABLE_SPARQL_CACHE:
        return None
    path = _cache_path(query)
    if not os.path.exists(path):
        return None
    age_days = (time.time() - os.path.getmtime(path)) / 86400
    if age_days > config.CACHE_TTL_DAYS:
        return None
    try:
        with open(path, "r", encoding="utf-8") as fh:
            return json.load(fh)
    except (json.JSONDecodeError, OSError):
        return None


def _write_cache(query: str, rows: list[dict]) -> None:
    if not config.ENABLE_SPARQL_CACHE:
        return
    os.makedirs(config.CACHE_DIR, exist_ok=True)
    try:
        with open(_cache_path(query), "w", encoding="utf-8") as fh:
            json.dump(rows, fh)
    except OSError:
        pass  # caching is an optimization, never a hard failure


_last_request_at = 0.0


def _pace() -> None:
    """Keep a minimum gap between requests so we stay a good WDQS citizen."""
    global _last_request_at
    elapsed = time.time() - _last_request_at
    wait = config.PAUSE_BETWEEN_QUERIES_SECONDS - elapsed
    if wait > 0:
        time.sleep(wait)
    _last_request_at = time.time()


def run_sparql(query: str, *, use_cache: bool = True) -> list[dict]:
    """
    Execute a SPARQL query, returning the raw `results.bindings` list.

    Raises QueryTooBig if the query times out — callers that build queries
    from a chunk of items should catch this and retry with a smaller chunk.
    """
    if use_cache:
        cached = _read_cache(query)
        if cached is not None:
            return cached

    headers = {
        "User-Agent": config.USER_AGENT,
        "Accept": "application/sparql-results+json",
    }

    last_error: Exception | None = None
    for attempt in range(config.MAX_RETRIES):
        _pace()
        try:
            response = requests.get(
                config.WIKIDATA_SPARQL_ENDPOINT,
                params={"query": query, "format": "json"},
                headers=headers,
                timeout=config.REQUEST_TIMEOUT_SECONDS,
            )
        except requests.exceptions.Timeout as exc:
            last_error = exc
            raise QueryTooBig("SPARQL request timed out client-side") from exc
        except requests.exceptions.RequestException as exc:
            last_error = exc
            backoff = config.RETRY_BACKOFF_BASE_SECONDS * (2 ** attempt)
            print(f"    network error ({exc.__class__.__name__}), retrying in {backoff}s...")
            time.sleep(backoff)
            continue

        if response.status_code == 200:
            try:
                rows = response.json()["results"]["bindings"]
            except (ValueError, KeyError) as exc:
                # A 200 whose body doesn't parse almost always means the
                # response was CUT OFF mid-transfer — WDQS starts streaming a
                # big result, then the connection dies part-way and we're left
                # holding half a JSON document ending inside a string.
                #
                # This is transient, so it must be retried rather than treated
                # as fatal: killing an hour-long scrape because one transfer
                # got clipped is indefensible. If it keeps happening for the
                # same query, the result is simply too large to move reliably,
                # so we escalate to QueryTooBig and let the caller halve the
                # chunk — which is the actual fix, not more retrying.
                size_kb = len(response.content) / 1024
                if attempt < config.MAX_RETRIES - 1:
                    backoff = config.RETRY_BACKOFF_BASE_SECONDS * (2 ** attempt)
                    print(f"    truncated response ({size_kb:.0f} KB, cut mid-JSON), "
                          f"retrying in {backoff}s...")
                    time.sleep(backoff)
                    continue
                raise QueryTooBig(
                    f"response kept arriving truncated at ~{size_kb:.0f} KB — "
                    f"asking for too much at once"
                ) from exc

            if use_cache:
                _write_cache(query, rows)
            return rows

        # WDQS signals "your query was too expensive" with a 500 carrying a
        # TimeoutException in the body, or occasionally a 503.
        body = response.text[:500]
        if response.status_code in (500, 503) and "imeout" in body:
            raise QueryTooBig(f"WDQS query timeout: {body[:200]}")

        if response.status_code == 429:
            retry_after = int(response.headers.get("Retry-After", 60))
            print(f"    rate limited by WDQS, sleeping {retry_after}s...")
            time.sleep(retry_after)
            continue

        if 500 <= response.status_code < 600:
            backoff = config.RETRY_BACKOFF_BASE_SECONDS * (2 ** attempt)
            print(f"    WDQS {response.status_code}, retrying in {backoff}s...")
            time.sleep(backoff)
            last_error = WikidataError(f"HTTP {response.status_code}: {body}")
            continue

        raise WikidataError(f"HTTP {response.status_code} from WDQS: {body}")

    raise WikidataError(f"Gave up after {config.MAX_RETRIES} attempts: {last_error}")


def run_chunked(
    items: list[str],
    query_builder: Callable[[list[str]], str],
    *,
    chunk_size: int | None = None,
    label: str = "chunk",
) -> list[dict]:
    """
    Run one query per chunk of `items`, halving the chunk and retrying
    whenever WDQS says the query was too expensive.

    `query_builder` receives a list of items and must return a SPARQL string.
    Returns the concatenated bindings from every chunk.
    """
    chunk_size = chunk_size or config.CLUB_CHUNK_SIZE
    all_rows: list[dict] = []
    queue: list[list[str]] = [
        items[i:i + chunk_size] for i in range(0, len(items), chunk_size)
    ]

    while queue:
        chunk = queue.pop(0)
        try:
            all_rows.extend(run_sparql(query_builder(chunk)))
        except QueryTooBig:
            if len(chunk) == 1:
                # A single item that can't be queried is a real problem, but
                # it shouldn't sink the whole run — skip it loudly.
                print(f"    !! {label} {chunk[0]} times out even alone — skipping it")
                continue
            mid = len(chunk) // 2
            print(f"    {label} of {len(chunk)} too big, splitting into {mid} + {len(chunk) - mid}")
            queue.insert(0, chunk[mid:])
            queue.insert(0, chunk[:mid])

    return all_rows


def search_entities(search_term: str, *, limit: int = 10) -> list[dict]:
    """
    Wikidata's wbsearchentities API — used to resolve a league name to
    candidate QIDs before we verify them structurally.
    """
    headers = {"User-Agent": config.USER_AGENT}
    params = {
        "action": "wbsearchentities",
        "search": search_term,
        "language": "en",
        "uselang": "en",
        "type": "item",
        "limit": limit,
        "format": "json",
    }
    _pace()
    response = requests.get(
        config.WIKIDATA_API_ENDPOINT,
        params=params,
        headers=headers,
        timeout=config.REQUEST_TIMEOUT_SECONDS,
    )
    response.raise_for_status()
    return response.json().get("search", [])


def _fetch_labels_batch(qids: list[str],
                        api_languages: tuple[str, ...] | None
                        ) -> tuple[dict[str, dict[str, str]], str | None]:
    """
    One wbgetentities call. Returns (labels_by_qid, error_message).

    KEEP `api_languages` SHORT — a handful at most, and always include the one
    you actually want first.

    Both extremes bite. Asking for twenty languages at once made MediaWiki
    reject the whole request with HTTP 200 and the error in the body, so it
    looked like "no labels exist". Asking for ALL languages instead returns a
    200 with an INCOMPLETE label set — no error, no warning, just a subset. On
    a 50-entity request that subset dropped David Beckham's English, Spanish,
    German and French labels and left Azerbaijani, so he ended up named
    "Devid Bekhem".

    Small explicit requests are the only shape that behaves predictably, which
    is why callers ask in tiers rather than all at once.
    """
    headers = {"User-Agent": config.USER_AGENT}
    params = {
        "action": "wbgetentities",
        "ids": "|".join(qids),
        "props": "labels",
        "format": "json",
        "formatversion": "2",
    }
    if api_languages:
        params["languages"] = "|".join(api_languages)

    last_error = "unknown error"
    for attempt in range(config.MAX_RETRIES):
        _pace()
        try:
            response = requests.get(
                config.WIKIDATA_API_ENDPOINT, params=params,
                headers=headers, timeout=config.REQUEST_TIMEOUT_SECONDS,
            )
            response.raise_for_status()
            payload = response.json()
        except (requests.exceptions.RequestException, ValueError) as exc:
            last_error = f"{exc.__class__.__name__}: {exc}"
            if attempt == config.MAX_RETRIES - 1:
                return {}, last_error
            time.sleep(config.RETRY_BACKOFF_BASE_SECONDS * (2 ** attempt))
            continue

        # MediaWiki reports its own errors inside a 200 response.
        if isinstance(payload, dict) and "error" in payload:
            error = payload["error"]
            return {}, error.get("info") or error.get("code") or str(error)

        out: dict[str, dict[str, str]] = {}
        for qid, entity in (payload.get("entities") or {}).items():
            if entity.get("missing") is not None:
                continue
            labels = entity.get("labels") or {}
            collected = {}
            for lang, node in labels.items():
                # formatversion=2 gives {"en": {"language": ..., "value": ...}}
                value_text = node.get("value") if isinstance(node, dict) else node
                if value_text:
                    collected[lang] = value_text
            if collected:
                out[qid] = collected
        return out, None

    return {}, last_error


def get_entity_labels(qids: list[str],
                      languages: tuple[str, ...] | None = None) -> dict[str, dict[str, str]]:
    """
    Fetch labels for a list of entities via the wbgetentities API.

    `languages` is sent TO the API and should be short — see
    _fetch_labels_batch for why. Pass None only when you genuinely want
    whatever comes back and can cope with it being partial.

    A failing batch is split in half and retried rather than abandoned, so one
    bad or deleted id cannot take 49 good lookups down with it.

    Returns {qid: {lang: label}}.
    """
    results: dict[str, dict[str, str]] = {}
    queue: list[list[str]] = [qids[i:i + 50] for i in range(0, len(qids), 50)]
    skipped = 0

    while queue:
        chunk = queue.pop(0)
        labels, error = _fetch_labels_batch(chunk, languages)

        if error:
            if len(chunk) == 1:
                skipped += 1
                if skipped <= 5:
                    print(f"    skipping {chunk[0]}: {error}")
                continue
            middle = len(chunk) // 2
            queue.insert(0, chunk[middle:])
            queue.insert(0, chunk[:middle])
            continue

        results.update(labels)

    if skipped > 5:
        print(f"    ...and {skipped - 5} more entities skipped")

    return results


def qid_from_uri(uri: str) -> str:
    """http://www.wikidata.org/entity/Q8682 -> Q8682"""
    return uri.rsplit("/", 1)[-1]


def value(row: dict, key: str) -> str | None:
    """Safely pull a binding value out of a SPARQL result row."""
    node = row.get(key)
    return node.get("value") if node else None


def year_from_iso(iso: str | None) -> int | None:
    """
    Wikidata dates look like '1998-07-01T00:00:00Z', sometimes with a
    leading '-' for BCE or reduced precision like '1998-00-00T00:00:00Z'.
    """
    if not iso:
        return None
    text = iso.lstrip("+")
    if text.startswith("-"):
        return None  # BCE dates are not football transfers
    try:
        return int(text[:4])
    except ValueError:
        return None
