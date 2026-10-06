/// Google account linking ("Google ile bağla" on Profil).
///
/// OFF by default: the Google OAuth clients do not exist yet. With the flag
/// off the button is not shown at all and no Google code runs.
///
/// To turn it on (docs/release.md, "Google account linking", has every step):
///   1. create the Web + Android OAuth clients in Google Cloud,
///   2. enable the Google provider (and manual linking) in Supabase,
///   3. set the two values below — or pass them at build time without
///      touching the source:
///
///        flutter build appbundle --dart-define=GOOGLE_LINKING=true \
///            --dart-define=GOOGLE_WEB_CLIENT_ID=1234-abc.apps.googleusercontent.com
class AuthConfig {
  AuthConfig._();

  /// TODO(release): true once the OAuth clients and the Supabase provider
  /// are set up.
  static const googleLinkingEnabled = bool.fromEnvironment(
    'GOOGLE_LINKING',
    defaultValue: false,
  );

  /// The WEB application OAuth client id (not the Android one). Google signs
  /// the ID token for this audience, and Supabase's Google provider must list
  /// it under "Client IDs". The Android client is matched by package name +
  /// SHA-1 and never appears in code.
  ///
  /// TODO(release): the real Web client id.
  static const googleWebClientId = String.fromEnvironment(
    'GOOGLE_WEB_CLIENT_ID',
    defaultValue: '',
  );

  static bool get googleLinkingAvailable =>
      googleLinkingEnabled && googleWebClientId.isNotEmpty;
}
