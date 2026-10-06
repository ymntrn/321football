"""
Offline test suite — exercises everything that does NOT need the internet.

Builds a small synthetic database modelled on real football relationships,
then runs the real scoring, pairing, and query code against it. This is how
you can confirm the logic is sound before spending hours scraping, and how
you check you haven't broken anything when you change a rule in config.py.

    python test_offline.py
"""

from __future__ import annotations

import os
import sys
import tempfile

import config
import db
from names import normalize_name, name_variants
from scrape_players import spell_passes_cutoff, date_confidence_for
from scrape_clubs import looks_like_reserve_team

PASSED = 0
FAILED = 0


def check(condition: bool, label: str, detail: str = "") -> None:
    global PASSED, FAILED
    if condition:
        PASSED += 1
        print(f"  PASS  {label}")
    else:
        FAILED += 1
        print(f"  FAIL  {label}" + (f"  <- {detail}" if detail else ""))


# -------------------------------------------------------------------------
# Synthetic fixture: real relationships, small scale
# -------------------------------------------------------------------------
CLUBS = [
    # (qid, name, distinct_players_padding, trophies, top_div_seasons)
    ("Q_INTER",   "Inter Milan",       120, 40, 34),
    ("Q_GALA",    "Galatasaray",        90, 60, 34),
    ("Q_REAL",    "Real Madrid",       140, 90, 34),
    ("Q_BARCA",   "Barcelona",         135, 85, 34),
    ("Q_MANU",    "Manchester United", 130, 60, 34),
    ("Q_CHELSEA", "Chelsea",           110, 35, 32),
    ("Q_FENER",   "Fenerbahçe",         85, 45, 34),
    ("Q_BASAK",   "Başakşehir",         25,  2, 15),
    ("Q_SHEFF",   "Sheffield United",   30,  3,  8),
    ("Q_BURNLEY", "Burnley",            28,  2,  9),
]

# (qid, name, nationality, [club qids])
PLAYERS = [
    ("Q_SNEIJDER", "Wesley Sneijder",     "Netherlands", ["Q_REAL", "Q_INTER", "Q_GALA"]),
    ("Q_MELO",     "Felipe Melo",         "Brazil",      ["Q_INTER", "Q_GALA"]),
    ("Q_SUKUR",    "Hakan Şükür",         "Turkey",      ["Q_GALA", "Q_INTER"]),
    ("Q_DROGBA",   "Didier Drogba",       "Ivory Coast", ["Q_CHELSEA", "Q_GALA"]),
    ("Q_RONALDO",  "Ronaldo",             "Brazil",      ["Q_INTER", "Q_REAL", "Q_BARCA"]),
    ("Q_FIGO",     "Luís Figo",           "Portugal",    ["Q_BARCA", "Q_REAL", "Q_INTER"]),
    ("Q_OZIL",     "Mesut Özil",          "Germany",     ["Q_REAL", "Q_BASAK"]),
    ("Q_RVP",      "Robin van Persie",    "Netherlands", ["Q_MANU", "Q_FENER"]),
    ("Q_BECKHAM",  "David Beckham",       "England",     ["Q_MANU", "Q_REAL"]),
    ("Q_CARLOS",   "Roberto Carlos",      "Brazil",      ["Q_REAL", "Q_FENER", "Q_INTER"]),
    ("Q_JOURNEY",  "Journeyman Nobody",   "England",     ["Q_SHEFF", "Q_BURNLEY"]),
]


