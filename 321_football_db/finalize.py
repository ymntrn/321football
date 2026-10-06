"""
Prepare the database for shipping inside the Flutter app.

    python finalize.py              # report size and what could be trimmed
    python finalize.py --apply      # VACUUM + ANALYZE in place
    python finalize.py --slim       # also write a stripped copy for the app

The database you build is a working database: it carries scrape provenance,
review flags, and every player it ever saw. The copy you ship inside an app
bundle doesn't need any of that, and on a phone the difference is worth
having.
"""

from __future__ import annotations

import os
import shutil
import sqlite3
import sys

import config
import db

SLIM_PATH = os.path.join(config.BASE_DIR, "321_football_slim.db")


def human_size(path: str) -> str:
    if not os.path.exists(path):
        return "missing"
    mb = os.path.getsize(path) / (1024 * 1024)
    return f"{mb:.1f} MB"


def table_sizes(conn) -> list[tuple[str, int]]:
    tables = [row["name"] for row in conn.execute(
        "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%'"
    )]
    sizes = []
    for table in tables:
        count = conn.execute(f"SELECT COUNT(*) AS n FROM {table}").fetchone()["n"]
        sizes.append((table, count))
    return sorted(sizes, key=lambda item: item[1], reverse=True)


def report(conn) -> None:
    print(f"database : {config.DB_PATH}")
    print(f"size     : {human_size(config.DB_PATH)}\n")

    print("ROW COUNTS")
    for table, count in table_sizes(conn):
        print(f"  {count:>10,}  {table}")

    single_club = conn.execute(
        "SELECT COUNT(*) AS n FROM players WHERE club_count < 2"
    ).fetchone()["n"]
    nameless = conn.execute(
        "SELECT COUNT(*) AS n FROM players WHERE display_name GLOB 'Q[0-9]*'"
    ).fetchone()["n"]
    batches = conn.execute("SELECT COUNT(*) AS n FROM scrape_batches").fetchone()["n"]

    print("\nWHAT --slim WOULD REMOVE")
    print(f"  {batches:>10,}  scrape_batches rows (provenance — never read at runtime)")
    print(f"  {nameless:>10,}  players with no resolved name (untypeable, so unanswerable)")
    print(f"  {single_club:>10,}  players with fewer than 2 clubs")
    print("\n  The last one is a judgement call, not free. A player with one club")
    print("  can never be a mutual answer, so dropping him costs no correct")
    print("  answers — but validate_answer would then report 'unknown_player'")
    print("  instead of 'he never played for both' when someone names him.")
    print("  Keep them if you want that distinction in the UI.")


def vacuum(conn) -> None:
    before = os.path.getsize(config.DB_PATH)
    print("running ANALYZE (helps the query planner pick the right index)...")
    conn.execute("ANALYZE")
    conn.commit()
    conn.close()

    print("running VACUUM (reclaims space and defragments)...")
    plain = sqlite3.connect(config.DB_PATH)
    plain.execute("VACUUM")
    plain.close()

    after = os.path.getsize(config.DB_PATH)
    saved = (before - after) / (1024 * 1024)
    print(f"  {before / 1048576:.1f} MB -> {after / 1048576:.1f} MB "
          f"({saved:+.1f} MB)")


def build_slim(drop_single_club: bool) -> None:
    if os.path.exists(SLIM_PATH):
        os.remove(SLIM_PATH)
    shutil.copy2(config.DB_PATH, SLIM_PATH)

    conn = db.connect(SLIM_PATH)

    print(f"\nbuilding {os.path.basename(SLIM_PATH)}")

    # Recount BEFORE deleting anything. club_count is a cached column, and
    # deleting on a stale one would throw away real answers — a player whose
    # count says 1 but who actually has two clubs is a valid mutual player.
    db.refresh_counters(conn)

    conn.execute("DELETE FROM scrape_batches")
    print("  dropped scrape provenance")

    # Retired duplicates and reserve sides are never surfaced by any query.
    conn.execute("DELETE FROM clubs WHERE is_reserve_or_b_team = 1")
    print("  dropped retired/reserve clubs")

    # A player with no resolved name cannot be typed, so he can never be a
    # correct answer no matter how many clubs he links.
    conn.execute("DELETE FROM players WHERE display_name GLOB 'Q[0-9]*'")
    print("  dropped players with no resolved name")

    if drop_single_club:
        removed = conn.execute(
            "SELECT COUNT(*) AS n FROM players WHERE club_count < 2"
        ).fetchone()["n"]
        conn.execute("DELETE FROM players WHERE club_count < 2")
        print(f"  dropped {removed:,} players with fewer than 2 clubs")

    conn.commit()
    conn.close()

    plain = sqlite3.connect(SLIM_PATH)
    plain.execute("VACUUM")
    plain.close()

    print(f"\n  {os.path.basename(SLIM_PATH)}: {human_size(SLIM_PATH)}")
    print(f"  (original: {human_size(config.DB_PATH)})")

    # Prove the slim copy still answers correctly before anyone ships it.
    verify_slim()


