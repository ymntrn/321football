"""
STEP 5 — precompute every club pair that Practice mode is allowed to serve.

WHY THIS EXISTS
---------------
Practice mode picks two clubs automatically. If it picks a pair with no
mutual player, the question is unanswerable and the player just sits there
until the timer runs out, convinced the game is broken. Checking for mutual
players at runtime on the phone would mean generating pairs, querying,
discarding, and retrying — slow and non-deterministic.

So we do it once, here, offline: every pair in this table is guaranteed to
have at least the configured minimum number of mutual players, and Practice
mode just draws a random row.

(Note: this does NOT solve the same problem for PvP, where both players pick
their own club and can legitimately choose two clubs with nothing in common.
See the note in README.md — that one needs a gameplay rule, not a data fix.)
"""

from __future__ import annotations

import sys

import config
import db

MIN_MUTUAL_BY_BAND = {
    "easy": config.MIN_MUTUAL_PLAYERS_EASY,
    "medium": config.MIN_MUTUAL_PLAYERS_MEDIUM,
    "hard": config.MIN_MUTUAL_PLAYERS_HARD,
}

# One self-join over the spells table gives every co-occurring club pair and
# its mutual-player count in a single pass — far faster than testing pairs
# one at a time, and it naturally skips pairs with zero overlap.
PAIRS_QUERY = """
INSERT OR REPLACE INTO practice_pairs
    (club_a_id, club_b_id, difficulty, mutual_count, min_answer_fame)
SELECT
    s1.club_id                AS club_a_id,
    s2.club_id                AS club_b_id,
    ?                         AS difficulty,
    COUNT(DISTINCT s1.player_id) AS mutual_count,
    MIN(p.fame_score)         AS min_answer_fame
FROM player_club_spells s1
JOIN player_club_spells s2
      ON s2.player_id = s1.player_id
     AND s2.club_id  > s1.club_id
JOIN players p ON p.player_id = s1.player_id
JOIN clubs ca  ON ca.club_id  = s1.club_id
JOIN clubs cb  ON cb.club_id  = s2.club_id
WHERE ca.difficulty_band = ?
  AND cb.difficulty_band = ?
  AND ca.is_reserve_or_b_team = 0
  AND cb.is_reserve_or_b_team = 0
GROUP BY s1.club_id, s2.club_id
HAVING COUNT(DISTINCT s1.player_id) >= ?
"""


def build(conn) -> dict[str, int]:
    conn.execute("DELETE FROM practice_pairs")
    conn.commit()

    results: dict[str, int] = {}
    for band, minimum in MIN_MUTUAL_BY_BAND.items():
        print(f"  building {band} pairs (need >= {minimum} mutual players)...", flush=True)
        conn.execute(PAIRS_QUERY, (band, band, band, minimum))
        conn.commit()
        count = conn.execute(
            "SELECT COUNT(*) AS n FROM practice_pairs WHERE difficulty = ?", (band,)
        ).fetchone()["n"]
        results[band] = count
        print(f"      {count:,} pairs")

    return results


def report(conn) -> None:
    print("\nSample pairs per difficulty:")
    for band in MIN_MUTUAL_BY_BAND:
        print(f"\n  {band.upper()}")
        rows = conn.execute("""
            SELECT ca.canonical_name AS a, cb.canonical_name AS b, pp.mutual_count
            FROM practice_pairs pp
            JOIN clubs ca ON ca.club_id = pp.club_a_id
            JOIN clubs cb ON cb.club_id = pp.club_b_id
            WHERE pp.difficulty = ?
            ORDER BY RANDOM() LIMIT 5
        """, (band,)).fetchall()
        if not rows:
            print("      (none — check that fame scores and bands were computed)")
        for row in rows:
            print(f"      {row['a']} vs {row['b']}  ({row['mutual_count']} mutual)")


def main() -> int:
    conn = db.connect()

    banded = conn.execute(
        "SELECT COUNT(*) AS n FROM clubs WHERE difficulty_band IS NOT NULL"
    ).fetchone()["n"]
    if not banded:
        print("No clubs have a difficulty_band yet. Run compute_fame_scores.py first.")
        conn.close()
        return 1

    counts = build(conn)
    total = sum(counts.values())
    print(f"\n{total:,} practice pairs total")

    if total == 0:
        print("\nNothing was generated. That means no two clubs in the same band share")
        print("a player — almost certainly the spells table is empty or too thin.")
        conn.close()
        return 1

    report(conn)
    conn.close()
    return 0


if __name__ == "__main__":
    sys.exit(main())
