# Export a name-normalization fixture straight out of the shipped database,
# so the Dart port is checked against values Python actually produced.
import sqlite3, os, random

db = r"C:\Users\PC\Documents\321-football\app\assets\db\321_football.db"
out = r"C:\Users\PC\Documents\321-football\app\test\fixtures\name_parity.tsv"
os.makedirs(os.path.dirname(out), exist_ok=True)

c = sqlite3.connect(db)
rows = c.execute("SELECT alias_name, normalized_alias FROM player_aliases").fetchall()
rows += c.execute("SELECT full_name, normalized_name FROM players").fetchall()
rows += c.execute("SELECT canonical_name, normalized_name FROM clubs").fetchall()
rows += c.execute("SELECT alias_name, normalized_alias FROM club_aliases").fetchall()
c.close()

def ascii_only(s):
    try:
        s.encode("ascii"); return True
    except Exception:
        return False

tricky = [r for r in rows if r[0] and not ascii_only(r[0])]
plain  = [r for r in rows if r[0] and ascii_only(r[0])]
random.seed(321)
sample = tricky[:25000] + random.sample(plain, min(15000, len(plain)))

seen, written = set(), 0
with open(out, "w", encoding="utf-8", newline="\n") as f:
    for raw, norm in sample:
        if "\t" in raw or "\n" in raw or raw in seen:
            continue
        seen.add(raw)
        f.write("%s\t%s\n" % (raw, norm))
        written += 1

print("total rows in db :", len(rows))
print("non-ascii names  :", len(tricky))
print("fixture written  :", written, "->", out)