def build_fixture(path: str):
    conn = db.connect(path)
    db.init_schema(conn)

    league_id = db.upsert_league(conn, key="test", qid="Q_TEST", name="Test League",
                                 country="Testland", country_qid="Q_TL", tier=1, region="Europe")

    club_ids = {}
    for qid, name, padding, trophies, seasons in CLUBS:
        club_id = db.upsert_club(conn, qid=qid, name=name, country="Testland", founded_year=1900)
        db.add_club_alias(conn, club_id, name)
        db.link_club_league(conn, club_id, league_id, 2000)
        conn.execute("UPDATE clubs SET trophy_count = ?, top_division_seasons = ? WHERE club_id = ?",
                     (trophies, seasons, club_id))
        club_ids[qid] = club_id

        # Padding players give each club a realistic squad size, which is what
        # the fame model's "depth of history" signal reads.
        for i in range(padding):
            pid = db.upsert_player(conn, qid=f"{qid}_pad{i}", full_name=f"Padding {name} {i}")
            db.insert_spell(conn, player_id=pid, club_id=club_id,
                            start_year=2000 + (i % 20), end_year=2001 + (i % 20),
                            date_confidence="exact", statement_id=None)

    player_ids = {}
    for qid, name, nationality, clubs in PLAYERS:
        pid = db.upsert_player(conn, qid=qid, full_name=name, nationality=nationality)
        for variant in name_variants(name):
            db.add_player_alias(conn, pid, variant)
        player_ids[qid] = pid
        for index, club_qid in enumerate(clubs):
            db.insert_spell(conn, player_id=pid, club_id=club_ids[club_qid],
                            start_year=2000 + index * 3, end_year=2003 + index * 3,
                            date_confidence="exact", statement_id=None)

    conn.commit()
    db.refresh_counters(conn)
    return conn, club_ids, player_ids


# -------------------------------------------------------------------------
# Tests
# -------------------------------------------------------------------------
def test_normalization() -> None:
    print("\n[1] Name normalization")
    cases = [
        ("Mesut Özil", "mesut ozil"),
        ("İlkay Gündoğan", "ilkay gundogan"),
        ("Hakan Şükür", "hakan sukur"),
        ("N'Golo Kanté", "ngolo kante"),
        ("Zlatan Ibrahimović", "zlatan ibrahimovic"),
        ("  Wesley   Sneijder  ", "wesley sneijder"),
        ("WESLEY SNEIJDER", "wesley sneijder"),
    ]
    for raw, expected in cases:
        actual = normalize_name(raw)
        check(actual == expected, f"{raw!r} -> {expected!r}", f"got {actual!r}")

    variants = name_variants("Wesley Sneijder")
    check("sneijder" in variants, "surname is generated as a variant", str(variants))
    check("wesley sneijder" in variants, "full name is a variant", str(variants))


def test_cutoff_rule() -> None:
    print(f"\n[2] Cutoff rule ({config.INCLUDE_SPELL_RULE!r}, cutoff {config.CUTOFF_YEAR})")
    original = config.INCLUDE_SPELL_RULE

    config.INCLUDE_SPELL_RULE = "overlaps"
    check(spell_passes_cutoff(1988, 1992)[0], "1988-1992 kept (overlaps the cutoff)")
    check(not spell_passes_cutoff(1980, 1985)[0], "1980-1985 dropped (entirely pre-cutoff)")
    check(spell_passes_cutoff(2010, None)[0], "2010-present kept (current club counts)")
    check(spell_passes_cutoff(1995, 1998)[0], "1995-1998 kept")

    config.INCLUDE_SPELL_RULE = "starts_after"
    check(not spell_passes_cutoff(1988, 1992)[0], "1988-1992 dropped under 'starts_after'")
    check(spell_passes_cutoff(1995, 1998)[0], "1995-1998 kept under 'starts_after'")

    config.INCLUDE_SPELL_RULE = original

    check(date_confidence_for(1990, 1995) == "exact", "both dates -> 'exact'")
    check(date_confidence_for(1990, None) == "partial", "one date -> 'partial'")
    check(date_confidence_for(None, None) == "unknown", "no dates -> 'unknown'")


