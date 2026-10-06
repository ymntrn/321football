# -*- coding: utf-8 -*-
"""Answer key for a club pair, straight out of the shipped asset DB."""
import sqlite3, sys, io
sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace")

db = r"C:\Users\PC\Documents\321-football\app\assets\db\321_football.db"
a_name, b_name = sys.argv[1], sys.argv[2]
c = sqlite3.connect(db); c.row_factory = sqlite3.Row

def club(n):
    return c.execute(
        "select club_id, canonical_name from clubs where canonical_name like ? "
        "order by fame_score desc limit 1", ("%" + n + "%",)).fetchone()

a, b = club(a_name), club(b_name)
print(a["canonical_name"], "x", b["canonical_name"])
rows = c.execute("""
  select p.display_name, p.normalized_name, p.fame_score
  from players p where p.player_id in (
    select player_id from player_club_spells where club_id=?
    intersect select player_id from player_club_spells where club_id=?)
  order by p.fame_score desc""", (a["club_id"], b["club_id"])).fetchall()
print("mutual:", len(rows))
for r in rows[:15]:
    print("   %-28s -> %s" % (r["display_name"], r["normalized_name"]))
