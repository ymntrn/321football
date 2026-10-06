"""
The runtime query layer — everything the game itself asks the database.

This is the reference implementation. When you build the Flutter client you'll
port these queries to Dart (sqflite), but keep them behaving identically:
this module is what verify.py tests against, so if the Dart version matches
this, it's correct.

The four things the game needs:
    search_clubs()          the team search bar during the pick phase
    get_mutual_players()    every valid answer for a pair of clubs
    validate_answer()       does this typed string win the point?
    random_practice_pair()  a guaranteed-answerable Practice question
"""

from __future__ import annotations

import sqlite3

import config
import db
from names import normalize_name, surname_key


# -------------------------------------------------------------------------
# Team search (pick phase)
# -------------------------------------------------------------------------
def search_clubs(conn: sqlite3.Connection, query: str, limit: int = 20) -> list[dict]:
    """
    Search clubs for the team-picker. Ranks exact prefix matches above
    substring matches, and more famous clubs above obscure ones — so typing
    "real" surfaces Real Madrid before Real Oviedo.
    """
    normalized = normalize_name(query)
    if len(normalized) < 2:
        return []

    rows = conn.execute("""
        SELECT DISTINCT c.club_id, c.canonical_name, c.country, c.fame_score
        FROM clubs c
        LEFT JOIN club_aliases a ON a.club_id = c.club_id
        WHERE c.is_reserve_or_b_team = 0
          AND (c.normalized_name LIKE ? OR a.normalized_alias LIKE ?)
        ORDER BY
            CASE WHEN c.normalized_name LIKE ? THEN 0 ELSE 1 END,
            c.fame_score DESC
        LIMIT ?
    """, (f"%{normalized}%", f"%{normalized}%", f"{normalized}%", limit)).fetchall()

    return [dict(row) for row in rows]


# -------------------------------------------------------------------------
# Mutual players
# -------------------------------------------------------------------------
def get_mutual_players(conn: sqlite3.Connection, club_a_id: int, club_b_id: int) -> list[dict]:
    """Every player who played for both clubs. This is the answer key."""
    rows = conn.execute("""
        SELECT p.player_id, p.display_name, p.nationality, p.fame_score
        FROM players p
        WHERE p.player_id IN (
            SELECT player_id FROM player_club_spells WHERE club_id = ?
            INTERSECT
            SELECT player_id FROM player_club_spells WHERE club_id = ?
        )
        ORDER BY p.fame_score DESC
    """, (club_a_id, club_b_id)).fetchall()
    return [dict(row) for row in rows]


def count_mutual_players(conn: sqlite3.Connection, club_a_id: int, club_b_id: int) -> int:
    row = conn.execute("""
        SELECT COUNT(*) AS n FROM (
            SELECT player_id FROM player_club_spells WHERE club_id = ?
            INTERSECT
            SELECT player_id FROM player_club_spells WHERE club_id = ?
        )
    """, (club_a_id, club_b_id)).fetchone()
    return row["n"]


# -------------------------------------------------------------------------
# Answer validation  (the hot path — runs while the clock is ticking)
# -------------------------------------------------------------------------
def count_players_sharing_name(conn: sqlite3.Connection, normalized: str) -> int:
    """How many distinct players answer to this exact string?"""
    row = conn.execute(
        "SELECT COUNT(DISTINCT player_id) AS n FROM player_aliases WHERE normalized_alias = ?",
        (normalized,),
    ).fetchone()
    return row["n"] if row else 0


def _candidate_player_ids(conn: sqlite3.Connection, typed: str) -> tuple[list[int], str]:
    """
    Resolve a typed string to candidate players. Returns (ids, reason).

    Matching is EXACT, on either the full normalized name or a stored alias.
    There is deliberately no fuzzy/edit-distance matching: under a 10-second
    clock a near-miss that silently counts as correct feels worse than a
    rejection, and it would let "ronaldo" claim a point meant for
    "ronaldinho".

    Two ambiguity cases matter, and they resolve differently:

    MULTI-WORD input is taken at its word. "David de Santos Silva" matches
    that player and not his namesake "David Santiago Jose Silva", because the
    typist asserted a first name. Typing the shorter "David Silva" matches
    BOTH — and that's correct, since if either of them links the two clubs,
    "David Silva" is a true answer. The matched player is returned so the UI
    can show who was credited.

    SINGLE-WORD input is where the exploit lives. Every player stores his bare
    surname as an alias, so "Silva" alone would match hundreds of players, and
    a blind guess would score whenever any one of them happened to link the
    clubs. So a bare surname shared by more than
    config.MAX_PLAYERS_SHARING_SURNAME players is refused as too ambiguous —
    unless it's someone's actual full name ("Ronaldinho", "Kaká", "Pelé"),
    which is definitive and always accepted.
    """
    normalized = normalize_name(typed)
    if len(normalized) < 3:
        return [], "too_short"

    ids: list[int] = []
    seen: set[int] = set()

    def add(rows):
        for row in rows:
            if row["player_id"] not in seen:
                seen.add(row["player_id"])
                ids.append(row["player_id"])

    # 1. The whole string IS somebody's name — definitive, never ambiguous.
    exact = conn.execute(
        "SELECT player_id FROM players WHERE normalized_name = ?", (normalized,)
    ).fetchall()
    add(exact)

    # 2. Alias match. Guard the single-word case against common surnames.
    if not exact and len(normalized.split()) == 1:
        shared = count_players_sharing_name(conn, normalized)
        if shared > config.MAX_PLAYERS_SHARING_SURNAME:
            return [], "surname_too_common"

    add(conn.execute(
        "SELECT player_id FROM player_aliases WHERE normalized_alias = ?", (normalized,)
    ).fetchall())

    return ids, "ok" if ids else "unknown_player"


