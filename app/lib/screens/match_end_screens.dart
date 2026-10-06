import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../data/app_database.dart';
import '../data/game_queries.dart';
import '../models/models.dart';
import '../theme/tokens.dart';
import '../widgets/app_chrome.dart';
import '../widgets/career_line.dart';
import '../widgets/lobby_chrome.dart';
import '../widgets/match_chrome.dart';
import '../widgets/screen_background.dart';

// ===========================================================================
// Round end: GOOOL (41:685) and Tur Bitti (109:8)
// ===========================================================================

/// The common shape of both round-end frames: the match screen's score strip
/// under a 78% black scrim, the round's verdict on top, and the
/// `SIRADAKİ TUR` progress bar near the foot.
class _RoundEndScaffold extends StatelessWidget {
  const _RoundEndScaffold({
    required this.playerName,
    required this.opponentName,
    required this.playerScore,
    required this.opponentScore,
    required this.since,
    required this.hold,
    required this.child,
  });

  final String playerName;
  final String opponentName;
  final int playerScore;
  final int opponentScore;
  final DateTime since;
  final Duration hold;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: ScreenBackground(
        child: Stack(
          children: [
            SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, T.sLg, 24, 0),
                child: MatchScoreStrip(
                  playerName: playerName,
                  opponentName: opponentName,
                  playerScore: playerScore,
                  opponentScore: opponentScore,
                ),
              ),
            ),
            // 41:781 — black at 78%, over everything including the strip.
            Positioned.fill(
              child: ColoredBox(color: Colors.black.withValues(alpha: 0.78)),
            ),
            SafeArea(
              child: Column(
                children: [
                  const SizedBox(height: T.sLg + MatchScoreStrip.height),
                  // Scrolls only on a phone too short for the frame; on
                  // anything near 932pt it sits still.
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: child,
                    ),
                  ),
                  const SizedBox(height: T.sLg),
                  const _Caption('SIRADAKİ TUR'),
                  const SizedBox(height: 16),
                  _NextRoundBar(since: since, hold: hold),
                  const SizedBox(height: 60),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// `İlerleme` (108:199) — 300x8, beyaz/016 track, green fill, filling over
/// the time the round end stays on screen. Anchored to [since] so a rebuild
/// mid-way does not restart it.
class _NextRoundBar extends StatefulWidget {
  const _NextRoundBar({required this.since, required this.hold});

  final DateTime since;
  final Duration hold;

  @override
  State<_NextRoundBar> createState() => _NextRoundBarState();
}

class _NextRoundBarState extends State<_NextRoundBar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: widget.hold,
  );