def verify_slim() -> None:
    conn = db.connect(SLIM_PATH)
    from game_queries import get_mutual_players, validate_answer
    from names import normalize_name

    def club(name: str):
        """
        Same cascade as verify.find_club — exact, then prefix, then substring.

        Prefix alone is not enough: "Barcelona" is not a prefix of
        "FC Barcelona", so a prefix-only lookup reports the club missing and
        fails a perfectly good database. That is a bug in the check, and it
        is worth avoiding: a verification step that cries wolf is worse than
        none, because you learn to ignore it.
        """
        norm = normalize_name(name)
        for pattern in (norm, f"{norm}%", f"%{norm}%"):
            row = conn.execute("""
                SELECT club_id, canonical_name FROM clubs
                WHERE normalized_name LIKE ? AND is_reserve_or_b_team = 0
                ORDER BY fame_score DESC LIMIT 1
            """, (pattern,)).fetchone()
            if row:
                return row
        return None

    print("\n  sanity check on the slim copy:")
    checks = [
        ("Wesley Sneijder", "Inter Milan", "Galatasaray"),
        ("Luís Figo", "Barcelona", "Real Madrid"),
        ("Didier Drogba", "Chelsea", "Galatasaray"),
    ]
    ok = True
    for player, a, b in checks:
        ca, cb = club(a), club(b)
        if not ca or not cb:
            print(f"    MISSING CLUB for {player}")
            ok = False
            continue
        result = validate_answer(conn, player, ca["club_id"], cb["club_id"])
        mark = "ok  " if result["correct"] else "FAIL"
        if not result["correct"]:
            ok = False
        print(f"    {mark} {player} @ {ca['canonical_name']} x {cb['canonical_name']}")

    pairs = conn.execute("SELECT COUNT(*) AS n FROM practice_pairs").fetchone()["n"]
    print(f"    {pairs:,} practice pairs still available")

    # THE invariant that must survive trimming: every Practice question must
    # still have a real, typeable answer. Deleting players is exactly the kind
    # of change that could quietly break it, so re-derive the answers rather
    # than trusting the stored mutual_count.
    from game_queries import count_mutual_players, random_practice_pair
    broken = 0
    sampled = 0
    for band in ("easy", "medium", "hard"):
        for _ in range(40):
            pair = random_practice_pair(conn, band)
            if not pair:
                break
            sampled += 1
            if count_mutual_players(conn, pair["club_a_id"], pair["club_b_id"]) == 0:
                broken += 1

    if broken:
        print(f"    {broken} of {sampled} sampled pairs now have NO answer")
        ok = False
    else:
        print(f"    {sampled} sampled pairs all still answerable")

    conn.close()

    if ok:
        print("\n  Slim copy is good. Ship this one.")
    else:
        print("\n  Slim copy FAILED its checks — ship the full database instead.")


def main() -> int:
    if not db.database_exists():
        print("No database found. Run build_database.py first.")
        return 1

    conn = db.connect()
    report(conn)

    if "--apply" in sys.argv or "--slim" in sys.argv:
        print()
        vacuum(conn)
    else:
        conn.close()
        print("\nNothing changed. To compact in place:")
        print("    python finalize.py --apply")
        print("To also build a stripped copy for the app bundle:")
        print("    python finalize.py --slim")
        print("    python finalize.py --slim --drop-single-club")
        return 0

    if "--slim" in sys.argv:
        build_slim(drop_single_club="--drop-single-club" in sys.argv)

    return 0


if __name__ == "__main__":
    sys.exit(main())
