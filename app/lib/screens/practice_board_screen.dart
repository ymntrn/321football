import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/app_database.dart';
import '../data/game_queries.dart';
import '../models/models.dart';
import '../theme/tokens.dart';
import '../widgets/practice_chrome.dart';
import '../widgets/screen_background.dart';
import '../widgets/search_bar_panel.dart';
import '../widgets/turkish_keyboard.dart';

/// `Alıştırma - Oyuncu Bulma` (Figma 50:353) and its typing state (78:356),
/// with the `Doğru Cevap` (78:610), `Cevap Onayı` (82:338) and
/// `Cevabı Göster` (78:483) popups over it.
///
/// Practice is untimed and ONE correct footballer ends the round, so there is
/// no found-players panel here: a correct answer is the Doğru popup and the
/// streak is the only score.
class PracticeBoardScreen extends StatefulWidget {
  const PracticeBoardScreen({super.key, required this.difficulty});

  final Difficulty difficulty;

  @override
  State<PracticeBoardScreen> createState() => _PracticeBoardScreenState();
}

class _PracticeBoardScreenState extends State<PracticeBoardScreen> {
  late final GameQueries _q = GameQueries(AppDatabase.instance.db);

  PracticePair? _pair;
  String _typed = '';
  List<Player> _suggestions = const [];
  AnswerResult? _rejection;
  Player? _won;
  int _streak = 0;
  bool _loading = true;

  /// Which answer popup is up, if any: the `Cevap Onayı` confirmation
  /// (82:338), then the `Cevabı Göster` list (78:483).
  _Reveal? _reveal;
  List<Player> _answers = const [];

  /// Guards against a slow suggestion query landing after the player has typed
  /// on — without this the panel flickers back to stale names.
  int _suggestToken = 0;

  /// Coalesces keystrokes so a fast typist fires one query, not one per
  /// letter. Short enough to feel instant, long enough that "sneijder" is a
  /// single round trip instead of eight.
  static const _suggestDebounce = Duration(milliseconds: 90);
  Timer? _suggestTimer;

  @override
  void initState() {
    super.initState();
    _nextPair();
  }

  @override
  void dispose() {
    _suggestTimer?.cancel();
    super.dispose();
  }

  Future<void> _nextPair() async {
    setState(() {
      _loading = true;
      _typed = '';
      _suggestions = const [];
      _rejection = null;
      _won = null;
      _reveal = null;
      _answers = const [];
    });
    final pair = await _q.randomPracticePair(widget.difficulty);
    if (!mounted) return;
    setState(() {
      _pair = pair;
      _loading = false;
    });
  }

  void _refreshSuggestions() {
    _suggestTimer?.cancel();
    _suggestTimer = Timer(_suggestDebounce, () async {
      final token = ++_suggestToken;
      final results = await _q.suggestPlayers(_typed, limit: 4);
      if (!mounted || token != _suggestToken) return;
      setState(() => _suggestions = results);
    });
  }

  void _onKey(String ch) {
    setState(() {
      _typed += ch.toLowerCase();
      _rejection = null;
    });
    _refreshSuggestions();
  }

  void _onSpace() {
    if (_typed.isEmpty || _typed.endsWith(' ')) return;
    setState(() {
      _typed += ' ';
      _rejection = null;
    });
    _refreshSuggestions();
  }

  void _onBackspace() {
    if (_typed.isEmpty) return;
    setState(() {
      _typed = _typed.substring(0, _typed.length - 1);
      _rejection = null;
    });
    _refreshSuggestions();
  }

  void _onClear() {
    setState(() {
      _typed = '';
      _suggestions = const [];
      _rejection = null;
    });
  }

  Future<void> _submit([String? override]) async {
    final pair = _pair;
    final answer = override ?? _typed;
    if (pair == null || answer.trim().isEmpty) return;

    final result = await _q.validateAnswer(answer, pair.clubAId, pair.clubBId);
    if (!mounted) return;

    if (result.correct) {
      HapticFeedback.mediumImpact();
      setState(() {
        _won = result.player;
        _streak += 1;
        _suggestions = const [];
      });
    } else {
      HapticFeedback.heavyImpact();
      setState(() => _rejection = result);
    }
  }

  /// PAS GEÇ. Figma could not wire this because a navigation cannot target
  /// its own frame — in the app it is a state change, not a navigation.
  void _skip() {
    setState(() => _streak = 0);
    _nextPair();
  }

  /// The Cevap chip. Opens the confirmation; the list comes after.
  void _showAnswers() {
    if (_pair == null || _won != null) return;
    setState(() => _reveal = _Reveal.confirm);
  }

  /// `N ALTIN HARCA`. Loads the answer key and shows it.
  ///
  /// The price is a PRICE TAG only — the coin balance lives on the profile,
  /// which does not exist yet, so nothing is actually debited.
  ///
  /// The streak is NOT reset: the design's own copy says "Seri sayacın
  /// sıfırlanmaz". (The invented sheet this replaced reset it.)
  Future<void> _confirmReveal() async {
    final pair = _pair;
    if (pair == null) return;
    final players = await _q.getMutualPlayers(pair.clubAId, pair.clubBId);
    if (!mounted) return;
    setState(() {
      _answers = players;
      _reveal = _Reveal.answers;
    });
  }

