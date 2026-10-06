# Testing checklists

- **§R — branch `release-prep` (6 Oct 2026): NOT yet run.** Below.
- §A — branch `front-door-and-ranked`: run on the emulator 6 Oct 2026
  (results at the end). Its fixed-bugs list still applies.
- §B onwards — branch `screens-from-figma`, run on the emulator 6 Oct 2026
  (results at the end). Its fixed-bugs list still applies; nothing on the
  new branch touches those code paths' rules (range comparisons, minPrefix
  3, explicit fontFamily on RichText, blur-0 hard shadows, full-width
  buttons).

---

# R. Release prep — branch `release-prep`

Written in a cloud session: no emulator, no Android SDK (Google's Android
download hosts are blocked there, so **Gradle never ran**), no database
file, no route to Supabase. What WAS checked there:

- `flutter analyze` — clean; `flutter test` — 95 pass, including
  `sfx_assets_test` (every Sfx has its file), `release_config_test`
  (Google flag off, ad ids well-formed and readable by Gradle, no banner /
  interstitial, signing / R8 / label / version settings), `legal_text_test`
  (the hosted policy matches the in-app text) and overflow tests for the
  2X Altın result screen, Gizlilik and Destek at three sizes
- migrations 010 and 011 applied after 006–009 to a local Postgres 16
  (`supabase/localpg/`, `check_010.py` 16 checks, `check_011.py` 11
  checks, 0 failures overall)

Not checked anywhere: any sound, any ad, the Gradle build (signing, R8,
the AdMob-id placeholder), Google Sign-In, the mail intent, and whether
Supabase lets `delete_my_account` delete from `auth.users`.

## R0. Supabase — apply 010, THEN 011

011 deletes from 010's `coin_doubles` table, so the order matters.

```
python supabase\migrate.py supabase\010_double_reward.sql
python supabase\smoke_test_010.py
python supabase\migrate.py supabase\011_delete_account.sql
python supabase\smoke_test_011.py
python supabase\purge_test_accounts.py          (lists the Smoke* players)
python supabase\purge_test_accounts.py --apply
```

Each smoke test ends with `FAILURES: 0`; if PostgREST says the function
does not exist, wait a few seconds (schema cache) and re-run, as with 006.

- **smoke_test_011's "auth user gone" is the important line.** Locally the
  function owner is a superuser; on Supabase it is `postgres`, which may
  or may not be allowed to delete from `auth.users`. If that line fails,
  paste the output — the fix is a small new migration, not an edit to 011.

## R1. Build

1. `git checkout release-prep`, `flutter pub get` (new packages:
   `audioplayers`, `google_mobile_ads`, `google_sign_in`, `url_launcher`).
2. **Cold build** (`app\tools\build_apk.ps1`): four new native plugins,
   the manifest and `build.gradle.kts` changed. If it fails, the likely
   places are, in order: the AdMob-id regex near the top of
   `build.gradle.kts` (error says `admobAppIdAndroid not found`), the
   `signingConfigs` block, a plugin's minSdk. Paste the error.
3. Launch. **The app must not crash at start** — the Mobile Ads SDK
   crashes on launch if the manifest's APPLICATION_ID is missing.
   `adb logcat | findstr /i "ads"` should show the SDK initialising.
4. Home screen label and recent-apps title read **321 Football**.

## R2. Sound effects (Ses on)

Placeholder beeps (`tools/make_sfx.py`); judge timing, not quality.

| Moment | Sound |
|---|---|
| Any letter / boşluk / ⌫ on the custom keyboard (Practice, PvP board, team picker) | short click (`tap`) — GÖNDER itself does not click |
| Correct answer (Practice, PvP) | rising two-note (`correct`) |
| Wrong answer | low buzz (`wrong`) |
| Countdown 3 · 2 · 1 | one tick per numeral (`tick`) |
| GOOOL | fanfare + noise (`goal`) |
| Tur Bitti | two falling notes (`round_over`) |
| Kazandın / Kaybettin | arpeggio up (`win`) / slide down (`lose`) |
| Maç Aranıyor → opponent found | two pings (`match_found`) |
| Ayarlar → Ses switched ON | one click (proof it works) |