  @override
  void initState() {
    super.initState();
    final done =
        DateTime.now().difference(widget.since).inMilliseconds /
        widget.hold.inMilliseconds;
    _c.value = done.clamp(0.0, 1.0);
    _c.forward();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 300,
      height: 8,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: AnimatedBuilder(
          animation: _c,
          builder: (_, __) => Stack(
            children: [
              const Positioned.fill(child: ColoredBox(color: T.beyaz016)),
              FractionallySizedBox(
                widthFactor: _c.value,
                heightFactor: 1,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: T.yesil,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// `Maç - Tur Sonu (GOOOL)` (Figma 41:685).
///
/// Shown to BOTH players whoever scored — the frame names the scorer
/// ("Oyuncuadı1 buldu"), so the same screen reads correctly from either
/// side. The career line under the name comes from the scorer's spells at
/// the round's two clubs.
class MatchGoalScreen extends StatelessWidget {
  const MatchGoalScreen({
    super.key,
    required this.playerName,
    required this.opponentName,
    required this.playerScore,
    required this.opponentScore,
    required this.scorerName,
    required this.scorerIsMe,
    required this.answer,
    required this.elapsedMs,
    required this.clubs,
    required this.since,
    required this.hold,
  });

  final String playerName;
  final String opponentName;
  final int playerScore;
  final int opponentScore;

  final String scorerName;
  final bool scorerIsMe;

  /// The matched footballer's display name, as written to the room.
  final String? answer;
  final int? elapsedMs;

  /// The round's two clubs by id, for the career line.
  final Map<int, String> clubs;

  final DateTime since;
  final Duration hold;

  static const _fillTop = Color(0xFFFF840A);
  static const _fillBottom = Color(0xFFEA3235);

  @override
  Widget build(BuildContext context) {
    return _RoundEndScaffold(
      playerName: playerName,
      opponentName: opponentName,
      playerScore: playerScore,
      opponentScore: opponentScore,
      since: since,
      hold: hold,
      child: Column(
        children: [
          const SizedBox(height: 50),
          // 41:783 — 96pt with 11.52 tracking is ~370pt wide; scaled down
          // rather than clipped on a narrow phone.
          const FittedBox(
            fit: BoxFit.scaleDown,
            child: OutlinedGradientText(
              'GOOOL',
              fontSize: T.t96,
              letterSpacing: 11.52,
              colors: [_fillTop, _fillBottom],
            ),
          ),
          const SizedBox(height: 30),
          _ScorerRing(name: scorerName, mine: scorerIsMe),
          const SizedBox(height: 20),
          Text(
            '$scorerName buldu',
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            // M PLUS 1p Medium in the design — not bundled.
            style: const TextStyle(
              fontFamily: T.fontUi,
              fontSize: T.t19,
              color: T.beyaz065,
            ),
          ),
          const SizedBox(height: T.sSm),
          if (answer != null)
            Text(
              answer!,
              textAlign: TextAlign.center,
              maxLines: 2,
              style: const TextStyle(
                fontFamily: T.fontUi,
                fontSize: T.t40,
                color: T.beyaz100,
                height: 1.1,
              ),
            ),
          const SizedBox(height: T.sLg),
          // 108:193. Height reserved so the pill below does not jump when
          // the line arrives.
          if (answer != null)
            SizedBox(
              height: 34,
              child: CareerLine(
                playerName: answer!,
                clubs: clubs,
                style: const TextStyle(
                  fontFamily: T.fontUi,
                  fontSize: T.t13,
                  color: T.beyaz050,
                ),
              ),
            ),
          if (elapsedMs != null) ...[
            const SizedBox(height: 30),
            _AnswerTimePill(elapsedMs: elapsedMs!),
          ],
        ],
      ),
    );
  }
}

/// `Skorer Halkası` (108:190) — the scorer's 96pt avatar in a green ring
/// with a soft green glow, initials at type/34.
///
/// PAINTED, not the exported SVG: the export's glow is an SVG blur filter,
/// which flutter_svg does not render (the same reason ScreenBackground
/// paints Ellipse 5).
class _ScorerRing extends StatelessWidget {
  const _ScorerRing({required this.name, required this.mine});

  final String name;
  final bool mine;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 96,
      height: 96,
      decoration: BoxDecoration(
        color: T.zeminAvatar,
        shape: BoxShape.circle,
        border: Border.all(color: T.yesil, width: 3),
        boxShadow: [
          BoxShadow(color: T.yesil.withValues(alpha: 0.45), blurRadius: 18),
        ],
      ),
      alignment: Alignment.center,
      padding: const EdgeInsets.all(T.sSm),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Text(
          playerInitials(name),
          style: const TextStyle(
            fontFamily: T.fontUi,
            fontSize: T.t34,
            color: T.beyaz100,
          ),
        ),
      ),
    );
  }
}

/// `Cevap Süresi` (108:194) — ⚡ 1,4 sn cevap süresi.
class _AnswerTimePill extends StatelessWidget {
  const _AnswerTimePill({required this.elapsedMs});

  final int elapsedMs;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
      decoration: BoxDecoration(
        color: T.beyaz012,
        borderRadius: BorderRadius.circular(T.rLg),
        border: Border.all(color: T.beyaz022),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('⚡', style: TextStyle(fontSize: T.t15)),
          const SizedBox(width: T.sSm),
          Text(
            formatSeconds(elapsedMs),
            style: const TextStyle(
              fontFamily: T.fontUi,
              fontSize: T.t17,
              color: Color(0xFFFF9C1A),
            ),
          ),
          const SizedBox(width: T.sSm),
          const Text(
            'cevap süresi',
            style: TextStyle(
              fontFamily: T.fontUi,
              fontSize: T.t13,
              color: T.beyaz050,
            ),
          ),
        ],
      ),
    );
  }
}

