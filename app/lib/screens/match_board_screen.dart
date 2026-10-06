import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/app_database.dart';
import '../data/game_queries.dart';
import '../models/models.dart';
import '../theme/tokens.dart';
import '../widgets/match_chrome.dart';
import '../widgets/practice_chrome.dart';
import '../widgets/screen_background.dart';
import '../widgets/search_bar_panel.dart';
import '../widgets/turkish_keyboard.dart';

/// `Maç - Oyuncu Arama` (Figma 41:584) and its typing state (86:334): the
/// ten seconds in which both players hunt for a footballer who played for
/// both clubs.
///
/// Built on the practice board — same keyboard, search bar, suggestion panel
/// and rejection line — with the PvP differences from the frames:
///
///  * the score strip and the red Jaro round clock across the top;
///  * idle, the two big club cards and the `Canlı Durum` strip; typing, the
///    `Eşleşme (Kompakt)` strip and THREE suggestions instead of four;
///  * no PAS GEÇ, no Cevap chip, no streak.
///
/// Presentational like the team picker: it owns what is being typed and the
/// stopwatch, and reports a correct answer through [onCorrect]. Everything
/// else — score, deadline, whether the opponent has answered — comes from the
/// room via the caller.
///
/// **Timing.** The round is decided by elapsed time measured on each phone
/// (see `Room.decideRoundWinner`). The [Stopwatch] is monotonic and runs from
/// this device's unlock; it is read the instant GÖNDER (or a suggestion) is
/// pressed, BEFORE validation runs, so a slow query on one phone cannot cost
/// that player the round.
class MatchBoardScreen extends StatefulWidget {
  const MatchBoardScreen({
    super.key,
    required this.playerName,
    required this.opponentName,
    required this.playerScore,
    required this.opponentScore,
    required this.clubAId,
    required this.clubAName,
    required this.clubBId,
    required this.clubBName,
    required this.unlockAt,
    required this.deadline,
    required this.answerSeconds,
    required this.opponentFound,
    required this.onCorrect,
  });

  final String playerName;
  final String opponentName;
  final int playerScore;
  final int opponentScore;

  /// The pair being played: this player's club first, the opponent's second,
  /// so each phone shows its own pick on the left.
  final int clubAId;
  final String clubAName;
  final int clubBId;
  final String clubBName;

  /// When input opened, on this device's clock. Used only to work out how
  /// late the board was mounted (see [_lateBy]).
  final DateTime unlockAt;

  /// When the round closes, on this device's clock.
  final DateTime deadline;

  /// The room's answer window, used to cap the late-mount correction.
  final int answerSeconds;

  /// Whether the opponent's correct answer is already in the row.
  final bool opponentFound;

  /// A correct answer: the matched player's display name and the elapsed time
  /// stamped when it was submitted. Called at most once.
  final Future<void> Function(String answer, int elapsedMs) onCorrect;

  @override
  State<MatchBoardScreen> createState() => _MatchBoardScreenState();
}

class _MatchBoardScreenState extends State<MatchBoardScreen> {
  late final GameQueries _q = GameQueries(AppDatabase.instance.db);

  /// Started in initState, which is as close to the unlock as this widget
  /// can get — see [_lateBy] for the remainder.
  final Stopwatch _stopwatch = Stopwatch();

  /// How long after the unlock this board was mounted.
  ///
  /// The match loop ticks four times a second, so the board can appear up to
  /// 250 ms after the unlock — and much later after a reconnect. Starting the
  /// stopwatch at mount would hand the player that gap for free. It is
  /// measured once, against the unlock instant already converted to this
  /// device's clock, and added to every reading. Capped at the window so a
  /// wild clock cannot produce an absurd time.
  late final Duration _lateBy;

  String _typed = '';
  List<Player> _suggestions = const [];
  AnswerResult? _rejection;

  /// The player this device found. Once set, input is closed: a round is one
  /// answer, and the repository refuses a second write anyway.
  Player? _found;

  /// A submission is being validated. Blocks a second press from stamping a
  /// second, later time over the first.
  bool _checking = false;

  int _suggestToken = 0;
  static const _suggestDebounce = Duration(milliseconds: 90);
  Timer? _suggestTimer;

  /// PvP shows three suggestions, not practice's four (86:459).
  static const _maxSuggestions = 3;

  Timer? _tick;
  late int _secondsLeft = _remaining();

  bool get _timeUp => _secondsLeft <= 0;
  bool get _locked => _found != null || _timeUp;

