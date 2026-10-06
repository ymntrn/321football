import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/app_database.dart';
import '../data/game_queries.dart';
import '../models/models.dart';
import '../theme/tokens.dart';
import '../widgets/club_search_panel.dart';
import '../widgets/match_chrome.dart';
import '../widgets/screen_background.dart';
import '../widgets/search_bar_panel.dart';
import '../widgets/turkish_keyboard.dart';

/// `Maç - Takım Seçme` (Figma 33:85) and its typing state (86:190).
///
/// Both players pick a club inside the same window; this screen is one
/// player's half of that. It is deliberately presentational — it owns the
/// text being typed and the club chosen, and nothing else. The score, the
/// opponent's progress and the deadline all come from the caller, because in
/// a real match they come from the room and not from this device.
///
/// The countdown is anchored to [deadline] rather than started as a local
/// timer on mount. That matters: a local `Duration` timer begun when a "go"
/// message lands gives each phone a window offset by its own latency. An
/// absolute instant every client counts down to does not.
class MatchTeamSelectScreen extends StatefulWidget {
  const MatchTeamSelectScreen({
    super.key,
    required this.playerName,
    required this.opponentName,
    required this.playerScore,
    required this.opponentScore,
    required this.deadline,
    required this.onPicked,
    this.onTimeout,
    this.opponentPicked = false,
  });

  final String playerName;
  final String opponentName;
  final int playerScore;
  final int opponentScore;

  /// When the pick window closes, on this device's clock. The match state
  /// machine converts the room's server timestamp into local time using the
  /// measured clock offset before handing it over.
  final DateTime deadline;

  /// Fired once, when this player commits a club.
  final ValueChanged<Club> onPicked;

  /// Fired once, if the window closes with nothing picked.
  final VoidCallback? onTimeout;

  /// Whether the opponent has already locked in, which changes the status
  /// pill from "seçiyor" to "hazır".
  final bool opponentPicked;

  @override
  State<MatchTeamSelectScreen> createState() => _MatchTeamSelectScreenState();
}

class _MatchTeamSelectScreenState extends State<MatchTeamSelectScreen> {
  late final GameQueries _q = GameQueries(AppDatabase.instance.db);

  String _typed = '';
  List<Club> _results = const [];
  Club? _picked;

  /// Guards against a slow query landing after the player has typed on.
  int _searchToken = 0;

  /// Same 90 ms coalescing the player search uses. Club search is far cheaper
  /// (3-5 ms against 821 rows, versus a scan of 198,626 player aliases), but
  /// under a 15-second clock there is no reason to fire a query per letter.
  static const _searchDebounce = Duration(milliseconds: 90);
  Timer? _searchTimer;

  Timer? _tick;
  late int _secondsLeft = _remaining();

  @override
  void initState() {
    super.initState();
    // 200 ms rather than a full second: the numeral should turn over close to
    // the real boundary, not up to a second late.
    _tick = Timer.periodic(const Duration(milliseconds: 200), (_) {
      final left = _remaining();
      if (left != _secondsLeft && mounted) {
        setState(() => _secondsLeft = left);
      }
      if (left <= 0) {
        _tick?.cancel();
        if (_picked == null) widget.onTimeout?.call();
      }
    });
  }

  int _remaining() {
    final ms = widget.deadline.difference(DateTime.now()).inMilliseconds;
    if (ms <= 0) return 0;
    return (ms / 1000).ceil();
  }

  @override
  void dispose() {
    _tick?.cancel();
    _searchTimer?.cancel();
    super.dispose();
  }

  void _refresh() {
    _searchTimer?.cancel();
    _searchTimer = Timer(_searchDebounce, () async {
      final token = ++_searchToken;
      final results = await _q.searchClubs(_typed, limit: 4);
      if (!mounted || token != _searchToken) return;
      setState(() => _results = results);
    });
  }

  void _onKey(String ch) {
    if (_picked != null) return;
    setState(() => _typed += ch.toLowerCase());
    _refresh();
  }

  void _onSpace() {
    if (_picked != null || _typed.isEmpty || _typed.endsWith(' ')) return;
    setState(() => _typed += ' ');
    _refresh();
  }

  void _onBackspace() {
    if (_picked != null || _typed.isEmpty) return;
    setState(() => _typed = _typed.substring(0, _typed.length - 1));
    _refresh();
  }

  void _onClear() {
    setState(() {
      _typed = '';
      _results = const [];
    });
  }

  /// GÖNDER commits the top suggestion — the row already wearing the ↵
  /// affordance, so the keyboard and the list agree on what Enter means.
  void _submit() {
    if (_results.isEmpty) return;
    _pick(_results.first);
  }

  void _pick(Club club) {
    if (_picked != null) return;
    HapticFeedback.selectionClick();
    setState(() {
      _picked = club;
      _typed = '';
      _results = const [];
    });
    widget.onPicked(club);
  }

  @override
  Widget build(BuildContext context) {
    final typing = _typed.isNotEmpty;
    final locked = _picked != null;

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
              RoundTimer(seconds: _secondsLeft, urgent: _secondsLeft <= 5),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: T.s2xl),
                  child: typing ? _panel() : _idle(locked),
                ),
              ),
              // Once a club is locked in there is nothing left to type, so the
              // search bar and keyboard give way to the waiting state.
              if (!locked) ...[
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: T.s2xl),
                  child: PracticeSearchBar(
                    typed: _typed,
                    onClear: _onClear,
                    placeholder: 'Takım ara...',
                  ),
                ),
                const SizedBox(height: T.sLg),
                TurkishKeyboard(
                  onKey: _onKey,
                  onSpace: _onSpace,
                  onBackspace: _onBackspace,
                  onAction: _submit,
                  actionLabel: 'SEÇ',
                  actionEnabled: _results.isNotEmpty,
                ),
              ] else
                const Padding(
                  padding: EdgeInsets.only(bottom: 40),
                  child: HomeIndicator(),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _idle(bool locked) {
    return SingleChildScrollView(
      child: Column(
        children: [
          const SizedBox(height: 50),
          TeamPickerSlot(club: _picked),
          const SizedBox(height: 40),
          OpponentStatusChip(
            name: widget.opponentName,
            message: locked && widget.opponentPicked
                ? 'Her iki takım da hazır'
                : widget.opponentPicked
                    ? '${widget.opponentName} hazır'
                    : '${widget.opponentName} takımını seçiyor',
            showDots: !widget.opponentPicked,
          ),
        ],
      ),
    );
  }

  /// While typing, the suggestion panel takes over the middle of the screen
  /// and is sized to the space rather than scrolled into it — the same rule
  /// the practice board follows, for the same reason: a panel allowed to
  /// overflow hides its own top row, which is the one carrying ↵.
  Widget _panel() {
    return LayoutBuilder(
      builder: (context, box) {
        final rows = ((box.maxHeight - ClubSuggestionPanel.chromeExtent) /
                ClubSuggestionPanel.rowExtent)
            .floor()
            .clamp(1, 4);
        return Align(
          alignment: Alignment.bottomCenter,
          child: ClubSuggestionPanel(
            typed: _typed,
            clubs: _results,
            maxRows: rows,
            onTap: _pick,
          ),
        );
      },
    );
  }
}
