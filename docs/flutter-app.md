# The Flutter app — state and architecture

Companion to `project-state.md` (the database) and `figma-to-flutter.md` (how
the UI gets built). Last updated: 6 October 2026.

> **6 Oct 2026, branch `release-prep`:** sound effects, the rewarded ad,
> Google linking (off), Gizlilik/Destek, account deletion and release
> signing/R8 — see `accounts-and-ranked.md` → *Release prep* and
> `release.md`. Not yet run on the emulator (`TESTING.md` §R).

> **6 Oct 2026 — branch `screens-from-figma`, written in a cloud session and
> NOT yet run on the emulator.** Practice's three popups are now built from
> Figma (see *Practice popups* below), the first-launch database copy is
> streamed with real progress on the splash, and `game_queries.py` has the
> namesake fix. `flutter analyze` is clean and `flutter test` passes
> (including new layout tests), but none of it has been looked at on a
> device. `docs/TESTING.md` is the checklist.

**Status: Practice mode is BUILT, RUNNING and VERIFIED on the emulator, and the
UI is now rebuilt from the Figma file rather than the written spec.** The full
loop works end to end — random pair, custom keyboard, live suggestions,
exact-match validation, streak, celebration, auto-advance. All three rejection
paths were exercised on device and each shows its own copy.

---

## Where it lives

    C:\Users\PC\Documents\321-football\app

Sibling of `321_football_db`, so the whole project sits under one parent.

---

## Toolchain on Yaman's PC

Everything is user-scoped under `C:\src`. Only one step ever needed admin
(enabling Windows Hypervisor Platform, already done, `tools\enable-emulator.ps1`).

| Component | Version | Path |
|---|---|---|
| Flutter | 3.47.3 stable (Dart 3.13.3) | `C:\src\flutter` |
| JDK | Microsoft OpenJDK 17.0.20 | `C:\src\jdk` |
| Android SDK | platforms 35 + 36, build-tools 35/36, platform-tools 37 | `C:\src\android-sdk` |
| Emulator | 37.1.11, AVD `football321` (Pixel 6, Android 15, x86_64) | same |

`JAVA_HOME`, `ANDROID_HOME`, `ANDROID_SDK_ROOT` and PATH are set as **user**
environment variables — new terminals pick them up, existing ones do not.

### `tools/` — the scripts that make this repeatable

| Script | Purpose |
|---|---|
| `check.ps1` | `flutter analyze` + `flutter test` with the right environment |
| `rebuild.ps1` | analyze, incremental build, install, relaunch (~60–120 s) |
| `build_apk.ps1` | Kills the emulator to free RAM, then does a cold build |
| `emulator.ps1` / `wait_boot.ps1` | Boot the AVD and wait for it |
| `play.ps1` / `type.ps1` / `reject.ps1` | Drive a round on device (see below) |
| `shot.ps1` | Screenshot the emulator into `build/shots/` |
| `ram.ps1` / `procs.ps1` | What is eating memory right now |
| `explain.py` | Candidate counts + timings for the suggestion query |
| `answer.py` | Answer key for any club pair, from the shipped asset DB |
| `fetch_assets.ps1` | Re-downloads the exported Figma assets |
| `export_name_fixture.py` | Regenerates the name-parity fixture |
| `make_sfx.py` | Writes the placeholder sound effects into `assets/audio/` (stdlib only; replace a WAV with a real sound of the same name) |

**`adb shell input text` does not work on this app.** The keyboard is a Flutter
widget, not a system IME, so there is no text field for Android to type into.
`type.ps1` taps letter coordinates measured from a screenshot of the real
keyboard — **if `turkish_keyboard.dart` changes its metrics, re-measure and
update the constants in that script.**

---

## This machine's constraints — all hit, all worked around

**RAM is the limit: 7.7 GB.** Disk is not (65 GB free after cleanup). The two
get confused; only RAM matters for building.

**The Flutter template asks for an 8 GB Gradle heap.** `android/gradle.properties`
shipped `-Xmx8G -XX:MaxMetaspaceSize=4G`, sized for a 16–32 GB machine. Capped
to `-Xmx1536m -XX:MaxMetaspaceSize=512m` with `org.gradle.parallel=false`.
**Do not let a Flutter upgrade restore the template values.**

**Cold builds need the emulator off** (it holds ~2.4 GB; free RAM fell to
270 MB and the build crawled). `build_apk.ps1` handles this. Incremental builds
with the emulator running are fine.

