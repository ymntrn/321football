# 321 Football Challenge

Mobile football trivia game: two clubs, type a player who played for both.
Practice (offline), Friend Match and ranked "Hemen Oyna" (online, Supabase),
anonymous accounts, the front door, friends, leaderboards and the economy
are on `main`, tested on the emulator (6 Oct 2026; migrations 006–009
applied). Branch `release-prep` adds sound effects, the one rewarded ad
(2X Altın, migration 010), Google linking behind a flag (off), Gizlilik /
Destek screens, in-app account deletion (migration 011) and release-build
signing/R8 — **010 and 011 not yet applied, nothing run on the emulator**
(`docs/TESTING.md` §R). `docs/release.md` is the human checklist for the
first Play Store release.

## Read before doing anything

1. `docs/release.md` — everything a human must do for the first Play
   release (keystore, AdMob, OAuth, policy hosting, data safety, testing).
   `docs/accounts-and-ranked.md` — accounts, the front door, economy,
   friends, leaderboards, ranked, and (newest) the release-prep decisions.
   `docs/friend-match.md` — the match engine and the room protocol.
   **Their decisions supersede the open questions in `pvp-handoff.md` and
   `project-state.md`** (no-answer rule = void the round; backend = Supabase).
2. `docs/figma-to-flutter.md` — before touching any screen.
3. `docs/flutter-app.md` — app architecture, tools/ scripts, this machine's limits.
4. `docs/project-state.md` — the database and the data rules.
5. `docs/pvp-handoff.md`, `docs/game-screens-ui.md` — background.
6. `docs/TESTING.md` — the emulator checklist (§R = the unverified branch).
7. `docs/privacy-policy.md` (generated from `app/lib/legal/legal_text.dart`)
   and `docs/store-listing.md` — drafts, not yet reviewed.

## Layout

| Folder | What |
|---|---|
| `321_football_db/` | Python scraper/builder for the football SQLite DB |
| `app/` | Flutter client |
| `supabase/` | SQL migrations, smoke tests, `bot.py` second player (`--ranked` queues for Hemen Oyna), `localpg/` local-Postgres harness (`python supabase/localpg/harness.py` needs a Postgres 16 on /tmp:5499) |
| `docs/` | The project docs above |

## Rules that bite

- **The Figma file is the source of truth for layout**, not the written spec.
  File key `UHMpbhjpqxQ94Xs1oD3Sfz`. Load the `figma-design-to-code` skill
  before `get_design_context`.
- Static analysis proves nothing about a UI. Verify on the emulator with
  `app/tools/shot.ps1` screenshots.
- 7.7 GB RAM. Cold builds need the emulator off (`build_apk.ps1`). Never let a
  Flutter upgrade restore the 8 GB Gradle heap.
- Never `LIKE 'x%'` on the SQLite DB — use range comparisons.
- No anti-cheat code, ever (Yaman's decision).
- Never edit a migration (`schema.sql`, `002`–`011`); add a new
  numbered file. Every new table/function needs explicit GRANTs — RLS
  policies do not imply them. Apply 010 before 011.
- Every vibration goes through `Haptics` (lib/settings/app_settings.dart);
  every sound through `Sounds.play`, one file per `Sfx` in assets/audio/
  (placeholders from `tools/make_sfx.py` — replace a file, keep its name).
  `test/haptics_test.dart` and `test/sfx_assets_test.dart` enforce it.
- One ad only: the rewarded 2X Altın on a ranked win. No banners or
  interstitials (`test/release_config_test.dart`). Ad ids live only in
  `lib/ads/ad_config.dart` (Google TEST ids until release; Gradle reads the
  app id from there). Coin doubling is server-side (`double_match_coins`).
- Google linking stays behind `AuthConfig.googleLinkingEnabled` (off) until
  the OAuth clients exist. Never restyle or enable the Apple button.
- The in-app legal text and `docs/privacy-policy.md` must match
  (`test/legal_text_test.dart`); edit the Dart, regenerate the Markdown.
- Never commit `app/android/key.properties` or a keystore (`.gitignore`).
- Cloud sessions: `assets/db/321_football.db` is gitignored — `touch` an
  empty one so `flutter test` can build (never commit it).
- Since 006 every script needs an anonymous sign-in (`supabase/sbclient.py`);
  the pre-006 smoke tests fail by design.
- Bump `AppDatabase.assetVersion` whenever a new database is dropped in.

## Git

Repo: https://github.com/ymntrn/321football (public — that's fine).
`.gitignore` keeps out `supabase/.pgpass.local` (DB password — **never commit**),
the `.venv`, build output, and all `*.db` files (too big for GitHub; back them
up separately). Commit after each piece of work that runs.

## Keeping docs current

`docs/` is now the canonical copy. When something lands or a decision is made,
update the relevant doc in the same commit.
