/// A row of `public.profiles` (006_accounts.sql).
class Profile {
  const Profile({
    required this.id,
    required this.username,
    required this.tag,
    required this.trophies,
    required this.coins,
    required this.matchesPlayed,
    required this.wins,
    required this.currentStreak,
    required this.bestStreak,
    this.fastestAnswerMs,
  });

  final String id;
  final String username;
  final String tag;
  final int trophies;
  final int coins;
  final int matchesPlayed;
  final int wins;
  final int currentStreak;
  final int bestStreak;
  final int? fastestAnswerMs;

  /// `Yaman#7K2M` — what people share and what friends are added by.
  String get handle => '$username#$tag';

  /// 0–100, rounded. Zero matches reads as 0, not as a division error.
  int get winRatePercent =>
      matchesPlayed == 0 ? 0 : (wins * 100 / matchesPlayed).round();

  factory Profile.fromRow(Map<String, dynamic> row) => Profile(
        id: row['id'] as String,
        username: row['username'] as String,
        tag: row['tag'] as String,
        trophies: (row['trophies'] as int?) ?? 0,
        coins: (row['coins'] as int?) ?? 0,
        matchesPlayed: (row['matches_played'] as int?) ?? 0,
        wins: (row['wins'] as int?) ?? 0,
        currentStreak: (row['current_streak'] as int?) ?? 0,
        bestStreak: (row['best_streak'] as int?) ?? 0,
        fastestAnswerMs: row['fastest_answer_ms'] as int?,
      );

  /// The rule on 92:190 — "3–16 karakter · harf, rakam ve _" — mirrored by
  /// the `profiles_username_valid` check constraint.
  static final usernamePattern = RegExp(r'^[A-Za-z0-9_ÇĞİÖŞÜçğıöşü]{3,16}$');

  static bool validUsername(String value) => usernamePattern.hasMatch(value);

  /// Splits `name#TAG` the way the friend search expects it. Null if the
  /// text is not that shape. The tag is upper-cased; the name is left alone
  /// (the server compares it case-insensitively).
  static ({String username, String tag})? parseHandle(String text) {
    final m = RegExp(r'^\s*([^#\s]+)\s*#\s*([A-Za-z0-9]{4})\s*$').firstMatch(text);
    if (m == null) return null;
    return (username: m.group(1)!, tag: m.group(2)!.toUpperCase());
  }
}