**`flutter test` needs `%PROGRAMFILES(X86)%` set** in non-interactive shells or
Flutter's Visual Studio probe throws, even for an Android-only project.

---

## Architecture

    lib/
      main.dart                       boot: opens the DB (splash with copy
                                      progress), then the dev menu
      theme/tokens.dart               the `321 Tokens` collection + gradients
      models/models.dart              Club, Player, PracticePair, AnswerResult
      data/
        name_normalizer.dart          port of names.py
        app_database.dart             streamed asset copy + sqflite open
        game_queries.dart             port of game_queries.py
      screens/
        practice_difficulty_screen.dart   Seviye Seç
        practice_board_screen.dart        the board + typing state + popups
      widgets/
        screen_background.dart        rings + glow backdrop, Undo, HomeIndicator
        club_card.dart                Kulüp Kartı (the Arma slot lives here)
        practice_chrome.dart          top bar, matchup, badges, PAS GEÇ,
                                      rejection banner, Doğru / Cevap Onayı /
                                      Cevabı Göster popups
        career_line.dart              "Club (2009–13) → Club (2013–17)"
        search_bar_panel.dart         Arama Çubuğu (+ its green Doğru state)
                                      + Öneriler panel
        turkish_keyboard.dart         the four-row Klavye

      ads/                            ad_config.dart (every AdMob id, TEST ids
                                      until release), rewarded_coins_ad.dart
                                      (consent + the 2X Altın rewarded ad)
      legal/legal_text.dart           Gizlilik policy + terms (DRAFT), support
                                      e-mail; docs/privacy-policy.md is
                                      generated from it

    assets/img/                       exported Figma assets (see figma-to-flutter.md)
    assets/audio/                     placeholder SFX (tools/make_sfx.py)
    android/.../MainActivity.kt       the `football321/asset_copy` channel
    test/match_layout_test.dart       overflow tests for the new screens at
                                      430x932, 411x914 and 360x640

`assets/db/321_football.db` is a copy of `321_football_slim.db` (62 MB). sqflite
needs a real file, so `AppDatabase.open()` copies it out of the bundle on first
launch and opens it read-only.

**The copy is streamed (6 Oct 2026).** `rootBundle.load()` held all 62 MB in
memory before writing a byte. On Android, `MainActivity.kt` now exposes a
`football321/asset_copy` MethodChannel: it reads the asset through
`AssetManager` in 1 MB chunks on a background thread, reports progress every
2 MB, writes `<db>.part` and renames it when done. The total comes from
`AssetInputStream.available()`, which is the *uncompressed* length, so the APK
keeps the database compressed (no `noCompress` needed). The splash shows a
determinate bar and "Veritabanı hazırlanıyor… %NN" while it runs. Any channel
failure falls back to the old `rootBundle.load()`. The version stamp is still
written only after the copy lands. **Bump `AppDatabase.assetVersion` whenever a new
database is dropped in**, or the stale copy wins and the new data never appears.

(Since 6 Oct 2026 the `.db` files are gitignored. After a fresh clone, copy
`321_football_db/321_football_slim.db` to `app/assets/db/321_football.db`.)

---

## Bugs found by actually running it

Every one of these was invisible to `flutter analyze`, which stayed clean
throughout. They were caught by the parity test, by driving the app on a device
and looking at screenshots, and by measuring queries.

### 1. The normalizer was wrong — caught by the parity test

`test/name_parity_test.dart` checks the Dart normalizer against **36,767 real
name/normalized pairs exported from the shipped database**, including all
23,515 non-ASCII ones. **It failed on the first run.**

Dart has no `unicodedata`, so the port originally used the `diacritic` package
in place of `unicodedata.normalize('NFKD', …)`. `diacritic` is a Latin-only
lookup table; NFKD is universal:

| Input | Python (NFKD) | `diacritic` |
|---|---|---|
| `Сергей` (Cyrillic и-breve) | `сергеи` | `сергей` |
| `Σωτήρης` (Greek accents) | `σωτηρης` | `σωτήρης` |
| `أولمرس` (Arabic hamza carrier) | `اولمرس` | `أولمرس` |
| `황희찬` (Hangul) | decomposed to Jamo | left composed |
| `Sylvain N´Diaye` (U+00B4) | `sylvain n diaye` | `sylvain ndiaye` |

