"""
A fast sanity check on the clubs table, meant to be run right after step 1.

Step 1 makes an irreversible-looking decision — it drops clubs it believes are
reserve/B teams — and a club dropped there never gets players scraped, never
appears in the game, and leaves no row behind to inspect. So the only way to
catch a bad exclusion is to check whether clubs you KNOW should exist actually
do.

    python diagnose.py
"""

from __future__ import annotations

import sys

import db
from names import normalize_name
from scrape_clubs import looks_like_reserve_team


def fix_reserves(conn) -> int:
    """
    Retroactively mark reserve/B sides that are already in the clubs table.

    Marking rather than deleting: an excluded club keeps its row (so we can
    see what happened and undo it), and every query the game runs already
    filters on is_reserve_or_b_team = 0.
    """
    marked = 0
    for row in conn.execute(
        "SELECT club_id, canonical_name FROM clubs WHERE is_reserve_or_b_team = 0"
    ).fetchall():
        is_reserve, method = looks_like_reserve_team(row["canonical_name"], None, None)
        if is_reserve:
            conn.execute(
                """UPDATE clubs SET is_reserve_or_b_team = 1,
                          reserve_detection_method = ?, updated_at = datetime('now')
                   WHERE club_id = ?""",
                (method, row["club_id"]),
            )
            marked += 1
    conn.commit()
    return marked

# Clubs that must be in any database claiming to cover these leagues. If one of
# these is missing, something upstream is wrong — don't scrape 700 clubs'
# players on top of a broken club list.
MUST_EXIST = [
    # Turkey — the ones most at risk from the multi-sport "part of" problem
    ("Galatasaray", "Süper Lig"),
    ("Fenerbahçe", "Süper Lig"),
    ("Beşiktaş", "Süper Lig"),
    ("Trabzonspor", "Süper Lig"),
    # Spain / Italy / England / Germany
    ("Real Madrid", "La Liga"),
    ("Barcelona", "La Liga"),
    ("Atlético Madrid", "La Liga"),
    ("Inter", "Serie A"),
    ("Milan", "Serie A"),
    ("Juventus", "Serie A"),
    ("Manchester United", "Premier League"),
    ("Liverpool", "Premier League"),
    ("Arsenal", "Premier League"),
    ("Chelsea", "Premier League"),
    ("Bayern", "Bundesliga"),
    ("Borussia Dortmund", "Bundesliga"),
    # Elsewhere
    ("Ajax", "Eredivisie"),
    ("Porto", "Primeira Liga"),
    ("Benfica", "Primeira Liga"),
    ("Celtic", "Scotland"),
    ("Rangers", "Scotland"),
    ("Paris Saint-Germain", "Ligue 1"),
    ("Olympiacos", "Greece"),
    ("Flamengo", "Brazil"),
    ("Al Hilal", "Saudi Pro League"),
    ("LA Galaxy", "MLS"),
]


def find_club(conn, name: str):
    normalized = normalize_name(name)
    row = conn.execute(
        "SELECT * FROM clubs WHERE normalized_name = ?", (normalized,)
    ).fetchone()
    if row:
        return row
    return conn.execute(
        "SELECT * FROM clubs WHERE normalized_name LIKE ? ORDER BY LENGTH(normalized_name) LIMIT 1",
        (f"%{normalized}%",),
    ).fetchone()


def main() -> int:
    conn = db.connect()

    if "--fix-reserves" in sys.argv:
        marked = fix_reserves(conn)
        print(f"Marked {marked} club(s) as reserve/B teams. They are now excluded "
              f"from the game without being deleted.")
        conn.close()
        return 0

    total = conn.execute(
        "SELECT COUNT(*) AS n FROM clubs WHERE is_reserve_or_b_team = 0"
    ).fetchone()["n"]
    print(f"{total} active clubs in the database\n")

    print("=" * 68)
    print("MUST-EXIST CLUBS")
    print("=" * 68)
    missing = []
    for name, league in MUST_EXIST:
        row = find_club(conn, name)
        if row:
            print(f"  found    {name:<22} -> {row['canonical_name']}")
        else:
            print(f"  MISSING  {name:<22} ({league})")
            missing.append((name, league))

    print("\n" + "=" * 68)
    print("CLUBS PER LEAGUE")
    print("=" * 68)
    for row in conn.execute("""
        SELECT l.name, l.country, COUNT(cl.club_id) AS n
        FROM leagues l
        LEFT JOIN club_leagues cl ON cl.league_id = l.league_id
        GROUP BY l.league_id ORDER BY n ASC
    """):
        flag = "  <-- suspiciously low" if row["n"] < 15 else ""
        print(f"  {row['n']:>4}  {row['name']} ({row['country']}){flag}")

    # Loosening the reserve-team rule fixed a false-positive problem (real
    # first teams being deleted) but could introduce the opposite one, so
    # check both directions rather than trusting the change.
    print("\n" + "=" * 68)
    print("RESERVE/B TEAMS THAT LEAKED INTO THE CLUB LIST")
    print("=" * 68)
    leaked = []
    for row in conn.execute(
        "SELECT club_id, canonical_name FROM clubs WHERE is_reserve_or_b_team = 0"
    ):
        is_reserve, method = looks_like_reserve_team(row["canonical_name"], None, None)
        if is_reserve:
            leaked.append((row["club_id"], row["canonical_name"], method))

    if leaked:
        print(f"  {len(leaked)} club(s) look like reserve/B sides but are still active:")
        for _, name, method in leaked[:30]:
            print(f"    - {name}  ({method})")
        if len(leaked) > 30:
            print(f"    ... and {len(leaked) - 30} more")
        print("\n  Fix them in place (no re-scrape needed) with:")
        print("    python diagnose.py --fix-reserves")
    else:
        print("  None — no B-team names found among the active clubs.")

    print("\n" + "=" * 68)
    print("EXCLUSIONS RECORDED DURING STEP 1")
    print("=" * 68)
    for row in conn.execute("""
        SELECT target_label, clubs_found, clubs_skipped_reserve
        FROM scrape_batches
        WHERE target_type = 'league' AND clubs_skipped_reserve > 0
        ORDER BY clubs_skipped_reserve DESC
    """):
        print(f"  {row['clubs_skipped_reserve']:>4} excluded as reserve/B  "
              f"({row['clubs_found']} kept)  {row['target_label']}")

    print("\n" + "=" * 68)
    if missing:
        print(f"PROBLEM: {len(missing)} must-exist club(s) are missing")
        print("=" * 68)
        for name, league in missing:
            print(f"   - {name} ({league})")
        print("\nDo NOT run step 2 until this is resolved — you'd be scraping")
        print("players for an incomplete club list.")
    else:
        print("All must-exist clubs are present. Safe to continue to step 2.")
    print("=" * 68)

    conn.close()
    return 1 if missing else 0


if __name__ == "__main__":
    sys.exit(main())
