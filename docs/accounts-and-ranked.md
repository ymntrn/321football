# Accounts, the front door, and ranked — the working doc

Started 6 October 2026, branch `front-door-and-ranked`. Covers everything
that turned the dev-menu prototype into an app: anonymous accounts, the
username + tag identity, the front-door screens, stats and the economy,
friends, leaderboards, settings, and ranked matchmaking ("Hemen Oyna").

**Status: written in a cloud session. `flutter analyze` is clean, `flutter
test` passes (62, including overflow tests for every new screen at three
phone sizes), and every migration was executed against a local Postgres 16
with Supabase stubs (`supabase/localpg/`, 0 failures). Nothing has run on
the emulator or against the real Supabase project yet.** `TESTING.md`
§A is the checklist.

---

## Decisions (Yaman, 6 Oct 2026)

| Topic | Decision |
|---|---|
| Accounts | Supabase **anonymous sign-in**; one stable auth user per install. Apple/Google later — the `Apple ile Giriş Yap` button stays exactly as designed, disabled. |
| Identity | `username#TAG`, tag = 4 chars from A–Z and 2–9 without 0/O/1/I. Username not unique; the pair is. Tag never changes. |
| Trophies | Start 0. Ranked win +30, loss −20, never below 0. |
| Coins | Start 30. Ranked win +10, loss +2. Practice Cevap costs 3, disabled under 3. |
| Friend Match | Counts toward stats, never trophies or coins. |
| Matchmaking | First to 3, the Friend Match room and engine. ±100 trophies, +100 every 5 s. Cancel leaves the queue. |
| Leaderboards | Global top 100 + own rank pinned. Arkadaş = friends by trophies, no podium, player highlighted. |
| Friends | Add by `username#tag`, request → accept/decline, remove. |
| Settings | Sound and haptics on/off, on the device. Haptics really off. Sounds are placeholders (release-prep, below). |
| Anti-cheat | None. Clients are trusted. |

### Decisions I had to make (not previously written down)

- **The username rule** comes from the frame (92:190): *3–16 characters,
  letters, digits and `_`*. Turkish letters count as letters. Enforced by a
  check constraint and mirrored in `Profile.validUsername`.
- **Username + tag uniqueness is case-insensitive** (`lower(username), tag`),
  because people type `yaman#7k2m`. A rename can collide with someone else's
  name under the same permanent tag (about one in a million per name); the
  profile screen then says *"Bu isim etiketinle kullanılıyor"*.
- **Username and friend-id fields use the system keyboard**, not the custom
  Turkish one. The custom keyboard has no digits, `_` or `#`, which both a
  username and `Kerem_07#B3D2` need. Same reasoning as the room-code field.
- **The username is stored on the device first**, so the username screen
  works offline; the profile (and the tag) is created on the next boot that
  reaches Supabase. Until then the tag reads `#••••`.
- **Offline**, Practice runs exactly as before on the on-device fallback id.
  The Cevap chip is dimmed (no known balance); every online screen shows
  *"Bağlantı kurulamadı"*.
- **Both players call `record_match_result`**, not only the host: after a
  forfeit the host may be the one who left. It is idempotent, so that is
  harmless — and the bot calls it too.
