# 321 Football Challenge — Project State

**Read this first in any new chat.** It is the canonical record of what exists,
what was decided, and what comes next.

Last updated: 11 September 2026

> **Note (6 Oct 2026):** `friend-match.md` is newer than this doc. Its
> decisions settle the "OPEN DECISION" below (void the round, both re-pick) and
> the backend choice (Supabase). Read it for current status.

**Companion docs:** `flutter-app.md` (the client), `figma-to-flutter.md` (how
the UI gets built — read before touching any screen), `pvp-handoff.md` (the
next piece of work), `game-screens-ui.md` (the Figma screen spec).

---

## Status at a glance

| Area | State |
|---|---|
| Figma design | Screens complete, prototyped, tokenised (51 variables). |
| **Football database** | **COMPLETE — 43/43 verification checks passing.** |
| **Flutter Practice mode** | **COMPLETE — built from Figma, running and verified on the emulator.** |
| PvP / multiplayer backend | Not started. **This is next** — see `pvp-handoff.md`. |
| Team picker screen | Not started. `searchClubs` is ported and unused. |
| Shop assets | Waiting on a friend's avatar/card illustrations. |

---

## The database — complete

Built from Wikidata (SPARQL endpoint + the `wbgetentities` API). Transfermarkt
was ruled out: its terms of service prohibit scraping and it has acted against
public projects that did it anyway.

Code and data live on Yaman's machine at
`C:\Users\PC\Documents\321-football\321_football_db`.

### Two files — use the right one

| File | Size | Purpose |
|---|---|---|
| `321_football_slim.db` | 62 MB | **Ship this in the Flutter app bundle.** |
| `321_football.db` | 90 MB | **Keep for maintenance.** Re-run updates against this one. |

(Both are gitignored — back them up outside the repo.)

The slim copy drops scrape provenance, retired duplicate clubs, and the 46,337
players who only ever played for one club (a player with one club can never be
a mutual answer, so this costs zero correct answers). Independently re-verified
this session: all 45,787 players with two or more clubs survive the trim, and
the 44 clubs missing from slim are empty duplicate rows tombstoned by
`merge_duplicates.py`, not real clubs. All 53 Bundesliga clubs are present.

### Contents

- 26 leagues, 821 clubs — every club that appeared since 1990, not just current
  members
- 45,787 players in the slim copy, all typeable on a Latin keyboard
- 235,210 player-club spells
- ~342,000 accepted spellings (aliases)
- 27,132 pre-validated practice pairs — 216 easy, 8,738 medium, 18,178 hard
- Difficulty split: 25 easy clubs, 230 medium, 566 hard

---

## Data rules — decided, do not re-litigate

- **Cutoff 1990**, applied as `overlaps`: a spell counts if the player was at
  the club at any point from 1990 onward. A 1988–1992 spell counts; one ending
  1985 does not. Switchable via `config.INCLUDE_SPELL_RULE`.
- **Loans count** the same as permanent moves — any official spell counts.
- **Current club counts** as a club played for (`end_year` is NULL).
- **Reserve and B teams are excluded** — detected by name or entity type,
  never by Wikidata's "part of" relation alone.
- **Renames resolve to one club.** Internazionale and Inter Milan are one row;
  old names are kept as searchable aliases.
- **Nationality only** for players. No other biographical data. (Consequence:
  there is **no position column** — the Figma suggestion sub-line shows
  `Forvet · 1988–2005`, and the app shows nationality instead.)
- **Difficulty from absolute Wikipedia language count**: ≥100 languages easy,
  50–99 medium, under 50 hard.
- **Untypeable players removed** (753 with non-Latin-only names or no name).

---

## What the Flutter app calls

`game_queries.py` is the reference implementation of every query the game
needs. **It is now ported to Dart** in `lib/data/game_queries.dart`, and
`verify.py` plus 71 offline tests still target the Python module.

    search_clubs(query)                    the team picker  (ported, unused)
    get_mutual_players(club_a, club_b)     the answer key
    validate_answer(typed, club_a, club_b) does this win the point?
    random_practice_pair(difficulty)       a guaranteed-answerable question
    check_pair_is_playable(club_a, club_b) the PvP guard (ported, unused)

### Two known divergences in the Dart port

1. **The rejection fallback orders by fame.** `game_queries.py` picks the name
   to blame with `LIMIT 1` and no `ORDER BY`, so SQLite returns an arbitrary
   namesake — typing "messi" reported *"Georges Parfait Mbida Messi never
   played for both"*. The Dart version orders by `fame_score DESC`. This
   affects only the DISPLAYED name, not accept/reject. **Worth fixing in the
   Python too.**
2. **Suggestions need 3 characters, not 2.** Short prefixes materialise a huge
   candidate set before `LIMIT` applies. See `flutter-app.md` for the numbers.

