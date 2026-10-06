"""
Look up one player and show everything the database knows about him.

Built for exactly the situation where a golden test fails and you need to know
WHY: is the player missing entirely, is one of his spells missing, or is his
club stored under a name you didn't expect?

    python inspect_player.py "David Beckham"
    python inspect_player.py beckham
    python inspect_player.py Q10520                                  # by Wikidata id
    python inspect_player.py "Real Madrid" --club
    python inspect_player.py "Real Madrid" --mutuals "Manchester United"
"""

from __future__ import annotations

import re
import sys

import db
from names import normalize_name


def show_player(conn, query: str) -> None:
    # A bare Q-number is looked up by Wikidata ID, not by name. Essential when
    # a player is stored WITHOUT a usable name — searching for "beckham" can't
    # find a row whose name is literally "Q10520".
    if re.fullmatch(r"Q\d+", query.strip(), re.IGNORECASE):
        qid = query.strip().upper()
        row = conn.execute(
            "SELECT * FROM players WHERE wikidata_qid = ?", (qid,)
        ).fetchone()
        if not row:
            print(f"{qid} is NOT in the players table at all.")
            return
        print(f"{qid} IS in the players table.")
        _print_player(conn, row)
        return

    normalized = normalize_name(query)
    tokens = [t for t in normalized.split() if len(t) >= 4]

    # Match on the full name, on any stored alias, on a substring, AND on each
    # individual word. That last one matters: Wikidata often stores a full
    # legal name ("David Robert Joseph Beckham"), which contains neither
    # "david beckham" nor anything a naive substring search would find.
    clauses = ["p.normalized_name = ?", "a.normalized_alias = ?", "p.normalized_name LIKE ?"]
    params: list[str] = [normalized, normalized, f"%{normalized}%"]
    for token in tokens:
        clauses.append("a.normalized_alias = ?")
        params.append(token)
        clauses.append("p.normalized_name LIKE ?")
        params.append(f"%{token}%")

    rows = conn.execute(f"""
        SELECT DISTINCT p.* FROM players p
        LEFT JOIN player_aliases a ON a.player_id = p.player_id
        WHERE {" OR ".join(clauses)}
        ORDER BY p.fame_score DESC
        LIMIT 10
    """, params).fetchall()

    if not rows:
        print(f"No player matching {query!r}.")
        print("\nThat means he was never scraped at all — check whether any club")
        print("he played for is in the database, and whether that club's scrape")
        print("was flagged 'needs_review'.")
        return

    for player in rows:
        print("=" * 70)
        _print_player(conn, player)


def _print_player(conn, player) -> None:
    print(f"{player['display_name']}   [{player['wikidata_qid']}]")
    print(f"  nationality : {player['nationality'] or '(unknown)'}")
    print(f"  fame score  : {player['fame_score']:.1f}")
    print(f"  clubs       : {player['club_count']}")

    columns = {row["name"] for row in conn.execute("PRAGMA table_info(players)")}
    if "needs_label" in columns:
        flag = player["needs_label"]
        print(f"  needs name  : {'YES — name never resolved' if flag else 'no'}")

    spells = conn.execute("""
        SELECT c.canonical_name, c.wikidata_qid, c.difficulty_band,
               s.start_year, s.end_year, s.date_confidence
        FROM player_club_spells s
        JOIN clubs c ON c.club_id = s.club_id
        WHERE s.player_id = ?
        ORDER BY s.start_year
    """, (player["player_id"],)).fetchall()

    print(f"\n  SPELLS ({len(spells)}):")
    for spell in spells:
        years = f"{spell['start_year'] or '?'}-{spell['end_year'] or 'now'}"
        print(f"    {years:<12} {spell['canonical_name']:<34} "
              f"[{spell['wikidata_qid']}] {spell['date_confidence']}")

    aliases = conn.execute(
        "SELECT alias_name FROM player_aliases WHERE player_id = ? LIMIT 12",
        (player["player_id"],),
    ).fetchall()
    if aliases:
        print(f"\n  ACCEPTED SPELLINGS: {', '.join(a['alias_name'] for a in aliases)}")
    else:
        print("\n  ACCEPTED SPELLINGS: none — this player cannot be typed as an answer")
    print()


