# First Play Store release — what a human must do

Written 6 Oct 2026 on branch `release-prep`. Everything the code can do is
done (sound, the rewarded ad, Google linking behind a flag, Gizlilik /
Destek, in-app account deletion, release signing and R8). What is left
needs accounts, keys, money or a lawyer. Do it **in this order** — later
steps need earlier ones (the Play App Signing SHA-1 only exists after the
first upload; AdMob wants the Play listing; the data safety form wants the
privacy policy URL).

Tick-list:

1. [ ] The upload keystore
2. [ ] Supabase: migrations 010 + 011, and the free-tier pause
3. [ ] Finish the placeholders in the code
4. [ ] AdMob: account, app, real ids, consent message
5. [ ] Host the privacy policy
6. [ ] Google Play Console account
7. [ ] Create the app and fill in *App content* (data safety, rating …)
8. [ ] Store listing
9. [ ] Build the release bundle
10. [ ] Internal testing, then closed testing, then production
11. [ ] (Optional, any time after step 9) Google account linking — Appendix A

---

## 1. The upload keystore

Play App Signing is mandatory for new apps: **Google keeps the key that
signs what players install; you keep an *upload* key** that proves an
upload is yours. A lost upload key can be reset through Play support (a
lost app signing key could not — that is why Google holds it).

1. Create it once, outside the repo (PowerShell, JDK on PATH):

   ```
   mkdir C:\keys
   keytool -genkey -v -keystore C:\keys\321football-upload.jks -keyalg RSA -keysize 2048 -validity 10000 -alias upload
   ```

   Pick a strong password; answer the name questions (they are not shown
   to players).
2. **Back up** `321football-upload.jks` and the password in two places
   that are not this PC (a password manager + a USB stick / cloud drive).