- **Ses off → none of the above**, everywhere; kill / relaunch keeps it.
- Titreşim is independent: Ses off + Titreşim on still vibrates.
- Play music from another app, then play: the music keeps going under the
  effects (mixed, not ducked or stopped).
- Typing fast does not stack clicks into a buzz (each effect restarts).

## R3. 2X Altın — the rewarded ad (Figma 46:352)

Test ads (Google's test ids) — they say "Test Ad".

1. `python supabase\bot.py --ranked --slow`, Hemen Oyna, **win**.
2. On Kazandın, within a second or two: **Tekrar Oyna and 2X Altın side by
   side** (170x90 each, the right one yellow with a coin), the coin row
   reading `+10`. Compare with the frame.
3. Tap 2X Altın → the test rewarded ad → watch it to the end → close.
   The coin row now reads **`+20`**, the 2X button is gone (Tekrar Oyna is
   full-width again), Ana Sayfa's coin chip shows +20 in total for the
   match.
4. Dashboard: `coin_doubles` has one row for that room; the profile's
   coins rose by 10 more.
5. Again, but **close the ad early** → button gone, coins stay at +10.
6. Again, but turn on **airplane mode** just before the last goal → no 2X
   button at all; the screen is otherwise normal.
7. **Lose** a ranked match → no 2X button. **Friend Match win** → no 2X.
8. Short phone check: on the Pixel 6 the ranked win with the 2X row still
   shows Ana Sayfa without scrolling far (fixed bug A-2 in §A results).

Not testable from Turkey without extra setup: the EEA/UK consent form
(UMP). Optional: AdMob → Privacy & messaging, plus a debug geography.

## R4. Google ile bağla — flag OFF

- Profil: **no Google button**; the Apple button exactly as before
  (dimmed, not tappable).
- With the flag on (only after `release.md` Appendix A): Profil → Google
  ile bağla → picker → "Hesabın Google'a bağlandı" → button reads
  "Google'a bağlı ✓". Supabase → Auth → Users: same user id, provider
  google. Then `pm clear`, pick a new username, Profil → Google ile bağla
  → **BU GOOGLE HESABI KULLANILIYOR** → O HESABA GEÇ → the old name, tag,
  trophies and coins come back. (The fresh account made in between is left
  behind on the leaderboard — `purge_test_accounts.py` lists it.)

## R5. Gizlilik & Şartlar (92:270) and Destek & İletişim (92:310)

Ayarlar → each row now opens its screen (no more `Yakında`).

- **Gizlilik:** title, `Son güncelleme: 6 Ekim 2026`, the orange TASLAK
  card, `GİZLİLİK POLİTİKASI` cards, `KULLANIM ŞARTLARI` cards, the thin
  scrollbar on the right; scrolls to the end; Undo goes back.
- **Destek:** the first FAQ open with `−`; tapping another opens it and
  closes the first. `BİZE ULAŞ` card: tap the e-mail row → "E-posta adresi
  kopyalandı"; **SORUN BİLDİR** → the mail app with the address, subject
  "321 Football — Sorun bildirimi" and a body ending with `Kimlik:
  Name#TAG` and the version. (No mail app on the emulator → it copies the
  address instead.) The `Kimlik · Sürüm · Veri` line shows your real
  `Name#TAG`.
- Compare both with their frames; the deliberate differences are listed
  in each screen's class comment.

## R6. Hesabımı sil — on a THROWAWAY account

**Not on your real account.** `adb shell pm clear com.yamanturan.football321`
first, pick a username like `SilTest`, play nothing or one Practice Cevap.

1. Optionally add the bot as a friend (§A7) so the friendship row exists.
2. Ayarlar → Destek → scroll down → `HESAP` → **Hesabımı sil** (red) →
   popup **HESABINI SİL** naming `SilTest#XXXX` → VAZGEÇ → nothing happens.
3. Again → **KALICI OLARAK SİL** → the username screen (first launch).
4. Dashboard: no `profiles` row for that id, no `friendships` rows, no
   `match_queue` row, and Authentication → Users no longer lists the user.
5. Pick a new username → Ana Sayfa; a **new tag**, 30 coins, 0 trophies.
6. Airplane mode → Hesabımı sil → KALICI OLARAK SİL → "Bağlantı
   kurulamadı", still on Destek, nothing deleted.

## R7. Release build (R8) — before any Play upload

1. Without `key.properties`: `flutter build apk --release` (signed with the
   debug key) → `adb install -r build\app\outputs\flutter-apk\app-release.apk`.
2. Play it as a player would: cold start (database copy), Practice, a
   ranked match against the bot with a win and **2X Altın** (proves R8 kept
   the ads SDK), sounds, Destek's SORUN BİLDİR, a Friend Match.
3. Any crash: `adb logcat` — `ClassNotFoundException` /
   `NoSuchMethodException` mean a missing keep rule in
   `android/app/proguard-rules.pro`; paste it.
4. With `key.properties` (release.md step 1):
   `flutter build appbundle --release` succeeds and the `.aab` is signed
   with the upload key (`keytool -printcert -jarfile app-release.aab`).

## R8. Regressions

Nothing on this branch touches the rules in §A/§B's fixed-bug lists, but
re-check the ones near changed code: ranked coins/trophies refresh after a
match (§A results 1), the ranked result screen fits the Pixel 6 (§A
results 2 — now with the 2X row), Practice's three popups (keyboard now
clicks), the team picker's tick haptic.