That last one is subtle: NFKD gives U+00B4 a *compatibility* decomposition to
space + combining acute, so stripping the accent leaves a **space**.

Fixed with real NFKD via `unorm_dart` plus a canonical-combining-class range
table. Stripping all marks *by general category* would over-strip: U+034F and
most Indic vowel signs have combining class 0 and Python keeps them.
**Now 36,767 / 36,767 match.**

### 2. `LIKE 'x%'` hung the app

Typing fast produced **"football321 isn't responding"**. The suggestion query
used `LIKE ?` with `'$prefix%'`, and **SQLite's LIKE is case-insensitive by
default, so it cannot use a BINARY-collated index:**

    LIKE 'mes%'   ->  SCAN player_aliases                    30.9 ms
    RANGE form    ->  SEARCH USING idx_player_aliases_norm    0.3 ms

A full scan of all 198,626 alias rows, on **every keystroke**. Fixed with a
range comparison (`>= 'mes' AND < 'met'`), exactly equivalent because both
normalized columns are already lowercase, plus a 90 ms debounce.

### 3. Short prefixes were still slow — `minPrefix` is now 3

Even with the index, a short prefix materialises a huge candidate set that must
be sorted by fame before `LIMIT 4` applies. Measured on the shipped DB:

| prefix | candidate ids | ms (laptop) |
|---|---|---|
| `a` | 8,126 | 187 |
| `ro` | 1,899 | 52 |
| `ron` | 112 | 12 |
| `sne` | 9 | 0.2 |

A phone is several times slower again — at two characters the panel was still
empty a second after typing. `GameQueries.minPrefix` is now **3**.

**This is a deliberate divergence: the Figma typing frame shows suggestions at
two characters ("BA").** Two-character suggestions are also not predictive —
they are the four most famous of ~1,900. To go back to 2, denormalise
`fame_score` into `player_aliases` so the LIMIT can push down, then flip the
constant.

**Both #2 and #3 matter far more for PvP than Practice** — Practice has no
clock, but the same query sits under the ten-second round timer.

### 4. The rejection named the wrong namesake

Typing "messi" against Bayern × Napoli reported *"Georges Parfait Mbida Messi
never played for both"*. The fallback that picks a name to blame used `LIMIT 1`
with **no ORDER BY**, so SQLite returned an arbitrary namesake.

The Dart version orders by `fame_score DESC`, and since 6 Oct 2026 so does
`game_queries.py`. **This affects only which name is DISPLAYED on a
rejection; the accept/reject decision is unchanged, so correctness parity
holds.**

### 5. Highlighting only matched a leading prefix

Typing "rein" surfaced "Alois Reinhardt" and "Pepe Reina" — correctly, since a
player's bare surname is one of his aliases — but only tinted the row whose
*display name* started with "rein". Now matched at every word start (hyphens
included, so "Saint-Germain" lights up on "germain").

### 6. `RichText` silently dropped the app font

`RichText` does **not** inherit the ambient `DefaultTextStyle` the way `Text`
does. Once every suggestion row became a `RichText` (to carry the green span),
they all fell back to the system sans. `fontFamily` is now explicit there.

### 7. The suggestion panel hid its own best row

The panel sat in a `reverse: true` scroll view, so when it outgrew the space it
scrolled its **top** row — the best match, the one carrying the ↵ affordance —
up behind the club cards. It is now sized to the space instead: the board
measures the available height and passes `maxRows`, so the panel shows 2–4 rows
and never clips.

Two extra fixes recovered a row's worth of space: the rejection banner no
longer reserves a blank 22pt line when there is no error, and the padding under
the search bar is 12 rather than the design's 20 (the 932pt design frame has
~50pt more vertical room than the devices this runs on).

Club-name length changes the card height — "Eintracht Frankfurt" wraps to two
lines where "AC Milan" does not — so the row count genuinely varies per pair.
That is the intended behaviour, not a bug.

---

## Measured on the emulator

| | |
|---|---|
| Debug APK | 170.6 MB (62 MB of it the database) |
| First launch, after `pm clear` | ~12.3 s — this is the 62 MB asset copy |
| Incremental build + install + relaunch | 60–120 s |
| Suggestion query, 3+ char prefix (laptop) | 0.2–12 ms |

**Cold start was the number to improve.** 12 s is the one-time asset copy.
It is now streamed with real progress (see *Where it lives*), **not yet
re-measured** — `pm clear` and time it again. Treat emulator timings as a lower bound on a real
phone — there is no Android phone available, so the emulator is the only target.

