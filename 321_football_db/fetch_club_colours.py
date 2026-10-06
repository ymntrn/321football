"""
Two colours per club for the in-app crest, read from each club's English
Wikipedia infobox home kit (body1, shorts1, leftarm1, socks1, pattern_b1).

    python fetch_club_colours.py      # writes club_colours_wiki.json

Wikidata's "official colour" (P6364) was tried first and rejected: only 288
of 748 playable clubs have it, as crude named colours (pure #FF0000 "red",
Juventus white-black-PINK, Bayern missing). The infobox kit is where football
sites take club colours from, and it carries real hex values.

Rule: colour A is the home shirt; colour B is the first of shorts, sleeves,
socks or the shirt's stripe/hoop colour that is clearly different from A.
curate.py applies club_colours_curated.json on top (hand pairs for the
best-known clubs) and writes the result to clubs.color_a / clubs.color_b.

Network: Wikidata SPARQL (titles) + the en.wikipedia API, 50 pages a request.
"""
from __future__ import annotations

import json
import os
import re
import sys
import time
import urllib.parse
import urllib.request

import config
import db
import wikidata_client as wd

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "club_colours_wiki.json")

NAMED = {  # colour words seen in kit pattern names and occasional plain values
    "white": "FFFFFF", "black": "000000", "red": "D71920", "blue": "1C4FA0",
    "navy": "0B1F4B", "sky": "6CABDD", "skyblue": "6CABDD", "lightblue": "6CABDD",
    "green": "1B7A3E", "yellow": "FFD200", "gold": "D4A017", "orange": "F07D00",
    "claret": "7A263A", "maroon": "7A1F2B", "purple": "5B2C83", "violet": "5B2C83",
    "grey": "8A8D8F", "gray": "8A8D8F", "pink": "F4A6C1", "amber": "FFBF00",
}
KIT_KEYS = ("body1", "shorts1", "leftarm1", "rightarm1", "socks1", "pattern_b1")


def titles(conn) -> dict[str, str]:
    qids = [r["wikidata_qid"] for r in conn.execute(
        "SELECT wikidata_qid FROM clubs WHERE is_reserve_or_b_team = 0")]

    def q(chunk):
        vals = " ".join("wd:" + x for x in chunk)
        return f"""SELECT ?club ?title WHERE {{
          VALUES ?club {{ {vals} }}
          ?a schema:about ?club ; schema:isPartOf <https://en.wikipedia.org/> ;
             schema:name ?title . }}"""
    out = {}
    for r in wd.run_chunked(qids, q, chunk_size=200, label="titles"):
        out[wd.qid_from_uri(wd.value(r, "club"))] = wd.value(r, "title")
    return out


def wikitext(batch: list[str]) -> dict[str, str]:
    params = {"action": "query", "prop": "revisions", "rvprop": "content",
              "rvslots": "main", "redirects": "1", "format": "json",
              "formatversion": "2", "titles": "|".join(batch)}
    url = "https://en.wikipedia.org/w/api.php?" + urllib.parse.urlencode(params)
    req = urllib.request.Request(url, headers={"User-Agent": config.USER_AGENT})
    for attempt in range(4):
        try:
            with urllib.request.urlopen(req, timeout=60) as r:
                data = json.load(r)
            break
        except Exception as e:  # noqa: BLE001 - retry anything transient
            if attempt == 3:
                raise
            time.sleep(5 * (attempt + 1))
    redirect = {x["from"]: x["to"] for x in data["query"].get("redirects", [])}
    normal = {x["from"]: x["to"] for x in data["query"].get("normalized", [])}
    pages = {}
    for p in data["query"]["pages"]:
        revs = p.get("revisions")
        if revs:
            pages[p["title"]] = revs[0]["slots"]["main"]["content"]
    out = {}
    for t in batch:
        final = redirect.get(normal.get(t, t), normal.get(t, t))
        if final in pages:
            out[t] = pages[final]
    return out


def hexval(v: str | None) -> str | None:
    if not v:
        return None
    v = re.sub(r"<!--.*?-->", "", v).strip().lstrip("#").strip()
    if re.fullmatch(r"[0-9A-Fa-f]{6}", v):
        return v.upper()
    if re.fullmatch(r"[0-9A-Fa-f]{3}", v):
        return "".join(ch * 2 for ch in v).upper()
    return NAMED.get(v.lower().replace(" ", ""))


def pattern_colour(p: str | None) -> str | None:
    if not p:
        return None
    p = p.lower()
    for word in sorted(NAMED, key=len, reverse=True):
        if word in p:
            return NAMED[word]
    return None


def dist(a: str, b: str) -> float:
    ra, ga, ba = (int(a[i:i + 2], 16) for i in (0, 2, 4))
    rb, gb, bb = (int(b[i:i + 2], 16) for i in (0, 2, 4))
    return ((ra - rb) ** 2 + (ga - gb) ** 2 + (ba - bb) ** 2) ** 0.5


def kit(text: str) -> dict[str, str]:
    found = {}
    for key in KIT_KEYS:
        m = re.search(r"\|\s*" + key + r"\s*=\s*([^|\n}]*)", text)
        if m:
            found[key] = m.group(1).strip()
    return found


def pick(k: dict[str, str]) -> tuple[str, str] | None:
    a = hexval(k.get("body1"))
    if not a:
        return None
    for cand in (pattern_colour(k.get("pattern_b1")), hexval(k.get("shorts1")),
                 hexval(k.get("leftarm1")), hexval(k.get("rightarm1")),
                 hexval(k.get("socks1"))):
        if cand and dist(a, cand) > 90:
            return a, cand
    # A one-colour kit: pair it with white, or with black when it is light.
    light = sum(int(a[i:i + 2], 16) for i in (0, 2, 4)) > 600
    return a, ("0B1F4B" if light else "FFFFFF")


def main() -> int:
    conn = db.connect()
    t = titles(conn)
    print(f"  {len(t)} clubs have an English Wikipedia page")
    qid_by_title = {v: k for k, v in t.items()}
    names = list(qid_by_title)
    result, no_kit = {}, []
    for i in range(0, len(names), 50):
        batch = names[i:i + 50]
        texts = wikitext(batch)
        for title in batch:
            qid = qid_by_title[title]
            k = kit(texts.get(title, ""))
            p = pick(k)
            if p:
                result[qid] = {"a": p[0], "b": p[1], "title": title}
            else:
                no_kit.append(title)
        time.sleep(1)
        print(f"    {min(i + 50, len(names))}/{len(names)}", flush=True)
    with open(OUT, "w", encoding="utf-8") as f:
        json.dump(result, f, ensure_ascii=False, indent=1, sort_keys=True)
    print(f"  colours for {len(result)} clubs -> {OUT}")
    print(f"  no usable kit in {len(no_kit)} pages, e.g. {no_kit[:8]}")
    conn.close()
    return 0


if __name__ == "__main__":
    sys.exit(main())
