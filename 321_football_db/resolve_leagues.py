"""
STEP 0 — resolve every league in leagues.py to a verified Wikidata QID.

Run this FIRST and read its output. It's the cheapest possible place to catch
a mistake: if a league resolves to the wrong competition here, you lose ten
seconds. If it resolves wrong and you don't notice, you lose an hour of
scraping and end up with a database full of the wrong clubs.

For each league it:
  1. searches Wikidata for the name (and each alias) via wbsearchentities
  2. verifies each candidate is actually a football league/competition
  3. verifies the candidate's country (P17) matches the expected country
  4. picks the best surviving candidate and reports how confident it is

Output: leagues_resolved.json + a table printed for you to eyeball.
Anything marked NEEDS REVIEW should be checked by hand on wikidata.org
before you run the scrape.
"""

from __future__ import annotations

import json
import sys

import config
import db
from leagues import LEAGUES, League
from wikidata_client import run_sparql, search_entities, qid_from_uri, value

VERIFY_CANDIDATE_QUERY = """
SELECT ?item ?itemLabel ?countryLabel ?country ?typeLabel ?type ?inception WHERE {{
  VALUES ?item {{ {items} }}
  OPTIONAL {{ ?item wdt:P17 ?country. }}
  OPTIONAL {{ ?item wdt:P31 ?type. }}
  OPTIONAL {{ ?item wdt:P571 ?inception. }}
  SERVICE wikibase:label {{ bd:serviceParam wikibase:language "en". }}
}}
"""

# The decisive test. A real league owns SEASON items ("2015-16 Premier
# League"), each linked back to it with P3450. A generic concept like
# "championship", a league's governing body, or a recently-created duplicate
# stub owns none.
#
# This matters more than any other signal because it is exactly what step 1
# depends on: we discover clubs by walking a league's seasons. A candidate
# with zero seasons will produce zero clubs no matter how good its label
# looks, so counting them here predicts whether the scrape will work at all.
SEASON_COUNT_QUERY = """
SELECT ?item (COUNT(DISTINCT ?season) AS ?seasons)
             (MIN(?year) AS ?firstYear) (MAX(?year) AS ?lastYear) WHERE {{
  VALUES ?item {{ {items} }}
  ?season wdt:P3450 ?item .
  OPTIONAL {{ ?season wdt:P580 ?start . }}
  BIND(YEAR(?start) AS ?year)
}}
GROUP BY ?item
"""


def fetch_season_counts(qids: list[str]) -> dict[str, dict]:
    """How many seasons does each candidate own, and over what span?"""
    if not qids:
        return {}
    items = " ".join(f"wd:{q}" for q in qids)
    try:
        rows = run_sparql(SEASON_COUNT_QUERY.format(items=items))
    except Exception as exc:  # noqa: BLE001 — best-effort signal
        print(f"    (season-count check failed: {exc.__class__.__name__})")
        return {}

    counts: dict[str, dict] = {}
    for row in rows:
        qid = qid_from_uri(value(row, "item"))
        try:
            seasons = int(value(row, "seasons") or 0)
        except ValueError:
            seasons = 0
        counts[qid] = {
            "seasons": seasons,
            "first_year": value(row, "firstYear"),
            "last_year": value(row, "lastYear"),
        }
    return counts


def fetch_candidate_details(qids: list[str]) -> dict[str, dict]:
    """Pull country + type for a batch of candidate QIDs in one query."""
    if not qids:
        return {}
    items = " ".join(f"wd:{q}" for q in qids)
    rows = run_sparql(VERIFY_CANDIDATE_QUERY.format(items=items))

    details: dict[str, dict] = {}
    for row in rows:
        qid = qid_from_uri(value(row, "item"))
        entry = details.setdefault(qid, {
            "qid": qid,
            "label": value(row, "itemLabel"),
            "countries": set(),
            "country_qids": set(),
            "types": set(),
            "type_qids": set(),
        })
        if value(row, "countryLabel"):
            entry["countries"].add(value(row, "countryLabel"))
        if value(row, "country"):
            entry["country_qids"].add(qid_from_uri(value(row, "country")))
        if value(row, "typeLabel"):
            entry["types"].add(value(row, "typeLabel"))
        if value(row, "type"):
            entry["type_qids"].add(qid_from_uri(value(row, "type")))
    return details


