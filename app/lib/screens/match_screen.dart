import 'dart:async';

import 'package:flutter/material.dart';

import '../ads/rewarded_coins_ad.dart';
import '../data/app_database.dart';
import '../data/game_queries.dart';
import '../models/models.dart';
import '../models/room.dart';
import '../net/account.dart';
import '../net/room_repository.dart';
import '../net/server_clock.dart';
import '../settings/app_settings.dart';
import '../theme/tokens.dart';
import '../widgets/screen_background.dart';
import 'match_board_screen.dart';
import 'match_countdown_screen.dart';
import 'match_end_screens.dart';
import 'match_screen_buttons.dart';
import 'match_team_select_screen.dart';
import 'match_versus_screen.dart';
import 'matchmaking_screen.dart';

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

  /// Whether this match has already moved past its first pick. Versus plays
  /// once per match (and again after a rematch), never on a re-pick — and a
  /// voided first round re-picks with the round number and score unchanged,
  /// so those alone cannot tell the two apart.
  bool _versusDone = false;

  /// How long Versus holds. The Figma prototype advances it on a 2 s timeout.
  static const _versusHold = Duration(seconds: 2);

  /// Every round this device saw end, for the result screen's MAÇ ÖZETİ.
  /// The room row is wiped by next_round, so the history has to be kept
  /// here; a client that reconnected mid-match only knows the rounds since.
  final List<_RoundRecord> _rounds = [];

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

  /// The 3-2-1 numeral last ticked for, so each beat sounds once although
  /// the loop runs four times a second.
  int? _lastBeat;

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
    _ad?.dispose();
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
      final leaving = _phaseSeen;
      _phaseSeen = _room.phase;
      _phaseSince = DateTime.now();
      _firstAnswerAt = null;
      if (_room.phase == MatchPhase.lobby) {
        _versusDone = false;
        _rounds.clear();
      } else if (_room.phase != MatchPhase.picking) {
        _versusDone = true;
      }
      // A round ends in round_over — except the deciding goal, which
      // finish_round takes straight to match_over with the round's verdict
      // and answers still in the row.
      final roundEnded = _room.phase == MatchPhase.roundOver ||
          (_room.phase == MatchPhase.matchOver &&
              _room.endedReason == 'goals' &&
              _room.roundReason != null);
      // finish_round writes the deciding goal as round_over and then, in the
      // same call, match_over - Realtime delivers BOTH updates. Count that
      // round once, or the summary reads 0/4 after a three-round match.
      final alreadyCounted = _room.phase == MatchPhase.matchOver &&
          leaving == MatchPhase.roundOver;
      if (roundEnded && !alreadyCounted) {
        _rounds.add(_RoundRecord(
          reason: _room.roundReason,
          winner: _room.roundWinner,
          myElapsedMs: _room.elapsedOf(_me),
        ));
        Sounds.play(_room.roundWinner != null ? Sfx.goal : Sfx.roundOver);
      }
      if (_room.phase == MatchPhase.matchOver) {
        Sounds.play(_room.winner == _me ? Sfx.win : Sfx.lose);
        unawaited(_recordResult());
        // 2X Altın is offered on a ranked win only: start fetching the ad
        // now, while GOOOL and the result screen are up.
        if (_room.ranked && _room.winner == _me && _ad == null) {
          _ad = RewardedCoinsAd()..load();
        }
      }
    }

    _countdownBeat();

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

  /// One tick per numeral of the countdown, timed by the same unlock_at
  /// instant MatchCountdownScreen counts down to.
  void _countdownBeat() {
    final unlock = _local(_room.unlockAt);
    if (_room.phase != MatchPhase.countdown || unlock == null) {
      _lastBeat = null;
      return;
    }
    final ms = unlock.difference(DateTime.now()).inMilliseconds;
    final n = ms <= 0 ? 0 : (ms / 1000).ceil();
    if (n > 0 && n != _lastBeat) Sounds.play(Sfx.tick);
    _lastBeat = n;
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

  /// Stats, and for a ranked room trophies and coins (007_results.sql).
  ///
  /// BOTH seats call it, not just the host: after a forfeit the host may be
  /// the one who left. The function is idempotent, so the second call is a
  /// no-op; its returned row carries the deltas the result screen shows.
  bool _recording = false;

  Future<void> _recordResult() async {
    // Not skipped when the room is already recorded: the opponent often
    // records first, and this call is also what refreshes OUR coins and
    // trophies (Ana Sayfa's own refresh fires when matchmaking is replaced
    // by the match, i.e. at the START). The RPC is idempotent, so calling
    // it after the other seat costs nothing and returns the deltas.
    if (_recording) return;
    _recording = true;
    try {
      for (var attempt = 0; attempt < 3; attempt++) {
        try {
          final room = await widget.rooms.recordResult(_room.code);
          if (mounted && room.phase == MatchPhase.matchOver) {
            setState(() => _room = room);
          }
          await Account.instance.refresh();
          return;
        } catch (e) {
          debugPrint('record_match_result failed (attempt ${attempt + 1}): $e');
          await Future<void>.delayed(const Duration(seconds: 1));
        }
      }
    } finally {
      _recording = false;
    }
  }

  /// The rewarded ad behind `2X Altın`; null unless this was a ranked win.
  RewardedCoinsAd? _ad;

  /// Once the ad has been shown (watched or not), the button is gone for
  /// this match: one ad per match, and a failure leaves the normal reward.
  bool _adUsed = false;

  /// Plays the ad; only a fully watched one asks the server to double. The
  /// server (double_match_coins, 010) holds "once per match, own ranked win
  /// only" — this client just shows the result it returns.
  Future<void> _doubleCoins() async {
    final ad = _ad;
    if (ad == null || _adUsed) return;
    setState(() => _adUsed = true);
    final earned = await ad.show();
    if (!earned) return;
    for (var attempt = 0; attempt < 3; attempt++) {
      try {
        final room = await widget.rooms.doubleMatchCoins(_room.code);
        if (mounted && room.phase == MatchPhase.matchOver) {
          setState(() => _room = room);
        }
        await Account.instance.refresh();
        return;
      } catch (e) {
        debugPrint('double_match_coins failed (attempt ${attempt + 1}): $e');
        await Future<void>.delayed(const Duration(seconds: 1));
      }
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
  /// A correct answer and the time the board stamped on it.
  ///
  /// Retried once: a dropped write here silently loses a round this player
  /// won. The `elapsed_ms is null` filter in submitAnswer makes the retry
  /// harmless if the first attempt did land.
  Future<void> _answer(String answer, int elapsedMs) async {
    for (var attempt = 0; attempt < 2; attempt++) {
      try {
        await widget.rooms.submitAnswer(
          code: _room.code,
          seat: _me,
          answer: answer,
          elapsedMs: elapsedMs,
        );
        return;
      } catch (e) {
        debugPrint('submitAnswer failed (attempt ${attempt + 1}): $e');
        await Future<void>.delayed(const Duration(milliseconds: 400));
      }
    }
  }

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

  /// Versus (27:42) sits between "the match is on" and the first team pick,
  /// as in the prototype. There is no phase for it — adding one would change
  /// the backend protocol — so it is drawn over the first two seconds of the
  /// first pick window. Both players lose the same two seconds of the 15,
  /// and the window is timed against the room's pick_deadline, so a client
  /// that reconnects later in the window skips straight to the picker.
  bool _showVersus(DateTime? pickDeadline) {
    if (_versusDone || pickDeadline == null) return false;
    if (_room.round != 1 || _room.hostScore + _room.guestScore != 0) {
      return false;
    }
    final sinceOpen = Duration(seconds: _room.pickSeconds) -
        pickDeadline.difference(DateTime.now());
    if (sinceOpen < _versusHold) return true;
    _versusDone = true;
    return false;
  }

  /// GOOOL (41:685) for a round somebody won, Tur Bitti (109:8) for one
  /// nobody did — the clock ran out, or the pair was unplayable.
  Widget _roundEnd() {
    final scorer = _room.roundWinner;
    if (_room.roundReason == RoundReason.correct && scorer != null) {
      return MatchGoalScreen(
        key: ValueKey('goal-${_room.round}'),
        playerName: _room.nameOf(_me),
        opponentName: _room.nameOf(_them),
        playerScore: _room.scoreOf(_me),
        opponentScore: _room.scoreOf(_them),
        scorerName: _room.nameOf(scorer),
        scorerIsMe: scorer == _me,
        answer: _room.answerOf(scorer),
        elapsedMs: _room.elapsedOf(scorer),
        clubs: {
          if (_room.hostClubId != null)
            _room.hostClubId!: _room.hostClubName ?? '',
          if (_room.guestClubId != null)
            _room.guestClubId!: _room.guestClubName ?? '',
        },
        since: _phaseSince,
        hold: _roundEndPause,
      );
    }
    return MatchRoundVoidScreen(
      key: ValueKey('void-${_room.round}'),
      playerName: _room.nameOf(_me),
      opponentName: _room.nameOf(_them),
      playerScore: _room.scoreOf(_me),
      opponentScore: _room.scoreOf(_them),
      unplayable: _room.roundReason == RoundReason.unplayable,
      clubAId: _room.clubIdOf(_me),
      clubBId: _room.clubIdOf(_them),
      since: _phaseSince,
      hold: _roundEndPause,
    );
  }

  /// Kazanma (46:352) / Kaybetme (48:534).
  Widget _result() {
    final reason = _room.endedReason ?? '';
    final String? note;
    if (reason == 'abandoned') {
      note = 'Maç yarıda kaldı';
    } else if (reason == 'forfeit_${_them.dbValue}') {
      note = 'Rakip ayrıldı';
    } else if (reason == 'forfeit_${_me.dbValue}') {
      note = 'Bağlantın koptu';
    } else {
      note = null;
    }

    final ad = _ad;
    if (ad == null) return _resultScreen(note, reason, offerDouble: false);
    return ValueListenableBuilder<bool>(
      valueListenable: ad.ready,
      builder: (context, ready, _) => _resultScreen(
        note,
        reason,
        // Only once the win is recorded (the server refuses before that)
        // and only while an ad is actually in hand.
        offerDouble: ready && !_adUsed && _room.resultRecorded,
      ),
    );
  }

  Widget _resultScreen(String? note, String reason,
      {required bool offerDouble}) {
    return MatchResultScreen(
      onDoubleCoins: offerDouble ? _doubleCoins : null,
      won: _room.winner == _me,
      playerName: _room.nameOf(_me),
      opponentName: _room.nameOf(_them),
      playerScore: _room.scoreOf(_me),
      opponentScore: _room.scoreOf(_them),
      summary: _summary(),
      note: note,
      ranked: _room.ranked,
      trophyDelta: _room.trophyDeltaOf(_me),
      coinDelta: _room.coinDeltaOf(_me),
      // Ranked: Tekrar Oyna queues again for a new opponent. Friend Match:
      // a rematch needs both players still here — only a match decided on
      // goals; after a forfeit or an abandoned match the other seat is gone.
      onRematch: _room.ranked
          ? () => Navigator.of(context).pushReplacement(
                MaterialPageRoute(builder: (_) => const MatchmakingScreen()),
              )
          : (reason == 'goals' ? _rematch : null),
      onHome: () => Navigator.of(context).popUntil((route) => route.isFirst),
    );
  }

  MatchSummary _summary() {
    int? fastest;
    var correct = 0;
    var played = 0;
    var streak = 0;
    var best = 0;
    for (final r in _rounds) {
      // A voided round could not be answered, so it counts for nothing —
      // not as played, and not as a break in a streak.
      if (r.reason == RoundReason.unplayable) continue;
      played++;
      final ms = r.myElapsedMs;
      if (ms != null) {
        correct++;
        fastest = fastest == null || ms < fastest ? ms : fastest;
      }
      streak = r.winner == _me ? streak + 1 : 0;
      if (streak > best) best = streak;
    }
    return MatchSummary(
      fastestMs: fastest,
      correct: correct,
      rounds: played,
      bestStreak: best,
    );
  }

  /// The PvP board for the round in progress (`Maç - Oyuncu Arama`).
  Widget _board(DateTime unlock) {
    final deadline = _local(_room.answerDeadline) ??
        unlock.add(Duration(seconds: _room.answerSeconds));
    return MatchBoardScreen(
      key: ValueKey('board-${_room.round}'),
      playerName: _room.nameOf(_me),
      opponentName: _room.nameOf(_them),
      playerScore: _room.scoreOf(_me),
      opponentScore: _room.scoreOf(_them),
      clubAId: _room.clubIdOf(_me)!,
      clubAName: _room.clubNameOf(_me) ?? '',
      clubBId: _room.clubIdOf(_them)!,
      clubBName: _room.clubNameOf(_them) ?? '',
      unlockAt: unlock,
      deadline: deadline,
      answerSeconds: _room.answerSeconds,
      opponentFound: _room.elapsedOf(_them) != null,
      onCorrect: _answer,
    );
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
        if (_showVersus(deadline)) {
          return MatchVersusScreen(
            playerName: _room.nameOf(_me),
            opponentName: _room.nameOf(_them),
            targetGoals: _room.targetGoals,
            ranked: _room.ranked,
          );
        }
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
        // Input opens when THIS device's clock reaches unlock_at, not when
        // the host's open_answers marker arrives — that is the protocol
        // (003_match_flow.sql), and it is what keeps latency out of the
        // elapsed times. Both phases share one board, under one key, so the
        // countdown -> answering flip lands on the SAME board and its
        // stopwatch keeps running.
        final unlock = _local(_room.unlockAt);
        if (unlock != null &&
            _room.bothPicked &&
            !DateTime.now().isBefore(unlock)) {
          return _board(unlock);
        }
        return MatchCountdownScreen(
          room: _room,
          seat: _me,
          unlockAt: unlock,
        );

      case MatchPhase.roundOver:
        return _roundEnd();

      case MatchPhase.matchOver:
        // The deciding goal skips round_over (see _drive), so it gets its
        // GOOOL here, for the same 2.5 s, before the result — the order the
        // prototype plays them in. Only when the match JUST ended: reopening
        // a finished match goes straight to the result.
        final justEnded = DateTime.now().difference(_phaseSince) <
                _roundEndPause &&
            widget.clock.nowOnServer().difference(_room.updatedAt) <
                _roundEndPause + const Duration(seconds: 1);
        if (_room.endedReason == 'goals' &&
            _room.roundWinner != null &&
            justEnded) {
          return _roundEnd();
        }
        return _result();
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

/// One finished round, as this device saw it.
class _RoundRecord {
  const _RoundRecord({
    required this.reason,
    required this.winner,
    required this.myElapsedMs,
  });

  final RoundReason? reason;
  final Seat? winner;

  /// This player's correct-answer time, if they found one — whether or not
  /// it won the round.
  final int? myElapsedMs;
}