  @override
  void initState() {
    super.initState();
    _stopwatch.start();
    final late = DateTime.now().difference(widget.unlockAt);
    final cap = Duration(seconds: widget.answerSeconds);
    _lateBy = late.isNegative ? Duration.zero : (late > cap ? cap : late);

    _tick = Timer.periodic(const Duration(milliseconds: 200), (_) {
      final left = _remaining();
      if (left != _secondsLeft && mounted) {
        setState(() => _secondsLeft = left);
      }
      if (left <= 0) _tick?.cancel();
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    _suggestTimer?.cancel();
    _stopwatch.stop();
    super.dispose();
  }

  int _remaining() {
    final ms = widget.deadline.difference(DateTime.now()).inMilliseconds;
    if (ms <= 0) return 0;
    return math.min((ms / 1000).ceil(), widget.answerSeconds);
  }

  int _elapsedMs() => (_lateBy + _stopwatch.elapsed).inMilliseconds;

  void _refreshSuggestions() {
    _suggestTimer?.cancel();
    _suggestTimer = Timer(_suggestDebounce, () async {
      final token = ++_suggestToken;
      final results = await _q.suggestPlayers(_typed, limit: _maxSuggestions);
      if (!mounted || token != _suggestToken) return;
      setState(() => _suggestions = results);
    });
  }

  void _onKey(String ch) {
    if (_locked) return;
    setState(() {
      _typed += ch.toLowerCase();
      _rejection = null;
    });
    _refreshSuggestions();
  }

  void _onSpace() {
    if (_locked || _typed.isEmpty || _typed.endsWith(' ')) return;
    setState(() {
      _typed += ' ';
      _rejection = null;
    });
    _refreshSuggestions();
  }

  void _onBackspace() {
    if (_locked || _typed.isEmpty) return;
    setState(() {
      _typed = _typed.substring(0, _typed.length - 1);
      _rejection = null;
    });
    _refreshSuggestions();
  }

  void _onClear() {
    if (_locked) return;
    setState(() {
      _typed = '';
      _suggestions = const [];
      _rejection = null;
    });
  }

  Future<void> _submit([String? override]) async {
    // THE TIMESTAMP. Read first, before anything that can take time.
    final elapsed = _elapsedMs();

    final answer = override ?? _typed;
    if (_locked || _checking || answer.trim().isEmpty) return;

    _checking = true;
    try {
      final result = await _q.validateAnswer(
        answer,
        widget.clubAId,
        widget.clubBId,
      );
      if (!mounted) return;

      if (result.correct) {
        HapticFeedback.mediumImpact();
        setState(() {
          _found = result.player;
          _suggestions = const [];
          _rejection = null;
        });
        // Fire and forget from the board's point of view: the room row is
        // what moves the match on, not this call returning.
        unawaited(widget.onCorrect(result.player!.displayName, elapsed));
      } else {
        HapticFeedback.heavyImpact();
        setState(() => _rejection = result);
      }
    } finally {
      _checking = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final typing = _typed.isNotEmpty && !_locked;

    return Scaffold(
      body: ScreenBackground(
        child: SafeArea(
          bottom: false,
          child: Column(
            children: [
              const SizedBox(height: T.sLg),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: MatchScoreStrip(
                  playerName: widget.playerName,
                  opponentName: widget.opponentName,
                  playerScore: widget.playerScore,
                  opponentScore: widget.opponentScore,
                ),
              ),
              const SizedBox(height: T.s2xl),
              RoundTimer(seconds: _secondsLeft, urgent: _secondsLeft <= 3),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: T.s2xl),
                  child: typing ? _typingBody() : _idleBody(),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: T.s2xl),
                child: Column(
                  children: [
                    if (_found != null)
                      _FoundLine(name: _found!.displayName)
                    else
                      RejectionBanner(rejection: _rejection),
                    const SizedBox(height: T.sSm),
                    PracticeSearchBar(typed: _typed, onClear: _onClear),
                  ],
                ),
              ),
              const SizedBox(height: T.sLg),
              TurkishKeyboard(
                onKey: _onKey,
                onSpace: _onSpace,
                onBackspace: _onBackspace,
                onAction: _submit,
                actionLabel: 'GÖNDER',
                actionEnabled: !_locked && _typed.trim().isNotEmpty,
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 41:584 — the two big cards, then `Canlı Durum`.
  ///
  /// Scrolls rather than overflowing: the frame is 932pt tall and a short
  /// phone has well under that between the clock and the search bar.
  Widget _idleBody() {
    final String opponentLabel;
    if (widget.opponentFound) {
      opponentLabel = 'buldu!';
    } else if (_timeUp) {
      opponentLabel = 'süre doldu';
    } else {
      opponentLabel = 'yazıyor';
    }

    return LayoutBuilder(
      builder: (context, box) => SingleChildScrollView(
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: box.maxHeight),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              MatchupRow(clubA: widget.clubAName, clubB: widget.clubBName),
              const SizedBox(height: 40),
              LiveStatusStrip(
                playerName: widget.playerName,
                opponentName: widget.opponentName,
                playerLabel: _found != null ? 'Sen · buldun!' : 'Sen',
                opponentLabel: opponentLabel,
                showDots: !widget.opponentFound && !_timeUp,
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 86:334 — the compact strip pinned under the clock, the suggestion panel
  /// sized to whatever is left above the search bar. Rows adapt to the
  /// height rather than the panel overflowing: an overflowing panel pushes
  /// its top row — the one carrying ↵ — up behind the strip.
  Widget _typingBody() {
    return Column(
      children: [
        const SizedBox(height: T.sXl),
        CompactMatchupStrip(clubA: widget.clubAName, clubB: widget.clubBName),
        Expanded(
          child: LayoutBuilder(
            builder: (context, box) {
              final rows =
                  ((box.maxHeight - SuggestionPanel.chromeExtent - T.sSm) /
                          SuggestionPanel.rowExtent)
                      .floor()
                      .clamp(0, _maxSuggestions);
              if (rows == 0) return const SizedBox.shrink();
              return Align(
                alignment: Alignment.bottomCenter,
                child: SuggestionPanel(
                  typed: _typed,
                  suggestions: _suggestions,
                  maxRows: rows,
                  onTap: (p) => _submit(p.displayName),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

/// The line that replaces the rejection message once this player has found
/// one. Not in the frames — they stop at the typing state — but without it a
/// correct answer looks like nothing happened for the up-to-900 ms the host
/// waits before settling the round.
class _FoundLine extends StatelessWidget {
  const _FoundLine({required this.name});

  final String name;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: 22),
      alignment: Alignment.center,
      child: Text(
        '✓ $name',
        textAlign: TextAlign.center,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          fontFamily: T.fontUi,
          fontSize: T.t15,
          color: T.yesil,
        ),
      ),
    );
  }
}
