class Club {
  final int id;
  final String name;
  final String? country;
  final double fameScore;
  final String? crestUrl;

  /// The club's most recent league, and that league's country. Only populated
  /// by [GameQueries.searchClubs], which needs them for the team-picker
  /// sub-line; every other query leaves them null.
  ///
  /// [leagueCountry] is preferred over [country] for display because
  /// `clubs.country` says "United Kingdom" for English AND Scottish sides,
  /// while `leagues.country` distinguishes England from Scotland.
  final String? leagueName;
  final String? leagueCountry;

  const Club({
    required this.id,
    required this.name,
    this.country,
    this.fameScore = 0,
    this.crestUrl,
    this.leagueName,
    this.leagueCountry,
  });

  factory Club.fromRow(Map<String, Object?> row) => Club(
        id: row['club_id'] as int,
        name: row['canonical_name'] as String,
        country: row['country'] as String?,
        fameScore: (row['fame_score'] as num?)?.toDouble() ?? 0,
        crestUrl: row['crest_asset_url'] as String?,
        leagueName: row['league_name'] as String?,
        leagueCountry: row['league_country'] as String?,
      );

  /// The team-picker sub-line: `İspanya · La Liga`.
  String get subtitle {
    final parts = [
      if (countryTr != null) countryTr!,
      if (leagueName != null) leagueName!,
    ];
    return parts.join(' · ');
  }

  /// Country in Turkish, preferring the league's country over the club's.
  String? get countryTr {
    final raw = leagueCountry ?? country;
    if (raw == null) return null;
    return countryNamesTr[raw] ?? raw;
  }

  /// Up to three letters for the crest placeholder, as the design's
  /// `BAR` / `BAY` / `BAŞ` badges. Leading throwaway words ("FC", "AC",
  /// "Real") would make every Spanish club read `REA`, so the longest
  /// significant word wins instead.
  String get badgeLetters {
    const noise = {
      'fc', 'ac', 'sc', 'cf', 'sk', 'jk', 'as', 'ss', 'us', 'rc', 'rcd', 'cd',
      'ud', 'sv', 'tsv', 'vfb', 'vfl', 'fk', 'afc', 'bsc', 'de', 'da', 'do',
      'club', 'clube', 'calcio', 'futebol', 'football', 'the', '04', '09',
    };
    final words = name
        .split(RegExp(r"[\s.\-']+"))
        .where((w) => w.isNotEmpty && !noise.contains(w.toLowerCase()))
        .toList();
    final pick = words.isEmpty
        ? name.replaceAll(RegExp(r'\s'), '')
        : words.reduce((a, b) => b.length > a.length ? b : a);
    final take = pick.length < 3 ? pick.length : 3;
    return pick.substring(0, take).toUpperCase();
  }
}

/// Country labels in Turkish, for the team-picker sub-line. Covers every
/// value present in `leagues.country` and `clubs.country`; anything missing
/// falls through to the raw English label rather than showing nothing.
const Map<String, String> countryNamesTr = {
  'Andorra': 'Andorra',
  'Austria': 'Avusturya',
  'Belgium': 'Belçika',
  'Botswana': 'Botsvana',
  'Brazil': 'Brezilya',
  'Canada': 'Kanada',
  'England': 'İngiltere',
  'France': 'Fransa',
  'Germany': 'Almanya',
  'Greece': 'Yunanistan',
  'Italy': 'İtalya',
  'Liechtenstein': 'Lihtenştayn',
  'Monaco': 'Monako',
  'Morocco': 'Fas',
  'Netherlands': 'Hollanda',
  'Portugal': 'Portekiz',
  'Russia': 'Rusya',
  'Saudi Arabia': 'Suudi Arabistan',
  'Scotland': 'İskoçya',
  'Soviet Union': 'Sovyetler Birliği',
  'Spain': 'İspanya',
  'Switzerland': 'İsviçre',
  'Tanzania': 'Tanzanya',
  'Turkey': 'Türkiye',
  'United Kingdom': 'İngiltere',
  'United States': 'ABD',
  'Wales': 'Galler',
};

class Player {
  final int id;
  final String displayName;
  final String? nationality;
  final double fameScore;

  /// Career span, derived from the player's spells. Only populated by
  /// [GameQueries.suggestPlayers], which needs it for the suggestion
  /// sub-line; every other query leaves these null.
  final int? firstYear;
  final int? lastYear;

  const Player({
    required this.id,
    required this.displayName,
    this.nationality,
    this.fameScore = 0,
    this.firstYear,
    this.lastYear,
  });

  factory Player.fromRow(Map<String, Object?> row) => Player(
        id: row['player_id'] as int,
        displayName: row['display_name'] as String,
        nationality: row['nationality'] as String?,
        fameScore: (row['fame_score'] as num?)?.toDouble() ?? 0,
        firstYear: row['first_year'] as int?,
        lastYear: row['last_year'] as int?,
      );
}

enum Difficulty {
  easy('easy', 'KOLAY'),
  medium('medium', 'ORTA'),
  hard('hard', 'ZOR');

  const Difficulty(this.dbValue, this.label);
  final String dbValue;
  final String label;
}

class PracticePair {
  final int pairId;
  final int mutualCount;
  final int clubAId;
  final String clubAName;
  final int clubBId;
  final String clubBName;

  const PracticePair({
    required this.pairId,
    required this.mutualCount,
    required this.clubAId,
    required this.clubAName,
    required this.clubBId,
    required this.clubBName,
  });

  factory PracticePair.fromRow(Map<String, Object?> row) => PracticePair(
        pairId: row['pair_id'] as int,
        mutualCount: row['mutual_count'] as int? ?? 0,
        clubAId: row['club_a_id'] as int,
        clubAName: row['club_a_name'] as String,
        clubBId: row['club_b_id'] as int,
        clubBName: row['club_b_name'] as String,
      );
}

/// Why an answer was rejected. Each case wants different UI copy — conflating
/// them makes players furious at the wrong thing.
enum AnswerReason {
  correct,

  /// Fewer than 3 characters after folding.
  tooShort,

  /// No player in the database answers to this string.
  unknownPlayer,

  /// A real player, but he never played for both of these clubs.
  notAMutualPlayer,

  /// A bare surname shared by too many players to credit a blind guess.
  surnameTooCommon,
}

class AnswerResult {
  final bool correct;
  final AnswerReason reason;
  final Player? player;

  const AnswerResult({
    required this.correct,
    required this.reason,
    this.player,
  });

  /// Turkish copy for each rejection. Kept next to the enum so a new reason
  /// cannot be added without someone noticing the message is missing.
  String get message {
    switch (reason) {
      case AnswerReason.correct:
        return 'DOĞRU';
      case AnswerReason.tooShort:
        return 'Biraz daha yaz';
      case AnswerReason.unknownPlayer:
        return 'Bu oyuncu veritabanında yok';
      case AnswerReason.notAMutualPlayer:
        return 'Bu oyuncu iki takımda da oynamadı';
      case AnswerReason.surnameTooCommon:
        return 'Hangisi? Adını da yaz';
    }
  }
}