---

# A. Accounts, front door, ranked — branch `front-door-and-ranked`

Written in a cloud session with no emulator, no database file and no route
to Supabase. What WAS checked there:

- `flutter analyze` — clean
- `flutter test` — 62 pass, including `test/front_door_layout_test.dart`
  (every new screen at 430x932, 411x914, 360x640, offline state) and
  `test/haptics_test.dart` (no raw HapticFeedback outside `Haptics`)
- migrations 006–009 applied in order to a local Postgres 16 with Supabase
  stubs and exercised by `supabase/localpg/check_00{6,7,8,9}.py` — 0
  failures (profiles, tags, RLS, a whole match through
  record_match_result twice, the economy, friends, pairing, the widening
  window, cancel)

Not checked anywhere: how any screen looks, the real Supabase project (auth
settings, grants, Realtime under the new RLS), and any timing.

## A0. Before anything — Supabase dashboard

1. **Authentication → Sign In / Providers → "Allow anonymous sign-ins": ON.**
   Without it the app cannot sign in, and after 006 nobody can read a room.
2. Authentication → Rate Limits: the anonymous sign-in limit is per IP
   (30/hour by default). Each smoke test makes 2–4 users; if a test says
   "anonymous sign-in failed (429)", wait or raise the limit.
3. (Optional baseline) run the OLD smoke tests now, before 006:
   `python supabase\smoke_test.py`, `smoke_test_flow.py`, `smoke_test_004.py`,
   `smoke_test_005.py`. **After 006 they fail by design** (they use the bare
   key and random ids, which the new RLS refuses).

## A1. Apply the migrations — in this order

```
python supabase\migrate.py supabase\006_accounts.sql
python supabase\smoke_test_006.py
python supabase\migrate.py supabase\007_results.sql
python supabase\smoke_test_007.py
python supabase\migrate.py supabase\008_friends.sql
python supabase\smoke_test_008.py
python supabase\migrate.py supabase\009_matchmaking.sql
python supabase\smoke_test_009.py
```

