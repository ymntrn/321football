import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/profile.dart';
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