def validate_answer(conn: sqlite3.Connection, typed: str,
                    club_a_id: int, club_b_id: int) -> dict:
    """
    Judge a typed answer.

    Returns a dict with:
        correct : bool
        reason  : 'correct' | 'not_a_mutual_player' | 'unknown_player'
                  | 'too_short' | 'surname_too_common'
        player  : the matched player record, when we matched one

    Each rejection reason wants different UI copy, and conflating them will
    make players furious at the wrong thing:
        unknown_player      "we don't have that player"
        not_a_mutual_player "he never played for both"
        surname_too_common  "which one? add a first name"
    """
    candidates, reason = _candidate_player_ids(conn, typed)
    if not candidates:
        return {"correct": False, "reason": reason, "player": None}

    placeholders = ",".join("?" * len(candidates))
    row = conn.execute(f"""
        SELECT p.player_id, p.display_name, p.nationality, p.fame_score
        FROM players p
        WHERE p.player_id IN ({placeholders})
          AND p.player_id IN (
              SELECT player_id FROM player_club_spells WHERE club_id = ?
              INTERSECT
              SELECT player_id FROM player_club_spells WHERE club_id = ?
          )
        ORDER BY p.fame_score DESC
        LIMIT 1
    """, (*candidates, club_a_id, club_b_id)).fetchone()

    if row:
        return {"correct": True, "reason": "correct", "player": dict(row)}

    known = conn.execute(
        f"SELECT player_id, display_name FROM players WHERE player_id IN ({placeholders}) LIMIT 1",
        candidates,
    ).fetchone()
    return {
        "correct": False,
        "reason": "not_a_mutual_player",
        "player": dict(known) if known else None,
    }


# -------------------------------------------------------------------------
# Practice mode
# -------------------------------------------------------------------------
def random_practice_pair(conn: sqlite3.Connection, difficulty: str) -> dict | None:
    """
    Draw a random Practice question. Every row in practice_pairs is
    guaranteed answerable, so this can never serve an impossible question.
    """
    row = conn.execute("""
        SELECT pp.pair_id, pp.mutual_count,
               ca.club_id AS club_a_id, ca.canonical_name AS club_a_name,
               cb.club_id AS club_b_id, cb.canonical_name AS club_b_name
        FROM practice_pairs pp
        JOIN clubs ca ON ca.club_id = pp.club_a_id
        JOIN clubs cb ON cb.club_id = pp.club_b_id
        WHERE pp.difficulty = ?
        ORDER BY RANDOM() LIMIT 1
    """, (difficulty,)).fetchone()
    return dict(row) if row else None


# -------------------------------------------------------------------------
# PvP helper
# -------------------------------------------------------------------------
def check_pair_is_playable(conn: sqlite3.Connection, club_a_id: int, club_b_id: int) -> dict:
    """
    Call this the moment both PvP players have locked in their clubs, BEFORE
    the 3-2-1 countdown finishes. If it comes back playable=False, the round
    has no valid answer and you should void it rather than run a 10-second
    timer nobody can beat.
    """
    count = count_mutual_players(conn, club_a_id, club_b_id)
    return {"playable": count > 0, "mutual_count": count}


if __name__ == "__main__":
    conn = db.connect()
    print("Clubs:", conn.execute("SELECT COUNT(*) AS n FROM clubs").fetchone()["n"])
    print("Players:", conn.execute("SELECT COUNT(*) AS n FROM players").fetchone()["n"])
    print("Spells:", conn.execute("SELECT COUNT(*) AS n FROM player_club_spells").fetchone()["n"])
    conn.close()
