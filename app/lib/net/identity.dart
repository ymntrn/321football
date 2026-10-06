import 'dart:math';

import 'package:shared_preferences/shared_preferences.dart';

/// Who this device is, as far as a room is concerned.
///
/// Not an account. `Kullanıcı Adı Oluştur` (Figma 92:190) and the
/// `Yaman#7K2M` tag it describes are a later job; until then a match needs
/// two things only — a stable id that survives an app restart, so a
/// reconnecting player is recognised as the same person rather than treated
/// as a third one, and a name to put on the scoreboard.
class Identity {
  Identity._(this.playerId, this._name);

  static const _idKey = 'player_id';
  static const _nameKey = 'player_name';

  final String playerId;
  String _name;

  String get name => _name;

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
    final name = prefs.getString(_nameKey) ?? 'Oyuncu';
    return _instance = Identity._(id, name);
  }

  Future<void> rename(String value) async {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return;
    _name = trimmed;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_nameKey, trimmed);
  }

  /// A random v4 UUID, in the shape Postgres expects for a `uuid` column.
  ///
  /// Hand-rolled rather than pulling in the `uuid` package for one function.
  /// Random.secure() is used because a predictable id would let someone guess
  /// the opponent's id — worth nothing today, but it costs nothing either.
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