def score_candidate(league: League, detail: dict, seasons: dict | None = None) -> tuple[int, list[str]]:
    """
    Score how well a candidate matches the league we're looking for.
    Higher is better. Reasons are returned so the printed report explains
    itself rather than being a black box.
    """
    score = 0
    reasons: list[str] = []

    # Season ownership is the dominant signal — see SEASON_COUNT_QUERY.
    # Most league items turn out to have no P17 country at all, which is why
    # country alone was never enough to disambiguate reliably.
    season_count = (seasons or {}).get("seasons", 0)
    if season_count >= 15:
        score += 80
        reasons.append(f"owns {season_count} seasons")
    elif season_count >= 5:
        score += 45
        reasons.append(f"owns {season_count} seasons")
    elif season_count >= 1:
        score += 10
        reasons.append(f"owns only {season_count} season(s)")
    else:
        score -= 70
        reasons.append("owns NO seasons — cannot yield clubs")

    # Country match, when the item actually has one.
    if league.country_qid in detail["country_qids"]:
        score += 50
        reasons.append("country matches")
    elif detail["country_qids"]:
        score -= 40
        reasons.append(f"country MISMATCH ({', '.join(sorted(detail['countries']))})")
    else:
        reasons.append("no country on item")

    label = (detail["label"] or "").lower()
    wanted = {league.name.lower(), *(a.lower() for a in league.aliases)}
    if label in wanted:
        score += 30
        reasons.append("exact label match")
    elif any(w in label or label in w for w in wanted):
        score += 15
        reasons.append("partial label match")

    type_text = " ".join(detail["types"]).lower()
    if "league" in type_text or "competition" in type_text or "division" in type_text:
        score += 20
        reasons.append("typed as a league/competition")

    # Season items ("2015-16 Premier League") are a common false positive.
    if "season" in type_text or "season" in label:
        score -= 60
        reasons.append("looks like a single season, not the league")

    # So are national teams and clubs.
    if "club" in type_text or "national team" in type_text:
        score -= 60
        reasons.append("looks like a team, not a league")

    return score, reasons


def resolve_one(league: League) -> dict:
    search_terms = [league.name] + league.aliases
    candidate_qids: list[str] = []

    if league.qid_hint:
        candidate_qids.append(league.qid_hint)

    for term in search_terms:
        try:
            for hit in search_entities(term, limit=8):
                if hit["id"] not in candidate_qids:
                    candidate_qids.append(hit["id"])
        except Exception as exc:  # noqa: BLE001 - report and continue
            print(f"    search failed for {term!r}: {exc}")

    if not candidate_qids:
        return {"key": league.key, "status": "unresolved", "qid": None,
                "label": None, "reasons": ["no candidates returned by search"]}

    details = fetch_candidate_details(candidate_qids[:25])
    season_counts = fetch_season_counts(list(details))

    scored = []
    for qid, detail in details.items():
        score, reasons = score_candidate(league, detail, season_counts.get(qid))
        scored.append((score, qid, detail, reasons))
    scored.sort(key=lambda item: item[0], reverse=True)

    if not scored:
        return {"key": league.key, "status": "unresolved", "qid": None,
                "label": None, "reasons": ["no candidate details returned"]}

    best_score, best_qid, best_detail, best_reasons = scored[0]
    runner_up = scored[1][0] if len(scored) > 1 else -999

    # An explicit qid_hint is a HUMAN ASSERTION and outranks anything the
    # search turned up — a hand-verified Q-number should never be silently
    # overridden by whatever wbsearchentities happened to rank first. We still
    # sanity-check it: a hint that owns no seasons is broken and gets rejected
    # loudly rather than quietly trusted.
    if league.qid_hint:
        hint_detail = details.get(league.qid_hint)
        hint_seasons = season_counts.get(league.qid_hint, {}).get("seasons", 0)

        if hint_detail is None:
            best_reasons.append(
                f"your hint {league.qid_hint} could not be looked up — using search result instead")
            status = "needs_review"
        elif hint_seasons == 0:
            best_reasons.append(
                f"your hint {league.qid_hint} owns no seasons — it will yield no clubs")
            status = "needs_review"
        else:
            span = season_counts.get(league.qid_hint, {})
            first, last = span.get("first_year"), span.get("last_year")
            span_text = f", {first}-{last}" if first and last else ""
            return {
                "key": league.key, "name": league.name, "country": league.country,
                "tier": league.tier, "region": league.region,
                "country_qid": league.country_qid,
                "qid": league.qid_hint,
                "label": hint_detail["label"],
                "resolved_country": sorted(hint_detail["countries"]),
                "seasons": hint_seasons,
                "score": None, "runner_up_score": None,
                "status": "verified_hint",
                "reasons": [f"pinned by hand, confirmed: owns {hint_seasons} seasons{span_text}"],
            }
    else:
        # Confidence comes mostly from owning a healthy run of seasons.
        if best_score >= 100 and (best_score - runner_up) >= 20:
            status = "confident"
        elif best_score >= 60:
            status = "probable"
        else:
            status = "needs_review"

    return {
        "key": league.key,
        "name": league.name,
        "country": league.country,
        "tier": league.tier,
        "region": league.region,
        "country_qid": league.country_qid,
        "qid": best_qid,
        "label": best_detail["label"],
        "resolved_country": sorted(best_detail["countries"]),
        "seasons": season_counts.get(best_qid, {}).get("seasons", 0),
        "score": best_score,
        "runner_up_score": runner_up,
        "status": status,
        "reasons": best_reasons,
    }


