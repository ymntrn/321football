import 'dart:math';

import 'package:shared_preferences/shared_preferences.dart';

/// Who this device is.
///
/// Since 006_accounts.sql the player id is the Supabase **anonymous auth
/// user** — every install signs in at boot and supabase_flutter keeps the
/// session, so the id is stable for the life of the install and is what rooms,
/// profiles and friendships are keyed on. [Account] binds it here once the
/// sign-in lands.
///
/// The on-device id is kept as a FALLBACK only: a first launch with no network
/// has no auth user yet, and Practice must still work fully offline. Nothing
/// online accepts the fallback id (room RLS checks `auth.uid()`), so online
/// screens call `Account.ensureOnline()` first.
///
/// The username is stored on the device too, so the username screen
/// (`Kullanıcı Adı Oluştur`, 92:190) is a first-launch-only step even when it
/// is filled in offline — the profile is created from it on the next boot
/// that reaches Supabase.
class Identity {
  Identity._(this._localId, this._username, this._tag);

  static const _idKey = 'player_id';
  static const _usernameKey = 'username';
  static const _tagKey = 'tag';

  final String _localId;
  String? _authId;
  String? _username;
  String? _tag;

  /// The auth user's id when signed in, otherwise the on-device fallback.
  String get playerId => _authId ?? _localId;

  bool get signedIn => _authId != null;

  /// Has this device ever chosen a username? False means first launch.
  bool get hasUsername => _username != null;

  String get name => _username ?? 'Oyuncu';

  /// The 4-character tag, once the server has issued one.
  String? get tag => _tag;

  /// `Yaman#7K2M`, or just the name before a tag exists.
  String get handle => _tag == null ? name : '$name#$_tag';

  static Identity? _instance;
  static Identity get instance {
    final i = _instance;
    if (i == null) {
      throw StateError('Identity.load() must complete before use');
    }
    return i;
  }

  static Future<Identity> load() async {
    final prefs = await SharedPreferences.getInstance();
    var id = prefs.getString(_idKey);
    if (id == null) {
      id = _uuidV4();
      await prefs.setString(_idKey, id);
    }
    return _instance = Identity._(
      id,
      prefs.getString(_usernameKey),
      prefs.getString(_tagKey),
    );
  }

  void bindAuth(String? authUserId) => _authId = authUserId;

  /// Stores what the server says this player is called. Also how the
  /// username screen records a name chosen offline.
  Future<void> remember({required String username, String? tag}) async {
    _username = username;
    if (tag != null) _tag = tag;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_usernameKey, username);
    if (tag != null) await prefs.setString(_tagKey, tag);
  }

  /// After "Hesabımı sil": forgets the name, tag and auth binding, so the
  /// next screen is the first-launch username screen and the next sign-in
  /// creates a brand-new anonymous player.
  Future<void> forget() async {
    _authId = null;
    _username = null;
    _tag = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_usernameKey);
    await prefs.remove(_tagKey);
  }

  /// A random v4 UUID, in the shape Postgres expects for a `uuid` column.
  static String _uuidV4() {
    final rng = Random.secure();
    final bytes = List<int>.generate(16, (_) => rng.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40; // version 4
    bytes[8] = (bytes[8] & 0x3f) | 0x80; // variant 1
    String hex(int from, int to) => bytes
        .sublist(from, to)
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join();
    return '${hex(0, 4)}-${hex(4, 6)}-${hex(6, 8)}-${hex(8, 10)}-${hex(10, 16)}';
  }
}
