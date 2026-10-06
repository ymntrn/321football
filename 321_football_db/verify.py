"""
STEP 6 — verify the database. This is the "double check" step.

Structural checks catch broken data. Golden tests catch WRONG data, which is
much more dangerous: a database that's internally consistent but missing
half of Galatasaray's squad will pass every integrity check and still ruin
the game.

So this script asserts real football facts that a human can confirm — Sneijder
played for both Inter and Galatasaray, Drogba for both Chelsea and
Galatasaray, Cristiano Ronaldo for both Real Madrid and Al Nassr — and fails
loudly if the database disagrees.

Run it after every full build, and after any re-scrape.
"""

from __future__ import annotations

import sys

import config
import db
from game_queries import (
    get_mutual_players, validate_answer, random_practice_pair, count_mutual_players,
)
from names import normalize_name

# -------------------------------------------------------------------------
# Golden facts — real, checkable, post-1990, spread across the leagues we cover
# -------------------------------------------------------------------------
# (player, club A, club B) — the player genuinely played for both.
# Club names here must be UNAMBIGUOUS. A bare "Milan" resolves to Inter Milan
# (it contains the string and outranks AC Milan on fame), which turned the Kaká
# test into a question about a transfer that never happened. A golden test that
# asks the wrong question is worse than no test — it burns your attention on a
# phantom bug.
GOLDEN_MUTUALS = [
    ("Wesley Sneijder",     "Inter Milan",       "Galatasaray"),
    ("Wesley Sneijder",     "Real Madrid",       "Inter Milan"),
    ("Felipe Melo",         "Inter Milan",       "Galatasaray"),
    ("Hakan Şükür",         "Galatasaray",       "Inter Milan"),
    ("Didier Drogba",       "Chelsea",           "Galatasaray"),
    ("Robin van Persie",    "Arsenal",           "Fenerbahçe"),
    ("Roberto Carlos",      "Real Madrid",       "Fenerbahçe"),
    ("Ronaldo",             "Inter Milan",       "Real Madrid"),
    ("Zlatan Ibrahimović",  "Inter Milan",       "Barcelona"),
    ("Thierry Henry",       "Arsenal",           "Barcelona"),
    ("David Beckham",       "Manchester United", "Real Madrid"),
    ("Kaká",                "AC Milan",          "Real Madrid"),
    ("Cristiano Ronaldo",   "Manchester United", "Real Madrid"),
    ("Andrea Pirlo",        "AC Milan",          "Juventus"),
    ("Luís Figo",           "Barcelona",         "Real Madrid"),
    ("Andriy Shevchenko",   "AC Milan",          "Chelsea"),
    ("Nicolas Anelka",      "Arsenal",           "Real Madrid"),
]

# Clubs we expect to be rated famous (Easy) and obscure (Hard). If the fame
# model puts Real Madrid in "hard", something is badly wrong.
EXPECTED_EASY_CLUBS = ["Real Madrid", "Barcelona", "Manchester United", "Liverpool", "Juventus"]
EXPECTED_NOT_EASY_CLUBS = ["Başakşehir", "Sheffield United", "Burnley"]

# Typed-answer variants that must all resolve to the same player.
ANSWER_VARIANTS = [
    ("Wesley Sneijder", ["Wesley Sneijder", "sneijder", "SNEIJDER", "Sneijder "]),
    ("Mesut Özil",      ["Mesut Ozil", "ozil", "Özil", "OZIL"]),
    ("Hakan Şükür",     ["Hakan Sukur", "sukur", "şükür", "SUKUR"]),
]


class Report:
    def __init__(self) -> None:
        self.passed = 0
        self.failed = 0
        self.warnings = 0
        self.failures: list[str] = []
        self.warns: list[str] = []

    def ok(self, message: str) -> None:
        self.passed += 1
        print(f"  PASS  {message}")

    def fail(self, message: str) -> None:
        self.failed += 1
        self.failures.append(message)
        print(f"  FAIL  {message}")

    def warn(self, message: str) -> None:
        self.warnings += 1
        self.warns.append(message)
        print(f"  WARN  {message}")