def show_club(conn, query: str) -> None:
    normalized = normalize_name(query)
    rows = conn.execute("""
        SELECT * FROM clubs
        WHERE normalized_name LIKE ?
        ORDER BY sitelink_count DESC, fame_score DESC LIMIT 10
    """, (f"%{normalized}%",)).fetchall()

    if not rows:
        print(f"No club matching {query!r}.")
        return

    for club in rows:
        print("=" * 70)
        print(f"{club['canonical_name']}   [{club['wikidata_qid']}]")
        print(f"  fame {club['fame_score']:.1f} ({club['difficulty_band']}), "
              f"{club['distinct_player_count']} players, "
              f"{club['trophy_count']} trophies, "
              f"scrape status: {club['scrape_status']}")

        leagues = conn.execute("""
            SELECT l.name, cl.first_season, cl.last_season
            FROM club_leagues cl JOIN leagues l ON l.league_id = cl.league_id
            WHERE cl.club_id = ?
        """, (club["club_id"],)).fetchall()
        for league in leagues:
            span = f"{league['first_season'] or '?'}-{league['last_season'] or '?'}"
            print(f"    {league['name']} ({span})")
        print()


def show_mutuals(conn, name_a: str, name_b: str) -> None:
    """
    The full answer key for a club pair — every player the game would accept.

    Useful well beyond debugging: this is what you check the UI against, and
    it's the fastest way to see whether a pair makes a fair question.
    """
    def find(name: str):
        norm = normalize_name(name)
        row = conn.execute("""
            SELECT club_id, canonical_name, wikidata_qid FROM clubs
            WHERE normalized_name LIKE ? AND is_reserve_or_b_team = 0
            ORDER BY fame_score DESC LIMIT 1
        """, (f"{norm}%",)).fetchone()
        if row:
            return row
        return conn.execute("""
            SELECT club_id, canonical_name, wikidata_qid FROM clubs
            WHERE normalized_name LIKE ? AND is_reserve_or_b_team = 0
            ORDER BY fame_score DESC LIMIT 1
        """, (f"%{norm}%",)).fetchone()

    club_a, club_b = find(name_a), find(name_b)
    if not club_a or not club_b:
        print(f"Could not resolve {'both clubs' if not club_a and not club_b else name_a if not club_a else name_b}.")
        return

    print("=" * 70)
    print(f"{club_a['canonical_name']} [{club_a['wikidata_qid']}]")
    print(f"  x  {club_b['canonical_name']} [{club_b['wikidata_qid']}]")
    print("=" * 70)

    rows = conn.execute("""
        SELECT p.display_name, p.wikidata_qid, p.nationality, p.fame_score
        FROM players p
        WHERE p.player_id IN (
            SELECT player_id FROM player_club_spells WHERE club_id = ?
            INTERSECT
            SELECT player_id FROM player_club_spells WHERE club_id = ?
        )
        ORDER BY p.fame_score DESC
    """, (club_a["club_id"], club_b["club_id"])).fetchall()

    print(f"\n{len(rows)} accepted answer(s):\n")
    for row in rows:
        unnamed = " <- NO NAME, cannot be typed" if row["display_name"].startswith("Q") \
            and row["display_name"][1:].isdigit() else ""
        print(f"  {row['fame_score']:5.1f}  {row['display_name']:<34} "
              f"[{row['wikidata_qid']}]{unnamed}")


def main() -> int:
    if len(sys.argv) < 2:
        print(__doc__)
        return 1

    query = sys.argv[1]
    conn = db.connect()

    if "--mutuals" in sys.argv:
        index = sys.argv.index("--mutuals")
        if index + 1 >= len(sys.argv):
            print("--mutuals needs a second club name")
            conn.close()
            return 1
        show_mutuals(conn, query, sys.argv[index + 1])
    elif "--club" in sys.argv:
        show_club(conn, query)
    else:
        show_player(conn, query)

    conn.close()
    return 0


if __name__ == "__main__":
    sys.exit(main())
