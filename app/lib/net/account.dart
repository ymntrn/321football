import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/profile.dart';
import 'auth_config.dart';
import 'identity.dart';

/// Why an account call failed, in terms a screen can show.
class AccountException implements Exception {
  const AccountException(this.message);
  final String message;
  @override
  String toString() => 'AccountException($message)';
}

/// The signed-in player: the anonymous auth session and the `profiles` row.
///
/// Every call here is safe to make offline. Nothing throws out of [boot];
/// screens that need the server call [ensureOnline] and show their own error
/// when it returns false. Practice never needs any of it except the coin
/// balance, and without one the Cevap chip is simply disabled.
class Account {
  Account._();
  static final Account instance = Account._();

  /// The latest known profile, or null before one has been read (offline, or
  /// a first launch that has not picked a username yet).
  final ValueNotifier<Profile?> profile = ValueNotifier(null);

  /// Set by main() once Supabase.initialize has succeeded.
  bool backendAvailable = false;

  /// How long a sign-in may hold up the splash before the app carries on
  /// offline. supabase_flutter restores a saved session without the network,
  /// so this only bites on a first launch with a bad connection.
  static const _signInTimeout = Duration(seconds: 6);

  SupabaseClient? get _client =>
      backendAvailable ? Supabase.instance.client : null;

  /// Called at boot, in parallel with the database open. Signs in (restoring
  /// the saved anonymous session if there is one) and loads the profile.
  Future<void> boot() async {
    try {
      await ensureOnline().timeout(_signInTimeout);
    } catch (e) {
      debugPrint('account boot: carrying on offline ($e)');
    }
  }

  /// Makes sure there is an auth user, and a profile if a username has been
  /// chosen. Returns false when the server cannot be reached.
  Future<bool> ensureOnline() async {
    final client = _client;
    if (client == null) return false;
    try {
      var user = client.auth.currentUser;
      if (user == null) {
        final res = await client.auth.signInAnonymously();
        user = res.user;
      }
      if (user == null) return false;
      Identity.instance.bindAuth(user.id);

      if (profile.value == null || profile.value!.id != user.id) {
        await _loadOrCreate(user.id);
      }
      return true;
    } catch (e) {
      debugPrint('ensureOnline failed: $e');
      return false;
    }
  }

  Future<void> _loadOrCreate(String uid) async {
    final client = _client!;
    final row =
        await client.from('profiles').select().eq('id', uid).maybeSingle();
    if (row != null) {
      _set(Profile.fromRow(row));
      return;
    }
    if (!Identity.instance.hasUsername) return; // username screen comes first
    final created = await client.rpc('create_profile', params: {
      'p_username': Identity.instance.name,
    });
    _set(Profile.fromRow(Map<String, dynamic>.from(created as Map)));
  }

  void _set(Profile p) {
    profile.value = p;
    // The server is the truth for the name and tag; keep the device copy in
    // step so an offline launch still shows `Yaman#7K2M`.
    unawaited(Identity.instance.remember(username: p.username, tag: p.tag));
  }

  /// The username screen's DEVAM ET. Stores the name on the device first, so
  /// this succeeds offline too — the profile is then created on the next
  /// boot that reaches the server.
  Future<void> chooseUsername(String username) async {
    await Identity.instance.remember(username: username);
    if (await ensureOnline()) {
      final client = _client!;
      final uid = client.auth.currentUser!.id;
      if (profile.value == null) await _loadOrCreate(uid);
    }
  }

  /// Re-reads the profile, e.g. after a match.
  Future<Profile?> refresh() async {
    final client = _client;
    final uid = client?.auth.currentUser?.id;
    if (client == null || uid == null) return profile.value;
    try {
      final row =
          await client.from('profiles').select().eq('id', uid).maybeSingle();
      if (row != null) _set(Profile.fromRow(row));
    } catch (e) {
      debugPrint('profile refresh failed: $e');
    }
    return profile.value;
  }

  /// Profil's edit. The tag stays; only the name changes.
  Future<void> rename(String username) async {
    if (!Profile.validUsername(username)) {
      throw const AccountException('3–16 karakter · harf, rakam ve _');
    }
    if (!await ensureOnline()) {
      throw const AccountException('Bağlantı kurulamadı');
    }
    final client = _client!;
    final uid = client.auth.currentUser!.id;
    try {
      final row = await client
          .from('profiles')
          .update({'username': username})
          .eq('id', uid)
          .select()
          .single();
      _set(Profile.fromRow(row));
    } on PostgrestException catch (e) {
      // 23505: this name with this (permanent) tag already belongs to
      // someone. About one chance in a million per name.
      if (e.code == '23505') {
        throw const AccountException('Bu isim etiketinle kullanılıyor');
      }
      throw AccountException(e.message);
    }
  }

