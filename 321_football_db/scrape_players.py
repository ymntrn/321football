"""
STEP 2 — scrape every player spell for every club in the database.

This is the long one: it's the step that actually fills player_club_spells,
the table the game runs on. It is resumable — each club is marked 'done' once
its data has landed, so you can stop it with Ctrl-C and re-run it later
without redoing work or duplicating rows.

Clubs are queried in chunks (config.CLUB_CHUNK_SIZE) rather than one at a
time; the client automatically halves a chunk and retries if WDQS says the
query was too expensive.
"""

from __future__ import annotations

import sys

import config
import db
from names import name_variants
from wikidata_client import (
    run_sparql, qid_from_uri, value, year_from_iso, QueryTooBig,
)

# NOTE: nationality is deliberately NOT fetched here.
#
# A player with dual nationality produces a duplicate row for EVERY spell he
# has, so pulling it inline inflates the response for no benefit — and these
# responses are already large enough that WDQS sometimes cuts them off
# mid-transfer. Nationality is a per-player fact, not a per-spell one, so it
# belongs in the enrichment step where it's fetched once per player.
# There is deliberately NO `?player wdt:P31 wd:Q5` ("must be a human") filter.
#
# It looked like sensible defence and it silently cost real players — David
# Beckham among them. `wdt:` exposes only a property's BEST-RANKED value, so
# any item whose "instance of: human" statement is outranked by another P31
# statement becomes invisible to that filter, and the player disappears along
# with his entire career.
#
# The filter was never earning its keep anyway: P54 ("member of sports team")
# is only ever stated about people, so requiring the club link already implies
# a person. Dropping it removes the failure mode at no real cost.
SPELLS_FOR_CLUBS_QUERY = """
SELECT ?club ?player ?playerLabel ?start ?end ?statement WHERE {{
  VALUES ?club {{ {clubs} }}
  ?player p:P54 ?statement .              # member of sports team
  ?statement ps:P54 ?club .
  OPTIONAL {{ ?statement pq:P580 ?start. }}   # start time qualifier
  OPTIONAL {{ ?statement pq:P582 ?end. }}     # end time qualifier
  SERVICE wikibase:label {{ bd:serviceParam wikibase:language "en". }}
}}
"""


def spell_passes_cutoff(start: int | None, end: int | None) -> tuple[bool, str]:
    """
    Apply config.INCLUDE_SPELL_RULE.

    Returns (keep, reason) where reason is one of:
      'ok' | 'pre_cutoff' | 'undated'
    """
    if start is None and end is None:
        return (config.KEEP_UNDATED_SPELLS, "undated")

    if config.INCLUDE_SPELL_RULE == "starts_after":
        if start is None:
            return (config.KEEP_UNDATED_SPELLS, "undated")
        return (start >= config.CUTOFF_YEAR, "ok" if start >= config.CUTOFF_YEAR else "pre_cutoff")

    # Default: "overlaps" — was the player at this club at any point from the
    # cutoff onward? An open-ended spell (end is NULL) is still running, so it
    # necessarily overlaps.
    if end is None:
        return (True, "ok")
    if end >= config.CUTOFF_YEAR:
        return (True, "ok")
    return (False, "pre_cutoff")


def date_confidence_for(start: int | None, end: int | None) -> str:
    if start is not None and end is not None:
        return "exact"
    if start is None and end is None:
        return "unknown"
    return "partial"