def find_club(conn, name: str):
    """
    Resolve a human club name to a row. Wikidata labels don't always match
    the name a fan would use ("Inter Milan" vs "FC Internazionale Milano"),
    so we try exact, then alias, then substring.
    """
    normalized = normalize_name(name)

    row = conn.execute(
        "SELECT * FROM clubs WHERE normalized_name = ? AND is_reserve_or_b_team = 0",
        (normalized,),
    ).fetchone()
    if row:
        return row

    row = conn.execute("""
        SELECT c.* FROM clubs c
        JOIN club_aliases a ON a.club_id = c.club_id
        WHERE a.normalized_alias = ? AND c.is_reserve_or_b_team = 0
    """, (normalized,)).fetchone()
    if row:
        return row

    # Prefer a name that STARTS with the query before falling back to a
    # contains-anywhere match. "AC Milan" should win over "Inter Milan" when
    # asked for "AC Milan", and asking for "Milan" should not silently land on
    # whichever club happens to rank highest.
    row = conn.execute("""
        SELECT * FROM clubs
        WHERE normalized_name LIKE ? AND is_reserve_or_b_team = 0
        ORDER BY fame_score DESC LIMIT 1
    """, (f"{normalized}%",)).fetchone()
    if row:
        return row

    return conn.execute("""
        SELECT * FROM clubs
        WHERE normalized_name LIKE ? AND is_reserve_or_b_team = 0
        ORDER BY fame_score DESC LIMIT 1
    """, (f"%{normalized}%",)).fetchone()


# -------------------------------------------------------------------------
# Checks
# -------------------------------------------------------------------------
def check_population(conn, report: Report) -> None:
    print("\n[1] Population")
    counts = {
        "leagues": conn.execute("SELECT COUNT(*) AS n FROM leagues").fetchone()["n"],
        "clubs": conn.execute("SELECT COUNT(*) AS n FROM clubs WHERE is_reserve_or_b_team = 0").fetchone()["n"],
        "players": conn.execute("SELECT COUNT(*) AS n FROM players").fetchone()["n"],
        "spells": conn.execute("SELECT COUNT(*) AS n FROM player_club_spells").fetchone()["n"],
    }
    for name, value in counts.items():
        print(f"        {name}: {value:,}")

    if counts["leagues"] == 0:
        report.fail("no leagues — run resolve_leagues.py")
    else:
        report.ok(f"{counts['leagues']} leagues present")

    if counts["clubs"] < 100:
        report.fail(f"only {counts['clubs']} clubs — expected well over 100 across ~23 leagues")
    else:
        report.ok(f"{counts['clubs']:,} clubs present")

    if counts["spells"] < 1000:
        report.fail(f"only {counts['spells']} spells — the player scrape looks incomplete")
    else:
        report.ok(f"{counts['spells']:,} player-club spells present")


def check_integrity(conn, report: Report) -> None:
    print("\n[2] Data integrity")

    bad_dates = conn.execute("""
        SELECT COUNT(*) AS n FROM player_club_spells
        WHERE start_year IS NOT NULL AND end_year IS NOT NULL AND end_year < start_year
    """).fetchone()["n"]
    if bad_dates:
        report.fail(f"{bad_dates} spells end before they start")
    else:
        report.ok("no spells end before they start")

    if config.INCLUDE_SPELL_RULE == "overlaps":
        violations = conn.execute("""
            SELECT COUNT(*) AS n FROM player_club_spells
            WHERE end_year IS NOT NULL AND end_year < ?
        """, (config.CUTOFF_YEAR,)).fetchone()["n"]
    else:
        violations = conn.execute("""
            SELECT COUNT(*) AS n FROM player_club_spells
            WHERE start_year IS NOT NULL AND start_year < ?
        """, (config.CUTOFF_YEAR,)).fetchone()["n"]

    if violations:
        report.fail(f"{violations} spells violate the {config.INCLUDE_SPELL_RULE!r} cutoff rule")
    else:
        report.ok(f"all spells respect the {config.CUTOFF_YEAR} cutoff ({config.INCLUDE_SPELL_RULE})")

    reserves = conn.execute(
        "SELECT COUNT(*) AS n FROM clubs WHERE is_reserve_or_b_team = 1"
    ).fetchone()["n"]
    reserve_spells = conn.execute("""
        SELECT COUNT(*) AS n FROM player_club_spells s
        JOIN clubs c ON c.club_id = s.club_id WHERE c.is_reserve_or_b_team = 1
    """).fetchone()["n"]
    if reserve_spells:
        report.fail(f"{reserve_spells} spells attached to reserve/B teams — they should be excluded")
    else:
        report.ok(f"no gameplay data attached to reserve/B teams ({reserves} such clubs stored but unused)")

    # Two Wikidata items for the same real club would split its squad in half
    # and silently break mutual lookups. Worth knowing about.
    dupes = conn.execute("""
        SELECT normalized_name, COUNT(*) AS n FROM clubs
        WHERE is_reserve_or_b_team = 0
        GROUP BY normalized_name HAVING COUNT(*) > 1
        ORDER BY n DESC LIMIT 10
    """).fetchall()
    if dupes:
        names = ", ".join(f"{r['normalized_name']} (x{r['n']})" for r in dupes)
        report.warn(f"possible duplicate clubs sharing a name: {names}")
    else:
        report.ok("no duplicate club names")

    undated = conn.execute(
        "SELECT COUNT(*) AS n FROM player_club_spells WHERE date_confidence = 'unknown'"
    ).fetchone()["n"]
    total = conn.execute("SELECT COUNT(*) AS n FROM player_club_spells").fetchone()["n"]
    if total:
        pct = 100 * undated / total
        if pct > 25:
            report.warn(f"{pct:.1f}% of spells have no dates at all — these could include pre-{config.CUTOFF_YEAR} stints")
        else:
            report.ok(f"{pct:.1f}% of spells are undated (acceptable)")