Each smoke test ends with `FAILURES: 0`. If one fails, stop and paste its
output. (009 assumes nobody else is queueing for ranked at that moment.)

## A2. Build

1. `git checkout front-door-and-ranked`
2. **Run `app\tools\fetch_assets.ps1`** — 13 new exports (nav icons, trophy,
   leaderboard toggle icons, pencil, the four profile stat icons, and the
   Apple button). The URLs expire about **13 Oct 2026**. Then
   `git add app/assets/img/*.png` and commit them. Until fetched, slots show
   Material icons / emoji and the Apple button slot is empty.
3. `app\tools\rebuild.ps1` (no Kotlin changed; incremental is fine).

## A3. First launch — splash and username (48:570, 92:190, 94:190)

1. `adb shell pm clear com.yamanturan.football321`, launch.
2. **Splash:** `Yükleniyor` / `Veritabanı hazırlanıyor… %NN` over the
   purple-to-blue bar on a dark track, `V 1.0.0` at the foot.
3. **Username screen** appears (only on a first launch). Tap the field — the
   SYSTEM keyboard opens (deliberate: digits and `_` are allowed).
   - Type `ab` → DEVAM ET stays dim, the hint turns red.
   - Type `Yaman` → green ✓ in the field, green `Bu kullanıcı adı uygun`.
   - DEVAM ET → for ~1 s the pill shows `Etiketin #XXXX` in green (the real
     tag), then Ana Sayfa.
4. Kill and relaunch: straight to Ana Sayfa, no username screen.
5. Supabase → Table editor → `profiles`: one row, username `Yaman`, a
   4-char tag with no 0/O/1/I, 0 trophies, 30 coins.

Also try once **offline** (airplane mode) on a fresh `pm clear`: the
username screen still accepts the name and goes to Ana Sayfa; coins and
trophies read `–`; Practice works; Cevap is dimmed. Turn the network back
on, relaunch → the chips fill in and the profile exists.

## A4. Ana Sayfa (4:4)

- Coin chip (top-left), trophy chip, the 👥 friends button with a green
  count badge when someone has sent you a request.
- Hemen Oyna (orange-red), Alıştırma Yap (green), Arkadaş Maçı (violet).
- Bottom nav: leaderboard · shop · settings · person. Shop → `Mağaza
  yakında`. From any tab, the Undo arrow returns to Ana Sayfa.
- **Debug builds only:** long-press the coin chip → the old dev menu.
- Back button on Ana Sayfa exits the app.

## A5. Practice coins

1. Alıştırma Yap → any level → Cevap → the confirm popup now shows
   `Bakiyen 🪙 30` (82:469).
2. `3 ALTIN HARCA` → the answer list; Ana Sayfa's coin chip later reads 27.
3. Repeat until under 3 coins → the Cevap chip dims to 45% and does nothing.
   (Give yourself coins back in the table editor.)

## A6. Profil (53:469)

- Name, `#TAG`, copy (copies `Name#TAG`), share, trophies, coin chip,
  the Apple button **dimmed and not tappable**, four stat cards: Toplam
  Maç, Kazanma Oranı `%NN`, Şu Anki Seri (+ `En iyi: N`), En Hızlı Cevap.
- Pencil → rename popup. Try `x` (refused), then a valid name → saved; the
  tag is unchanged. Check `profiles` in the dashboard.

## A7. Friends (92:230, 97:190) — needs a second account

Use the bot's account or `python -c` with sbclient; the simplest is:
`python supabase\bot.py --ranked --name Kanka` (Ctrl+C it at once — it has
created a profile `Kanka#XXXX`; the tag is printed as `bot is Kanka#XXXX`).

1. 👥 → Arkadaşlar: your own card (tap → `Kimliğin kopyalandı`).
2. ARKADAŞ EKLE → type `kanka#xxxx` (any case) → the result card with EKLE →
   `İstek gönderildi`. Wrong tag → `Böyle bir oyuncu yok`. Your own id →
   EKLE dimmed.
