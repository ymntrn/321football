# Testing checklist — branch `screens-from-figma`

Everything on this branch was written in a cloud session with **no emulator,
no Android SDK and no database file**. What was checked there:

- `flutter analyze` — clean
- `flutter test` — all pass, including `test/match_layout_test.dart`, which
  pumps every new screen at 430x932, 411x914 and 360x640 and fails on any
  overflow (idle board, Versus, GOOOL, Tur Bitti, win, lose, the three
  practice popups, a 30-answer list)
- the new SQL (`mutualSpells`) against a small fixture built from
  `schema.sql`; `321_football_db/test_offline.py` — 71 passed

What was **not** checked anywhere: how any of it looks, the typing state of
the PvP board (needs the database), the Kotlin in `MainActivity.kt` (never
compiled), and every timing. That is this list.

Screens are listed with their Figma node so you can open the frame next to
the screenshot. `app\tools\shot.ps1` after each step.

---

## 0. Before building

1. `git checkout screens-from-figma`
2. Copy `321_football_db\321_football_slim.db` to
   `app\assets\db\321_football.db` if it is not already there.
3. **Run `app\tools\fetch_assets.ps1`.** It now also fetches the three Versus
   vectors (`versus_banner_top.svg`, `versus_banner_bottom.svg`,
   `versus_vs.svg`). The Figma asset URLs expire about a week after
   6 Oct 2026 — if they 404, re-export the three vectors of frame `27:42`
   (nodes `32:73`, `32:74`, `32:78`) and save them under those names.
   Then `git add app/assets/img/versus_*.svg` and commit them.
4. **Cold build** with `app\tools\build_apk.ps1` — `MainActivity.kt` changed,
   so this is the first time the Kotlin is compiled. If it fails, the error
   is almost certainly there; paste it back.

---

## 1. Cold start (item 5)

1. `adb shell pm clear com.yamanturan.football321`
2. Launch the app and watch the splash.

Expect: the `321` wordmark, a bar that **fills from left to right** with
`Veritabanı hazırlanıyor… %NN` counting up, then the dev menu.

Look closely at:
- Does the bar move at all? If it stays indeterminate (sliding) for the whole
  copy, `AssetInputStream.available()` returned 0 on this device — the copy
  still works, only the percentage is missing. Tell me.
- How long it takes. It was ~12.3 s with the old whole-file load; note the
  new number in `flutter-app.md`.
- Relaunch (no `pm clear`): the splash should flash by with no text.
- `adb logcat | findstr "streamed asset copy failed"` — if this appears, the
  channel failed and it fell back to the old path. Paste the message.

---

## 2. Practice (item 4)

Dev menu → **ALIŞTIRMA** → any difficulty.

| Step | Expect | Frame |
|---|---|---|
| Type a correct answer, GÖNDER | Board dims (60%), green **DOĞRU!** card: name, career line ("Club (2009–13) → Club (2013–17)"), `SIRADAKİ EŞLEŞME` bar filling over 2.5 s. Search bar underneath turns green with ✓, the name and a white `+1 SERİ` pill. Then a new pair, streak +1. | 78:610 |
| Same, but tap anywhere on the card | Skips straight to the next pair | — |
| Tap the **Cevap** chip | 72% scrim, blue card with the lightbulb badge on its top edge: `CEVABI GÖSTER?`, the cost text, VAZGEÇ / `3 ALTIN HARCA` | 82:338 |
| VAZGEÇ, or tap outside the card | Closes; same pair; streak unchanged | — |
| Cevap → `3 ALTIN HARCA` | `OLASI CEVAPLAR`: numbered green discs, names, career lines, `-3 🪙 altın harcandı`, green DEVAM | 78:483 |
| A pair with many answers (Hard) | List scrolls **inside** the card; DEVAM stays visible | — |
| DEVAM | **New pair, streak NOT reset** | — |