3. Create `app\android\key.properties` (gitignored — never commit it):

   ```
   storePassword=<the password>
   keyPassword=<the password>
   keyAlias=upload
   storeFile=C:/keys/321football-upload.jks
   ```

   **Forward slashes** in `storeFile`: a `.properties` file treats `\` as
   an escape character.
4. `android/app/build.gradle.kts` picks it up automatically. Without the
   file, release builds are signed with the debug key (fine for testing on
   the emulator, rejected by Play).

## 2. Supabase

1. Apply **010 then 011** (011 deletes from 010's table) and run their
   smoke tests — `TESTING.md` §R0 has the exact commands.
2. Run `python supabase\purge_test_accounts.py` (then `--apply`) to clear
   the Smoke* players off the leaderboard before real players arrive.
3. **The free plan pauses a project after 7 days without traffic**, and a
   paused project means every online mode fails until someone un-pauses it
   in the dashboard. Before players depend on it: either upgrade to Pro
   (~$25/month, no pausing, daily backups) or accept the risk while the
   game is small. Free-tier limits: `friend-match.md` → *The backend*.
4. Authentication → Rate limits: the anonymous sign-in limit is per IP
   (30/hour by default). Many players behind one carrier NAT can hit it;
   raise it to a few hundred per hour for launch.

## 3. Finish the placeholders in the code

| Where | What |
|---|---|
| `app/lib/legal/legal_text.dart` → `LegalText.controller` | your legal name (or company) and a contact address — the privacy policy must name the data controller |
| `app/lib/legal/legal_text.dart` → `SupportConfig.email` | `destek@321football.app` is the address from the Figma frame. Make sure that mailbox exists (it needs the domain), or replace it everywhere it appears: this constant, `docs/store-listing.md` |
| the whole of `legal_text.dart` | **have the policy and terms reviewed** (KVKK + GDPR). Then delete `draftNotice`'s card (`_DraftCard` in `privacy_screen.dart`), update `lastUpdated`, and regenerate `docs/privacy-policy.md` (see the comment at its top) |
| launcher icon | still Flutter's default (`android/app/src/main/res/mipmap-*`). Replace it with the real 321 Football icon (adaptive icon recommended) |
| `lib/screens/settings_screen.dart` → `version` | shown on the splash, Ayarlar and Destek; now `V 1.0.0`. Bump it together with `version:` in `pubspec.yaml` |
| `assets/audio/*.wav` | placeholder beeps from `tools/make_sfx.py`; drop real sounds in with the same names whenever they exist |
| Figma exports | run `app\tools\fetch_assets.ps1` if not done (the URLs expire ~13 Oct 2026) — the Apple button and the nav icons |

## 4. AdMob — real ids and the consent message

Until this step the app uses Google's **test** ids (they always fill and
never pay). Do not tap real ads on your own phone — AdMob bans accounts for
invalid traffic.

1. <https://admob.google.com> → sign in with the Google account that will
   own the money; fill in payments and tax (Turkey: tax info under
   *Payments*).
2. **Apps → Add app → Android**. "Is the app listed on a supported app
   store?" → *No* for now (link it to the Play listing after step 10).
   Name `321 Football`.
3. **Ad units → Add ad unit → Rewarded**. Name `2X Altın`. Reward amount
   `1`, reward item `altın` — the value is ignored: the server pays the
   coins (`double_match_coins`, 010). Leave *server-side verification*
   off (no anti-cheat, by decision).
4. Copy the two ids into `app/lib/ads/ad_config.dart`:
   - `admobAppIdAndroid` = the **App ID** (`ca-app-pub-…~…`)
   - `rewardedUnitAndroid` = the **ad unit ID** (`ca-app-pub-…/…`)

   Keep the `static const admobAppIdAndroid = '…';` line on one line —
   Gradle reads the app id out of it into the manifest.
5. **Settings → Test devices → Add**: your phone's advertising id (the
   app logs it on the first ad request: `Use RequestConfiguration…
   setTestDeviceIds(["…"])` in `adb logcat`). Test devices get test ads
   on real ids.
6. **Privacy & messaging → European regulations (GDPR) → Create message**
   for the app, languages Turkish + English, then **Publish**. The app
   already runs Google's UMP consent flow at launch
   (`RewardedCoinsAd.initialize`); without a published message, players in
   the EEA/UK get no ads at all. (US state regulations message: optional.)
7. **app-ads.txt**: AdMob shows a line like
   `google.com, pub-XXXXXXXX, DIRECT, f08c47fec0942fa0`. Host it as
   `https://<your website>/app-ads.txt` on the domain of the website you
   put in the Play listing (step 8). Unverified apps can have ad serving
   limited.
8. After the Play listing is live: AdMob → the app → *App settings* →
   link it to the Google Play listing.

## 5. Host the privacy policy

Play requires a public, non-PDF, non-editable URL. `docs/privacy-policy.md`
is that page (generated from the in-app text).

Simplest — GitHub Pages from this public repo:

1. GitHub → `ymntrn/321football` → *Settings → Pages* → Source:
   *Deploy from a branch*, branch `main`, folder `/docs` → Save.
2. After a minute: `https://ymntrn.github.io/321football/privacy-policy`
   (Jekyll renders the Markdown). Open it on a phone and check it reads
   well.
3. That URL goes into: Play Console (*App content → Privacy policy*, and as
   the **account deletion URL** — its *Hesabını ve verilerini silme*
   section says how to delete in the app and by e-mail), the OAuth consent
   screen (Appendix A), and optionally the AdMob app.

(Pages publishes every file under `docs/`. They are already public in the
repo; if you would rather publish only the policy, use a separate
`gh-pages` branch or a one-page site instead.)

## 6. Google Play Console account

1. <https://play.google.com/console/signup> — **$25 once**. *Personal*
   account (yourself) or *Organisation* (needs a D-U-N-S number). Identity
   verification takes a few days.
2. **New personal accounts must run a closed test with at least 12
   testers for 14 continuous days before they can publish to
   production.** Line up 12+ people with Android phones (friends, family)
   early — this is the longest wait in the whole list.
3. Verify a contact phone number and e-mail; a developer page / website is
   optional.

## 7. Create the app and fill in *App content*

*Create app*: name `321 Football`, default language Turkish (tr-TR), App
(well — **Game**), Free. Package name comes from the first upload:
`com.yamanturan.football321`. Then *Policy and programs → App content*:

### Privacy policy
The URL from step 5.

### App access
*All functionality is available without special access* (no login; Google
linking is off — if you turn it on later it is optional, so this stays the
same).

### Ads
**Yes, my app contains ads.**

### Content rating (IARC questionnaire)
Category **Game** (not *Social or communication*). Answers, from what the
app really contains:

| Question | Answer | Why |
|---|---|---|
| Violence, blood, gore | No | text and club names only |
| Fear / horror | No | |
| Sexuality, nudity | No | |
| Gambling (real or simulated) | No | coins buy nothing, there is no chance mechanic and no real money |
| Language (profanity, crude humour) | No | no in-app text of that kind; usernames are user-generated (see next) |
| Controlled substances (drugs, alcohol, tobacco) | No | |
| Does the app allow users to interact or exchange content? | **Yes** | players see each other's usernames in matches, leaderboards and friends; there is **no chat** and no free-text messaging |
| Shares the user's current location with other users? | No | no location at all |
| Allows users to purchase digital goods? | No | no in-app purchases |
| Unrestricted internet access (a browser)? | No | |
| Promotes or displays ads | Yes | one rewarded ad |

Expected outcome: **PEGI 3 / IARC 3+ / ESRB Everyone** with the
"Users Interact" interactive element (and "In-Game Ads" where the rating
board shows it).

### Target audience and content
Age groups **13–15, 16–17, 18+** (the terms say the game is not for
under-13s). *Could the app unintentionally appeal to children?* → No (a
football trivia game with no child-directed design). Choosing an under-13
group would pull the app into the Families policy and require
child-directed ad settings — not wanted.

### Data safety
Answer from what the app and its SDKs really do (the code, 006–011, and
Google's published AdMob / Sign-In disclosures — re-check those two pages
when you fill the form, Google updates them):

**Overview questions**

| Question | Answer |
|---|---|
| Does your app collect or share any of the required user data types? | Yes |
| Is all of the user data collected by your app encrypted in transit? | **Yes** (HTTPS to Supabase and Google) |
| Do you provide a way for users to request that their data is deleted? | **Yes** — in-app (*Destek → Hesabımı sil*) and the URL from step 5 |

**Data types** (✓ = declare it)

| Category → type | Collected | Shared | Optional? | Purposes | Source |
|---|---|---|---|---|---|
| Personal info → **User IDs** | ✓ | – | Required | App functionality, Account management | the anonymous account id; `username#TAG` (an account name) |
| Personal info → **Email address** | only if Google linking is ON | – | Optional | Account management | Google identity linked in Supabase (Appendix A). While the flag is off, do **not** declare it |
| App activity → **App interactions** | ✓ | ✓ (Google, via AdMob) | Required | App functionality (stats, matches, trophies, coins, leaderboards); Advertising / Analytics (AdMob) | `profiles`, `rooms`, `match_queue`; AdMob SDK |
| App activity → **Other user-generated content** | ✓ | – | Required | App functionality | the username; correct answers written to match rooms |
| App activity → **Other actions** | ✓ | – | Required | App functionality | friend requests and friendships |
| Device or other IDs → **Device or other IDs** | ✓ | ✓ (Google) | Required | Advertising or marketing, Analytics, Fraud prevention | Android advertising id (AdMob; `play-services-ads` adds the `AD_ID` permission) |
| Location → **Approximate location** | ✓ | ✓ (Google) | Required | Advertising, Analytics, Fraud prevention | AdMob derives it from the IP address |
| App info and performance → **Crash logs / Diagnostics** | ✓ | ✓ (Google) | Required | Analytics, Fraud prevention | AdMob SDK diagnostics |

Not collected at all: name, phone, address, precise location, contacts,
photos/videos, audio, files, calendar, health, financial info, messages,
web history, installed apps.

"Shared" means sent to a third party that is not acting only as your
service provider. **Supabase is your processor** (it stores data on your
behalf), so data sent to it is *collected*, not *shared*. AdMob uses data
for Google's own advertising purposes, so its data types are *shared*.

### Advertising ID
*Does your app use advertising ID?* **Yes** → purpose **Advertising or
marketing** (and Analytics). The Mobile Ads SDK adds
`com.google.android.gms.permission.AD_ID` to the merged manifest.

### Government apps / Financial features / Health / News
None of these apply → No.

## 8. Store listing

Copy from `docs/store-listing.md` (Turkish default + English translation).
Upload the 512×512 icon, a 1024×500 feature graphic and at least two phone
screenshots — none of those exist yet (step 3 / store-listing.md).
Category *Trivia*; contact e-mail; website (where `app-ads.txt` lives).

## 9. Build the release bundle

```
cd C:\Users\PC\Documents\321-football\app
flutter clean
flutter pub get
flutter build appbundle --release --obfuscate --split-debug-info=build\symbols
```

- Close the emulator first (7.7 GB RAM; `tools\build_apk.ps1` does the
  same for APKs).
- Output: `build\app\outputs\bundle\release\app-release.aab`.
- Keep `build\symbols` for each release (needed to read obfuscated
  crash stacks) — zip it next to the keystore backup, named by version.
- **Every upload needs a higher versionCode**: bump the `+N` in
  `pubspec.yaml` (`version: 1.0.0+1` → `1.0.0+2`).
- Before uploading, install a release build and play it once:
  `flutter build apk --release` → `adb install -r build\app\outputs\flutter-apk\app-release.apk`
  (TESTING.md §R7). R8 problems only show up in release builds.

## 10. Internal testing → closed testing → production

1. **Internal testing** (*Test and release → Testing → Internal testing*):
   create a release, upload the `.aab`, release notes in Turkish, *Save →
   Review → Start rollout*. Add up to 100 testers by e-mail list; they
   join with the opt-in link and install from Play within minutes. The
   first upload also enrols the app in Play App Signing — copy the **App
   signing key SHA-1** now if you will do Appendix A.
2. Test on real phones from Play (not adb): first launch, a ranked match
   between two testers, 2X Altın (still test ads until step 4 is done —
   test ads on a Play build are fine), Destek's mail link, Hesabımı sil
   on a throwaway account.
3. **Closed testing** (personal accounts): a closed track with ≥ 12
   testers who stay opted in for 14 days. Then *Apply for production*
   (Dashboard), answering the questions about the test.
4. **Production**: create the release (same `.aab` or a newer one),
   countries (Turkey first, or worldwide), staged rollout (e.g. 20 %), and
   send for review (a few hours to a few days for a new app).
5. After it is live: link the AdMob app to the listing (step 4.8), and
   switch the ids to the real ones in a new build if you had not yet.

---

## Appendix A — Google account linking ("Google ile bağla")

**State:** built, OFF. `lib/net/auth_config.dart` → `googleLinkingEnabled`
is false and `googleWebClientId` is empty, so Profil shows no Google
button and no Google code runs. The Apple button is untouched (disabled,
exactly as designed).

**How it works:** native Google Sign-In (`google_sign_in`) returns an ID
token; `Account.linkGoogle()` passes it to Supabase
`linkIdentityWithIdToken`, which attaches a Google identity to the
**current anonymous user**. The user id does not change, so profile, tag,
trophies, coins, stats and friends all stay. After a reinstall the player
gets a fresh anonymous account; tapping *Google ile bağla* then finds the
Google account already attached to the old player and offers
**O HESABA GEÇ**, which signs in as the old player
(`signInWithIdToken`). No deep link or redirect URL is involved.

### 1. Google Cloud — the OAuth consent screen

1. <https://console.cloud.google.com> → create (or pick) a project, e.g.
   `321 Football`.
2. **APIs & Services → OAuth consent screen** (Google Auth Platform →
   Branding / Audience): User type **External**; app name `321 Football`;
   support e-mail; developer contact e-mail; the privacy policy URL
   (step 5 of the main checklist). Scopes: `openid`, `email`, `profile`
   only (non-sensitive — no verification review needed).
3. **Publish** the app (Audience → *In production*). In *Testing* only the
   listed test users can sign in.

### 2. Google Cloud — the OAuth clients

Create these under **APIs & Services → Credentials → Create credentials →
OAuth client ID**:

1. **Web application** — name `321 Football Supabase`. Authorised redirect
   URI: `https://yjdcsdikcrdupqmaqoqn.supabase.co/auth/v1/callback`.
   Keep the **Client ID** and **Client secret**. *This* client id is the
   one the app and Supabase use (`serverClientId`), even on Android.
2. **Android** — one per signing key that will ever run the app, each with
   package name `com.yamanturan.football321` and that key's **SHA-1**:

   | Key | How to get its SHA-1 |
   |---|---|
   | Debug (emulator / `flutter run`) | `keytool -list -v -keystore %USERPROFILE%\.android\debug.keystore -alias androiddebugkey -storepass android -keypass android` |
   | Upload key (your release keystore) | `keytool -list -v -keystore C:\keys\321football-upload.jks -alias upload` |
   | **Play App Signing key** (what Play-installed copies are signed with) | Play Console → the app → *Test and release → App integrity → App signing* → "App signing key certificate" → SHA-1 |

   The Play App Signing one is easy to forget and is the one real players
   use: without it, sign-in works from `adb install` and fails from the
   Play Store (error `developerError` / code 10).

   The Android clients have no secret and never appear in code; Google
   matches them by package name + SHA-1.

### 3. Supabase — the provider

Dashboard → project `yjdcsdikcrdupqmaqoqn`:

1. **Authentication → Sign In / Providers → Google**: enable.
   - *Client IDs*: the **Web** client id (comma-separate if you add more).
   - *Client Secret (for OAuth)*: the Web client secret.
   - *Skip nonce checks*: leave **off**; turn on only if linking fails with
     an error that mentions `nonce`.
2. **Authentication → Sign In / Providers → (User Signups)**: turn on
   **Allow manual linking**. Without it `linkIdentity` fails with
   `manual_linking_disabled` (the app shows *Supabase: manual linking
   kapalı*).
3. Keep **Allow anonymous sign-ins** on — every install still starts
   anonymous.

### 4. Turn it on in the app

Either edit `lib/net/auth_config.dart` (`googleLinkingEnabled = true`,
`googleWebClientId = '<web client id>'`) or build with

```
flutter build appbundle --dart-define=GOOGLE_LINKING=true --dart-define=GOOGLE_WEB_CLIENT_ID=<web client id>
```

`test/release_config_test.dart` asserts the flag is off; flip that test
in the same commit if you turn it on in source.

### 5. Check it (TESTING.md §R4)

Profil → **Google ile bağla** → account picker → toast *Hesabın Google'a
bağlandı*, the button reads *Google'a bağlı ✓*. Supabase → Authentication
→ Users: the same user id now lists `google` and is no longer anonymous.
