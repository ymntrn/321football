"""
Merge duplicate club entities.

WHY THIS MATTERS FOR GAMEPLAY, NOT JUST TIDINESS
------------------------------------------------
Wikidata sometimes holds two items for the same real club — usually a
well-populated main item plus a thin stub created for a specific era or
competition. When that happens, the club's squad gets SPLIT between them, and
two players who really were teammates end up attached to different club_ids.
They then never appear as mutual players, and a question that should work
silently doesn't.

The tell is stark: the real 1. FC Kaiserslautern appears in dozens of language
Wikipedias, so a "1. FC Kaiserslautern" row with 0 languages and 1 player is
not a club — it's a fragment of one.

    python merge_duplicates.py            # report only, changes nothing
    python merge_duplicates.py --apply    # perform the merges
"""

from __future__ import annotations

import sys

import db


def find_duplicate_groups(conn) -> list[dict]:
    """
    Group active clubs by normalized name, keeping only names with more than
    one row. The keeper is the row with the most Wikipedia languages, falling
    back to the most players.
    """
    db.ensure_column(conn, "clubs", "sitelink_count", "INTEGER NOT NULL DEFAULT 0")

    names = conn.execute("""
        SELECT normalized_name FROM clubs
        WHERE is_reserve_or_b_team = 0
        GROUP BY normalized_name HAVING COUNT(*) > 1
    """).fetchall()

    groups = []
    for name_row in names:
        members = conn.execute("""
            SELECT club_id, wikidata_qid, canonical_name, sitelink_count,
                   distinct_player_count, scrape_status
            FROM clubs
            WHERE normalized_name = ? AND is_reserve_or_b_team = 0
            ORDER BY sitelink_count DESC, distinct_player_count DESC
        """, (name_row["normalized_name"],)).fetchall()

        if len(members) < 2:
            continue
        groups.append({
            "normalized_name": name_row["normalized_name"],
            "keeper": members[0],
            "duplicates": members[1:],
        })
    return groups


def merge_group(conn, group: dict) -> dict:
    keeper = group["keeper"]
    moved_spells = 0
    moved_leagues = 0

    for duplicate in group["duplicates"]:
        # Move spells onto the keeper. INSERT OR IGNORE against the unique
        # spell index means a player who somehow has the same spell on both
        # rows collapses to one instead of erroring.
        conn.execute("""
            INSERT OR IGNORE INTO player_club_spells
                (player_id, club_id, start_year, end_year, date_confidence,
                 source, source_statement_id, scraped_at)
            SELECT player_id, ?, start_year, end_year, date_confidence,
                   source, source_statement_id, scraped_at
            FROM player_club_spells WHERE club_id = ?
        """, (keeper["club_id"], duplicate["club_id"]))
        moved_spells += conn.total_changes

        conn.execute("DELETE FROM player_club_spells WHERE club_id = ?",
                     (duplicate["club_id"],))

        # Carry over league memberships the keeper doesn't already have.
        for link in conn.execute(
            "SELECT league_id, first_season, last_season FROM club_leagues WHERE club_id = ?",
            (duplicate["club_id"],),
        ).fetchall():
            db.link_club_league(conn, keeper["club_id"], link["league_id"],
                                link["first_season"])
            moved_leagues += 1
        conn.execute("DELETE FROM club_leagues WHERE club_id = ?",
                     (duplicate["club_id"],))

        # Keep the duplicate's name searchable, then retire the row. We mark
        # rather than delete so the merge is auditable and reversible.
        db.add_club_alias(conn, keeper["club_id"], duplicate["canonical_name"])
        conn.execute("""
            UPDATE clubs SET is_reserve_or_b_team = 1,
                   reserve_detection_method = 'merged_duplicate',
                   scrape_status = 'done',
                   updated_at = datetime('now')
            WHERE club_id = ?
        """, (duplicate["club_id"],))

    conn.commit()
    return {"spells": moved_spells, "leagues": moved_leagues}


def main() -> int:
    apply_changes = "--apply" in sys.argv
    conn = db.connect()

    groups = find_duplicate_groups(conn)
    if not groups:
        print("No duplicate clubs found.")
        conn.close()
        return 0

    print(f"{len(groups)} duplicate club group(s) found\n")
    print("=" * 76)
    for group in groups:
        keeper = group["keeper"]
        print(f"KEEP  {keeper['canonical_name']:<38} [{keeper['wikidata_qid']:<10}] "
              f"{keeper['sitelink_count']:>3} langs, {keeper['distinct_player_count']:>4} players")
        for duplicate in group["duplicates"]:
            print(f"  merge {duplicate['canonical_name']:<36} [{duplicate['wikidata_qid']:<10}] "
                  f"{duplicate['sitelink_count']:>3} langs, "
                  f"{duplicate['distinct_player_count']:>4} players")
    print("=" * 76)

    if not apply_changes:
        print("\nReport only — nothing changed.")
        print("Run with --apply to merge these:")
        print("    python merge_duplicates.py --apply")
        conn.close()
        return 0

    total_spells = 0
    for group in groups:
        result = merge_group(conn, group)
        total_spells += result["spells"]

    db.refresh_counters(conn)
    conn.close()

    print(f"\nMerged {len(groups)} group(s). Roughly {total_spells} spell rows moved.")
    print("\nRe-run the scoring and verification so fame and practice pairs")
    print("reflect the merged clubs:")
    print("    python build_database.py --from 4")
    return 0


if __name__ == "__main__":
    sys.exit(main())