def test_reserve_detection() -> None:
    print("\n[3] Reserve / B team detection")
    positives = [
        ("FC Barcelona B", None, None),
        ("Real Madrid Castilla", None, None),
        ("Bayern Munich II", None, None),
        ("Manchester United Reserves", None, None),
        ("Ajax U21", None, None),
        ("Some Club", None, "reserve team"),
    ]
    for label, part_of, type_label in positives:
        is_reserve, method = looks_like_reserve_team(label, part_of, type_label)
        check(is_reserve, f"{label!r} detected as reserve/B ({method})")

    negatives = [
        "Hertha BSC", "Inter Milan", "Galatasaray", "Barcelona",
        "Bayer Leverkusen", "Brighton & Hove Albion", "Sheffield United",
    ]
    for label in negatives:
        is_reserve, _ = looks_like_reserve_team(label, None, None)
        check(not is_reserve, f"{label!r} correctly NOT flagged as reserve")

    # THE REGRESSION THAT MATTERS: multi-sport clubs are "part of" a parent
    # institution on Wikidata. If P361 alone counts as a B-team signal, these
    # first teams get silently deleted from the database.
    multisport = [
        "Galatasaray S.K.", "Fenerbahçe S.K.", "Beşiktaş J.K.",
        "FC Barcelona", "FC Bayern Munich", "Olympiacos F.C.",
    ]
    for label in multisport:
        is_reserve, method = looks_like_reserve_team(
            label, "http://www.wikidata.org/entity/Q123", None)
        check(not is_reserve,
              f"{label!r} survives despite being 'part of' a parent club",
              f"wrongly flagged via {method}")

    # A real B-team that is ALSO part of its parent is still caught.
    is_reserve, method = looks_like_reserve_team(
        "FC Barcelona B", "http://www.wikidata.org/entity/Q123", None)
    check(is_reserve and method == "part_of+label",
          "a genuine B-team with a parent is still detected", f"method={method}")


def test_fame_and_bands(conn) -> None:
    print("\n[4] Fame scoring and difficulty bands")
    import compute_fame_scores

    compute_fame_scores.compute_club_fame(conn)
    compute_fame_scores.compute_player_fame(conn)

    def band(name: str) -> tuple[str, float]:
        row = conn.execute(
            "SELECT difficulty_band, fame_score FROM clubs WHERE canonical_name = ?", (name,)
        ).fetchone()
        return row["difficulty_band"], row["fame_score"]

    real_band, real_score = band("Real Madrid")
    basak_band, basak_score = band("Başakşehir")
    check(real_score > basak_score,
          f"Real Madrid ({real_score:.1f}) scores above Başakşehir ({basak_score:.1f})")
    check(real_band == "easy", f"Real Madrid is in the easy band (got {real_band!r})")
    check(basak_band in ("medium", "hard"),
          f"Başakşehir is not easy (got {basak_band!r})")

    bands = {row["difficulty_band"] for row in
             conn.execute("SELECT DISTINCT difficulty_band FROM clubs")}
    check(bands <= {"easy", "medium", "hard"}, f"only valid bands assigned: {bands}")


def test_practice_pairs(conn) -> None:
    print("\n[5] Practice pairs")
    import build_practice_pairs
    from game_queries import count_mutual_players, random_practice_pair

    build_practice_pairs.build(conn)

    total = conn.execute("SELECT COUNT(*) AS n FROM practice_pairs").fetchone()["n"]
    check(total > 0, f"{total} practice pairs generated")

    # The invariant that matters: no pair may be unanswerable.
    bad = []
    for row in conn.execute("SELECT club_a_id, club_b_id FROM practice_pairs"):
        if count_mutual_players(conn, row["club_a_id"], row["club_b_id"]) == 0:
            bad.append((row["club_a_id"], row["club_b_id"]))
    check(not bad, f"every practice pair has at least one valid answer ({len(bad)} bad)")

    ordering = conn.execute(
        "SELECT COUNT(*) AS n FROM practice_pairs WHERE club_a_id >= club_b_id"
    ).fetchone()["n"]
    check(ordering == 0, "pairs are canonically ordered (no A/B + B/A duplicates)")