3. The request shows under ARKADAŞLARIN as `bekliyor` with ✕.
4. Accept it from the other side (smoke_test_008 style, or the dashboard:
   set `friendships.status = 'accepted'`) → the row shows 🏆 and ✕.
5. ✕ → confirm popup → SİL → gone.
6. Incoming: have the other account send YOU a request → Ana Sayfa's 👥
   shows a green `1`; Arkadaşlar shows it under İSTEKLER with ✓ / ✕.

## A8. Leaderboards (51:567, 51:860)

- Global: gold/silver/bronze podium, `4 – 100. SIRA`, the list scrolls, and
  YOUR row is pinned above the nav with your rank in green.
- Toggle (people icon) → Arkadaş: `N ARKADAŞ`, one list, your row green.
- No flags (no country data — deliberate).

## A9. Ayarlar (51:1088)

- Two switches, `Ses` and `Titreşim`, both on. Version text.
- **Titreşim off → play Practice: a wrong answer and a correct answer must
  NOT vibrate; the team picker must not tick.** Back on → they vibrate.
  Kill/relaunch → the switch keeps its state.
- Ses toggles and persists; it plays nothing (no sound files yet).

## A10. Ranked "Hemen Oyna" with the bot (12:95 → match → result)

The app must host (the bot cannot drive a match); `--ranked` takes care of
that whichever side pairs.

1. `python supabase\bot.py --ranked` (add `--slow` to let yourself win). It
   prints `queueing for ranked ...`.
2. In the app: **Hemen Oyna** → Maç Aranıyor: the arched title, orange dots
   circling, `Rakip aranıyor 0:0N`, `0 – 100 kupa aralığında
   eşleştiriliyorsun` (widening by 100 every 5 s), your slot with trophies,
   the dashed `?` slot, the red İptal.
3. Within a second or two the slot fills with `Bot`, `bulundu!`, then
   **Versus with `SIRALI MAÇ · İLK 3 GOL`**, then the normal match.
4. Win (with `--slow`) → Kazandın with **`+30 🏆` and `+10 🪙`** under MAÇ
   ÖZETİ. Lose → **`0 🏆`** (if you were at 0) or **`-20 🏆`** in red, and
   `+2 🪙`.
5. Ana Sayfa → the chips show the new trophies and coins. Profil: matches
   +1, win rate, streak, fastest answer updated.
6. Kazandın → **Tekrar Oyna → back to Maç Aranıyor** (queues again).
7. **Cancel:** Hemen Oyna with no bot running → İptal → back on Ana Sayfa.
   Android back does the same.
8. Dashboard: `rooms` row has `ranked = true`, `result_recorded_at` set, the
   four delta columns; `match_queue` is empty afterwards.

## A11. Friend Match still works — and now counts

1. Arkadaş Maçı → Oda Kur → `python supabase\bot.py <code>` → Başlat.
2. Play to the end. The result screen has **no** trophy/coin row.
3. Profil: matches +1 (stats count); trophies and coins unchanged.

## A12. Things I am unsure about

1. **Realtime under the new room RLS.** Postgres changes are filtered by
   RLS, so the subscription now depends on the session JWT reaching
   Realtime (supabase_flutter does this). The 2-second poll is a backstop
   either way; if updates feel ~2 s late, Realtime is not seeing the JWT.
2. Two clients polling find_match: the advisory lock serialises them;
   watch for two rooms being created for one pair (should be impossible).
3. Arc title and orbit loader on Maç Aranıyor — painted approximations;
   compare with the frame.
4. Nav-bar icon positions are scaled from the 430 frame; check on the
   Pixel 6.
5. Long usernames (16 chars) in the profile header and the leaderboard rows
   (they shrink/ellipsize, never overflow — tested, but not looked at).

---

# B. Testing checklist — branch `screens-from-figma`

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


