/// The `rooms` row: one row holds an entire Friend Match.
///
/// Both clients subscribe to this row and derive their whole screen from it.
/// Neither phone ever tells the other what to do, which is what makes
/// reconnection a plain re-read and removes the need for any server-side game
/// code.
library;

enum MatchPhase {
  lobby,
  picking,
  countdown,
  answering,
  roundOver,
  matchOver;

  static MatchPhase fromDb(String value) {
    switch (value) {
      case 'lobby':
        return MatchPhase.lobby;
      case 'picking':
        return MatchPhase.picking;
      case 'countdown':
        return MatchPhase.countdown;
      case 'answering':
        return MatchPhase.answering;
      case 'round_over':
        return MatchPhase.roundOver;
      case 'match_over':
        return MatchPhase.matchOver;
    }
    throw ArgumentError('unknown phase: $value');
  }

  String get dbValue {
    switch (this) {
      case MatchPhase.lobby:
        return 'lobby';
      case MatchPhase.picking:
        return 'picking';
      case MatchPhase.countdown:
        return 'countdown';
      case MatchPhase.answering:
        return 'answering';
      case MatchPhase.roundOver:
        return 'round_over';
      case MatchPhase.matchOver:
        return 'match_over';
    }
  }
}

/// Which side of the room a player is sitting on. This is a database detail —
/// who happened to create the room — and deliberately does NOT leak into the
/// screens, which only ever deal in "me" and "opponent".
enum Seat {
  host,
  guest;

  String get dbValue => this == Seat.host ? 'host' : 'guest';
  Seat get other => this == Seat.host ? Seat.guest : Seat.host;

  static Seat? fromDb(String? value) {
    if (value == 'host') return Seat.host;
    if (value == 'guest') return Seat.guest;
    return null;
  }
}

/// Why a round ended.
enum RoundReason {
  /// Somebody named a mutual player.
  correct,

  /// The ten seconds ran out with no correct answer.
  noAnswer,

  /// The two clubs share no player at all, so the round was never winnable.
  /// The decision (13 Sep 2026) is to VOID the round and have both players
  /// pick again — no goal either way.
  unplayable;

  static RoundReason? fromDb(String? value) {
    switch (value) {
      case 'correct':
        return RoundReason.correct;
      case 'no_answer':
        return RoundReason.noAnswer;
      case 'unplayable':
        return RoundReason.unplayable;
    }
    return null;
  }

  String get dbValue {
    switch (this) {
      case RoundReason.correct:
        return 'correct';
      case RoundReason.noAnswer:
        return 'no_answer';
      case RoundReason.unplayable:
        return 'unplayable';
    }
  }
}

class Room {
  const Room({
    required this.code,
    required this.createdAt,
    required this.updatedAt,
    required this.hostId,
    required this.hostName,
    this.guestId,
    this.guestName,
    required this.targetGoals,
    required this.pickSeconds,
    required this.countdownSeconds,
    required this.answerSeconds,
    required this.phase,
    required this.round,
    required this.hostScore,
    required this.guestScore,
    this.hostClubId,
    this.hostClubName,
    this.guestClubId,
    this.guestClubName,
    this.pickDeadline,
    this.unlockAt,
    this.answerDeadline,
    this.hostAnswer,
    this.hostElapsedMs,
    this.guestAnswer,
    this.guestElapsedMs,
    this.roundWinner,
    this.roundReason,
    this.winner,
    this.endedReason,
    this.hostSeenAt,
    this.guestSeenAt,
  });

  final String code;
  final DateTime createdAt;
  final DateTime updatedAt;

  final String hostId;
  final String hostName;
  final String? guestId;
  final String? guestName;

  final int targetGoals;
  final int pickSeconds;
  final int countdownSeconds;
  final int answerSeconds;

  final MatchPhase phase;
  final int round;
  final int hostScore;
  final int guestScore;

  final int? hostClubId;
  final String? hostClubName;
  final int? guestClubId;
  final String? guestClubName;

  /// All three are SERVER instants. Convert with ServerClock.toLocal before
  /// counting down against them.
  final DateTime? pickDeadline;
  final DateTime? unlockAt;
  final DateTime? answerDeadline;