  /// Practice's `N ALTIN HARCA`. Returns the new balance; throws when the
  /// balance is short or the server cannot be reached.
  Future<int> spendCoins(int amount) async {
    if (!await ensureOnline()) {
      throw const AccountException('Bağlantı kurulamadı');
    }
    try {
      final balance =
          await _client!.rpc('spend_coins', params: {'p_amount': amount});
      final p = profile.value;
      if (p != null) {
        profile.value = Profile.fromRow({
          ..._toRow(p),
          'coins': balance as int,
        });
      }
      return balance as int;
    } on PostgrestException catch (e) {
      if (e.message.contains('insufficient_coins')) {
        throw const AccountException('Yeterli altının yok');
      }
      throw AccountException(e.message);
    }
  }

  // -------------------------------------------------------------------------
  // Google account linking (behind AuthConfig.googleLinkingEnabled)
  // -------------------------------------------------------------------------
  /// Whether this account already has a Google identity attached.
  bool get googleLinked =>
      _client?.auth.currentUser?.identities
          ?.any((i) => i.provider == 'google') ??
      false;

  static bool _googleReady = false;

  /// Asks Google for an ID token (the native account picker). Null when the
  /// player cancels.
  Future<String?> _googleIdToken() async {
    final google = GoogleSignIn.instance;
    if (!_googleReady) {
      await google.initialize(serverClientId: AuthConfig.googleWebClientId);
      _googleReady = true;
    }
    try {
      final account = await google.authenticate();
      return account.authentication.idToken;
    } on GoogleSignInException catch (e) {
      if (e.code == GoogleSignInExceptionCode.canceled ||
          e.code == GoogleSignInExceptionCode.interrupted) {
        return null;
      }
      throw AccountException('Google girişi başarısız (${e.code.name})');
    }
  }

  /// Profil's "Google ile bağla": attaches a Google identity to the CURRENT
  /// anonymous user (Supabase identity linking). The user id does not change,
  /// so the profile, tag, trophies, coins, friends and stats all stay; what
  /// changes is that a later install can get back to them by signing in
  /// with the same Google account ([switchToGoogleAccount]).
  ///
  /// Returns [GoogleLink.linked], [GoogleLink.cancelled], or
  /// [GoogleLink.belongsToAnother] when that Google account is already
  /// attached to a different player (typically: this is a reinstall and the
  /// old progress lives there). Throws [AccountException] otherwise.
  Future<GoogleLink> linkGoogle() async {
    if (!AuthConfig.googleLinkingAvailable) {
      throw const AccountException('Google bağlama henüz açık değil');
    }
    if (!await ensureOnline()) {
      throw const AccountException('Bağlantı kurulamadı');
    }
    final idToken = await _googleIdToken();
    if (idToken == null) return GoogleLink.cancelled;
    _pendingIdToken = idToken;
    try {
      await _client!.auth.linkIdentityWithIdToken(
        provider: OAuthProvider.google,
        idToken: idToken,
      );
      _pendingIdToken = null;
      await _client!.auth.refreshSession();
      return GoogleLink.linked;
    } on AuthException catch (e) {
      if (e.code == 'identity_already_exists') {
        return GoogleLink.belongsToAnother;
      }
      if (e.code == 'manual_linking_disabled') {
        throw const AccountException('Supabase: manual linking kapalı');
      }
      throw AccountException(e.message);
    }
  }

  /// The ID token from the last [linkGoogle] that found the Google account
  /// already in use, so switching does not open the picker twice.
  String? _pendingIdToken;

  /// After [GoogleLink.belongsToAnother], with the player's confirmation:
  /// signs in AS the player that Google account belongs to. The anonymous
  /// account on this device is left behind (its progress is not merged).
  Future<void> switchToGoogleAccount() async {
    final client = _client;
    if (client == null) throw const AccountException('Bağlantı kurulamadı');
    final idToken = _pendingIdToken ?? await _googleIdToken();
    if (idToken == null) return;
    try {
      final res = await client.auth.signInWithIdToken(
        provider: OAuthProvider.google,
        idToken: idToken,
      );
      _pendingIdToken = null;
      final user = res.user;
      if (user == null) throw const AccountException('Giriş başarısız');
      Identity.instance.bindAuth(user.id);
      profile.value = null;
      await _loadOrCreate(user.id);
    } on AuthException catch (e) {
      throw AccountException(e.message);
    }
  }

  static Map<String, dynamic> _toRow(Profile p) => {
        'id': p.id,
        'username': p.username,
        'tag': p.tag,
        'trophies': p.trophies,
        'coins': p.coins,
        'matches_played': p.matchesPlayed,
        'wins': p.wins,
        'current_streak': p.currentStreak,
        'best_streak': p.bestStreak,
        'fastest_answer_ms': p.fastestAnswerMs,
      };
}

/// What [Account.linkGoogle] did.
enum GoogleLink { linked, cancelled, belongsToAnother }