def test_game_queries(conn, club_ids) -> None:
    print("\n[6] Game queries")
    from game_queries import (
        get_mutual_players, validate_answer, search_clubs, check_pair_is_playable,
    )

    inter, gala = club_ids["Q_INTER"], club_ids["Q_GALA"]
    real, barca = club_ids["Q_REAL"], club_ids["Q_BARCA"]
    basak, sheff = club_ids["Q_BASAK"], club_ids["Q_SHEFF"]

    mutuals = {m["display_name"] for m in get_mutual_players(conn, inter, gala)}
    check("Wesley Sneijder" in mutuals, "Sneijder found for Inter x Galatasaray", str(mutuals))
    check("Felipe Melo" in mutuals, "Felipe Melo found for Inter x Galatasaray")
    check("Hakan Şükür" in mutuals, "Hakan Şükür found for Inter x Galatasaray")
    check("Didier Drogba" not in mutuals, "Drogba correctly NOT in Inter x Galatasaray")

    real_barca = {m["display_name"] for m in get_mutual_players(conn, real, barca)}
    check("Ronaldo" in real_barca and "Luís Figo" in real_barca,
          "Ronaldo and Figo found for Real Madrid x Barcelona", str(real_barca))

    # Typed answers, including the spellings a rushed player actually types
    for typed in ["Wesley Sneijder", "sneijder", "SNEIJDER", " Sneijder "]:
        result = validate_answer(conn, typed, inter, gala)
        check(result["correct"], f"answer {typed!r} accepted for Inter x Galatasaray",
              result["reason"])

    for typed in ["Hakan Sukur", "sukur", "Şükür"]:
        result = validate_answer(conn, typed, inter, gala)
        check(result["correct"], f"answer {typed!r} accepted (Turkish folding)", result["reason"])

    # A real player who did NOT play for both must be rejected — with the
    # right reason, so the UI can say the right thing.
    result = validate_answer(conn, "Didier Drogba", inter, gala)
    check(not result["correct"] and result["reason"] == "not_a_mutual_player",
          "real-but-wrong player rejected as 'not_a_mutual_player'", str(result))

    result = validate_answer(conn, "Xyz Nobody", inter, gala)
    check(not result["correct"] and result["reason"] == "unknown_player",
          "unknown name rejected as 'unknown_player'", str(result))

    result = validate_answer(conn, "ab", inter, gala)
    check(not result["correct"] and result["reason"] == "too_short",
          "very short input rejected as 'too_short'", str(result))

    # Club search
    results = search_clubs(conn, "real")
    check(any(r["canonical_name"] == "Real Madrid" for r in results),
          "search 'real' finds Real Madrid", str([r["canonical_name"] for r in results]))

    results = search_clubs(conn, "basaksehir")
    check(any(r["canonical_name"] == "Başakşehir" for r in results),
          "accent-free search 'basaksehir' finds Başakşehir",
          str([r["canonical_name"] for r in results]))

    # PvP guard: two clubs with nothing in common must be reported unplayable
    playable = check_pair_is_playable(conn, basak, sheff)
    check(not playable["playable"],
          "Başakşehir x Sheffield United correctly reported unplayable (no mutual players)",
          str(playable))

    playable = check_pair_is_playable(conn, inter, gala)
    check(playable["playable"] and playable["mutual_count"] >= 3,
          "Inter x Galatasaray reported playable", str(playable))


