# First Play Store release — what a human must do

(The full checklist is filled in at the end of the `release-prep` branch.)

---

## Google account linking ("Google ile bağla")

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

### 5. Check it (TESTING.md §R3)

Profil → **Google ile bağla** → account picker → toast *Hesabın Google'a
bağlandı*, the button reads *Google'a bağlı ✓*. Supabase → Authentication
→ Users: the same user id now lists `google` and is no longer anonymous.
