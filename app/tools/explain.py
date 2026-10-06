# -*- coding: utf-8 -*-
"""Timings for the suggestion query at different prefix lengths.

A short prefix matches a very large id set before the outer LIMIT applies,
which is the same failure shape as the old LIKE scan. Run this after touching
suggestPlayers.
"""
import sqlite3, sys, io, time
sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace")
db = r"C:\Users\PC\Documents\321-football\app\assets\db\321_football.db"
c = sqlite3.connect(db)

SQL = """
SELECT p.player_id, p.display_name, p.nationality, p.fame_score,
       (SELECT MIN(s.start_year) FROM player_club_spells s
         WHERE s.player_id = p.player_id) AS first_year,
       (SELECT MAX(s.end_year) FROM player_club_spells s
         WHERE s.player_id = p.player_id) AS last_year
FROM players p
WHERE p.player_id IN (
    SELECT player_id FROM players
      WHERE normalized_name >= ? AND normalized_name < ?
    UNION
    SELECT player_id FROM player_aliases
      WHERE normalized_alias >= ? AND normalized_alias < ?)
ORDER BY p.fame_score DESC
LIMIT 4"""

COUNT = """
SELECT COUNT(*) FROM (
    SELECT player_id FROM players
      WHERE normalized_name >= ? AND normalized_name < ?
    UNION
    SELECT player_id FROM player_aliases
      WHERE normalized_alias >= ? AND normalized_alias < ?)"""

def succ(p):
    return p[:-1] + chr(ord(p[-1]) + 1)

print("%-10s %10s %12s" % ("prefix", "candidates", "ms"))
for prefix in ["a", "ro", "ron", "rona", "sn", "sne", "ba", "bat", "s", "de"]:
    args = (prefix, succ(prefix), prefix, succ(prefix))
    n = c.execute(COUNT, args).fetchone()[0]
    t = time.perf_counter()
    runs = 3
    for _ in range(runs):
        c.execute(SQL, args).fetchall()
    ms = (time.perf_counter() - t) * 1000 / runs
    print("%-10s %10d %12.1f" % (prefix, n, ms))
