import 'dart:async';

import 'package:flutter/material.dart';

import '../data/app_database.dart';
import '../data/game_queries.dart';
import '../models/models.dart';
import '../models/room.dart';
import '../net/room_repository.dart';
import '../net/server_clock.dart';
import '../theme/tokens.dart';
import '../widgets/screen_background.dart';
import 'match_countdown_screen.dart';
import 'match_screen_buttons.dart';
import 'match_team_select_screen.dart';

/// The match loop.
///
/// Every screen in a Friend Match is a rendering of one row in `rooms`. This
/// widget subscribes to that row, shows whatever the current phase calls for,
/// and — on the host only — advances the phase when the conditions for the
/// next one are met.
///
/// **The host drives; the guest only writes its own columns.** Both clients
/// compute the same verdicts from the same row, but exactly one of them is
/// allowed to write a transition, which is what keeps them from racing. A
/// host that disappears forfeits the match, so the role never has to migrate.
class MatchScreen extends StatefulWidget {
  const MatchScreen({
    super.key,
    required this.initial,
    required this.seat,
    required this.clock,
    required this.rooms,
  });

  final Room initial;
  final Seat seat;
  final ServerClock clock;
  final RoomRepository rooms;

  @override
  State<MatchScreen> createState() => _MatchScreenState();
}

class _MatchScreenState extends State<MatchScreen> {
  late final GameQueries _q = GameQueries(AppDatabase.instance.db);
  late Room _room = widget.initial;

  StreamSubscription<Room>? _sub;
  Timer? _heartbeat;
  Timer? _tick;

  bool get _isHost => widget.seat == Seat.host;
  Seat get _me => widget.seat;
  Seat get _them => widget.seat.other;

  /// Guards a transition so it fires once per (phase, round) rather than on
  /// every one of the four ticks a second. The value is the key of the
  /// transition currently in flight.
  String? _inFlight;

  /// When this device first saw the current phase. Used for the deliberate
  /// pauses — how long GOOOL stays on screen before the next round.
  DateTime _phaseSince = DateTime.now();
  MatchPhase? _phaseSeen;

  /// When the first correct answer of the round landed in the row.
  ///
  /// The round is NOT settled the instant one appears. If both players answer
  /// within a few hundred milliseconds of each other, the slower player's
  /// write can easily reach the database first — deciding immediately would
  /// hand the round to whoever had the better connection, which is the exact
  /// unfairness the elapsed-time rule exists to avoid. So the host waits a
  /// short grace window for the second submission, then compares the two
  /// durations. If both are already in, there is nothing to wait for.
  DateTime? _firstAnswerAt;
  static const _answerGrace = Duration(milliseconds: 900);

  /// How long a finished round stays on screen. The Figma prototype gives
  /// GOOOL 2.5 s.
  static const _roundEndPause = Duration(milliseconds: 2500);

  /// Silence that counts as the opponent having gone. Heartbeats go out every
  /// five seconds, so this is four missed ones — long enough to ride out a
  /// hiccup, short enough that nobody stares at a frozen round.
  static const _opponentSilence = 20;

  /// Claims are rate-limited because the tick runs four times a second and
  /// the answer does not change that fast.
  DateTime? _lastClaim;