/// "1,4 sn" — Turkish decimal comma, one place.
String formatSeconds(int ms) =>
    '${(ms / 1000).toStringAsFixed(1).replaceAll('.', ',')} sn';

/// `Maç - Tur Bitti (Beraberlik)` (Figma 109:8) — a round nobody won.
///
/// The frame covers the ten seconds running out: no goal, and the three
/// most famous correct answers. It is ALSO used for an unplayable pair (the
/// two clubs share no player, so the round is voided and both re-pick);
/// there the subtitle changes and the answer panel, which would be empty,
/// is left out.
class MatchRoundVoidScreen extends StatefulWidget {
  const MatchRoundVoidScreen({
    super.key,
    required this.playerName,
    required this.opponentName,
    required this.playerScore,
    required this.opponentScore,
    required this.unplayable,
    required this.clubAId,
    required this.clubBId,
    required this.since,
    required this.hold,
  });

  final String playerName;
  final String opponentName;
  final int playerScore;
  final int opponentScore;
  final bool unplayable;
  final int? clubAId;
  final int? clubBId;
  final DateTime since;
  final Duration hold;

  @override
  State<MatchRoundVoidScreen> createState() => _MatchRoundVoidScreenState();
}

class _MatchRoundVoidScreenState extends State<MatchRoundVoidScreen> {
  late final Future<List<Player>> _answers = _load();

  Future<List<Player>> _load() async {
    final a = widget.clubAId;
    final b = widget.clubBId;
    if (widget.unplayable || a == null || b == null) return const [];
    try {
      final all = await GameQueries(AppDatabase.instance.db)
          .getMutualPlayers(a, b);
      return all.take(3).toList();
    } catch (e) {
      debugPrint('answer list failed: $e');
      return const [];
    }
  }

  @override
  Widget build(BuildContext context) {
    return _RoundEndScaffold(
      playerName: widget.playerName,
      opponentName: widget.opponentName,
      playerScore: widget.playerScore,
      opponentScore: widget.opponentScore,
      since: widget.since,
      hold: widget.hold,
      child: Column(
        children: [
          const SizedBox(height: 50),
          const FittedBox(
            fit: BoxFit.scaleDown,
            child: OutlinedGradientText(
              'TUR BİTTİ',
              fontSize: 62,
              letterSpacing: 7.44,
              colors: [T.kirmizi, T.kirmizi],
            ),
          ),
          const SizedBox(height: T.s2xl),
          Text(
            widget.unplayable
                ? 'Bu iki takımın ortak oyuncusu yok'
                : 'Kimse doğru futbolcuyu bulamadı',
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontFamily: T.fontUi,
              fontSize: T.t19,
              color: T.beyaz065,
            ),
          ),
          const SizedBox(height: T.s2xl),
          const Text(
            'Puan yok',
            style: TextStyle(
              fontFamily: T.fontUi,
              fontSize: T.t34,
              color: T.beyaz080,
            ),
          ),
          if (widget.unplayable) ...[
            const SizedBox(height: T.sLg),
            const Text(
              'Takımlar yeniden seçilecek',
              style: TextStyle(
                fontFamily: T.fontUi,
                fontSize: T.t15,
                color: T.beyaz050,
              ),
            ),
          ] else ...[
            const SizedBox(height: 30),
            FutureBuilder<List<Player>>(
              future: _answers,
              builder: (context, snap) {
                final players = snap.data ?? const <Player>[];
                if (players.isEmpty) return const SizedBox(height: 0);
                return _AnswerPanel(players: players);
              },
            ),
          ],
        ],
      ),
    );
  }
}

/// `Doğru Cevaplar` (109:40) — 340 wide, the three answers as quiet rows.
class _AnswerPanel extends StatelessWidget {
  const _AnswerPanel({required this.players});

