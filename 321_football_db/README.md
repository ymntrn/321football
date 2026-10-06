# 321 Football Challenge — Database

Builds the football database the game runs on: every club in ~23 leagues since
1990, every player who turned out for them, and the index that answers *"who
played for both of these clubs?"* in milliseconds.

Source is **Wikidata**, queried through its public SPARQL endpoint. It is free,
structured, and explicitly open to automated querying — unlike Transfermarkt,
whose terms of service prohibit scraping and who have acted against public
projects that did it anyway.

---

## Setup

You need Python 3.10 or newer.

```bash
cd 321_football_db
python -m venv .venv

# macOS / Linux
source .venv/bin/activate
# Windows
.venv\Scripts\activate

pip install -r requirements.txt
```

Then open `config.py` and change one line — the contact address in
`USER_AGENT`. Wikidata asks every automated client to identify itself, and
blocks ones that don't.

---

## Running the build

```bash
python build_database.py
```

That runs all seven steps in order. Expect **a few hours**, almost all of it in
step 2. That's Wikidata's rate limits, not your machine.

It is safe to stop at any time with `Ctrl-C` and resume:

```bash
python build_database.py --from 2
```

Steps already completed are skipped, and clubs already scraped aren't
re-fetched. Responses are cached on disk in `.sparql_cache/`, so a re-run
after a crash costs almost nothing.

### The steps

| Step | Script | What it does |
|---|---|---|
| 0 | `resolve_leagues.py` | Finds and verifies each league's Wikidata ID |
| 1 | `scrape_clubs.py` | Every club that played in those leagues since 1990 |
| 2 | `scrape_players.py` | Every player spell at those clubs *(the long one)* |
| 3 | `enrich.py` | Trophy counts, top-flight seasons, real player nicknames |
| 4 | `compute_fame_scores.py` | Fame ranking → Easy / Medium / Hard bands |
| 5 | `build_practice_pairs.py` | Pre-validated Practice-mode questions |
| 6 | `verify.py` | The double-check (see below) |

You can also run any step alone: `python build_database.py --only 4`.

### Step 0 deserves your attention

Read what step 0 prints. It resolves each league name to a Wikidata ID and
reports how confident it is. This is the cheapest place to catch a mistake — if
"Serie A" resolves to the Brazilian one instead of the Italian one, you find
out in ten seconds instead of after an hour of scraping the wrong clubs.

Anything marked `!!` should be checked by hand: open
`https://www.wikidata.org/wiki/Q…` for that ID and confirm it's the competition
you meant. If it's wrong, set `qid_hint="Q…"` for that league in `leagues.py`
and re-run step 0.

---

## Verifying it worked

```bash
python verify.py
```

Structural checks catch broken data. But a database can be perfectly consistent
and still be *wrong* — missing half of Galatasaray's squad, say. So `verify.py`
also runs **golden tests**: real transfers that must be findable.

```
[4] Golden tests — real transfers that MUST be findable
  PASS  Wesley Sneijder @ Inter x Galatasaray (14 mutual players)
  PASS  Didier Drogba @ Chelsea x Galatasaray (9 mutual players)
  ...
```

If Sneijder doesn't come back for Inter × Galatasaray, the database is not
ready, whatever else passes. Add your own known transfers to `GOLDEN_MUTUALS`
in `verify.py` — the more the better.

There's also an offline test suite that needs no internet, for checking the
logic after you change a rule in `config.py`:

```bash
python test_offline.py     # 58 tests, no network required
```

---

## The rules this encodes

All in `config.py`, all one-line changes:

- **Cutoff: 1990**, applied as `"overlaps"` — a player is included if he was at
  the club *at any point* from 1990 on. A 1988–1992 spell counts (he was there
  in 1990, '91, '92); a spell ending in 1985 doesn't. This is the "no strict
  edge" reading of your rule. Set `INCLUDE_SPELL_RULE = "starts_after"` for the
  stricter version.
- **Loans count the same as permanent moves.** Every official spell counts.
- **Current club counts** as a club played for (`end_year` is simply `NULL`).
- **Reserve and B teams are excluded** — Barcelona B, Real Madrid Castilla,
  Bayern II, U21 sides. Detected structurally (Wikidata's "part of" relation)
  and by name, with the method recorded so it's auditable.
- **Renames resolve to one club.** Internazionale and Inter Milan are one row;
  the old name is kept as an alias so a scrape hit on it doesn't create a
  duplicate.
- **Nationality is stored** for players; nothing else biographical.

---

## Two things you should decide about

**1. Undated spells.** Wikidata's date coverage is patchy — plenty of real
spells have no start or end date. Right now we keep them
(`KEEP_UNDATED_SPELLS = True`), flagged `date_confidence='unknown'`, because
dropping them loses a lot of legitimate data. The tradeoff is that a few could
be pre-1990 stints. `verify.py` reports the percentage; if it comes back above
25% it'll warn you, and you can flip the flag.

**2. PvP rounds with no possible answer.** This one is a gameplay problem, not
a data one, and it will happen. Both players pick their own club — so one can
pick Başakşehir and the other Sheffield United, two clubs that share no player
at all. The round is then unwinnable, and both players stare at a 10-second
timer wondering why nothing works.

Practice mode is already immune (every pair in `practice_pairs` is
pre-validated). For PvP, call this the moment both clubs are locked in, before
the 3-2-1 countdown finishes:

```python
from game_queries import check_pair_is_playable
result = check_pair_is_playable(conn, club_a_id, club_b_id)
# {'playable': False, 'mutual_count': 0}
```

Then decide what the game does — void the round and re-pick, show "no common
player, both get a point", or block the second pick. Worth settling before you
build the match loop, since it affects the UI.

---

## What the game calls

`game_queries.py` is the reference implementation of everything the app asks
the database. Port these to Dart for the Flutter client and keep the behaviour
identical — `verify.py` tests against this module, so if your Dart matches it,
it's correct.

```python
search_clubs(conn, "real")                       # the team picker
get_mutual_players(conn, club_a, club_b)         # the answer key
validate_answer(conn, "sneijder", club_a, club_b)# does this win the point?
random_practice_pair(conn, "hard")               # a guaranteed-answerable question
check_pair_is_playable(conn, club_a, club_b)     # the PvP guard above
```

`validate_answer` distinguishes *"we don't have that player"* from *"he never
played for both"* — worth surfacing differently in the UI, because players will
be furious at the wrong one if you conflate them.

Typed answers are matched on a folded form, so `Özil` / `Ozil` / `ozil` / `OZIL`
all hit, and Turkish characters are handled explicitly (`Şükür` → `sukur`).
There is deliberately **no fuzzy matching** — under a ten-second clock, a
near-miss silently counting as correct is worse than a rejection, and it would
let "ronaldo" claim a point meant for "ronaldinho".

---

## Keeping it current

A few transfer windows a year, so this is a manual job, not a pipeline:

```bash
python build_database.py --from 2
```

Step 2 only fetches clubs marked `pending`, so to refresh everything after a
window closes:

```sql
UPDATE clubs SET scrape_status = 'pending';
```

Then re-run from step 2 and finish with `verify.py`.

---

## Shipping it to Flutter

The finished `321_football.db` is a plain SQLite file. Copy it into your Flutter
project's `assets/` folder, declare it in `pubspec.yaml`, and open it with
`sqflite`. It's read-only at runtime, so it can ship inside the app bundle with
no server involved — which is also what makes offline Practice mode work.

Before shipping, shrink it:

```sql
VACUUM;
```