def test_same_surname_disambiguation(conn, club_ids) -> None:
    """
    Two different players sharing a surname must not be confused, and a bare
    common surname must not become a blind-guess cheat code.
    """
    print("\n[7] Same-surname disambiguation")
    from game_queries import validate_answer
    from names import name_variants

    inter, gala = club_ids["Q_INTER"], club_ids["Q_GALA"]
    other = club_ids["Q_BURNLEY"]

    def add_player(name, clubs, qid):
        pid = db.upsert_player(conn, qid=qid, full_name=name)
        for variant in name_variants(name):
            db.add_player_alias(conn, pid, variant)
        for club_id in clubs:
            db.insert_spell(conn, player_id=pid, club_id=club_id,
                            start_year=2005, end_year=2008,
                            date_confidence="exact", statement_id=None)
        return pid

    # Namesakes: one links the two clubs, the other doesn't.
    add_player("David Santiago Jose Silva", [inter, gala], "Q_SILVA_A")
    add_player("David de Santos Silva", [other], "Q_SILVA_B")
    conn.commit()
    db.refresh_counters(conn)

    result = validate_answer(conn, "David Santiago Jose Silva", inter, gala)
    check(result["correct"], "the namesake who DID play for both is accepted")

    result = validate_answer(conn, "David de Santos Silva", inter, gala)
    check(not result["correct"] and result["reason"] == "not_a_mutual_player",
          "the namesake who did NOT is rejected, not credited via his surname",
          str(result))

    result = validate_answer(conn, "David Silva", inter, gala)
    check(result["correct"] and result["player"]["display_name"] == "David Santiago Jose Silva",
          "the shared short form credits the player who actually qualifies",
          str(result))

    # A rare surname stays usable on its own.
    result = validate_answer(conn, "Silva", inter, gala)
    check(result["correct"], "a rare surname alone is still accepted", str(result))

    # Make it common, and it must stop being a free point.
    for i in range(config.MAX_PLAYERS_SHARING_SURNAME + 2):
        add_player(f"Filler{i} Silva", [other], f"Q_FILLER_{i}")
    conn.commit()

    result = validate_answer(conn, "Silva", inter, gala)
    check(not result["correct"] and result["reason"] == "surname_too_common",
          "once the surname is common, typing it alone is refused as ambiguous",
          str(result))

    result = validate_answer(conn, "David Silva", inter, gala)
    check(result["correct"],
          "adding a first name still works when the surname is common",
          str(result))


def test_idempotency(conn, club_ids) -> None:
    print("\n[8] Re-run safety")
    before = conn.execute("SELECT COUNT(*) AS n FROM player_club_spells").fetchone()["n"]

    pid = conn.execute("SELECT player_id FROM players WHERE wikidata_qid = 'Q_SNEIJDER'").fetchone()["player_id"]
    inserted = db.insert_spell(conn, player_id=pid, club_id=club_ids["Q_INTER"],
                               start_year=2003, end_year=2006,
                               date_confidence="exact", statement_id=None)
    conn.commit()

    after = conn.execute("SELECT COUNT(*) AS n FROM player_club_spells").fetchone()["n"]
    check(not inserted and before == after,
          "re-inserting an identical spell is a no-op (safe to re-run the scraper)",
          f"{before} -> {after}")


def main() -> int:
    print("=" * 72)
    print("321 FOOTBALL CHALLENGE — OFFLINE TEST SUITE")
    print("=" * 72)

    test_normalization()
    test_cutoff_rule()
    test_reserve_detection()

    handle, path = tempfile.mkstemp(suffix=".db")
    os.close(handle)
    os.remove(path)

    try:
        conn, club_ids, _ = build_fixture(path)
        test_fame_and_bands(conn)
        test_practice_pairs(conn)
        test_game_queries(conn, club_ids)
        test_same_surname_disambiguation(conn, club_ids)
        test_idempotency(conn, club_ids)
        conn.close()
    finally:
        for suffix in ("", "-wal", "-shm"):
            if os.path.exists(path + suffix):
                os.remove(path + suffix)

    print("\n" + "=" * 72)
    print(f"{PASSED} passed, {FAILED} failed")
    print("=" * 72)
    return 1 if FAILED else 0


if __name__ == "__main__":
    sys.exit(main())