def main() -> int:
    print(f"Resolving {len(LEAGUES)} leagues against Wikidata...\n")
    resolved = []
    for league in LEAGUES:
        print(f"  {league.name} ({league.country})...", flush=True)
        try:
            result = resolve_one(league)
        except Exception as exc:  # noqa: BLE001
            result = {"key": league.key, "name": league.name, "status": "error",
                      "qid": None, "reasons": [str(exc)]}
        resolved.append(result)

    with open(config.RESOLVED_LEAGUES_PATH, "w", encoding="utf-8") as fh:
        json.dump(resolved, fh, indent=2, ensure_ascii=False)

    # ---- report -----------------------------------------------------------
    print("\n" + "=" * 92)
    print(f"{'LEAGUE':<32} {'QID':<11} {'STATUS':<14} {'SEASONS':>8}  RESOLVED LABEL")
    print("=" * 92)
    problems = 0
    for entry in resolved:
        status = entry["status"]
        marker = {"verified_hint": "ok", "confident": "ok", "probable": "~",
                  "needs_review": "!!", "unresolved": "XX", "error": "XX"}.get(status, "?")
        if status not in ("verified_hint", "confident", "probable"):
            problems += 1
        seasons = entry.get("seasons")
        seasons_text = str(seasons) if seasons is not None else "-"
        print(f"{marker:<3}{entry.get('name', entry['key']):<29} {str(entry.get('qid')):<11} "
              f"{status:<14} {seasons_text:>8}  {entry.get('label')}")

    print("=" * 92)

    # A league that resolved cleanly but owns no seasons will silently produce
    # zero clubs in step 1, so surface it here rather than letting it look fine.
    barren = [e for e in resolved
              if e.get("qid") and not e.get("seasons")
              and e["status"] in ("verified_hint", "confident", "probable")]
    if barren:
        print(f"\n{len(barren)} league(s) resolved but own NO season items, so step 1")
        print("will find no clubs for them:")
        for entry in barren:
            print(f"   - {entry.get('name')} ({entry.get('qid')})")
    print(f"\nWrote {config.RESOLVED_LEAGUES_PATH}")

    if problems:
        print(f"\n{problems} league(s) need a human look before scraping.")
        print("Open each one's QID on wikidata.org and confirm it's the competition")
        print("you meant. If it's wrong, set `qid_hint` for that league in leagues.py")
        print("and re-run this script.")
    else:
        print("\nAll leagues resolved cleanly. Safe to continue to step 1.")

    for entry in resolved:
        if entry["status"] in ("needs_review", "unresolved", "error"):
            print(f"\n  {entry.get('name')}: {'; '.join(entry.get('reasons', []))}")

    # ---- persist the good ones -------------------------------------------
    conn = db.connect()
    db.init_schema(conn)
    saved = 0
    for entry in resolved:
        if entry["status"] in ("verified_hint", "confident", "probable") and entry.get("qid"):
            db.upsert_league(
                conn, key=entry["key"], qid=entry["qid"], name=entry["name"],
                country=entry["country"], country_qid=entry.get("country_qid"),
                tier=entry["tier"], region=entry.get("region"),
            )
            saved += 1
    conn.commit()
    conn.close()
    print(f"\n{saved} leagues written to the database.")

    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())