---

## Results — emulator run, 6 Oct 2026

Run on the Pixel 6 AVD, app as host, `supabase/bot.py` as guest, plus a
throwaway driver that patched the host's club and typed answers on the
emulator keyboard so rounds could be won inside ten seconds.

**Verified working:** cold build (the new `MainActivity.kt` compiles, the
streamed copy runs with no fallback), the progress splash, Practice end to end
(Doğru card, Cevap → confirm → answer list → DEVAM with the streak kept), the
Friend Match lobby, Versus, team pick and its 15 s auto-pick, the PvP board
with the compact matchup strip, GOOOL with career line and answer time,
Tur Bitti for a dead pair (round replayed with the same number), win and lose
screens with a correct summary, and a live forfeit (`Rakip ayrıldı`).

**Bugs found and fixed in this run:**

1. **The match froze on an unplayable pair** — found on device, and older than
   this branch. The host voids a dead pair from `picking`, but
   `finish_round`'s guard only accepted `answering`/`countdown`, so the call
   was a silent no-op retried four times a second. Fixed server-side in
   `supabase/005_void_from_picking.sql` (applied), checked by
   `smoke_test_005.py` (9/9); the three older smoke tests still pass.
2. **The summary counted the deciding round twice** ("0/4 doğru" after three
   rounds) — `finish_round` writes round_over and match_over in one call and
   Realtime delivers both. `match_screen.dart` now skips match_over when it
   follows round_over.
3. **Career lines merged a club's spells** — Staunton showed
   "Liverpool (1986–2000) → Aston Villa (1991–2003)". `mutualSpells` now
   returns one entry per spell in career order, joining only back-to-back
   spells at the same club.
4. **A stale rejection stayed under the Doğru card** in Practice — cleared on
   a correct answer now (the PvP board already did this).
5. **Rematch was offered after a forfeit**, when the other player is gone —
   now only after a match decided on goals.
6. **Launch flashed white with the Flutter logo** — Android launch theme and
   the Android 12+ system splash are now navy (`#0A0D3B`), no icon.
7. **Supabase init blocked the first frame** — it now runs in parallel with
   the database open.
8. **The DB copy spent its time decompressing** — `.db` is stored
   uncompressed in the APK (`noCompress`). Debug APK 189 → 219 MB; the Play
   download size is unaffected.

**Cold start on the debug emulator:** about 12 s from tap to ready, of which
~7 s is the debug build's own engine start-up (absent in release) and ~5 s
the database copy. Measure again on a release build on a real phone.

**Noticed, not changed (decisions or later work):**

- GÖNDER submits exactly what is typed; it does not take the highlighted
  suggestion. That follows the exact-match rule, but the top row's ↵ mark
  suggests otherwise. Decide which you want.
- The coin count stays at 3 after "spending" 3 — there is no coin balance yet.
- The VS glyph's SVG filter (its shadow) is ignored by flutter_svg.
- Jaro's `0` renders as a hollow bar, very visible at timer and score sizes.
- Data: pre-1990 players with year-less spells (e.g. Bertram Goode for Aston
  Villa × Liverpool) still count as answers — the 1990 cutoff lets NULL-year
  spells through.


---

## §A results — emulator run, 6 Oct 2026 (evening)