  final List<Player> players;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 340,
      padding: const EdgeInsets.all(T.sXl),
      decoration: BoxDecoration(
        color: T.beyaz006,
        borderRadius: BorderRadius.circular(T.rXl),
        border: Border.all(color: T.beyaz016, width: 1.5),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const _Caption('DOĞRU CEVAPLAR ŞUNLARDI'),
          for (final p in players) ...[
            const SizedBox(height: T.sSm),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(
                horizontal: T.sLg,
                vertical: T.sSm,
              ),
              decoration: BoxDecoration(
                color: T.beyaz006,
                borderRadius: BorderRadius.circular(T.rMd),
                border: Border.all(color: T.beyaz012),
              ),
              child: Text(
                p.displayName,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontFamily: T.fontUi,
                  fontSize: T.t17,
                  color: T.beyaz080,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// The small spaced-out caps label (`SIRADAKİ TUR`, `MAÇ ÖZETİ`, …).
class _Caption extends StatelessWidget {
  const _Caption(this.text, {this.color = T.beyaz050});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      textAlign: TextAlign.center,
      style: TextStyle(
        fontFamily: T.fontUi,
        fontSize: T.t13,
        color: color,
        letterSpacing: 1.04,
      ),
    );
  }
}

// ===========================================================================
// Match end: Kazanma (46:352) and Kaybetme (48:534)
// ===========================================================================

/// What this device saw of the match, for `MAÇ ÖZETİ`.
///
/// Kept locally by the match loop, because the room row is reset every
/// round — so a player who reconnected mid-match sees only the rounds since.
class MatchSummary {
  const MatchSummary({
    required this.fastestMs,
    required this.correct,
    required this.rounds,
    required this.bestStreak,
  });

  /// This player's quickest correct answer, if any.
  final int? fastestMs;

  /// Rounds this player answered correctly, out of [rounds] played (voided
  /// rounds are not counted — nobody could answer them).
  final int correct;
  final int rounds;

  /// Longest run of consecutive rounds this player won.
  final int bestStreak;

  static const empty = MatchSummary(
    fastestMs: null,
    correct: 0,
    rounds: 0,
    bestStreak: 0,
  );
}

/// `Maç - Maç Sonu Kazanma` (46:352) / `Kaybetme` (48:534).
///
/// One widget for both — the frames are the same layout with the title,
/// its colours and the crowned avatar swapped.
///
/// The trophy and coin row (48:533) appears for RANKED rooms only, with the
/// amounts record_match_result actually applied (+30 / -20 trophies,
/// +10 / +2 coins — the frame's +20 coins predates the decided economy). A
/// Friend Match awards neither, so it has no row.
///
/// Left out on purpose: the `2X Altın` button (ads, out of scope). With it
/// gone, `Tekrar Oyna` takes the full-width 341x90 form the Kaybetme frame
/// already uses, on both screens. In a ranked match it queues again.
class MatchResultScreen extends StatelessWidget {
  const MatchResultScreen({
    super.key,
    required this.won,
    required this.playerName,
    required this.opponentName,
    required this.playerScore,
    required this.opponentScore,
    required this.summary,
    required this.onHome,
    this.note,
    this.onRematch,
    this.ranked = false,
    this.trophyDelta,
    this.coinDelta,
  });

  /// A Hemen Oyna match: show the economy row.
  final bool ranked;

  /// What this player gained or lost; null until the result is recorded.
  final int? trophyDelta;
  final int? coinDelta;

  final bool won;
  final String playerName;
  final String opponentName;
  final int playerScore;
  final int opponentScore;
  final MatchSummary summary;

  /// Why the match ended, when it was not on goals: "Rakip ayrıldı",
  /// "Bağlantın koptu", "Maç yarıda kaldı".
  final String? note;

  /// Null hides `Tekrar Oyna` (an abandoned room cannot be replayed).
  final VoidCallback? onRematch;
  final VoidCallback onHome;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: ScreenBackground(
        child: SafeArea(
          child: LayoutBuilder(
            builder: (context, box) {
              // The frame is 932 pt tall. On a real phone (~860 pt under the
              // status bar) the ranked trophy/coin row pushed Ana Sayfa off
              // the bottom, so the fixed gaps shrink when height is short.
              final tight = box.maxHeight < 900;
              double gap(double full) => tight ? full * 0.55 : full;
              return SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: box.maxHeight),
                child: IntrinsicHeight(
                  child: Column(
                    children: [
                      const SizedBox(height: T.sSm),
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        child: won
                            ? const OutlinedGradientText(
                                'Kazandın',
                                fontSize: 64,
                                colors: [T.yesil, T.yesilKoyu],
                              )
                            : const OutlinedGradientText(
                                'Kaybettin',
                                fontSize: 64,
                                colors: [Color(0xFFFF840A), Color(0xFFEA3235)],
                                stops: [0, 0.40865],
                              ),
                      ),
                      SizedBox(height: gap(30)),
                      _Sides(
                        playerName: playerName,
                        opponentName: opponentName,
                        playerScore: playerScore,
                        opponentScore: opponentScore,
                        won: won,
                      ),
                      SizedBox(height: gap(37)),
                      const _Caption('MAÇ ÖZETİ', color: T.beyaz038),
                      const SizedBox(height: 11),
                      _SummaryRow(summary: summary),
                      if (ranked) ...[
                        SizedBox(height: gap(26)),
                        _EconomyRow(trophies: trophyDelta, coins: coinDelta),
                      ],
                      const Spacer(),
                      if (note != null)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: T.s2xl),
                          child: Text(
                            note!,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontFamily: T.fontUi,
                              fontSize: T.t19,
                              color: T.beyaz065,
                            ),
                          ),
                        )
                      else
                        SizedBox(height: gap(40)),
                      // A rematch keeps the same room and the same code, so
                      // nobody has to share a new one to play again.
                      if (onRematch != null)
                        SizedBox(
                          width: 341,
                          child: LobbyButton(
                            label: 'Tekrar Oyna',
                            tone: LobbyButtonTone.mor,
                            onTap: onRematch,
                          ),
                        ),
                      SizedBox(height: gap(44)),
                      SizedBox(
                        width: 247,
                        child: LobbyButton(
                          label: 'Ana Sayfa',
                          tone: LobbyButtonTone.mor,
                          height: 62,
                          fontSize: T.t24,
                          onTap: onHome,
                        ),
                      ),
                      const SizedBox(height: T.s2xl),
                    ],
                  ),
                ),
              ),
            );
            },
          ),
        ),
      ),
    );
  }
}