def process_chunk(conn, club_rows: list) -> dict:
    """Scrape one chunk of clubs. Returns counters."""
    qid_to_club_id = {row["wikidata_qid"]: row["club_id"] for row in club_rows}
    values_clause = " ".join(f"wd:{qid}" for qid in qid_to_club_id)

    rows = run_sparql(SPELLS_FOR_CLUBS_QUERY.format(clubs=values_clause))

    counters = {
        "spells_found": 0, "spells_inserted": 0,
        "spells_skipped_precutoff": 0, "spells_skipped_undated": 0,
        "parse_errors": 0,
    }
    players_seen: set[int] = set()
    per_club_players: dict[str, set[int]] = {qid: set() for qid in qid_to_club_id}

    for row in rows:
        counters["spells_found"] += 1
        try:
            club_qid = qid_from_uri(value(row, "club"))
            club_id = qid_to_club_id.get(club_qid)
            if club_id is None:
                continue

            player_qid = qid_from_uri(value(row, "player"))
            player_name = value(row, "playerLabel") or player_qid

            # Wikidata's label SERVICE is intermittently flaky: it sometimes
            # returns an entity's Q-number instead of its name, for rows that
            # are otherwise perfectly good. (You can see the same hiccup in
            # step 0, where Serie A came back labelled "Q15804".)
            #
            # This used to DISCARD the player — which silently lost ~1,700
            # players including David Beckham, because one flaky lookup threw
            # away an entire career. Now we keep the player and mark him for a
            # label repair pass, which fetches the name via rdfs:label directly
            # instead of through the label service.
            label_missing = player_name.startswith("Q") and player_name[1:].isdigit()
            if label_missing:
                counters["labels_deferred"] = counters.get("labels_deferred", 0) + 1

            start = year_from_iso(value(row, "start"))
            end = year_from_iso(value(row, "end"))

            # Obviously corrupt date pair — don't trust either value.
            if start is not None and end is not None and end < start:
                counters["parse_errors"] += 1
                start, end = None, None

            keep, reason = spell_passes_cutoff(start, end)
            if not keep:
                if reason == "pre_cutoff":
                    counters["spells_skipped_precutoff"] += 1
                else:
                    counters["spells_skipped_undated"] += 1
                continue

            # nationality arrives later, in the enrichment step
            player_id = db.upsert_player(
                conn, qid=player_qid, full_name=player_name, nationality=None,
            )

            if label_missing:
                # Flag for repair, and generate NO aliases — "q10520" must
                # never become an accepted spelling of somebody's name.
                conn.execute(
                    "UPDATE players SET needs_label = 1 WHERE player_id = ?",
                    (player_id,),
                )
            else:
                for variant in name_variants(player_name):
                    db.add_player_alias(conn, player_id, variant)

            if db.insert_spell(
                conn, player_id=player_id, club_id=club_id,
                start_year=start, end_year=end,
                date_confidence=date_confidence_for(start, end),
                statement_id=value(row, "statement"),
            ):
                counters["spells_inserted"] += 1

            players_seen.add(player_id)
            per_club_players[club_qid].add(player_id)

        except Exception:  # noqa: BLE001 — one bad row must not kill the run
            counters["parse_errors"] += 1

    # Mark each club done (or needing review if it came back suspiciously thin)
    for qid, club_id in qid_to_club_id.items():
        found = len(per_club_players[qid])
        status = "done" if found >= config.MIN_EXPECTED_PLAYERS_PER_CLUB else "needs_review"
        conn.execute(
            "UPDATE clubs SET scrape_status = ?, scraped_at = ?, updated_at = datetime('now') WHERE club_id = ?",
            (status, db.utcnow(), club_id),
        )

    conn.commit()
    counters["players_found"] = len(players_seen)
    counters["thin_clubs"] = [
        row["canonical_name"] for row in club_rows
        if len(per_club_players[row["wikidata_qid"]]) < config.MIN_EXPECTED_PLAYERS_PER_CLUB
    ]
    return counters