def check_coverage(conn, report: Report) -> None:
    print("\n[3] Coverage")

    empty = conn.execute("""
        SELECT COUNT(*) AS n FROM clubs
        WHERE is_reserve_or_b_team = 0 AND distinct_player_count = 0
    """).fetchone()["n"]
    total = conn.execute(
        "SELECT COUNT(*) AS n FROM clubs WHERE is_reserve_or_b_team = 0"
    ).fetchone()["n"]

    if total and empty / total > 0.25:
        report.fail(f"{empty}/{total} clubs have no players at all — scrape looks incomplete")
    elif empty:
        report.warn(f"{empty}/{total} clubs have no players (likely thin Wikidata coverage on small clubs)")
    else:
        report.ok("every club has at least one player")

    needs_review = conn.execute(
        "SELECT COUNT(*) AS n FROM clubs WHERE scrape_status = 'needs_review'"
    ).fetchone()["n"]
    if needs_review:
        report.warn(f"{needs_review} clubs flagged 'needs_review' during scraping")
    else:
        report.ok("no clubs flagged during scraping")

    failed_batches = conn.execute(
        "SELECT COUNT(*) AS n FROM scrape_batches WHERE status = 'failed'"
    ).fetchone()["n"]
    if failed_batches:
        report.warn(f"{failed_batches} scrape batches failed — re-run the scraper to retry them")
    else:
        report.ok("no failed scrape batches")


def check_golden_mutuals(conn, report: Report) -> None:
    print("\n[4] Golden tests — real transfers that MUST be findable")

    for player_name, club_a_name, club_b_name in GOLDEN_MUTUALS:
        club_a = find_club(conn, club_a_name)
        club_b = find_club(conn, club_b_name)

        if not club_a or not club_b:
            missing = club_a_name if not club_a else club_b_name
            report.warn(f"{player_name}: club {missing!r} not in database — cannot test")
            continue

        mutuals = get_mutual_players(conn, club_a["club_id"], club_b["club_id"])
        target = normalize_name(player_name)
        found = any(normalize_name(m["display_name"]) == target
                    or target.split()[-1] == normalize_name(m["display_name"]).split()[-1]
                    for m in mutuals)

        label = f"{player_name} @ {club_a['canonical_name']} x {club_b['canonical_name']}"
        if found:
            report.ok(f"{label} ({len(mutuals)} mutual players)")
        else:
            sample = ", ".join(m["display_name"] for m in mutuals[:4]) or "none"
            report.fail(f"{label} — NOT FOUND. Mutuals returned: {sample}")


def check_answer_matching(conn, report: Report) -> None:
    print("\n[5] Typed-answer matching")

    for canonical, variants in ANSWER_VARIANTS:
        player = conn.execute(
            "SELECT player_id FROM players WHERE normalized_name = ?",
            (normalize_name(canonical),),
        ).fetchone()
        if not player:
            report.warn(f"{canonical} not in database — cannot test typed variants")
            continue

        spell = conn.execute(
            "SELECT club_id FROM player_club_spells WHERE player_id = ? LIMIT 2",
            (player["player_id"],),
        ).fetchall()
        if len(spell) < 2:
            report.warn(f"{canonical} has fewer than 2 clubs — cannot test typed variants")
            continue

        a, b = spell[0]["club_id"], spell[1]["club_id"]
        failures = [v for v in variants
                    if not validate_answer(conn, v, a, b)["correct"]]
        if failures:
            report.fail(f"{canonical}: these spellings were rejected: {failures}")
        else:
            report.ok(f"{canonical}: all {len(variants)} spellings accepted")

    # A wrong-but-real player must NOT be accepted.
    pair = conn.execute("""
        SELECT club_a_id, club_b_id FROM practice_pairs LIMIT 1
    """).fetchone()
    if pair:
        result = validate_answer(conn, "Zzzz Notaplayer", pair["club_a_id"], pair["club_b_id"])
        if result["correct"]:
            report.fail("a nonsense name was accepted as a correct answer")
        else:
            report.ok(f"nonsense input correctly rejected ({result['reason']})")


