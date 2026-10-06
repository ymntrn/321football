"""
Ask Wikidata directly about one entity, to find out why the scraper missed it.

    python debug_wikidata.py Q10520          # David Beckham
    python debug_wikidata.py Q10520 Q18656   # ...and check a specific club link

This bypasses the database entirely and queries the live endpoint, which is the
only way to distinguish "Wikidata doesn't have this" from "our query fails to
see what Wikidata has".
"""

from __future__ import annotations

import sys

from wikidata_client import run_sparql, qid_from_uri, value

LABELS_QUERY = """
SELECT ?label WHERE {{
  wd:{qid} rdfs:label ?label .
}}
"""

TYPES_QUERY = """
SELECT ?type ?typeLabel ?rank WHERE {{
  wd:{qid} p:P31 ?statement .
  ?statement ps:P31 ?type .
  ?statement wikibase:rank ?rank .
  SERVICE wikibase:label {{ bd:serviceParam wikibase:language "en". }}
}}
"""

TRUTHY_TYPE_QUERY = """
SELECT ?type ?typeLabel WHERE {{
  wd:{qid} wdt:P31 ?type .
  SERVICE wikibase:label {{ bd:serviceParam wikibase:language "en". }}
}}
"""

TEAMS_QUERY = """
SELECT ?club ?clubLabel ?start ?end ?rank WHERE {{
  wd:{qid} p:P54 ?statement .
  ?statement ps:P54 ?club .
  ?statement wikibase:rank ?rank .
  OPTIONAL {{ ?statement pq:P580 ?start. }}
  OPTIONAL {{ ?statement pq:P582 ?end. }}
  SERVICE wikibase:label {{ bd:serviceParam wikibase:language "en". }}
}}
"""

# The scraper's own query, run for this one player, so we can see whether the
# filter is what excludes him.
SCRAPER_QUERY = """
SELECT ?club ?playerLabel WHERE {{
  VALUES ?club {{ {clubs} }}
  wd:{qid} wdt:P31 wd:Q5 .
  wd:{qid} p:P54 ?statement .
  ?statement ps:P54 ?club .
  BIND(wd:{qid} AS ?player)
  SERVICE wikibase:label {{ bd:serviceParam wikibase:language "en". }}
}}
"""

SCRAPER_QUERY_NO_HUMAN_FILTER = """
SELECT ?club ?clubLabel WHERE {{
  VALUES ?club {{ {clubs} }}
  wd:{qid} p:P54 ?statement .
  ?statement ps:P54 ?club .
  SERVICE wikibase:label {{ bd:serviceParam wikibase:language "en". }}
}}
"""


def main() -> int:
    if len(sys.argv) < 2:
        print(__doc__)
        return 1

    qid = sys.argv[1]
    extra_clubs = sys.argv[2:]

    print("=" * 70)
    print(f"WIKIDATA REPORT FOR {qid}")
    print("=" * 70)

    labels = run_sparql(LABELS_QUERY.format(qid=qid), use_cache=False)
    print(f"\nLABELS ({len(labels)} languages)")
    for row in labels[:8]:
        node = row.get("label", {})
        print(f"   {node.get('xml:lang', '?'):<5} {node.get('value')}")
    if not labels:
        print("   NONE — this entity has no label in any language.")

    print("\nP31 'instance of' — ALL statements, with rank")
    types = run_sparql(TYPES_QUERY.format(qid=qid), use_cache=False)
    for row in types:
        rank = (value(row, "rank") or "").rsplit("#", 1)[-1]
        print(f"   {rank:<18} {value(row, 'typeLabel')} ({qid_from_uri(value(row, 'type'))})")
    if not types:
        print("   NONE")

    print("\nP31 as the scraper sees it (wdt: = best rank only)")
    truthy = run_sparql(TRUTHY_TYPE_QUERY.format(qid=qid), use_cache=False)
    for row in truthy:
        print(f"   {value(row, 'typeLabel')} ({qid_from_uri(value(row, 'type'))})")
    is_human_truthy = any(qid_from_uri(value(r, "type")) == "Q5" for r in truthy)
    print(f"   -> human visible to `wdt:P31 wd:Q5`? {'YES' if is_human_truthy else 'NO'}")
    if not is_human_truthy and types:
        print("      THIS is why the scraper skipped him: the human classification")
        print("      is outranked, so the truthy filter cannot see it.")

    print("\nP54 'member of sports team'")
    teams = run_sparql(TEAMS_QUERY.format(qid=qid), use_cache=False)
    for row in teams:
        start = (value(row, "start") or "?")[:4]
        end = (value(row, "end") or "now")[:4]
        rank = (value(row, "rank") or "").rsplit("#", 1)[-1]
        print(f"   {start}-{end:<5} {value(row, 'clubLabel'):<34} "
              f"({qid_from_uri(value(row, 'club'))}) rank={rank}")
    if not teams:
        print("   NONE — no club spells recorded at all.")

    if extra_clubs:
        clubs = " ".join(f"wd:{c}" for c in extra_clubs)
        print(f"\nSCRAPER QUERY against {', '.join(extra_clubs)}")
        with_filter = run_sparql(SCRAPER_QUERY.format(qid=qid, clubs=clubs), use_cache=False)
        without = run_sparql(SCRAPER_QUERY_NO_HUMAN_FILTER.format(qid=qid, clubs=clubs),
                             use_cache=False)
        print(f"   with `wdt:P31 wd:Q5` filter : {len(with_filter)} row(s)")
        print(f"   without the filter          : {len(without)} row(s)")
        if len(without) > len(with_filter):
            print("   -> the human filter is dropping real spells. Remove it.")

    return 0


if __name__ == "__main__":
    sys.exit(main())