  /// DEVAM moves on to a new pair. Staying would leave the answer on screen
  /// a moment ago one keystroke away from a free streak point.
  void _afterReveal() => _nextPair();

  Map<int, String> _clubs(PracticePair pair) => {
        pair.clubAId: pair.clubAName,
        pair.clubBId: pair.clubBName,
      };

  @override
  Widget build(BuildContext context) {
    final pair = _pair;

    return Scaffold(
      body: ScreenBackground(
        child: Stack(
          children: [
            SafeArea(
              bottom: false,
              child: Column(
                children: [
                  PracticeTopBar(
                    onBack: () => Navigator.of(context).maybePop(),
                    onHint: _showAnswers,
                  ),
                  Expanded(
                    child: _loading || pair == null
                        ? Center(
                            child: _loading
                                ? const CircularProgressIndicator(
                                    color: T.turuncu)
                                : const Text(
                                    'Bu seviyede soru bulunamadı.',
                                    style: TextStyle(
                                      color: T.beyaz065,
                                      fontSize: T.t17,
                                    ),
                                  ),
                          )
                        : _body(pair),
                  ),
                  TurkishKeyboard(
                    onKey: _onKey,
                    onSpace: _onSpace,
                    onBackspace: _onBackspace,
                    onAction: _submit,
                    actionLabel: 'GÖNDER',
                    actionEnabled: _typed.trim().isNotEmpty,
                  ),
                ],
              ),
            ),
            if (_won != null && pair != null)
              Positioned.fill(
                child: CorrectAnswerOverlay(
                  player: _won!,
                  clubs: _clubs(pair),
                  onDone: _nextPair,
                ),
              ),
            if (_reveal != null && pair != null) ...[
              Positioned.fill(
                child: PopupScrim(
                  opacity: 0.72,
                  // The list has its own DEVAM; only the confirmation can be
                  // dismissed by tapping outside it.
                  onTap: _reveal == _Reveal.confirm
                      ? () => setState(() => _reveal = null)
                      : null,
                ),
              ),
              Align(
                alignment: const Alignment(0, -0.3),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: T.sLg),
                  child: _reveal == _Reveal.confirm
                      ? RevealConfirmPopup(
                          cost: PracticeTopBar.answerCost,
                          onCancel: () => setState(() => _reveal = null),
                          onConfirm: _confirmReveal,
                        )
                      : RevealAnswersPopup(
                          players: _answers,
                          clubs: _clubs(pair),
                          cost: PracticeTopBar.answerCost,
                          onContinue: _afterReveal,
                        ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _body(PracticePair pair) {
    final typing = _typed.isNotEmpty;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: T.s2xl),
      child: Column(
        children: [
          const SizedBox(height: 12),
          MatchupRow(clubA: pair.clubAName, clubB: pair.clubBName),
          // While typing, the suggestion panel takes over the middle of the
          // screen; idle, the prompt / badges / PAS GEÇ stack sits there.
          //
          // The panel is sized to the space rather than scrolled into it. An
          // earlier reverse-scrolling version let it grow past the available
          // height, which pushed its top row — the best match, and the one
          // with the ↵ affordance — up behind the club cards where it could
          // not be read. Now the row count adapts instead.
          Expanded(
            child: LayoutBuilder(
              builder: (context, box) {
                if (!typing) {
                  return SingleChildScrollView(
                    child: Column(
                      children: [
                        const SizedBox(height: 26),
                        const Text(
                          'İki takımda da oynamış bir futbolcu yaz',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontFamily: T.fontUi,
                            fontSize: T.t17,
                            color: T.beyaz065,
                          ),
                        ),
                        const SizedBox(height: T.s2xl),
                        StatusBadges(
                          difficulty: widget.difficulty,
                          streak: _streak,
                        ),
                        const SizedBox(height: 34),
                        SkipButton(onTap: _skip),
                      ],
                    ),
                  );
                }

                final rows = ((box.maxHeight -
                            SuggestionPanel.chromeExtent -
                            T.sSm) /
                        SuggestionPanel.rowExtent)
                    .floor()
                    .clamp(1, 4);

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
          RejectionBanner(rejection: _rejection),
          const SizedBox(height: T.sSm),
          // 78:638 — once the answer is accepted the bar itself turns green
          // and carries the name and the +1 SERİ pill.
          if (_won != null)
            ConfirmedSearchBar(name: _won!.displayName)
          else
            PracticeSearchBar(typed: _typed, onClear: _onClear),
          // The design leaves 20pt under the search bar on a 932pt frame.
          // Trimmed here because that frame has ~50pt more vertical room than
          // the devices this runs on, and the difference comes straight out
          // of the suggestion panel.
          const SizedBox(height: T.sLg),
        ],
      ),
    );
  }
}

enum _Reveal { confirm, answers }
