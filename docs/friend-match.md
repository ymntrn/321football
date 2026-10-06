# Friend Match — the live working doc

Started 13 September 2026. The doc for the online private-room mode.

**Supersedes the open questions in `pvp-handoff.md` and `project-state.md`**
("OPEN DECISION — PvP rounds with no possible answer", "Choose Firebase or
Supabase"). Reconcile those when this piece lands.

Scope: **Friend Match only.** No matchmaking, no ELO, no trophies.

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
| **PvP board (the answering phase)** | **NOT BUILT — this is the gap** |
| Versus, GOOOL, Tur Bitti, win/lose screens | **Placeholders, not from Figma** |

**The honest summary: the backend is finished and the loop runs end to end,
but four screens are still mine rather than Yaman's design, and there is no
board to type an answer into.**

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

Verify with `smoke_test.py` (14), `smoke_test_flow.py` (26 — drives a whole
match over HTTP), `smoke_test_004.py` (18). `audit.py` reports room counts,
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

Any holder of the publishable key can read and write any room. That matches
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
  match_screen.dart             THE STATE MACHINE + placeholder round/match ends
  match_countdown_screen.dart   Maç - Geri Sayım (38:200)
  match_team_select_screen.dart Maç - Takım Seçme (33:85, 86:190)
lib/widgets/
  lobby_chrome.dart      tab buttons, room panel, name strips, avatars, action button
  club_search_panel.dart TAKIMLAR panel + ClubBadge
  match_chrome.dart      score strip, round timer, crest slot, opponent pill
```

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
| `27:42` | Versus | **no — skipped** |
| `41:584` / `86:334` | Maç - Oyuncu Arama (+ typing) | **no — the gap** |
| `41:685` | Maç - Tur Sonu (GOOOL) | **placeholder** |
| `109:8` | Maç - Tur Bitti (Beraberlik) | **placeholder** |
| `46:352` / `48:534` | Maç Sonu Kazanma / Kaybetme | **placeholder** |

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

1. **The PvP board** (`41:584` / `86:334`) — the practice board plus the clock
   ring, three suggestions, the compact matchup strip, `Stopwatch` stamped at
   the GÖNDER press. Without it there is no way to answer.
2. Versus (`27:42`).
3. Real GOOOL / Tur Bitti / win-loss screens.
4. Profile `validateAnswer` on device — it now sits between the keypress and
   the timestamp that decides the round, and has never been measured on a phone.