---

## Verified on device

- Difficulty screen → board → typing → validate → celebrate → next pair, with
  the streak incrementing.
- Turkish keyboard: all four rows, backspace inside row 3, `boşluk` + `GÖNDER`
  on row 4.
- Suggestions panel with header, avatars, sub-lines, green word-boundary
  highlight, ↵ / › affordances; green caret and ✕ clear in the search bar.
- **Correct answer:** "REINA" for Aston Villa × AC Milan → celebration, streak 1.
- **`surname_too_common`:** "SILVA" → *"Hangisi? Adını da yaz"*.
- **`not_a_mutual_player`:** "SNEIJDER" for Bayern × Inter and "DROGBA" for
  Chelsea × Inter → both correctly rejected, naming the famous namesake.
- Spot-checked data: Aston Villa × AC Milan gives Laursen, Reina, Walker,
  Senderos, Abraham. Bayern × Leverkusen gives Kroos, Ballack, Emre Can.

---

## Practice popups — built from Figma (6 Oct 2026)

The invented full-screen celebration and the AlertDialog + bottom-sheet
answer list are gone. Three frames replace them, drawn as overlays on the
board over their `Karartma` scrims:

| Frame | What |
|---|---|
| `78:610` Doğru Cevap | green `Doğru Popup` (name, career line, `SIRADAKİ EŞLEŞME` bar, 2.5 s, tap to skip) + the search bar's confirmed state (✓, name, `+1 SERİ`) |
| `82:338` Cevap Onayı | `CEVABI GÖSTER?` — VAZGEÇ / `3 ALTIN HARCA` |
| `78:483` Cevabı Göster | `OLASI CEVAPLAR` — numbered rows with career lines, `-3 altın harcandı`, DEVAM |

Deliberate differences, all worth a look:

- **The streak is no longer reset by revealing the answer.** The design's own
  copy says *"Seri sayacın sıfırlanmaz"*; the reset belonged to the invented
  sheet. **DEVAM moves to a new pair**, otherwise the answer just shown would
  be one keystroke from a free streak point. *Yaman to confirm the rule.*
- **No `Bakiyen 120` chip** on the confirmation: there is no coin balance yet.
  Nothing is debited either; `-3 altın harcandı` is the price, as the chip in
  the top bar already shows.
- The **lightbulb badge** (`Ampul Rozeti`) disc and glow are painted — the
  export's glow is an SVG blur filter, which flutter_svg does not draw. The
  bulb is the existing `lightbulb.png`. Colours are approximate.
- The answer list **scrolls inside the card** — the frame shows four rows,
  real pairs can have dozens.
- The career line is new data on screen: `GameQueries.mutualSpells` reads the
  spells for the two clubs (min start / max end per club, open end shown as
  `2018–`).

---

## Small things noticed, not yet done

- **Nationality labels are verbose.** The panel shows "Kingdom of the
  Netherlands" where "Netherlands" would do. That is the raw Wikidata country
  label in `players.nationality` — a data-side tidy, not an app fix.
- **Jaro's `0` glyph** reads as a narrow bar at streak-chip size.
- **No position column**, so the suggestion sub-line shows nationality where
  the design shows `Forvet`.
- **Name order** — design shows `Drogba, Didier`, the DB stores
  `Didier Drogba`. Product decision, left alone.

---

## Club crests — decided, deferred

`clubs.crest_asset_url` is empty for all 821 clubs.

**Decision (Yaman, 11 Sep 2026): crests will not be the real ones** — each club
gets two coloured stripes in its club colours, sidestepping the trademark
problem. This lands later, with the avatars and player banners. Not near-term.

The `Arma` slot in `club_card.dart` renders a deterministic initials badge on a
colour hashed from the club name. Only `_ArmaSlot` changes when the stripes
land.

---

## Next steps

1. **Run `docs/TESTING.md` on the emulator** — everything from 6 Oct 2026 is
   unverified on a device (popups, streamed copy, the Kotlin channel).
2. Re-measure cold start after `pm clear`.
3. Before PvP goes near a clock, profile `validateAnswer` on device the way
   `suggestPlayers` was profiled here.

Done since the last version of this list: Doğru Cevap / Cevap Onayı (and
Cevabı Göster) from Figma, the streamed copy with progress, the team picker
and the PvP loop (see `friend-match.md`).
