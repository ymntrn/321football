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

/// Country labels in Turkish. Covers every value in `leagues.country`,
/// `clubs.country` and - since 6 Oct 2026 - `players.nationality` (after
/// curate.py has cleaned the raw Wikidata labels). Anything missing falls
/// through to the raw English label rather than showing nothing; add new
/// values here when a rebuild brings one in.
const Map<String, String> countryNamesTr = {
  'Afghanistan': 'Afganistan',
  'Albania': 'Arnavutluk',
  'Algeria': 'Cezayir',
  'Andorra': 'Andorra',
  'Angola': 'Angola',
  'Antigua and Barbuda': 'Antigua ve Barbuda',
  'Argentina': 'Arjantin',
  'Armenia': 'Ermenistan',
  'Australia': 'Avustralya',
  'Austria': 'Avusturya',
  'Azerbaijan': 'Azerbaycan',
  'Bahrain': 'Bahreyn',
  'Barbados': 'Barbados',
  'Belarus': 'Belarus',
  'Belgium': 'Belçika',
  'Benin': 'Benin',
  'Bermuda': 'Bermuda',
  'Bolivia': 'Bolivya',
  'Bosnia and Herzegovina': 'Bosna-Hersek',
  'Botswana': 'Botsvana',
  'Brazil': 'Brezilya',
  'Brunei': 'Brunei',
  'Bulgaria': 'Bulgaristan',
  'Burkina Faso': 'Burkina Faso',
  'Burundi': 'Burundi',
  'Cameroon': 'Kamerun',
  'Canada': 'Kanada',
  'Cape Verde': 'Yeşil Burun Adaları',
  'Central African Republic': 'Orta Afrika Cumhuriyeti',
  'Chad': 'Çad',
  'Chile': 'Şili',
  'China': 'Çin',
  'Colombia': 'Kolombiya',
  'Comoros': 'Komorlar',
  'Costa Rica': 'Kosta Rika',
  'Croatia': 'Hırvatistan',
  'Cuba': 'Küba',
  'Cyprus': 'Kıbrıs',
  'Czech Republic': 'Çekya',
  'Czechoslovakia': 'Çekoslovakya',
  'Democratic Republic of the Congo': 'Demokratik Kongo',
  'Denmark': 'Danimarka',
  'Dominica': 'Dominika',
  'Dominican Republic': 'Dominik Cumhuriyeti',
  'East Germany': 'Doğu Almanya',
  'Ecuador': 'Ekvador',
  'Egypt': 'Mısır',
  'El Salvador': 'El Salvador',
  'England': 'İngiltere',
  'Equatorial Guinea': 'Ekvator Ginesi',
  'Eritrea': 'Eritre',
  'Estonia': 'Estonya',
  'Eswatini': 'Esvatini',
  'Ethiopia': 'Etiyopya',
  'Fiji': 'Fiji',
  'Finland': 'Finlandiya',
  'France': 'Fransa',
  'Gabon': 'Gabon',
  'Georgia': 'Gürcistan',
  'Germany': 'Almanya',
  'Ghana': 'Gana',
  'Greece': 'Yunanistan',
  'Grenada': 'Grenada',
  'Guatemala': 'Guatemala',
  'Guinea': 'Gine',
  'Guinea-Bissau': 'Gine-Bissau',
  'Guyana': 'Guyana',
  'Haiti': 'Haiti',
  'Honduras': 'Honduras',
  'Hungary': 'Macaristan',
  'Iceland': 'İzlanda',
  'India': 'Hindistan',
  'Indonesia': 'Endonezya',
  'Iran': 'İran',
  'Iraq': 'Irak',
  'Ireland': 'İrlanda',
  'Israel': 'İsrail',
  'Italy': 'İtalya',
  'Ivory Coast': 'Fildişi Sahili',
  'Jamaica': 'Jamaika',
  'Japan': 'Japonya',
  'Jordan': 'Ürdün',
  'Kazakhstan': 'Kazakistan',
  'Kenya': 'Kenya',
  'Kosovo': 'Kosova',
  'Kuwait': 'Kuveyt',
  'Kyrgyzstan': 'Kırgızistan',
  'Latvia': 'Letonya',
  'Lebanon': 'Lübnan',
  'Lesotho': 'Lesotho',
  'Liberia': 'Liberya',
  'Libya': 'Libya',
  'Liechtenstein': 'Lihtenştayn',
  'Lithuania': 'Litvanya',
  'Luxembourg': 'Lüksemburg',
  'Madagascar': 'Madagaskar',
  'Malawi': 'Malavi',
  'Malaysia': 'Malezya',
  'Mali': 'Mali',
  'Malta': 'Malta',
  'Mauritania': 'Moritanya',
  'Mauritius': 'Mauritius',
  'Mexico': 'Meksika',
  'Moldova': 'Moldova',
  'Monaco': 'Monako',
  'Montenegro': 'Karadağ',
  'Morocco': 'Fas',
  'Mozambique': 'Mozambik',
  'Myanmar': 'Myanmar',
  'Namibia': 'Namibya',
  'Netherlands': 'Hollanda',
  'New Zealand': 'Yeni Zelanda',
  'Nicaragua': 'Nikaragua',
  'Niger': 'Nijer',
  'Nigeria': 'Nijerya',
  'North Korea': 'Kuzey Kore',
  'North Macedonia': 'Kuzey Makedonya',
  'Northern Cyprus': 'KKTC',
  'Norway': 'Norveç',
  'Oman': 'Umman',
  'Pakistan': 'Pakistan',
  'Palestine': 'Filistin',
  'Panama': 'Panama',
  'Papua New Guinea': 'Papua Yeni Gine',
  'Paraguay': 'Paraguay',
  'Peru': 'Peru',
  'Philippines': 'Filipinler',
  'Poland': 'Polonya',
  'Portugal': 'Portekiz',
  'Qatar': 'Katar',
  'Republic of the Congo': 'Kongo',
  'Romania': 'Romanya',
  'Russia': 'Rusya',
  'Rwanda': 'Ruanda',
  'Réunion': 'Réunion',
  'Saint Kitts and Nevis': 'Saint Kitts ve Nevis',
  'Saint Lucia': 'Saint Lucia',
  'Saint Vincent and the Grenadines': 'Saint Vincent ve Grenadinler',
  'San Marino': 'San Marino',
  'Saudi Arabia': 'Suudi Arabistan',
  'Scotland': 'İskoçya',
  'Senegal': 'Senegal',
  'Serbia': 'Sırbistan',
  'Serbia and Montenegro': 'Sırbistan-Karadağ',
  'Seychelles': 'Seyşeller',
  'Sierra Leone': 'Sierra Leone',
  'Singapore': 'Singapur',
  'Slovakia': 'Slovakya',
  'Slovenia': 'Slovenya',
  'Somalia': 'Somali',
  'South Africa': 'Güney Afrika',
  'South Korea': 'Güney Kore',
  'South Sudan': 'Güney Sudan',
  'Soviet Union': 'Sovyetler Birliği',
  'Spain': 'İspanya',
  'Sri Lanka': 'Sri Lanka',
  'Sudan': 'Sudan',
  'Suriname': 'Surinam',
  'Sweden': 'İsveç',
  'Switzerland': 'İsviçre',
  'Syria': 'Suriye',
  'São Tomé and Príncipe': 'São Tomé ve Príncipe',
  'Taiwan': 'Tayvan',
  'Tajikistan': 'Tacikistan',
  'Tanzania': 'Tanzanya',
  'Thailand': 'Tayland',
  'The Gambia': 'Gambiya',
  'Togo': 'Togo',
  'Trinidad and Tobago': 'Trinidad ve Tobago',
  'Tunisia': 'Tunus',
  'Turkey': 'Türkiye',
  'Turkmenistan': 'Türkmenistan',
  'Uganda': 'Uganda',
  'Ukraine': 'Ukrayna',
  'United Arab Emirates': 'BAE',
  'United Kingdom': 'İngiltere',
  'United States': 'ABD',
  'Uruguay': 'Uruguay',
  'Uzbekistan': 'Özbekistan',
  'Venezuela': 'Venezuela',
  'Vietnam': 'Vietnam',
  'Wales': 'Galler',
  'Yemen': 'Yemen',
  'Yugoslavia': 'Yugoslavya',
  'Zambia': 'Zambiya',
  'Zimbabwe': 'Zimbabve',
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