Backend: anonymous sign-ins switched on in the dashboard; 006–009 applied in
order; smoke tests 006/007/008/009 all `FAILURES: 0` (006 needed one re-run
right after migrating — PostgREST's schema cache had not caught up yet).
`finish_round` is untouched by 006–009, so 005's fix stands.

**Verified on the emulator:** first launch → username screen (validation
both ways, keyboard ✓ submits, real tag `#UKZH` from the server) → Ana Sayfa;
Profil, Global and Arkadaş leaderboards, Ayarlar; ranked Hemen Oyna against
`bot.py --ranked` (paired in ~1 s, Versus says SIRALI MAÇ, live room updates
arrive under the new room RLS, +30 🏆 / +10 coins, loser floored at 0
trophies with +2 coins); Friend Match under the new RLS (stats count,
trophies/coins unchanged, no economy row); Practice Cevap spends real coins
(50 → 47 on the server); friends: add by `bot#5wdx` (case-insensitive),
request, accepted list with trophies and remove button.

**Bugs found and fixed:**

1. **Coins/trophies went stale after a ranked match** when the opponent
   recorded the result first: `_recordResult` returned early on an
   already-recorded room, and that call is also what refreshes the account
   (Ana Sayfa's own refresh fires when matchmaking is *replaced* by the match,
   i.e. at the start). It now always calls the idempotent RPC once.
2. **Ranked result screen pushed Ana Sayfa off the bottom** — the trophy/coin
   row did not fit with the frame's fixed gaps on a ~860 pt phone. Gaps now
   shrink to 55 % when the available height is under 900 pt.
3. **Test accounts on the real leaderboard.** Every bot run created a new
   `Bot#XXXX`. `sbclient.Player(session=...)` now reuses a saved session and
   `bot.py` keeps one per name in `supabase/.bot_<name>.local` (gitignored).
   `supabase/purge_test_accounts.py` lists the leftovers (dry run) and deletes
   them with `--apply`; run it after smoke tests. 006's test creates
   realistically named players (`Yaman2`, `Şükrü_10`, `Yaman`) — pass their
   tags with `--also`.

**Not checked on device:** vibration (the emulator cannot show it; covered by
the unit test that fails if any haptic skips the Titreşim setting), the
offline first launch, incoming friend requests and the badge, rename, and
cancelling matchmaking.

---

## Data fixes - 6 Oct 2026 (night)

Backups of both databases before any change: `db_backup_2026-10-06/` (gitignored).

1. **Duplicate clubs.** Wikidata has a second, page-less item for many German
   clubs under the formal name (Q979xxxxx: "FC Bayern München", "BV Borussia
   09 Dortmund", "SG Dynamo Dresden" ...), splitting a stray player off the
   real club. 14 are merged by `merge_duplicates.py` (new MANUAL_MERGES list,
   keyed by QID, keepers checked against the DB); their names became search
   aliases. Lookalikes that are different clubs were left alone (VfB Leipzig
   is not RB Leipzig, Fortuna Köln is not 1. FC Köln).
2. **Club nicknames.** 278 added by the new `curate.py` step. Checked in the
   team picker: `gs` -> Galatasaray first, `barca` -> FC Barcelona, `spurs`
   -> Tottenham.
3. **Nationality labels.** 4,272 players relabelled ("Kingdom of the
   Netherlands", "United Kingdom of Great Britain and Ireland", "German
   Reich", a stray genid URL ...). The suggestion sub-line is now Turkish
   (`İrlanda · 1986-2005`) through an extended `countryNamesTr`.
4. **Pre-1990 players counting as answers.** New `enrich_players.py` step:
   own Wikipedia sitelinks for 89,750 players and birth years for 91,321;
   14,678 open/undated spells of players born before 1955 dropped.
5. **Player fame (found on the way).** Fame now leads with the player's own
   sitelinks. Villa x Liverpool's answer key opens with Reina, Coutinho,
   Keane, Milner; `messi` ranks Lionel first; Bertram Goode is gone.

Verified: `verify.py` 43 passed / 0 failed; `test_offline.py` 71 passed;
slim sanity check good; practice pairs 27,132 -> 27,109 (easy unchanged at
216); `flutter test` 62 passed with the regenerated name-parity fixture
(36,077 pairs). `AppDatabase.assetVersion` is 2 - on the emulator an install
over the old build replaced the database on first launch (60.4 MB).

Not changed: "Luka Modriç" is stored with ç (a Wikidata label quirk); fix
with `manual_names.py` if it matters.