  @override
  void initState() {
    super.initState();
    _sub = widget.rooms.watch(_room.code).listen((room) {
      if (!mounted) return;
      setState(() => _room = room);
      _drive();
    });
    _heartbeat = Timer.periodic(const Duration(seconds: 5), (_) {
      widget.rooms.touchSeen(code: _room.code, seat: _me);
    });
    // Deadlines are instants, not events: nothing arrives to tell a client
    // that the ten seconds are up, so the clock has to be watched.
    _tick = Timer.periodic(const Duration(milliseconds: 250), (_) {
      if (mounted) setState(_drive);
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    _heartbeat?.cancel();
    _tick?.cancel();
    super.dispose();
  }

  /// A server instant on this device's clock.
  DateTime? _local(DateTime? serverTime) =>
      serverTime == null ? null : widget.clock.toLocal(serverTime);

  bool _passed(DateTime? serverTime) {
    final t = _local(serverTime);
    return t != null && DateTime.now().isAfter(t);
  }

  Future<void> _once(String key, Future<void> Function() action) async {
    if (_inFlight != null) return;
    _inFlight = key;
    try {
      await action();
    } catch (e) {
      debugPrint('match transition $key failed: $e');
    } finally {
      if (mounted) _inFlight = null;
    }
  }

  void _drive() {
    if (_phaseSeen != _room.phase) {
      _phaseSeen = _room.phase;
      _phaseSince = DateTime.now();
      _firstAnswerAt = null;
    }

    // Either player may claim an abandoned match, not just the host — a host
    // who walks out must not be the only one able to end the match, or the
    // guest waits forever.
    _watchOpponent();

    if (!_isHost) return;

    final key = '${_room.phase.dbValue}:${_room.round}';

    switch (_room.phase) {
      case MatchPhase.lobby:
        break;

      case MatchPhase.picking:
        if (!_room.bothPicked) return;
        _once('$key:lock', () async {
          // THE NO-ANSWER RULE. Both clubs are in; before anyone watches a
          // countdown, check the pair can actually be answered. A dead pair
          // is voided and replayed rather than run as a round nobody can win.
          final check = await _q.checkPairIsPlayable(
            _room.hostClubId!,
            _room.guestClubId!,
          );
          if (check.playable) {
            await widget.rooms.beginCountdown(_room.code);
          } else {
            await widget.rooms.finishRound(
              code: _room.code,
              winner: null,
              reason: RoundReason.unplayable,
            );
          }
        });

      case MatchPhase.countdown:
        if (!_passed(_room.unlockAt)) return;
        _once('$key:open', () => widget.rooms.openAnswers(_room.code));

      case MatchPhase.answering:
        final mine = _room.hostElapsedMs;
        final theirs = _room.guestElapsedMs;

        if (mine != null && theirs != null) {
          _once('$key:settle', () => _settle());
          return;
        }
        if (mine != null || theirs != null) {
          _firstAnswerAt ??= DateTime.now();
          if (DateTime.now().difference(_firstAnswerAt!) > _answerGrace) {
            _once('$key:settle', () => _settle());
          }
          return;
        }
        if (_passed(_room.answerDeadline)) {
          _once('$key:timeout', () async {
            await widget.rooms.finishRound(
              code: _room.code,
              winner: null,
              reason: RoundReason.noAnswer,
            );
          });
        }

      case MatchPhase.roundOver:
        if (DateTime.now().difference(_phaseSince) < _roundEndPause) return;
        _once('$key:next', () => widget.rooms.nextRound(_room.code));

      case MatchPhase.matchOver:
        break;
    }
  }

  /// Has the opponent stopped checking in?
  ///
  /// This only ASKS. The server compares the opponent's own heartbeat against
  /// its own clock and refuses the claim if they are still alive — which is
  /// what stops a wobble on this device's connection, where nothing arrives
  /// and the opponent merely looks gone, from handing this player the match.
  void _watchOpponent() {
    if (_room.phase == MatchPhase.matchOver ||
        _room.phase == MatchPhase.lobby) {
      return;
    }
    final seen = _room.seenAtOf(_them) ?? _room.createdAt;
    final silence = widget.clock.nowOnServer().difference(seen);
    if (silence.inSeconds < _opponentSilence) return;

    final now = DateTime.now();
    if (_lastClaim != null && now.difference(_lastClaim!).inSeconds < 5) return;
    _lastClaim = now;

    unawaited(_claim());
  }

  Future<void> _claim() async {
    try {
      final room = await widget.rooms.claimForfeit(
        code: _room.code,
        claimant: _me,
        silenceSeconds: _opponentSilence,
      );
      if (mounted) setState(() => _room = room);
    } catch (e) {
      // A failed claim is not worth surfacing: it usually means THIS device
      // is the one that lost its connection, which the next tick retries.
      debugPrint('forfeit claim failed: $e');
    }
  }

  /// Walking out mid-match hands it to the opponent. That is the decided
  /// rule: no grace period, no seat held open.
  Future<void> _leave() async {
    if (_room.phase == MatchPhase.matchOver) return;
    try {
      await widget.rooms.leaveMatch(code: _room.code, seat: _me);
    } catch (e) {
      debugPrint('leave failed: $e');
    }
  }

  Future<void> _rematch() async {
    try {
      final room = await widget.rooms.rematch(_room.code);
      if (!mounted) return;
      setState(() => _room = room);
    } catch (e) {
      debugPrint('rematch failed: $e');
    }
  }

  Future<void> _settle() async {
    await widget.rooms.finishRound(
      code: _room.code,
      winner: _room.decideRoundWinner(),
      reason: RoundReason.correct,
    );
  }

  // -------------------------------------------------------------------------
  // This player's own writes
  // -------------------------------------------------------------------------
  Future<void> _pick(Club club) =>
      widget.rooms.pickClub(code: _room.code, seat: _me, club: club);

  /// The 15 seconds ran out with nothing chosen.
  ///
  /// Each client picks for ITSELF rather than the host picking for both —
  /// that keeps the rule "only the host writes transitions, each player
  /// writes its own columns" intact, and it means an absent host does not
  /// stall the other player's round.
  Future<void> _autoPick() async {
    if (_room.clubIdOf(_me) != null) return;
    final club = await _q.randomPickableClub(
      excludeClubId: _room.clubIdOf(_them),
    );
    if (club != null) await _pick(club);
  }

  @override
  Widget build(BuildContext context) {
    // Backing out of a live match forfeits it. Intercepting the pop rather
    // than letting it through is what makes that happen at all — otherwise
    // the opponent is left staring at a round that never advances.
    return PopScope(
      canPop: _room.phase == MatchPhase.matchOver,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        // Captured before the await: the context can be gone by the time the
        // forfeit round-trips.
        final navigator = Navigator.of(context);
        await _leave();
        if (mounted) navigator.pop();
      },
      child: _body(),
    );
  }

  Widget _body() {
    switch (_room.phase) {
      case MatchPhase.lobby:
        // Only reachable after a rematch, which resets the room to the lobby
        // so neither player is dropped straight into a pick phase they were
        // not looking at. The host starts it again from here rather than
        // being sent back to a lobby screen that no longer exists.
        return _Waiting(
          label: _isHost ? 'Yeni maç' : 'Başlatma bekleniyor',
          action: _isHost
              ? EndButton(
                  label: 'BAŞLAT',
                  filled: true,
                  onTap: () => widget.rooms.startMatch(_room.code),
                )
              : null,
        );

      case MatchPhase.picking:
        final deadline = _local(_room.pickDeadline);
        return MatchTeamSelectScreen(
          key: ValueKey('pick-${_room.round}'),
          playerName: _room.nameOf(_me),
          opponentName: _room.nameOf(_them),
          playerScore: _room.scoreOf(_me),
          opponentScore: _room.scoreOf(_them),
          deadline: deadline ?? DateTime.now().add(const Duration(seconds: 15)),
          opponentPicked: _room.clubIdOf(_them) != null,
          onPicked: _pick,
          onTimeout: _autoPick,
        );

      case MatchPhase.countdown:
      case MatchPhase.answering:
        return MatchCountdownScreen(
          room: _room,
          seat: _me,
          unlockAt: _local(_room.unlockAt),
        );

      case MatchPhase.roundOver:
        return _RoundEnd(room: _room, seat: _me);

      case MatchPhase.matchOver:
        return _MatchEnd(room: _room, seat: _me, onRematch: _rematch);
    }
  }
}

class _Waiting extends StatelessWidget {
  const _Waiting({required this.label, this.action});