/// `48:533`: `+30 🏆` in green (red when trophies were lost) and `+10 🪙`
/// in #F7FF00, type/34. Dashes until record_match_result has answered.
class _EconomyRow extends StatelessWidget {
  const _EconomyRow({required this.trophies, required this.coins});

  final int? trophies;
  final int? coins;

  static const _coinYellow = Color(0xFFF7FF00);

  static String _signed(int? n) =>
      n == null ? '…' : (n > 0 ? '+$n' : (n == 0 ? '0' : '$n'));

  @override
  Widget build(BuildContext context) {
    final t = trophies;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _signed(t),
              style: TextStyle(
                fontFamily: T.fontUi,
                fontSize: T.t34,
                color: t != null && t < 0 ? T.kirmizi : T.yesil,
              ),
            ),
            const SizedBox(width: T.sXs),
            const TrophyIcon(width: 37, height: 45),
          ],
        ),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _signed(coins),
              style: const TextStyle(
                fontFamily: T.fontUi,
                fontSize: T.t34,
                color: _coinYellow,
              ),
            ),
            const SizedBox(width: T.sXs),
            const CoinIcon(size: 38),
          ],
        ),
      ],
    );
  }
}

/// The two players side by side: Jaro score, name block, avatar. Column
/// centres sit 108pt either side of the middle, as in the frame.
class _Sides extends StatelessWidget {
  const _Sides({
    required this.playerName,
    required this.opponentName,
    required this.playerScore,
    required this.opponentScore,
    required this.won,
  });

  final String playerName;
  final String opponentName;
  final int playerScore;
  final int opponentScore;
  final bool won;

  @override
  Widget build(BuildContext context) {
    // Sized from the screen, not a LayoutBuilder: this sits inside the
    // result screen's IntrinsicHeight, which cannot measure through one.
    // 170 + 44 + 170 on the frame (inside 20pt gutters); narrower phones
    // give up the gap first.
    final available = MediaQuery.sizeOf(context).width - 40;
    final col = math.min(170.0, (available - 16) / 2);
    final gap = math.min(44.0, available - col * 2);
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: col,
          child: _Side(
            name: playerName,
            score: playerScore,
            fill: playerBlockFill,
            winner: won,
          ),
        ),
        SizedBox(width: gap),
        SizedBox(
          width: col,
          child: _Side(
            name: opponentName,
            score: opponentScore,
            fill: opponentBlockFill,
            winner: !won,
          ),
        ),
      ],
    );
  }
}

