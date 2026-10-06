"""
Per-player facts from Wikidata that the club-centred scrape never asked for.

    python enrich_players.py            # fetch (cached) and apply
    python enrich_players.py --report   # numbers only, change nothing

1. OWN FAME. players.fame_score used to come only from the clubs a player
   was at, so anyone with two famous clubs scored ~99 - a 1910s Real Madrid
   amateur level with Zidane, Bertram Goode (Villa, Liverpool, pre-WWI) top of
   the Villa x Liverpool answer list. Fetch each player's own Wikipedia
   sitelink count - the same recognition signal the clubs already use - and
   let compute_fame_scores.py lead with it.

2. THE ERA GAP. KEEP_UNDATED_SPELLS keeps spells Wikidata gives no years for,
   and an open-ended spell (no end year) is read as "still at the club". For
   a player born in 1886 both are plainly pre-1990, yet both counted. Using
   the birth year ONLY as a filter, drop such spells for players born before
   ERA_BIRTH_CUTOFF. Players with no birth year keep everything, as before.

The birth year is stored in the maintenance database so a rebuild can
re-filter, and blanked in the slim copy (finalize.py): per the data rules the
shipped game holds nationality and nothing else biographical.
"""
from __future__ import annotations

import sys

import db
import wikidata_client as wd

ERA_BIRTH_CUTOFF = 1955   # 35 in 1990 - a footballer born earlier was done
OPEN_START_CUTOFF = 1985  # an open-ended spell that began before this, for such a player, is old


def query(qids: list[str]) -> str:
    values = " ".join("wd:" + q for q in qids)
    return f"""
    SELECT ?p ?n (MIN(?dob) AS ?birth) WHERE {{
      VALUES ?p {{ {values} }}
      ?p wikibase:sitelinks ?n .
      OPTIONAL {{ ?p wdt:P569 ?dob . }}
    }} GROUP BY ?p ?n"""


def fetch(conn) -> int:
    db.ensure_column(conn, "players", "sitelink_count", "INTEGER NOT NULL DEFAULT 0")
    db.ensure_column(conn, "players", "birth_year", "INTEGER")
    qids = [r["wikidata_qid"] for r in conn.execute(
        "SELECT wikidata_qid FROM players WHERE wikidata_qid LIKE 'Q%' ORDER BY player_id")]
    print(f"  fetching sitelinks + birth dates for {len(qids):,} players ...")
    rows = wd.run_chunked(qids, query, chunk_size=300, label="player batch")
    updates = []
    for r in rows:
        qid = wd.qid_from_uri(wd.value(r, "p"))
        n = int(wd.value(r, "n") or 0)
        birth = wd.year_from_iso(wd.value(r, "birth"))
        updates.append((n, birth, qid))
    conn.executemany(
        "UPDATE players SET sitelink_count = ?, birth_year = ? WHERE wikidata_qid = ?", updates)
    conn.commit()
    return len(updates)


ERA_WHERE = f"""
    player_id IN (SELECT player_id FROM players WHERE birth_year < {ERA_BIRTH_CUTOFF})
    AND end_year IS NULL
    AND (start_year IS NULL OR start_year < {OPEN_START_CUTOFF})"""


def era_filter(conn, apply: bool) -> int:
    n = conn.execute(f"SELECT COUNT(*) FROM player_club_spells WHERE {ERA_WHERE}").fetchone()[0]
    if apply and n:
        conn.execute(f"DELETE FROM player_club_spells WHERE {ERA_WHERE}")
        db.refresh_counters(conn)
        conn.commit()
    return n


def main() -> int:
    conn = db.connect()
    report_only = "--report" in sys.argv
    if not report_only:
        got = fetch(conn)
        print(f"  {got:,} players updated")
    have = conn.execute("""SELECT COUNT(*), SUM(sitelink_count > 0), SUM(birth_year IS NOT NULL)
                           FROM players""").fetchone()
    print(f"  players: {have[0]:,}  with a Wikipedia page: {have[1]:,}  with a birth year: {have[2]:,}")
    n = era_filter(conn, apply=not report_only)
    verb = "would drop" if report_only else "dropped"
    print(f"  era filter: {verb} {n:,} pre-{ERA_BIRTH_CUTOFF}-born open/undated spells")
    conn.close()
    return 0


if __name__ == "__main__":
    sys.exit(main())