### The two hot queries

Mutual players between two clubs:

```sql
SELECT p.player_id, p.display_name, p.nationality, p.fame_score
FROM players p
WHERE p.player_id IN (
    SELECT player_id FROM player_club_spells WHERE club_id = :a
    INTERSECT
    SELECT player_id FROM player_club_spells WHERE club_id = :b
)
ORDER BY p.fame_score DESC;
```

Resolving a typed answer to candidate players:

```sql
-- 1. exact full-name match (definitive)
SELECT player_id FROM players WHERE normalized_name = :typed;
-- 2. alias match (surnames, nicknames, real Wikidata alternate names)
SELECT player_id FROM player_aliases WHERE normalized_alias = :typed;
```

**Never use `LIKE 'x%'` for prefix search.** SQLite's LIKE is case-insensitive
by default and cannot use a BINARY-collated index; it turns into a full scan of
all 198,626 alias rows and hung the app. Use a range comparison
(`>= 'mes' AND < 'met'`), which is exactly equivalent since the normalized
columns are already lowercase.

### Tables the app needs

- `clubs` — club_id, canonical_name, normalized_name, country, fame_score,
  difficulty_band, sitelink_count, crest_asset_url
- `club_aliases` — club_id, normalized_alias
- `players` — player_id, display_name, normalized_name, nationality, fame_score
- `player_aliases` — player_id, normalized_alias
- `player_club_spells` — player_id, club_id, start_year, end_year
- `practice_pairs` — club_a_id, club_b_id, difficulty, mutual_count

Indexes on `(club_id, player_id)` and `(player_id, club_id)` make the
intersection a pure index scan. Keep them.

---

## Answer matching — behaviour the UI depends on

Matching is EXACT on full name or stored alias. **No fuzzy matching, ever** —
under a ten-second clock a near-miss silently counting as correct is worse than
a rejection, and it would let "ronaldo" take a point meant for "ronaldinho".

Names are compared in a folded form, so `Özil` / `Ozil` / `ozil` / `OZIL` all
match, and Turkish characters are handled explicitly (`Şükür` → `sukur`,
`İlkay` → `ilkay`). **The Dart port of this folding is checked against 36,767
real name pairs from the shipped database** (`test/name_parity_test.dart`) —
it caught a real bug on its first run. Do not skip it.

`validate_answer` returns a `reason` code. **Give each one different UI copy** —
conflating them will make players angry at the wrong thing:

| reason | What to show |
|---|---|
| `correct` | GOOOL — plus the matched player's full name |
| `not_a_mutual_player` | "He never played for both" |
| `unknown_player` | "We don't have that player" |
| `surname_too_common` | "Which one? Add a first name" |
| `too_short` | nothing — keep waiting for input |

Two ambiguity rules worth knowing:

- **Multi-word input is taken at its word.** "David de Santos Silva" matches
  him and not his namesake, because the typist asserted a first name.
- **A bare surname shared by more than 20 players is refused** as ambiguous.
  Without this, typing "Silva" blind would score whenever any Silva linked the
  two clubs. Rare surnames still work alone, so "Sneijder" stays on the fast
  path. Threshold is `config.MAX_PLAYERS_SHARING_SURNAME`.

---

## Practice mode — built

Every row in `practice_pairs` is guaranteed to have at least one valid answer,
so Practice can never serve an impossible question. Minimum mutual players per
band: easy 3, medium 2, hard 1.

The client is complete and verified on the emulator — difficulty screen, board,
custom Turkish keyboard, live suggestions, exact-match validation, streak,
celebration, auto-advance, and all three rejection paths. See `flutter-app.md`.

---

## OPEN DECISION — PvP rounds with no possible answer

*(Settled 13 Sep 2026 — option 1, void the round. See `friend-match.md`.)*

**This needs settling before the match loop is built, because it changes the UI.**

Both players pick their own club, so one can pick Başakşehir and the other
Sheffield United — two clubs sharing no player at all. The round is unwinnable
and both players watch a ten-second timer they cannot beat.

Practice mode is immune. For PvP, call `checkPairIsPlayable()` the moment both
clubs lock in, **before the 3-2-1 countdown finishes**. It returns
`{playable, mutualCount}` and is already ported to Dart.

What the game then does is undecided. Options discussed:

1. Void the round and make both players re-pick
2. Award both players a point and move on
3. Block the second player from choosing a club with no overlap

The Figma `Tur Bitti` frame draws option 1, but it was never formally chosen.

---

## Figma

File: `321-Football-Mobile`, key `UHMpbhjpqxQ94Xs1oD3Sfz`. 34 screens, fully
prototyped and tokenised (51 variables in the `321 Tokens` collection).

