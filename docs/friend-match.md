# Friend Match — the live working doc

Started 13 September 2026. The doc for the online private-room mode.

**Supersedes the open questions in `pvp-handoff.md` and `project-state.md`**
("OPEN DECISION — PvP rounds with no possible answer", "Choose Firebase or
Supabase"). Reconcile those when this piece lands.

Scope: **Friend Match only.** No matchmaking, no ELO, no trophies.

> **6 Oct 2026, branch `front-door-and-ranked`:** accounts, ranked
> matchmaking, stats, trophies and coins are built on top of this engine —
> see `accounts-and-ranked.md`. What changed HERE: rooms now carry auth user
> ids and RLS is `auth.uid() in (host_id, guest_id)` (006, the upgrade the
> *RLS — honestly* section below describes); rooms gained `ranked` and the
> recorded-result columns (007); both seats call `record_match_result` at
> `match_over`; `bot.py` signs in anonymously.

---

## Status

| Piece | State |
|---|---|
| Supabase schema + flow functions | **Done — 14 + 26 + 18 smoke checks pass** |
| Forfeit, rematch, reconnect, cleanup | **Done and verified live** |
| Team picker | **Done, from Figma** |
| Lobby (Oda Kur / Odaya Katıl) | **Done, from Figma** |
| Countdown | **Done, from Figma** |
| Match state machine | **Done — full match verified against the bot** |
| Bot second player | **Done** |
| PvP board (the answering phase) | **Built from Figma 6 Oct — not yet run on a device** |
| Versus | **Built from Figma 6 Oct — not yet run; SVGs need `fetch_assets.ps1`** |
| GOOOL, Tur Bitti, Kazanma / Kaybetme | **Built from Figma 6 Oct — not yet run on a device** |

**The honest summary (6 Oct 2026):** every match screen now exists and is
built from the Figma frames, on branch `screens-from-figma`. It was written
in a cloud session with no emulator: `flutter analyze` is clean and
`flutter test` passes (layout tests pump each new screen at three phone sizes
and fail on overflow), but **nothing from that branch has been seen on a
device yet.** `docs/TESTING.md` is the checklist. The backend protocol is
unchanged — no migration, no new column.

---

## Decisions (Yaman, 13 September 2026)

| Question | Decision |
|---|---|
| No-answer rule | **Void the round, both re-pick.** Round number does not advance. |
| Backend | **Supabase**, project `yjdcsdikcrdupqmaqoqn`, **eu-west-1**. |
| Second test client | **A scripted bot** (`supabase/bot.py`). |
| Disconnect | **Immediate forfeit.** |
| Anti-cheat | **None, ever.** Answers are trusted; nothing server-side checks them. |

Carried over from 11 September: the round winner is decided by comparing
**elapsed time measured locally on each phone**, and validation stays local
and exact-match.

### Decisions I had to make while building (not previously written down)

- **A round does not end the instant someone answers.** If both players answer
  within a few hundred milliseconds, the *slower* one's write can reach the
  database first — settling immediately would hand the round to the better
  connection, the exact unfairness the elapsed-time rule exists to prevent.
  The host waits a **900 ms grace window** for the second submission, then
  compares durations. Both already in → settles at once.
- **A player who doesn't pick in 15 s gets a club chosen for them** — famous,
  has players, and never the club the opponent just took (Barcelona vs
  Barcelona makes every squad member correct). Each client picks for itself.
- **An unplayable pair skips the countdown.** `checkPairIsPlayable` runs the
  moment both clubs lock in; a dead pair goes straight to the voided round.
- **Either player may claim a forfeit**, not just the host — otherwise a host
  who walks out leaves the guest waiting forever.

---

## The backend

Supabase no longer provisions the direct `db.<ref>.supabase.co` host; new
projects are pooler-only. Working connection:
`aws-1-eu-west-1.pooler.supabase.com:6543`. `supabase/migrate.py` applies a
`.sql` file straight to it, reading the URI from `supabase/.pgpass.local`
(**never commit that file**).

Free tier: 500 MB, 5 GB egress, 200 concurrent realtime connections, 2M
realtime messages/month — ~100 simultaneous matches, ~13,000 matches a month.
A free project **pauses after 7 days of inactivity**.

**There is no server-side game code**, and that is the point: the winner is a
pure function of two numbers already in the row, so both clients reach the
same verdict and the backend is only a synced data store. No Edge Functions,
nothing needing a paid plan.

### Migrations

| File | What |
|---|---|
| `schema.sql` | `rooms`, `server_now`, `create_room`, `join_room`, RLS, Realtime |
| `002_fix_grants.sql` | the table GRANTs `schema.sql` forgot |
| `003_match_flow.sql` | `start_match`, `begin_countdown`, `open_answers`, `finish_round`, `next_round`, `forfeit`, `touch_seen` |
| `004_forfeit_rematch_cleanup.sql` | `claim_forfeit`, `leave_match`, `rematch`, `active_room_for`, `abandon_stale_matches`, pg_cron jobs |
| `005_void_from_picking.sql` | `finish_round` may void an unplayable pair straight from `picking` (the freeze found 6 Oct) |
| `006`–`011` | accounts, results, friends, matchmaking, 2X Altın, account deletion — see `accounts-and-ranked.md` |

Verify with `smoke_test.py` (14), `smoke_test_flow.py` (26 — drives a whole
match over HTTP), `smoke_test_004.py` (18), `smoke_test_005.py` (9). `audit.py` reports room counts,
cron jobs and anything stuck.

### Four things that were easy to get wrong

**RLS policies do not imply GRANTs.** Postgres checks privileges first, so
`schema.sql` produced a table every direct read and write failed on with
`42501` — while `create_room` and `join_room` kept working, because
`SECURITY DEFINER` functions run as their owner and hid it completely.

**`replica identity full`** or Realtime sends only the primary key on an
UPDATE, clients receive `{code: "123456"}`, and the match appears to freeze.

**Deadlines are stamped by Postgres**, as `now() + interval` inside the flow
functions. PostgREST cannot express that in a PATCH body, and a client writing
its own `DateTime.now()` would reintroduce the drift this design removes.

**The forfeit staleness check is server-side, and it is not anti-cheat.** A
client can only observe that updates stopped arriving — it cannot tell that
apart from *its own* connection dropping, where the opponent is alive and
playing. `claim_forfeit` compares the other seat's heartbeat against the one
clock both players share, and returns the row unchanged if they are still
there. Without it, a blip on the losing player's wifi hands them the match.

### The host drives

The host advances phases; **the guest only writes its own columns** — club
pick, answer, heartbeat. That is what stops two clients racing to write the
same transition, and it costs nothing because a host who disappears forfeits.
Every flow function is guarded (`where phase = …`) and returns the row as it
stands when the guard misses, so a double call is harmless.

### Housekeeping

pg_cron 1.6.4 was available but not installed; it is now. Two jobs:

- `321-abandon-matches` every 15 min — closes mid-match rooms silent for over
  10 minutes as `ended_reason = 'abandoned'`, so a stale row cannot drag
  somebody back into a match that ended an hour ago
- `321-purge-rooms` nightly at 04:17 — deletes rooms older than a day

Before this existed, one afternoon of testing left three rooms frozen in
`picking` for up to 95 minutes.

### RLS — honestly

*(Superseded by 006_accounts.sql: rooms are now readable and writable only
by their two signed-in players.)* Before 006: any holder of the publishable
key could read and write any room. That matches
the no-anti-cheat decision: two friends sharing a code, no economy to exploit.
It is **not** protection against someone guessing six digits. The upgrade, if
it ever matters, is anonymous sign-ins plus
`auth.uid() in (host_id, guest_id)`.

### Clock offset

No `.info/serverTimeOffset` on Supabase, so `ServerClock` measures it
NTP-style against `server_now()`: five samples, `offset = server − (t0+t1)/2`,
keep the smallest round trip. **+26 ms from the laptop, −114 ms from the
emulator** — they differ because the emulator keeps its own clock, which is
the whole reason the offset exists.

It matters less than `pvp-handoff.md` assumed: under the elapsed-time rule
each phone's ten seconds starts at its own unlock, so latency already cancels.
The offset only makes the 3-2-1 *look* simultaneous.

---

## The client

```
lib/net/
  supabase_config.dart   url + publishable key (safe to ship; dart-define overrides)
  server_clock.dart      the NTP-style offset
  room_repository.dart   create / join / watch / flow RPCs / own-column writes
                         / claimForfeit / leaveMatch / rematch / activeRoomFor
  identity.dart          a stable player id + name in SharedPreferences
lib/models/room.dart     the row, MatchPhase, Seat, RoundReason, decideRoundWinner()
lib/screens/
  friend_match_screen.dart      Oda Kur + Odaya Katıl (51:471, 51:524)
  match_screen.dart             THE STATE MACHINE (+ local round history)
  match_versus_screen.dart      Versus (27:42)
  match_countdown_screen.dart   Maç - Geri Sayım (38:200)
  match_team_select_screen.dart Maç - Takım Seçme (33:85, 86:190)
  match_board_screen.dart       Maç - Oyuncu Arama (41:584, 86:334)
  match_end_screens.dart        GOOOL (41:685), Tur Bitti (109:8),
                                Kazanma / Kaybetme (46:352, 48:534)
lib/widgets/
  lobby_chrome.dart      tab buttons, room panel, name strips, avatars, action button
  club_search_panel.dart TAKIMLAR panel + ClubBadge
  match_chrome.dart      score strip, name block, round timer, crest slot,
                         opponent pill, Canlı Durum strip, compact matchup,
                         avatars, OutlinedGradientText (GOOOL / TUR BİTTİ /
                         Kazandın / countdown numeral)
  career_line.dart       "Club (2009–13) → Club (2013–17)"
```

### The board and the clock (6 Oct 2026)

The board appears when **this device's clock reaches `unlock_at`** — the
rule `003_match_flow.sql` already states — in both the `countdown` and
`answering` phases, under one widget key, so the host's `open_answers` flip
does not rebuild it. A `Stopwatch` starts when the board mounts and is
**read the instant GÖNDER (or a suggestion) is pressed, before
`validateAnswer` runs**. The board can mount up to 250 ms after the unlock
(the loop's tick) or much later after a reconnect, so the gap between the
unlock and the mount is measured once and added to every reading — otherwise
a late mount would be free time. Only correct answers are written, through
the existing `submitAnswer` (retried once; its `elapsed_ms is null` filter
makes the retry harmless). Input closes after a correct answer and when the
local clock passes the deadline; the host's timeout and 900 ms grace window
are untouched.

The deciding goal never passes through `round_over` — `finish_round` goes
straight to `match_over` — so the loop shows that goal's GOOOL for the same
2.5 s before the result, but only when the match has *just* ended (a
reopened finished match goes straight to the result).

`MAÇ ÖZETİ` (fastest answer, correct/played, best run of round wins) is kept
**locally** round by round, because `next_round` wipes the row. A player who
reconnected mid-match only sees the rounds since.

`watch()` subscribes to the room row **and polls every 2 seconds as a
backstop**, de-duplicating by `updated_at`. A dropped realtime message and a
frozen game look identical to a player.

`submitAnswer` filters on `elapsed_ms is null`, so a second submission cannot
overwrite a faster first one. Only correct answers are written.

Back-button out of a live match goes through `PopScope` and forfeits before
popping. On opening Friend Match, `active_room_for` puts a player straight
back into a match they were killed out of — which matters much more now that
leaving actually loses it.

### Deliberate divergences from the design

- **The code entry is the one place using the system keyboard** — the custom
  Turkish keyboard has no digits, and a system numeric pad brings paste with
  it. It opens on tap, not on arrival.
- Name strips and scoreboard blocks are **rounded** (`radius/sm`). The Figma
  frames drew them square; both the file and the app were changed on 13 Sep.
- The countdown's bottom slots show each player's **club** rather than the
  design's matchmaking state, since both are known by then.
- The opponent pill is PoetsenOne; M PLUS 1p is not bundled.
- The suggestion sub-line shows nationality; the database has no position.
- The lobby panel does not exist until a mode is chosen (added 13 Sep, and
  drawn into Figma as `Arkadaş Maçı - Başlangıç`).

Added 6 Oct 2026, with the screens built that day:

- **Board: no clock ring.** The written spec (`pvp-handoff.md`,
  `game-screens-ui.md`) asks for a red Jaro numeral "in a 158 px ring"; the
  Figma frames 41:584 / 86:334 draw only the numeral over the backdrop glow.
  The frame won. Add the ring to the frame first if it is wanted.
- **Board: `Canlı Durum` says "yazıyor" while the round is open, not while the
  opponent is actually typing.** The protocol carries no typing signal (the
  row only learns of a CORRECT answer), so it reads `yazıyor` → `buldu!` →
  `süre doldu`. "Sen" becomes "Sen · buldun!" after this player's answer.
- **Board: a `✓ name` line** replaces the rejection line after a correct
  answer — not in the frames, but otherwise nothing visible happens for the
  up-to-900 ms before the host settles.
- **Board: the compact strip's crests are the tinted initials badge** used by
  the big club cards, not the frame's grey `T1` / `T2` text.
- **Versus has no phase of its own** — adding one would change the protocol.
  It is drawn over the **first 2 s of round 1's 15 s pick window** (the
  prototype's 2 s timeout), so both players pick in 13 s that round. Timed
  against `pick_deadline`, so a reconnect later in the window skips it; never
  shown on a voided round 1 re-pick; shown again after a rematch.
- **Versus: player names on the blank white `Oyuncu Kartı` banners** (the
  frame leaves them empty pending card art) and the caption reads
  `ARKADAŞ MAÇI · İLK N GOL` instead of the ranked `SIRALI MAÇ`.
- **Versus vectors are not committed yet.** The cloud session could not reach
  figma.com; the three export URLs are in `tools/fetch_assets.ps1` (Figma
  asset URLs expire after ~7 days — run it soon). Missing files fall back to
  a plain Jaro `VS` and the names, so the match still runs.
- **GOOOL's scorer ring is painted**, not the exported SVG (a blur-filter
  glow flutter_svg cannot draw — the same reason as Ellipse 5).
- **Tur Bitti also covers the unplayable pair**, with its own subtitle ("Bu
  iki takımın ortak oyuncusu yok", "Takımlar yeniden seçilecek") and no
  answer panel. The frame only draws the time-out case.
- **Result screens: no trophy/coin row and no `2X Altın` button** — that is
  the ranked economy, out of scope for Friend Match. `Tekrar Oyna` takes the
  full-width 341x90 form the Kaybetme frame already uses, on both screens.
- **Result screens: the end reason** sits where the trophy row was:
  `Rakip ayrıldı` (opponent forfeited), `Bağlantın koptu` (this player was
  claimed against), `Maç yarıda kaldı` (abandoned; no Tekrar Oyna).
- **`MAÇ ÖZETİ` → `seri` is the longest run of rounds won in this match.**
  The frame's `8` looks like a profile-wide streak, which does not exist.
- Everything set in M PLUS 1p in the frames uses PoetsenOne (not bundled).

### Bugs worth remembering

**Widgets that size to their text.** `LobbyTabButton` and `LobbyButton` came
out a third of their drawn width because their `Container` had a height but no
width. Invisible to `flutter analyze`; obvious in one screenshot.

**`INTERNET` was only in the debug manifest.** Debug builds worked; a
**release** build would have had no network at all.

**A fixed-height panel, not a filled one.** With the keyboard up there is
nowhere near 506 pt left, so the panel was squeezed to ~140 and its contents
overflowed by 209 px. It now takes its height from its width and the screen
scrolls.

---

## Testing without a second device

`python supabase\bot.py <code>` joins and plays; `--host` creates a room and
prints the code; `--slow` makes it lose on purpose. It reads answers straight
out of the shipped SQLite file, so a failure is always a protocol or timing
bug, never the bot being bad at football.

**Note: the bot cannot host a real test of the state machine** — the host
drives the transitions and the bot does not implement them. For loop testing,
the APP must be host and the bot the guest.

Verified end to end on the emulator: a full first-to-3 match (bot won 3-0,
every phase transition correct), and a live forfeit — bot killed mid-match,
app claimed it 20 s later and showed `KAZANDIN · Rakip ayrıldı`.

---

## Two database findings, both fixed in the app

**Club search ranked the wrong clubs first.** `BA` gave Bayer Leverkusen,
Barnsley, Balıkesirspor, then FC Barcelona — the prefix bonus only counted the
canonical name, and Barcelona is stored as "FC Barcelona". Now matches at any
word start. **`club_aliases` is still useless**: 823 rows for 821 clubs, each
a copy of the canonical name, so `PSG`, `Barça` and `Spurs` find nothing.
Adding real aliases is a data job worth doing.

**61 clubs have zero players**, not the 45 the notes claim, and they are not
harmless: `FC Bayern München` (a duplicate of `FC Bayern Munich`, which holds
all 497), `BV Borussia 09 Dortmund`, `FC Schalke 04`, `DSC Arminia Bielefeld`,
and two clubs named after their own Wikidata ID. `searchClubs` now excludes
them. **The duplicates still want a proper `merge_duplicates.py` pass.**

---

## Figma

| Node | Frame | Built |
|---|---|---|
| `51:471` / `51:524` | Oda Kur / Odaya Katıl | yes |
| `141:41` | Arkadaş Maçı - Başlangıç (added 13 Sep) | yes |
| `33:85` / `86:190` | Maç - Takım Seçme (+ typing) | yes |
| `38:200` | Maç - Geri Sayım | yes |
| `27:42` | Versus | yes, 6 Oct (assets via `fetch_assets.ps1`) |
| `41:584` / `86:334` | Maç - Oyuncu Arama (+ typing) | yes, 6 Oct |
| `41:685` | Maç - Tur Sonu (GOOOL) | yes, 6 Oct |
| `109:8` | Maç - Tur Bitti (Beraberlik) | yes, 6 Oct |
| `46:352` / `48:534` | Maç Sonu Kazanma / Kaybetme | yes, 6 Oct (no economy row) |

"Yes, 6 Oct" = built from `get_design_context`, analyzer- and layout-test
clean, **not yet screenshotted on the emulator**.

`get_metadata` on page `0:1` is 288k characters and must be saved and grepped.

**Figma edits made 13 Sep** (in place, on Page 1 — version history is the
undo): 29 nodes rounded to radius 12 across 11 frames; the `Odaya Katıl` code
field shortened to a full pill with a YAPIŞTIR button; the `Başlangıç` frame
added at (3272, 1009).

---

## Working on this machine

Long commands exceed the 60-second desktop-bridge window and surface as
"unable to reach desktop-commander" while still running. Start them with
`start_process` and poll in short reads. (This applies to cloud sessions
reaching the PC through the bridge, not to Claude Code running locally.)

An incremental rebuild is **150–350 s**. The emulator was killed twice by
memory pressure during Gradle builds, threw a SystemUI ANR, and once wedged
entirely (frozen clock, stale frames — `adb emu kill` and relaunch). 7.7 GB is
tight. Re-check `adb devices` after every long build.

**Under version control since 6 October 2026:**
https://github.com/ymntrn/321football (public). `.gitignore` excludes
`supabase/.pgpass.local`, the `.venv`, build output and every `*.db` file —
the databases are too big for GitHub and need backing up separately.

Supabase was checked on 6 October after a three-week break: not paused,
`smoke_test.py` 0 failures.

---

## Next

1. **Run `docs/TESTING.md`** — the board, Versus and the four end screens
   against the bot, on the emulator. Run `tools\fetch_assets.ps1` first.
2. Profile `validateAnswer` on device. It no longer sits between the keypress
   and the timestamp (the stopwatch is read first), but it still decides how
   long a player waits to see "✓".
3. Decide the open questions the build raised: the clock ring (spec vs
   frame), Versus eating 2 s of the first pick, and what `seri` should mean.
