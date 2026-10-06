"""
Remove players who can never be typed as an answer.

Two groups qualify, and both are dead weight in a game where you win by typing
a name on a Latin keyboard:

  1. players whose name is in a non-Latin script and who have no Latin name
     anywhere on Wikidata
  2. players still named "Q12345" because no label could be resolved at all

Neither can ever be a correct answer, so removing them costs nothing in
correctness and makes the shipped database smaller and its answer keys honest
— right now a practice pair can claim three mutual players when only two are
actually typeable.

IMPORTANT: this rebuilds practice_pairs automatically. Deleting a player can
drop a pair's mutual count to zero, and a pair with no possible answer is
exactly the failure Practice mode must never serve.

    python purge_unanswerable.py            # report only
    python purge_unanswerable.py --apply    # delete, then rebuild pairs
"""

from __future__ import annotations

import sys

import db
from fix_names import is_latin_text


def find_unanswerable(conn) -> tuple[list, list]:
    non_latin, nameless = [], []

    for row in conn.execute(
        "SELECT player_id, wikidata_qid, display_name, club_count FROM players"
    ).fetchall():
        name = row["display_name"]
        if name.startswith("Q") and name[1:].isdigit():
            nameless.append(row)
        elif not is_latin_text(name):
            non_latin.append(row)

    return non_latin, nameless


def main() -> int:
    apply_changes = "--apply" in sys.argv
    conn = db.connect()

    total_players = conn.execute("SELECT COUNT(*) AS n FROM players").fetchone()["n"]
    non_latin, nameless = find_unanswerable(conn)
    doomed = non_latin + nameless

    print(f"{total_players:,} players in the database\n")
    print(f"  {len(non_latin):,} with a non-Latin name (untypeable)")
    print(f"  {len(nameless):,} with no resolved name at all")
    print(f"  {len(doomed):,} unanswerable in total "
          f"({100 * len(doomed) / total_players:.1f}%)")

    if not doomed:
        print("\nNothing to remove.")
        conn.close()
        return 0

    multi_club = [row for row in doomed if row["club_count"] >= 2]
    print(f"\n  of those, {len(multi_club):,} currently appear in answer keys "
          f"despite being untypeable")

    print("\n  sample:")
    for row in doomed[:8]:
        print(f"    {row['display_name']}  [{row['wikidata_qid']}] "
              f"({row['club_count']} clubs)")

    if not apply_changes:
        print("\nNothing changed. To remove them and rebuild practice pairs:")
        print("    python purge_unanswerable.py --apply")
        conn.close()
        return 0

    ids = [row["player_id"] for row in doomed]
    for start in range(0, len(ids), 500):
        chunk = ids[start:start + 500]
        placeholders = ",".join("?" * len(chunk))
        # Spells and aliases go with them: both tables cascade on delete.
        conn.execute(f"DELETE FROM players WHERE player_id IN ({placeholders})", chunk)
    conn.commit()

    remaining = conn.execute("SELECT COUNT(*) AS n FROM players").fetchone()["n"]
    spells = conn.execute("SELECT COUNT(*) AS n FROM player_club_spells").fetchone()["n"]
    print(f"\nRemoved {len(doomed):,} players. "
          f"{remaining:,} remain, {spells:,} spells.")

    db.refresh_counters(conn)

    # Mandatory: mutual counts have changed, so the pre-validated pairs are
    # no longer trustworthy until they're regenerated.
    print("\nRebuilding practice pairs (mutual counts have changed)...")
    import build_practice_pairs
    counts = build_practice_pairs.build(conn)
    print(f"  {sum(counts.values()):,} pairs")

    conn.close()

    print("\nNow re-run scoring and verification:")
    print("    python build_database.py --from 4")
    return 0


if __name__ == "__main__":
    sys.exit(main())