**The Figma file is the source of truth for layout — `game-screens-ui.md` is
not.** The first build of Practice mode was written from the spec doc and came
out looking nothing like the design. Read `figma-to-flutter.md` before building
any screen.

**Do not touch:** the "Sign in with Apple" button. It is Apple's official
asset and restyling it violates their guidelines.

---

## Tooling

| Script | Purpose |
|---|---|
| `build_database.py` | Runs steps 0–6. Resumable: `--from N`, `--only N` |
| `verify.py` | 43 checks including golden tests against real transfers |
| `test_offline.py` | 71 tests, no network required |
| `diagnose.py` | Club-list sanity, must-exist clubs, B-team leaks |
| `inspect_player.py` | Lookup by name or QID; `--club`; `--mutuals` answer key |
| `debug_wikidata.py` | Queries Wikidata directly about one entity |
| `merge_duplicates.py` | Finds and merges split club entities |
| `fix_names.py` | Upgrades non-Latin names, tiered language requests |
| `manual_names.py` | Hand-set a name by QID when the API mangles it |
| `purge_unanswerable.py` | Removes untypeable players, rebuilds pairs |
| `reset_scrape.py` | Marks clubs pending for a re-scrape |
| `finalize.py` | VACUUM/ANALYZE and the slim build |

The Flutter app has its own `tools/` directory — see `flutter-app.md`.

---

## Maintenance after a transfer window

A few windows a year, so this is manual by design:

```powershell
python reset_scrape.py --apply
python build_database.py --from 2      # ~12 minutes
python verify.py
python finalize.py --slim --drop-single-club
```

Then replace the slim database in the app bundle — **and bump
`AppDatabase.assetVersion` in the Flutter app**, or the stale copy already on
the phone wins and the new data silently never appears.

---

## Known gaps — all accepted

- 45 clubs have no players (defunct or century-old sides with almost no
  Wikidata coverage). They rate as obscure and sit harmlessly in Hard.
  *(Correction in `friend-match.md`: actually 61, including duplicates of
  major clubs like `FC Bayern München`. Needs a `merge_duplicates.py` pass.)*
- 91 clubs flagged `needs_review` during scraping — thin coverage on small
  clubs, checked and accepted.
- One scrape batch failed; retrying it is optional and affects minor clubs.
- Trophy data exists for only 53 of 821 clubs, so it is **excluded** from the
  fame model. At 20% weight it acted as a large arbitrary bonus for the 6%
  that had it, which put Samsunspor above Sheffield United.
- Scotland pre-2013 and some German lower divisions are thin — Wikidata does
  not record participating teams for those seasons. The Scottish Championship
  was added as a back door to most of the missing clubs.
- 676 players had names only in non-Latin scripts and were removed rather than
  shipped as unanswerable.
- **No position column** and **no club crests** — see `flutter-app.md`.
- Nationality labels are raw Wikidata ("Kingdom of the Netherlands").

---

## Traps that cost real time — worth knowing before touching this again

**Every bug in the database build was found by a verification step, never by
code failing.** The scraper ran perfectly clean while resolving Segunda División
to the *third* tier, deleting Galatasaray, Fenerbahçe and Beşiktaş, and
splitting 44 squads across duplicate club entities. Golden tests — real
transfers a human can confirm — earned their keep repeatedly. Keep adding.

**The same held for the Flutter client.** Every bug in Practice mode was
invisible to `flutter analyze`, which stayed clean throughout. They were found
by the parity test, by driving the app on a device and looking at screenshots,
and by measuring queries. Static analysis proves nothing about a UI.

**Check what the data holds before theorising about why it doesn't.** One
missing-player bug took five wrong theories before a direct lookup by Wikidata
ID showed the player's spells sitting there intact all along.

**Wikidata's label API misbehaves at both extremes.** Requesting twenty
languages at once is rejected with HTTP 200 and the error buried in the body.
Requesting *all* languages returns HTTP 200 with a silently incomplete set.
Small, explicit, tiered requests with English first are the only predictable
shape.

**`wdt:` in SPARQL exposes only a property's best-ranked value.** Anything
relying on it silently misses historical statements — which is why club
discovery walks league *seasons* rather than current league membership.

**Blocklists lose.** Script detection started as a list of scripts to reject
and let Bengali and Ethiopic through as "Latin". It is now an allowlist
checked against Unicode character names.

---

## Next steps

1. **PvP** — see `pvp-handoff.md`. Settle the no-answer rule, choose a backend,
   build the team picker, then Friend Match before ranked matchmaking.
   *(Superseded — see `friend-match.md` → Next.)*
2. Build `Doğru Cevap` and `Cevap Onayı` from Figma (the current celebration
   and answer sheet predate reading the file).
3. Cold start: stream the 62 MB asset copy instead of loading it whole.
4. Shop assets, audio/haptics, ads/IAP, release builds.