def main(limit: int | None = None) -> int:
    conn = db.connect()
    db.init_schema(conn)
    db.ensure_column(conn, "players", "needs_label", "INTEGER NOT NULL DEFAULT 0")

    pending = conn.execute(
        """SELECT club_id, wikidata_qid, canonical_name FROM clubs
           WHERE scrape_status = 'pending' AND is_reserve_or_b_team = 0
           ORDER BY club_id"""
    ).fetchall()

    already_done = conn.execute(
        "SELECT COUNT(*) AS n FROM clubs WHERE scrape_status != 'pending'"
    ).fetchone()["n"]

    if not pending:
        print(f"Nothing pending — all {already_done} clubs already scraped.")
        print("To force a re-scrape:  UPDATE clubs SET scrape_status='pending';")
        conn.close()
        return 0

    if limit:
        pending = pending[:limit]

    print(f"{len(pending)} clubs to scrape ({already_done} already done)")
    print(f"Rule: {config.INCLUDE_SPELL_RULE!r} against cutoff {config.CUTOFF_YEAR}; "
          f"undated spells {'KEPT' if config.KEEP_UNDATED_SPELLS else 'DROPPED'}\n")

    chunk_size = config.CLUB_CHUNK_SIZE
    totals = {k: 0 for k in
              ("spells_found", "spells_inserted", "spells_skipped_precutoff",
               "spells_skipped_undated", "parse_errors")}
    all_thin: list[str] = []

    index = 0
    while index < len(pending):
        chunk = pending[index:index + chunk_size]
        labels = ", ".join(row["canonical_name"] for row in chunk[:3])
        suffix = f" (+{len(chunk) - 3} more)" if len(chunk) > 3 else ""
        print(f"  [{index + 1}-{index + len(chunk)}/{len(pending)}] {labels}{suffix}", flush=True)

        batch_id = db.start_batch(conn, target_type="club_chunk", target_qid=None,
                                  target_label=f"{len(chunk)} clubs from {chunk[0]['canonical_name']}")
        try:
            counters = process_chunk(conn, chunk)
        except QueryTooBig:
            if len(chunk) == 1:
                print("      !! single club times out — marking failed, moving on")
                conn.execute("UPDATE clubs SET scrape_status='failed' WHERE club_id = ?",
                             (chunk[0]["club_id"],))
                conn.commit()
                db.finish_batch(conn, batch_id, status="failed", flagged=True,
                                notes="SPARQL timeout on a single club")
                index += 1
                continue
            chunk_size = max(1, len(chunk) // 2)
            print(f"      chunk too big, dropping chunk size to {chunk_size} and retrying")
            db.finish_batch(conn, batch_id, status="failed", notes="chunk too big, split")
            continue  # retry the same index with the smaller chunk size
        except KeyboardInterrupt:
            db.finish_batch(conn, batch_id, status="failed", notes="interrupted by user")
            print("\nInterrupted — progress is saved, just re-run to continue.")
            conn.close()
            return 130

        thin = counters.pop("thin_clubs", [])
        all_thin += thin
        for key in totals:
            totals[key] += counters.get(key, 0)

        db.finish_batch(
            conn, batch_id,
            status="needs_review" if thin else "success",
            flagged=bool(thin),
            notes=("thin: " + ", ".join(thin)) if thin else None,
            **{k: counters.get(k, 0) for k in
               ("players_found", "spells_found", "spells_inserted",
                "spells_skipped_precutoff", "spells_skipped_undated", "parse_errors")},
        )

        print(f"      +{counters['spells_inserted']} spells, "
              f"{counters['players_found']} players"
              + (f"  !! thin: {', '.join(thin)}" if thin else ""))

        index += len(chunk)

    db.refresh_counters(conn)

    deferred = conn.execute(
        "SELECT COUNT(*) AS n FROM players WHERE needs_label = 1"
    ).fetchone()["n"]

    print("\n" + "-" * 60)
    print(f"spells inserted      : {totals['spells_inserted']}")
    print(f"skipped (pre-{config.CUTOFF_YEAR})  : {totals['spells_skipped_precutoff']}")
    print(f"skipped (undated)    : {totals['spells_skipped_undated']}")
    print(f"parse errors         : {totals['parse_errors']}")
    if deferred:
        print(f"awaiting name repair : {deferred}  (step 3 fetches these)")
    if all_thin:
        print(f"\n{len(all_thin)} club(s) returned very few players and are marked "
              f"'needs_review' in the clubs table:")
        for name in all_thin[:25]:
            print(f"   - {name}")
        if len(all_thin) > 25:
            print(f"   ... and {len(all_thin) - 25} more")
        print("\nThat usually means thin Wikidata coverage for a small club, which is")
        print("fine — but check a couple by hand before trusting them in the game.")

    conn.close()
    return 0


if __name__ == "__main__":
    arg_limit = int(sys.argv[1]) if len(sys.argv) > 1 else None
    sys.exit(main(arg_limit))