  final String? hostAnswer;
  final int? hostElapsedMs;
  final String? guestAnswer;
  final int? guestElapsedMs;

  final Seat? roundWinner;
  final RoundReason? roundReason;
  final Seat? winner;
  final String? endedReason;

  final DateTime? hostSeenAt;
  final DateTime? guestSeenAt;

  bool get hasGuest => guestId != null;
  bool get bothPicked => hostClubId != null && guestClubId != null;

  static DateTime? _time(Object? value) =>
      value == null ? null : DateTime.parse(value as String);

  factory Room.fromRow(Map<String, dynamic> row) => Room(
        code: row['code'] as String,
        createdAt: _time(row['created_at'])!,
        updatedAt: _time(row['updated_at'])!,
        hostId: row['host_id'] as String,
        hostName: row['host_name'] as String,
        guestId: row['guest_id'] as String?,
        guestName: row['guest_name'] as String?,
        targetGoals: row['target_goals'] as int,
        pickSeconds: row['pick_seconds'] as int,
        countdownSeconds: row['countdown_seconds'] as int,
        answerSeconds: row['answer_seconds'] as int,
        phase: MatchPhase.fromDb(row['phase'] as String),
        round: row['round'] as int,
        hostScore: row['host_score'] as int,
        guestScore: row['guest_score'] as int,
        hostClubId: row['host_club_id'] as int?,
        hostClubName: row['host_club_name'] as String?,
        guestClubId: row['guest_club_id'] as int?,
        guestClubName: row['guest_club_name'] as String?,
        pickDeadline: _time(row['pick_deadline']),
        unlockAt: _time(row['unlock_at']),
        answerDeadline: _time(row['answer_deadline']),
        hostAnswer: row['host_answer'] as String?,
        hostElapsedMs: row['host_elapsed_ms'] as int?,
        guestAnswer: row['guest_answer'] as String?,
        guestElapsedMs: row['guest_elapsed_ms'] as int?,
        roundWinner: Seat.fromDb(row['round_winner'] as String?),
        roundReason: RoundReason.fromDb(row['round_reason'] as String?),
        winner: Seat.fromDb(row['winner'] as String?),
        endedReason: row['ended_reason'] as String?,
        hostSeenAt: _time(row['host_seen_at']),
        guestSeenAt: _time(row['guest_seen_at']),
      );

  /// Which seat this device is sitting in, or null if it is neither player.
  Seat? seatOf(String playerId) {
    if (playerId == hostId) return Seat.host;
    if (playerId == guestId) return Seat.guest;
    return null;
  }

  int scoreOf(Seat seat) => seat == Seat.host ? hostScore : guestScore;

  String nameOf(Seat seat) =>
      seat == Seat.host ? hostName : (guestName ?? 'Rakip');

  int? clubIdOf(Seat seat) =>
      seat == Seat.host ? hostClubId : guestClubId;

  String? clubNameOf(Seat seat) =>
      seat == Seat.host ? hostClubName : guestClubName;

  String? answerOf(Seat seat) =>
      seat == Seat.host ? hostAnswer : guestAnswer;

  int? elapsedOf(Seat seat) =>
      seat == Seat.host ? hostElapsedMs : guestElapsedMs;

  DateTime? seenAtOf(Seat seat) =>
      seat == Seat.host ? hostSeenAt : guestSeenAt;

  /// Decides the round from the two submitted times.
  ///
  /// This is the whole of the "who answered first" logic, and it lives on
  /// BOTH clients rather than on a server, which works only because it is a
  /// pure function of two numbers already in the row: given the same row,
  /// both phones necessarily reach the same verdict.
  ///
  /// Only CORRECT answers are written into the elapsed columns, so a wrong
  /// guess costs nothing but the time spent typing it, and a player may keep
  /// trying until the clock runs out.
  ///
  /// A tie to the millisecond is possible in principle. The host takes it —
  /// arbitrary, but it must be deterministic, because "both clients pick a
  /// winner independently" and "they disagree" would be a genuinely bad bug.
  Seat? decideRoundWinner() {
    final h = hostElapsedMs;
    final g = guestElapsedMs;
    if (h == null && g == null) return null;
    if (g == null) return Seat.host;
    if (h == null) return Seat.guest;
    return h <= g ? Seat.host : Seat.guest;
  }
}