- **The fastest answer is the fastest *correct* answer**, whether or not it
  won the round (both players' correct times are in the row). Kept per match
  by a trigger, because `next_round` wipes the elapsed columns.
- **Streak = consecutive match wins** (current and best). Friend Matches
  count, per the decision.
- **An abandoned match (no winner) counts for nobody.**
- **`rooms.ranked` is added in 007**, not 009, because 007's function needs
  it. 009 is what sets it.
- **Matchmaking pairs when the trophy gap fits EITHER player's window**, so
  whoever has waited longest widens the search for both.
- **The finder of a match hosts** — except that the test bot asks to be the
  guest (`find_match(p_prefer_guest => true)`), because the bot cannot drive
  phase transitions. A harmless parameter; no player-facing effect.
- **A matched room starts in `picking` with 2 s of slack** on the pick
  deadline: the other player learns of it on their next one-second poll.
- **Cancelling after a match was made enters the match** instead of backing
  out (backing out would forfeit it).
- **Ranked Tekrar Oyna queues again** (a new opponent); Friend Match keeps
  the same-room rematch.
- **Global rank ties** are ordered `trophies desc, id` everywhere, so the
  pinned row agrees with the list.
- **Room RLS is now `auth.uid() in (host_id, guest_id)`** and the anon role
  has no table access. `create_room`/`join_room` take the id from the
  session; the old `p_host_id`/`p_guest_id` parameters are ignored, so the
  signatures (and older clients) still work. Joining your own room is
  refused (`Bu senin odan`).
- The flow functions (`start_match` … `rematch`) are untouched; they remain
  SECURITY DEFINER and callable by any signed-in player, as before.

### Where the build differs from the frames (all deliberate)

- **Ayarlar:** the frame has Müzik, SFX, Titreşim and Bildirimler. The
  decision is one sound switch and one haptics switch, so the card has
  `Ses` and `Titreşim`; Bildirimler is left out (no notifications). Gizlilik
  and Destek open their screens (92:270, 92:310 — built on `release-prep`).
- **Profil:** the coin balance sits beside the trophies, and `Şu Anki Seri`
  carries `En iyi: N` — the decisions put both on the profile and the frame
  has no slot. The avatar is initials until the avatar art lands.
- **Leaderboards:** no country flags — there is no country data.
- **Arkadaşlar:** requests have no frame; incoming ones sit on top under
  `İSTEKLER` with ✓/✕, outgoing ones read `bekliyor` with ✕. The ⚔
  `Meydan Oku` tile and the online dot are left out (no challenge flow, no
  presence); that slot holds ✕ (remove, which asks first).
- **Maç Aranıyor:** the curved title (a text-path, no exportable asset) is
  painted on an arc, and the loader — a still of a Lottie animation in the
  frame — is painted as an animated ring of dots.
- **Result screens:** the ranked trophy/coin row shows the decided amounts
  (+10 coins, not the frame's +20). `2X Altın` appears only on a ranked win
  with an ad loaded (`release-prep`).
- **Splash:** the frame's `Yükleniyor` bar, which still shows real progress
  during the first-launch database copy.
- **Ana Sayfa:** the shop icon says *Mağaza yakında* (shop out of scope).
- Everything set in M PLUS 1p in the frames uses PoetsenOne (not bundled).

---

## The backend

| File | What |
|---|---|
| `006_accounts.sql` | `profiles`, `create_profile`, tag rules, column grants (a player may update only their own `username`), room RLS → the two players, `create_room`/`join_room` from the session |
| `007_results.sql` | `rooms.ranked` + per-match bests + recorded deltas, the `rooms_track_match` trigger, `record_match_result`, `spend_coins` |
| `008_friends.sql` | `friendships`, `find_player`, `send_friend_request`, `respond_friend_request`, `remove_friend`, `my_friends`, `my_rank`, `friends_leaderboard` |
| `009_matchmaking.sql` | `match_queue`, `find_match`, `leave_queue` |
| `010_double_reward.sql` | `coin_doubles` (function-only), `double_match_coins` — 2X Altın, once per match, own ranked win |
| `011_delete_account.sql` | `delete_my_account` — friendships, queue, 2X records, profile, auth user |

Every table write a client makes is either its own room seat's columns, its
own username, or a SECURITY DEFINER function. Every new function has
`revoke … from public, anon` + `grant execute … to authenticated`; tables
that clients read have explicit `grant select` (RLS policies do not imply
GRANTs).

`smoke_test_006.py` … `smoke_test_009.py` check each one over HTTP against
the real project, through `sbclient.py` (anonymous sign-in for scripts).
`localpg/harness.py` applies every migration to a throwaway local Postgres
with stubs for `auth.uid()`, the roles and pg_cron, then runs
`localpg/check_00N.py` — that is how this branch's SQL was executed without
access to Supabase.

**The pre-006 smoke tests (`smoke_test.py`, `smoke_test_flow.py`,
`smoke_test_004.py`, `smoke_test_005.py`) fail after 006 by design**: they
call with the bare publishable key and random player ids, which the new
RLS refuses. `smoke_test_006.py` and `007.py` cover the same room path with
signed-in players.

## The client

```
lib/net/account.dart          sign-in at boot (6 s cap), the profile, rename,
                              spendCoins; ensureOnline() for online screens
lib/net/identity.dart         playerId = auth user (fallback: on-device id),
                              username/tag kept on the device
lib/net/social_repository.dart leaderboards + friends
lib/models/profile.dart       the profiles row, username rule, name#TAG parse
lib/settings/app_settings.dart sound/haptics, Haptics (the ONLY vibration
                              path), Sounds.play (the one place sounds go)
lib/widgets/app_chrome.dart   front-door furniture: nav bar, chips, menu
                              buttons, glass panels, player rows, popup,
                              FigmaAsset (export + fallback)
lib/screens/
  username_screen.dart        92:190 / 94:190
  home_screen.dart            4:4
  nav.dart                    tab routing (Undo always lands on Ana Sayfa)
  leaderboard_screen.dart     51:567 / 51:860
  profile_screen.dart         53:469
  friends_screen.dart         92:230 / 97:190
  settings_screen.dart        51:1088
  matchmaking_screen.dart     12:95
```

Boot: `Identity.load` → `AppSettings.load` → `runApp`; the splash waits for
the database open and for Supabase init + sign-in **in parallel**. Then
`UsernameScreen` on a first launch, `HomeScreen` after.

MatchScreen is the same engine; the only additions are the Versus caption
(`SIRALI MAÇ` when ranked), recording the result at `match_over`, the
ranked economy row, and ranked Tekrar Oyna → matchmaking.

## Figma

| Node | Frame | Built |
|---|---|---|
| `48:570` | Yükleme ekranı | yes |
| `92:190` / `94:190` | Kullanıcı Adı Oluştur (+ typing) | yes |
| `4:4` | Ana Sayfa (incl. Menubar 8:16, Arkadaşlar Butonu 104:190) | yes |
| `12:95` | Maç Aranıyor | yes |
| `51:567` / `51:860` | Leaderboard Global / Arkadaş | yes |
| `53:469` | Profil | yes |
| `92:230` / `97:190` | Arkadaşlar / Arkadaş Ekle | yes |
| `51:1088` | Ayarlar | yes |
| `82:469` | Bakiye chip (Cevap Onayı) | yes |
| `92:270`, `92:310` | Gizlilik, Destek | yes (`release-prep`) |
| `46:516` | 2X Altın (on Kazanma 46:352) | yes (`release-prep`) |
| `92:350`, `102:190`, `103:190` | Mağaza tabs | out of scope |

**Exports are not committed yet.** The cloud session could not reach
figma.com; the 13 new URLs are in `tools/fetch_assets.ps1` and expire about
13 Oct 2026. Until fetched, every slot shows a stand-in (a Material icon or
an emoji); the Apple button slot stays empty rather than imitate Apple.

---

## Release prep — branch `release-prep` (6 Oct 2026)

**Status: written in a cloud session. `flutter analyze` clean, `flutter
test` 95 pass, 010 and 011 executed on local Postgres (0 failures). Not run
on the emulator, Gradle never ran (no Android SDK reachable), 010/011 not
applied to Supabase.** `TESTING.md` §R is the checklist, `release.md` the
human steps.

### Decisions (Yaman)

| Topic | Decision |
|---|---|
| Sound | Placeholder effects generated by a committed stdlib script (`app/tools/make_sfx.py`) into `assets/audio/`, swappable without code changes. All through `Sounds.play`, respecting Ses. |
| Haptics | Already wired through Titreşim; unchanged. |
| Ads | ONE rewarded ad: `2X Altın` on the RANKED win screen (46:352). Doubles that match's coin reward once, server-side. `google_mobile_ads`, Google's TEST ids in one config file. No banners or interstitials. |
| Google linking | `Google ile bağla` on Profil, Supabase identity linking, behind a flag, OFF. Apple button exactly as designed, disabled. |
| Legal / support | Gizlilik and Destek screens replace *Yakında*; draft Turkish policy + terms; the policy also in `docs/privacy-policy.md`. |
| Deletion | `Hesabımı sil` on Destek with a confirmation; `delete_my_account()`. |
| Release build | `key.properties` signing (fallback debug), R8, label `321 Football`, version from pubspec, no keystore committed. |
| Shop / IAP | Out of scope. |

### Decisions I had to make (not previously written down)

- **Audio package: `audioplayers`**, one player per effect in low-latency
  mode, `mixWithOthers` audio focus (the player's music keeps playing).
  Files are 16-bit mono WAV at 22.05 kHz, ~170 KB for all nine. GÖNDER does
  not click (its correct/wrong sound is the feedback). A failed platform
  call disables sound for the session instead of retrying per keystroke.
  Under `flutter test` sound is off (the plugin does not exist there).
- **The countdown tick** is driven from the match loop's 250 ms tick
  against `unlock_at`, one per numeral.
- **"Once per match" lives in a new `coin_doubles` table**, not a flag on
  `rooms`: since 006 both players may UPDATE any column of their own room,
  so a room flag could just be cleared. It is keyed by (room, player,
  `result_recorded_at`), so a rematch in the same room is a new match.
  The bonus is the constant ranked win reward (10), not the room's
  client-writable coin delta. This is the asked-for rule, not anti-cheat:
  nothing checks that an ad was really watched.
- **The 2X button shows only when** the match is ranked, this player won,
  `record_match_result` has landed and an ad is loaded. Shown → the
  frame's 170x90 pair; any failure, an early close or a second visit →
  hidden, the normal reward stands. One ad per match.
- **Consent:** Google's UMP flow runs at launch (EEA/UK only, when a
  message is published in AdMob) — AdMob requires a certified CMP there.
- **The AdMob app id is read by Gradle out of `ad_config.dart`** into a
  manifest placeholder, so the ids stay in one file.
- **Google linking uses native Google Sign-In (`google_sign_in` 7) +
  `linkIdentityWithIdToken`**, not the browser OAuth flow: no deep link,
  no redirect scheme. After a reinstall, linking finds the Google account
  already used and offers **O HESABA GEÇ** (`signInWithIdToken`); the fresh
  anonymous account is left behind (not deleted — its JWT is gone once the
  session switches). The flag and Web client id can also come from
  `--dart-define`.
- **Gizlilik shows both documents** on one screen with two captions; a
  `TASLAK` card leads until reviewed. The data controller name and the
  support mailbox are placeholders to fill (`legal_text.dart`).
- **Support address = the frame's `destek@321football.app`**, in
  `SupportConfig.email`. SORUN BİLDİR opens a pre-filled mail
  (`url_launcher`), copying the address when there is no mail app.
- **Destek's 4th question** drops "satın alma gelmedi" (no purchases).
- **`Hesabımı sil` sits at the foot of Destek** under a `HESAP` caption
  (no frame). Rooms are not deleted (the opponent's too); the nightly purge
  removes them within a day. After deleting, the device signs out locally,
  forgets the name and tag and goes to the username screen.
- **pubspec version → `1.0.0+1`** for the first release.
- **R8 on** (`isMinifyEnabled`, `isShrinkResources`) with keep rules for
  the plugins, MainActivity's channel, the ads/UMP SDKs and Credential
  Manager; `-dontwarn` for Play Core.
- **Target audience 13+** in the release notes (the terms say the game is
  not for under-13s), which keeps the app out of the Families policy.