  final String label;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: ScreenBackground(
        child: SafeArea(
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    fontFamily: T.fontUi,
                    fontSize: T.t24,
                    color: T.beyaz080,
                  ),
                ),
                if (action != null) ...[
                  const SizedBox(height: T.s2xl),
                  action!,
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Placeholder for `Tur Sonu (GOOOL)` (41:685) and `Tur Bitti` (109:8).
/// Built properly from Figma next; this exists so the loop can be driven end
/// to end and the transitions verified.
class _RoundEnd extends StatelessWidget {
  const _RoundEnd({required this.room, required this.seat});

  final Room room;
  final Seat seat;

  @override
  Widget build(BuildContext context) {
    final reason = room.roundReason;
    final winner = room.roundWinner;
    final String headline;
    if (reason == RoundReason.unplayable) {
      headline = 'TUR BİTTİ';
    } else if (reason == RoundReason.noAnswer) {
      headline = 'SÜRE DOLDU';
    } else {
      headline = winner == seat ? 'GOOOL' : 'RAKİP BULDU';
    }

    final answer = winner == null ? null : room.answerOf(winner);

    return Scaffold(
      body: ScreenBackground(
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                headline,
                style: TextStyle(
                  fontFamily: T.fontUi,
                  fontSize: T.t40,
                  color: winner == seat ? T.yesil : T.beyaz100,
                ),
              ),
              const SizedBox(height: T.sLg),
              Text(
                reason == RoundReason.unplayable
                    ? 'Bu iki takımda oynamış oyuncu yok'
                    : (answer ?? 'Kimse bulamadı'),
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: T.t17, color: T.beyaz065),
              ),
              const SizedBox(height: T.s2xl),
              Text(
                '${room.scoreOf(seat)} - ${room.scoreOf(seat.other)}',
                style: const TextStyle(
                  fontFamily: T.fontNumeral,
                  fontSize: T.t40,
                  color: T.beyaz080,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Placeholder for `Maç Sonu Kazanma` (46:352) / `Kaybetme` (48:534).
class _MatchEnd extends StatelessWidget {
  const _MatchEnd({
    required this.room,
    required this.seat,
    required this.onRematch,
  });

  final Room room;
  final Seat seat;
  final Future<void> Function() onRematch;

  @override
  Widget build(BuildContext context) {
    final won = room.winner == seat;
    final reason = room.endedReason ?? '';
    final forfeit = reason.startsWith('forfeit');
    final abandoned = reason == 'abandoned';

    return Scaffold(
      body: ScreenBackground(
        child: SafeArea(
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  won ? 'KAZANDIN' : 'KAYBETTİN',
                  style: TextStyle(
                    fontFamily: T.fontUi,
                    fontSize: T.t40,
                    color: won ? T.yesil : T.kirmizi,
                  ),
                ),
                const SizedBox(height: T.sLg),
                Text(
                  '${room.scoreOf(seat)} - ${room.scoreOf(seat.other)}',
                  style: const TextStyle(
                    fontFamily: T.fontNumeral,
                    fontSize: T.t96,
                    color: T.beyaz100,
                  ),
                ),
                if (forfeit || abandoned) ...[
                  const SizedBox(height: T.sLg),
                  Text(
                    abandoned ? 'Maç yarıda kaldı' : 'Rakip ayrıldı',
                    style: const TextStyle(
                      fontSize: T.t15,
                      color: T.beyaz050,
                    ),
                  ),
                ],
                const SizedBox(height: 40),
                // A rematch keeps the same room and the same code, so nobody
                // has to share a new one to play again.
                if (!abandoned)
                  EndButton(
                    label: 'TEKRAR OYNA',
                    filled: true,
                    onTap: onRematch,
                  ),
                const SizedBox(height: T.sLg),
                EndButton(
                  label: 'ANA MENÜ',
                  filled: false,
                  onTap: () async => Navigator.of(context)
                      .popUntil((route) => route.isFirst),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