class _Side extends StatelessWidget {
  const _Side({
    required this.name,
    required this.score,
    required this.fill,
    required this.winner,
  });

  final String name;
  final int score;
  final Color fill;
  final bool winner;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          '$score',
          style: const TextStyle(
            fontFamily: T.fontNumeral,
            fontSize: T.t96,
            color: T.kirmizi,
            height: 1.2,
          ),
        ),
        const SizedBox(height: T.sXxs),
        SizedBox(
          width: 154,
          child: MatchNameBlock(name: name, fill: fill),
        ),
        const SizedBox(height: 9),
        _ResultAvatar(name: name, winner: winner),
      ],
    );
  }
}

/// `Avatar/avatar1` (114:21): 84pt, radius/xl, zemin/avatar. The winner's
/// wears a 3pt gold ring, a soft gold glow and the `Kazanan Rozeti` crown
/// badge hanging off its corner; the loser's a plain 1.5pt beyaz/030 ring.
class _ResultAvatar extends StatelessWidget {
  const _ResultAvatar({required this.name, required this.winner});

  final String name;
  final bool winner;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 84 + 3,
      height: 84 + 3,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            width: 84,
            height: 84,
            decoration: BoxDecoration(
              color: T.zeminAvatar,
              borderRadius: BorderRadius.circular(T.rXl),
              border: Border.all(
                color: winner ? T.altin : T.beyaz030,
                width: winner ? 3 : 1.5,
              ),
              boxShadow: winner
                  ? [
                      BoxShadow(
                        color: T.altin.withValues(alpha: 0.5),
                        blurRadius: 14,
                      ),
                    ]
                  : null,
            ),
            alignment: Alignment.center,
            padding: const EdgeInsets.all(T.sSm),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                playerInitials(name),
                style: const TextStyle(
                  fontFamily: T.fontUi,
                  fontSize: T.t24,
                  color: T.beyaz100,
                ),
              ),
            ),
          ),
          if (winner)
            Positioned(
              left: 55,
              top: 53,
              child: Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: T.altin,
                  shape: BoxShape.circle,
                  border: Border.all(color: T.zeminAna, width: 2.5),
                ),
                alignment: Alignment.center,
                child: const Text('👑', style: TextStyle(fontSize: T.t15)),
              ),
            ),
        ],
      ),
    );
  }
}

/// `Maç Özeti` (115:11) — three cards: fastest answer, correct out of
/// played, best streak.
class _SummaryRow extends StatelessWidget {
  const _SummaryRow({required this.summary});

  final MatchSummary summary;

  @override
  Widget build(BuildContext context) {
    final fastest = summary.fastestMs;
    return Row(
      children: [
        Expanded(
          child: _SummaryCard(
            icon: '⚡',
            value: fastest == null ? '—' : formatSeconds(fastest),
            label: 'en hızlı',
          ),
        ),
        const SizedBox(width: T.sMd),
        Expanded(
          child: _SummaryCard(
            icon: '🎯',
            value: '${summary.correct}/${summary.rounds}',
            label: 'doğru',
          ),
        ),
        const SizedBox(width: T.sMd),
        Expanded(
          child: _SummaryCard(
            icon: '🔥',
            value: '${summary.bestStreak}',
            label: 'seri',
          ),
        ),
      ],
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
    required this.icon,
    required this.value,
    required this.label,
  });

  final String icon;
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: T.sSm, vertical: T.sLg),
      decoration: BoxDecoration(
        color: T.beyaz006,
        borderRadius: BorderRadius.circular(T.rLg),
        border: Border.all(color: T.beyaz016),
      ),
      child: Column(
        children: [
          Text(icon, style: const TextStyle(fontSize: T.t17)),
          const SizedBox(height: T.sHairline),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              value,
              style: const TextStyle(
                fontFamily: T.fontUi,
                fontSize: T.t19,
                color: T.beyaz100,
              ),
            ),
          ),
          const SizedBox(height: T.sHairline),
          Text(
            label,
            style: const TextStyle(
              fontFamily: T.fontUi,
              fontSize: T.t11,
              color: T.beyaz038,
            ),
          ),
        ],
      ),
    );
  }
}
