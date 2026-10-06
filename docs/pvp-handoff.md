# PvP — handoff for the next chat

> **Note (6 Oct 2026):** background only. `friend-match.md` records what was
> built on top of this and settles its open questions (Supabase; void the
> round on a dead pair).

**Read `flutter-app.md` and `figma-to-flutter.md` first.** This doc covers only
what PvP adds on top of a finished Practice mode.

Written 11 September 2026, at the end of the session that built Practice mode.

---

## Where things stand

Practice mode is **done and verified on the emulator**: the database layer, the
answer validation, the Turkish keyboard, the suggestion panel and both screens
are built from the Figma file and working. PvP is the next piece.

Yaman's read, and it is right: **most of the game already exists.** PvP is the
same round — two clubs, type a mutual player, first correct answer wins — with
a clock, an opponent, and something keeping both phones in step.

---

## What PvP reuses unchanged

Almost the whole client. None of this needs rewriting:

| Piece | Notes |
|---|---|
| `game_queries.dart` | `validateAnswer`, `getMutualPlayers`, `searchClubs` (unused so far — PvP needs it for the team picker), `checkPairIsPlayable` (written for PvP, never called yet) |
| `name_normalizer.dart` | plus its 36,767-case parity test |
| `app_database.dart` | the shipped 62 MB SQLite asset |
| `turkish_keyboard.dart` | identical component |
| `search_bar_panel.dart` | the design specifies **3** suggestions in PvP vs 4 in Practice, plus a compact matchup strip so the panel never covers the crests during a ten-second round |
| `club_card.dart`, `screen_background.dart`, `practice_chrome.dart` | top bar, matchup, badges, rejection banner all carry over |
| `theme/tokens.dart` | whole design system |

**The board screen itself is the model to copy.** `practice_board_screen.dart`
already holds the typing state, the debounce, the validation call and the
rejection handling. A PvP board is that plus a clock and an opponent.

---

## What is genuinely new

1. **A backend.** Undecided: Firebase or Supabase. Nothing has been built.
2. **Matchmaking** — the ELO/trophy pool for "Hemen Oyna".
3. **Friend rooms** — 6-digit codes, create and join.
4. **Two clocks** — 15 s to pick a club, 10 s to find the player, both drawn as
   a red Jaro numeral in a 158 px ring.
5. **Scoring** — first to N goals, trophies and coins on the result screens.
6. **Keeping both phones in step** (below).

---

## Keeping both phones in step — DECIDED

Yaman's framing — *"a system that gives the same screen to both players in very
small time"* — is the right one. Three things have to stay in step:

**1. Both players see the same two clubs.** One side picks, the other picks,
the server broadcasts both. No timing subtlety.

**2. The 3-2-1 countdown ends at the same instant on both phones.** Do NOT
start a local 3-second timer when the "go" message arrives — the two phones
drift by whatever their latency differs by, and the player on the slower
connection silently gets less time. **Send a server timestamp for when input
unlocks** and have each client count down to that. Same for the 10 s answer
window.

**3. Who answered first.**

**Decision (Yaman, 11 Sep 2026): each client measures its own elapsed time, the
server compares the two numbers and declares the winner. Nothing more.**

The important detail is *elapsed time, not wall-clock time*. Two phones' clocks
are not synchronised — NTP drift of hundreds of milliseconds is normal and a
user can set the clock by hand — so comparing two timestamps compares readings
from two different rulers. Comparing two **durations measured since the round
started** makes skew cancel out entirely, because each phone measures against
its own clock over a ten-second window where drift is microseconds.

This is also **fairer than ranking by which answer reached the server first**,
which would rank connections rather than players.

Two implementation details:

- Stamp the moment **GÖNDER is pressed**, not when validation returns.
  Otherwise a slower phone is penalised for its own database lookup.
- Use a **monotonic** clock — Dart's `Stopwatch`, not `DateTime`. If the OS
  corrects the system clock mid-round, a `DateTime` delta can jump or go
  backwards.

### Explicitly out of scope: anti-cheat

**Decision (Yaman, 11 Sep 2026): do not write any code to detect or prevent
cheating, now or later.** Yes, a client reporting its own speed could lie. This
is a modest trivia game, not a title with a competitive economy worth
exploiting. Sanity bounds, server-side re-validation, arrival-time
cross-checks — none of it. Do not reintroduce this.

Keep validation local on each phone: both have the full database, it is instant,
and it is what makes the game feel fast.

---

## Settle this before building the match loop

