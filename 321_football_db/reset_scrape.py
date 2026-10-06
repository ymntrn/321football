"""
Reset the player scrape so step 2 runs again.

Exists because passing SQL through `python -c "..."` on Windows PowerShell is a
quoting minefield — the shell eats the escaped quotes and Python receives a
broken string, which fails silently enough that the build carries on as if
nothing was wrong.

    python reset_scrape.py            # show what would be reset
    python reset_scrape.py --apply    # actually reset

Retired duplicate clubs are deliberately left alone, so a merge isn't undone.
"""

from __future__ import annotations

import sys

import db


def main() -> int:
    apply_changes = "--apply" in sys.argv
    conn = db.connect()

    pending = conn.execute(
        "SELECT COUNT(*) AS n FROM clubs WHERE scrape_status = 'pending' AND is_reserve_or_b_team = 0"
    ).fetchone()["n"]
    active = conn.execute(
        "SELECT COUNT(*) AS n FROM clubs WHERE is_reserve_or_b_team = 0"
    ).fetchone()["n"]
    retired = conn.execute(
        "SELECT COUNT(*) AS n FROM clubs WHERE is_reserve_or_b_team = 1"
    ).fetchone()["n"]
    spells = conn.execute("SELECT COUNT(*) AS n FROM player_club_spells").fetchone()["n"]
    players = conn.execute("SELECT COUNT(*) AS n FROM players").fetchone()["n"]

    print(f"active clubs        : {active}")
    print(f"  already pending   : {pending}")
    print(f"retired / merged    : {retired}  (left untouched)")
    print(f"players             : {players:,}")
    print(f"spells              : {spells:,}")

    if not apply_changes:
        print(f"\nWould mark {active - pending} club(s) as pending so step 2 re-scrapes them.")
        print("Nothing has changed. To do it:")
        print("    python reset_scrape.py --apply")
        conn.close()
        return 0

    cur = conn.execute(
        "UPDATE clubs SET scrape_status = 'pending' WHERE is_reserve_or_b_team = 0"
    )
    conn.commit()

    print(f"\n{cur.rowcount} club(s) marked pending.")
    print("\nExisting spells are kept — the scraper uses INSERT OR IGNORE, so a")
    print("re-scrape adds what's missing rather than duplicating what's there.")
    print("\nNow run:")
    print("    python build_database.py --from 2")

    conn.close()
    return 0


if __name__ == "__main__":
    sys.exit(main())