Look closely at:
- **The rule change:** revealing answers no longer resets the streak (the
  design's copy says so), and DEVAM skips to a new pair. Confirm that is
  what you want.
- The lightbulb badge's disc and glow are painted approximations of an SVG
  that could not be rendered — compare with the frame.
- Career lines: a row with no line means the query found no spells for that
  name at those clubs; a few blanks are expected, many are a bug.
- The three rejection messages still work (unchanged code, but the search
  bar area was touched): "SILVA" → `Hangisi? Adını da yaz`.

---

## 3. Friend Match (items 1–3)

The app must be the **host** — the bot does not drive phase transitions.

1. Dev menu → **ARKADAŞ MAÇI** → **Oda Kur**. Note the code.
2. `python supabase\bot.py <code>` (add `--slow` to let yourself win).
3. In the app, **Başlat**.

### 3a. Versus — 27:42

Expect for ~2 s right after Başlat: two white banners (yours top-left with
your name, the bot's bottom-right, mirrored), the orange-red **VS** glyph in
the middle, `ARKADAŞ MAÇI · İLK 3 GOL` under it. Then the team picker with
~13 s on its clock (Versus takes the first 2 of the 15).

Look closely at:
- If you see a flat red Jaro **VS** and no banners, the SVGs were not
  fetched (step 0.3).
- flutter_svg ignores SVG filters. If the VS glyph's export has a drop
  shadow it will be missing or hard-edged — compare with the frame.
- Banner names over the curved ends; long names should shrink, not clip.

### 3b. The board — 41:584 / 86:334

After both pick and the 3-2-1:

| Check | Expect |
|---|---|
| Idle | Score strip, red **10** counting down, the two big club cards, `Canlı Durum` strip (orange `Sen` avatar left, `yazıyor •••` + green bot avatar right), search bar, keyboard |
| Type 3+ letters | Big cards swap for the **compact strip** (crest · name · VS · name · crest) under the clock; **three** suggestions, best one with green border and ↵ |
| Correct answer via GÖNDER | `✓ Name` in green above the search bar; keyboard stops typing; `Sen · buldun!`; GOOOL within ~1 s |
| Correct answer by tapping a suggestion | Same |
| Wrong answer | Red rejection line, keep typing |
| Last 3 seconds | numeral pulses |
| Bot answers first | `buldu!` on its side, then GOOOL naming the bot |

**`app\tools\type.ps1` should work on this board unchanged** — the keyboard
widget and its position at the bottom are the same as Practice's, and
`turkish_keyboard.dart` was not touched. If taps land on the wrong letters,
re-measure from a board screenshot.

Look closely at:
- **Timing fairness.** Answer as fast as you can with `--slow` off: compare
  the `answered … after N ms` line the bot prints with the time on your
  GOOOL pill when you win, and that your pill time is believable (it is
  measured from the unlock, not from when the board appeared).
- The compact strip and the suggestion panel with the **system keyboard
  hidden** on a short screen: nothing should overflow (yellow/black bars).
- Long club names in the compact strip ellipsize rather than push VS off.
- There is deliberately **no ring** around the clock — the spec has one, the
  Figma frame does not. Say if you want it.

### 3c. GOOOL — 41:685

Expect: the score strip dimmed under a dark scrim, **GOOOL** in the
orange-red outlined lettering, the scorer's initials in a green glowing ring,
`<scorer> buldu`, the footballer's full name large, the career line, the
`⚡ 1,4 sn cevap süresi` pill, `SIRADAKİ TUR` and a bar filling over 2.5 s.

- Score at the top already includes the goal.
- **The final goal** (reaching 3) also gets its GOOOL for 2.5 s, *then* the
  result screen — check this specifically; it is a separate code path.

### 3d. Tur Bitti — 109:8

The bot never misses, so force a timeout: after both clubs are picked and
the 3-2-1 starts, **stop the bot with Ctrl+C** and don't answer.

Expect at 10 s: `TUR BİTTİ` in red outlined lettering, `Kimse doğru
futbolcuyu bulamadı`, `Puan yok`, and a `DOĞRU CEVAPLAR ŞUNLARDI` panel with
the three most famous answers. Score unchanged.

Then do not restart the bot — this continues into 3f.

The **unplayable** variant (`Bu iki takımın ortak oyuncusu yok`, no answer
panel, `Takımlar yeniden seçilecek`) needs two clubs with no shared player,
which the bot's random famous pick almost never produces. If you see it by
chance, screenshot it; otherwise it is unverified.

### 3e. Win / lose — 46:352 / 48:534

- **Kazandın:** play with `bot.py <code> --slow` and win 3 rounds.
- **Kaybettin:** play normally and let the bot answer every round.

Expect: green **Kazandın** / orange-red **Kaybettin** outlined title, the two
Jaro scores, orange and green name blocks, avatars with the **winner's gold
ring, glow and 👑 badge**, `MAÇ ÖZETİ` with three cards (`⚡ fastest`,
`🎯 correct/played`, `🔥 best run`), the violet **Tekrar Oyna** and
**Ana Sayfa**.

- `MAÇ ÖZETİ` numbers: check them against what actually happened. `seri`
  is the longest run of rounds *you* won in this match.
- There is deliberately **no trophy/coin row and no `2X Altın`** (economy,
  out of scope).
- **Tekrar Oyna** → the app lands on the waiting screen with BAŞLAT; press
  it and **Versus should play again** before the picker. Note the bot exits
  at `match_over` and cannot rejoin (it joins with a fresh id, and
  `join_room` refuses once the guest seat is taken), so after the rematch
  nobody plays the other side — expect a `Rakip ayrıldı` win ~20 s later.
  That is a limit of the bot, not of the rematch.
- **Ana Sayfa** → back to the dev menu.

### 3f. Forfeit — "Rakip ayrıldı"

Continuing from 3d (bot stopped): about 20 s after the bot's last heartbeat
the app claims the match. Expect **Kazandın** with `Rakip ayrıldı` above the
buttons.

Also try: in a fresh match, press Android back mid-round — the app should
forfeit and leave; the bot's console should show the room ending.

Not testable with the bot: `Bağlantın koptu` (you being claimed against —
the bot does not claim forfeits) and `Maç yarıda kaldı` (needs the
10-minute abandon job). Both are one-line text choices in `_result()` in
`match_screen.dart`.

---

## 4. Things I am unsure about

In rough order of how much I would want a second look:

1. **`MainActivity.kt` compiles and the channel works** (§0.4, §1).
2. **Versus eating 2 s of the first pick window** — the only way to show it
   without a protocol change. If 13 s feels short, the alternative is a
   backend change to start `pick_deadline` later.
3. **The board appearing on the clock, not on the phase.** The board shows
   once your clock passes `unlock_at`, even if the host's `open_answers`
   has not landed yet. The bot only answers once the phase is `answering`,
   so you may genuinely be a few hundred ms ahead of it — that is the
   protocol's design, not a bug, but watch for anything odd at the start of
   a round.
4. **The practice streak rule** (§2).
5. Painted approximations: the scorer ring on GOOOL and the lightbulb
   badge — compare with the frames.
6. On a short phone, the result screen and GOOOL **scroll** rather than
   squeeze; the layout tests prove no overflow at 360x640, not that it
   looks good there.