def check_fame_model(conn, report: Report) -> None:
    print("\n[6] Fame model / difficulty bands")

    banded = conn.execute(
        "SELECT COUNT(*) AS n FROM clubs WHERE difficulty_band IS NOT NULL"
    ).fetchone()["n"]
    if not banded:
        report.fail("no clubs have a difficulty band — run compute_fame_scores.py")
        return
    report.ok(f"{banded:,} clubs have a difficulty band")

    for name in EXPECTED_EASY_CLUBS:
        club = find_club(conn, name)
        if not club:
            report.warn(f"{name} not in database — cannot check its difficulty band")
            continue
        if club["difficulty_band"] == "easy":
            report.ok(f"{club['canonical_name']} rated easy (fame {club['fame_score']:.1f})")
        else:
            report.fail(f"{club['canonical_name']} rated {club['difficulty_band']!r} "
                        f"(fame {club['fame_score']:.1f}) — expected easy")

    for name in EXPECTED_NOT_EASY_CLUBS:
        club = find_club(conn, name)
        if not club:
            report.warn(f"{name} not in database — cannot check its difficulty band")
            continue
        if club["difficulty_band"] in ("medium", "hard"):
            report.ok(f"{club['canonical_name']} rated {club['difficulty_band']} "
                      f"(fame {club['fame_score']:.1f})")
        else:
            report.fail(f"{club['canonical_name']} rated easy (fame {club['fame_score']:.1f}) "
                        f"— expected medium or hard")


def check_practice_pairs(conn, report: Report) -> None:
    print("\n[7] Practice pairs")

    total = conn.execute("SELECT COUNT(*) AS n FROM practice_pairs").fetchone()["n"]
    if not total:
        report.fail("no practice pairs — run build_practice_pairs.py")
        return
    report.ok(f"{total:,} practice pairs available")

    for band in ("easy", "medium", "hard"):
        count = conn.execute(
            "SELECT COUNT(*) AS n FROM practice_pairs WHERE difficulty = ?", (band,)
        ).fetchone()["n"]
        if count == 0:
            report.fail(f"no {band} practice pairs")
        else:
            report.ok(f"{count:,} {band} pairs")

    # The critical invariant: EVERY served pair must be answerable. Re-derive
    # the mutual count independently rather than trusting the stored one.
    bad = 0
    for band in ("easy", "medium", "hard"):
        for _ in range(10):
            pair = random_practice_pair(conn, band)
            if not pair:
                break
            actual = count_mutual_players(conn, pair["club_a_id"], pair["club_b_id"])
            if actual == 0:
                bad += 1
    if bad:
        report.fail(f"{bad} sampled practice pairs have ZERO mutual players — unanswerable questions")
    else:
        report.ok("every sampled practice pair has at least one valid answer")


def main() -> int:
    if not db.database_exists():
        print("No database found. Run build_database.py first.")
        return 1

    conn = db.connect()
    report = Report()

    print("=" * 72)
    print("321 FOOTBALL CHALLENGE — DATABASE VERIFICATION")
    print("=" * 72)

    check_population(conn, report)
    check_integrity(conn, report)
    check_coverage(conn, report)
    check_golden_mutuals(conn, report)
    check_answer_matching(conn, report)
    check_fame_model(conn, report)
    check_practice_pairs(conn, report)

    print("\n" + "=" * 72)
    print(f"{report.passed} passed, {report.failed} failed, {report.warnings} warnings")
    print("=" * 72)

    if report.failures:
        print("\nFAILURES — these need fixing before the database is usable:")
        for failure in report.failures:
            print(f"  - {failure}")

    if report.warns:
        print("\nWarnings — worth a look, not necessarily broken:")
        for warning in report.warns:
            print(f"  - {warning}")

    conn.close()
    return 1 if report.failed else 0


if __name__ == "__main__":
    sys.exit(main())