**The no-answer rule is still open** and it changes the UI, so it cannot be
deferred. From `project-state.md`:

Both players pick their own club, so one can pick Başakşehir and the other
Sheffield United — two clubs sharing no player at all. The round is unwinnable
and both players watch a ten-second timer they cannot beat.

`checkPairIsPlayable(clubA, clubB)` is already ported to Dart and returns
`{playable, mutualCount}`. **Call it the moment both clubs lock in, before the
countdown finishes.** What happens then is undecided:

1. Void the round and make both re-pick
2. Award both a point and move on
3. Block the second player from choosing a club with no overlap

The Figma `Tur Bitti` frame draws option 1, but it was never formally chosen.

---

## Performance findings that matter more under a clock

Practice has no timer, so these were merely annoying there. Under ten seconds
they are the difference between a fair round and a lost one. Both are fixed in
the current code — **do not regress them.**

**`LIKE 'x%'` cannot use a SQLite index** (LIKE is case-insensitive by default,
so a BINARY-collated index is unusable). It made every keystroke scan all
198,626 alias rows — 31 ms on a laptop, far worse on a phone — and hung the app
outright. The fix is a range comparison, which is exactly equivalent because
the normalized columns are already lowercase.

**Short prefixes are expensive even indexed**, because the candidate set is
materialised and sorted by fame before `LIMIT 4`:

| prefix | candidates | ms (laptop) |
|---|---|---|
| `a` | 8,126 | 187 |
| `ro` | 1,899 | 52 |
| `ron` | 112 | 12 |

`GameQueries.minPrefix` is 3 for this reason. The Figma typing frame shows
suggestions at two characters; going back to 2 needs `fame_score` denormalised
into `player_aliases` so the LIMIT can push down. **Decide this for PvP
specifically** — a stall on the second keystroke of a ten-second round is worse
than in Practice.

**`validateAnswer` has not been profiled on-device.** It is the hot path under
the clock, and it now also sits between the keypress and the timestamp that
decides the round. Profile it the way `suggestPlayers` was profiled
(`tools/explain.py`) before the match loop ships.

---

## Testing

**Decision (Yaman): PvP gets tested on two real phones, not the emulator.**
Sensible — the emulator on a 7.7 GB machine tells you nothing useful about
reaction timing, and PvP needs two clients anyway.

Practicalities when that time comes:

- The debug APK is ~189 MB (62 MB of it the database). It installs on any phone
  via `adb install`, or by copying the file across and allowing install from
  unknown sources. No Play Store or signing needed for testing.
- `tools/build_apk.ps1` produces it. A release AAB would be roughly 75–85 MB
  and is worth doing before real testing.
- There is no Android phone available right now. Until there is, build PvP
  against the emulator for layout and logic, and leave timing verification for
  the two-phone session.
- Two emulator instances can run simultaneously in principle, but **not on this
  machine** — one already takes 2.4 GB of 7.7 GB.

---

## Suggested order

1. Settle the no-answer rule. It gates the UI.
2. Choose Firebase or Supabase.
3. Build the **team picker** screen (`searchClubs` is ported and unused) — it is
   needed by PvP and is a self-contained, offline, testable piece.
4. Build the PvP board as a variant of the Practice board: add the clock ring,
   drop to 3 suggestions, add the compact matchup strip.
5. Wire Friend Match (6-digit rooms) before ranked matchmaking — a private room
   is far easier to test with two devices than a matchmaking pool.
6. Ranked matchmaking, trophies, leaderboards.

Friend Match first is the recommendation: it exercises the whole
keep-both-phones-in-step problem with none of the matchmaking complexity, and
it is the mode two people in the same room can actually test.

---

## Loose ends inherited from Practice

- ~~`Doğru Cevap` (78:610) and `Cevap Onayı` (82:338) not built from Figma~~ —
  built 6 Oct 2026, with `Cevabı Göster` (78:483); see `flutter-app.md`.
- ~~Cold start copies the 62 MB database whole~~ — streamed with real progress
  since 6 Oct 2026; not yet re-measured.
- ~~`game_queries.py` unordered `LIMIT 1` namesake bug~~ — fixed 6 Oct 2026.
- No position column in the database, so suggestion sub-lines show nationality
  where the design shows `Forvet`.
- Nationality labels are raw Wikidata ("Kingdom of the Netherlands").
- **Disk:** the project folder reads ~2.6 GB but 87% of that is `app\build` and
  `.dart_tool`. `flutter clean` returns it to ~230 MB. Nothing to fix.
