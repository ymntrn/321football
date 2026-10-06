import 'dart:async';

import 'package:flutter/material.dart';

import '../models/models.dart';
import '../theme/tokens.dart';
import 'club_card.dart';
import 'screen_background.dart';

/// The top bar: Undo on the left, and the `Cevap` chip on the right holding
/// the lightbulb, the label, the coin and the PRICE
/// (Figma 50:450 — 152x44 at radius/lg over zemin/panel).
class PracticeTopBar extends StatelessWidget {
  const PracticeTopBar({
    super.key,
    this.cost = answerCost,
    required this.onBack,
    required this.onHint,
  });

  /// What revealing the answer costs, in coins. This is a PRICE TAG and is
  /// fixed — it does not count down. Buying an answer debits the player's coin
  /// balance, which lives on the profile and is not wired up yet.
  static const answerCost = 3;

  final int cost;
  final VoidCallback onBack;
  final VoidCallback onHint;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
      child: Row(
        children: [
          UndoButton(onTap: onBack),
          const Spacer(),
          GestureDetector(
            onTap: onHint,
            behavior: HitTestBehavior.opaque,
            child: Container(
              height: 44,
              padding: const EdgeInsets.symmetric(horizontal: 13),
              decoration: BoxDecoration(
                color: T.zeminPanel,
                borderRadius: BorderRadius.circular(T.rLg),
                border: Border.all(color: T.beyaz038),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Image.asset('assets/img/lightbulb.png',
                      width: 31, height: 32, fit: BoxFit.contain),
                  const SizedBox(width: T.sSm),
                  const Text(
                    'Cevap',
                    style: TextStyle(
                      fontFamily: T.fontUi,
                      fontSize: T.t17,
                      color: T.beyaz100,
                    ),
                  ),
                  const SizedBox(width: T.sMd),
                  Image.asset('assets/img/coin.png', width: 26, height: 26),
                  const SizedBox(width: T.sXxs),
                  Text(
                    '$cost',
                    style: const TextStyle(
                      fontSize: T.t17,
                      fontWeight: FontWeight.bold,
                      color: T.beyaz100,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// `Eşleşme` — the two club cards with the Jaro "VS" between them.
class MatchupRow extends StatelessWidget {
  const MatchupRow({super.key, required this.clubA, required this.clubB});

  final String clubA;
  final String clubB;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // Two 150pt cards plus a 20pt gap either side of VS on a 430pt frame.
        final cardWidth =
            ((constraints.maxWidth - 100) / 2).clamp(120.0, 150.0);
        return Row(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            ClubCard(name: clubA, width: cardWidth),
            const SizedBox(width: T.s2xl),
            const Text(
              'VS',
              style: TextStyle(
                fontFamily: T.fontNumeral,
                fontSize: T.t40,
                color: T.kirmizi,
              ),
            ),
            const SizedBox(width: T.s2xl),
            ClubCard(name: clubB, width: cardWidth),
          ],
        );
      },
    );
  }
}

/// `Durum Rozetleri` — the ZORLUK and SERİ chips.
class StatusBadges extends StatelessWidget {
  const StatusBadges({
    super.key,
    required this.difficulty,
    required this.streak,
  });

  final Difficulty difficulty;
  final int streak;

  Color get _tint => switch (difficulty) {
        Difficulty.easy => T.yesilKoyu,
        Difficulty.medium => T.turuncuKoyu,
        Difficulty.hard => T.kirmizi,
      };

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _Badge(
          label: 'ZORLUK: ${difficulty.label}',
          fill: _tint.withValues(alpha: 0.35),
          border: T.beyaz038,
        ),
        const SizedBox(width: T.sMd),
        _Badge(
          label: 'SERİ $streak',
          fill: T.zeminPanel.withValues(alpha: 0.85),
          border: T.beyaz030,
        ),
      ],
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({
    required this.label,
    required this.fill,
    required this.border,
  });

  final String label;
  final Color fill;
  final Color border;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.circular(T.rLg),
        border: Border.all(color: border, width: 1.2),
      ),
      child: Text(
        label,
        style: const TextStyle(
          fontFamily: T.fontUi,
          fontSize: T.t13,
          color: T.beyaz100,
        ),
      ),
    );
  }
}

/// `Buton/Pas Geç` — beyaz/012 fill, radius/xl, hard 4pt #040629 shadow.
class SkipButton extends StatelessWidget {
  const SkipButton({super.key, required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 13),
        decoration: BoxDecoration(
          color: T.beyaz012,
          borderRadius: BorderRadius.circular(T.rXl),
          border: Border.all(color: T.beyaz030, width: 1.5),
          boxShadow: const [
            BoxShadow(
              color: T.golgeCubuk,
              offset: Offset(0, 4),
              blurRadius: 0,
            ),
          ],
        ),
        child: const Text(
          'PAS GEÇ  ›',
          style: TextStyle(
            fontFamily: T.fontUi,
            fontSize: T.t17,
            color: T.beyaz080,
          ),
        ),
      ),
    );
  }
}

/// The one-line rejection message. Each reason gets its own copy — conflating
/// them makes players angry at the wrong thing.
class RejectionBanner extends StatelessWidget {
  const RejectionBanner({super.key, required this.rejection});

  final AnswerResult? rejection;

  @override
  Widget build(BuildContext context) {
    final r = rejection;
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 160),
      // Collapses to nothing when there is no rejection. Reserving a blank
      // 22pt line here cost the suggestion panel a whole row on a 914pt
      // viewport, and the panel is on screen far more often than an error is.
      child: r == null
          ? const SizedBox(width: double.infinity)
          : Container(
              key: ValueKey(r.reason),
              constraints: const BoxConstraints(minHeight: 22),
              alignment: Alignment.center,
              child: Text(
                r.reason == AnswerReason.notAMutualPlayer && r.player != null
                    ? '${r.player!.displayName} iki takımda da oynamadı'
                    : r.message,
                textAlign: TextAlign.center,
                // Two lines: some display names are long enough that one line
                // would clip the verdict itself.
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontFamily: T.fontUi,
                  fontSize: T.t13,
                  color: T.kirmizi,
                ),
              ),
            ),
    );
  }
}

/// The answer list behind the Cevap chip.
class AnswerSheet extends StatelessWidget {
  const AnswerSheet({super.key, required this.players});

  final List<Player> players;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(T.s2xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${players.length} ORTAK OYUNCU',
              style: const TextStyle(
                fontFamily: T.fontUi,
                fontSize: T.t19,
                color: T.altin,
              ),
            ),
            const SizedBox(height: T.sLg),
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: players.length,
                separatorBuilder: (_, __) =>
                    const Divider(height: 1, color: T.beyaz012),
                itemBuilder: (_, i) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: T.sMd),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          players[i].displayName,
                          style: const TextStyle(
                            fontFamily: T.fontUi,
                            fontSize: T.t17,
                            color: T.beyaz100,
                          ),
                        ),
                      ),
                      if (players[i].nationality != null)
                        Text(
                          players[i].nationality!,
                          style: const TextStyle(
                            fontSize: T.t11,
                            color: T.beyaz050,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Full-screen correct-answer celebration with the auto-advance bar the
/// prototype drives on a 2.5 s timeout.
class CorrectAnswerOverlay extends StatefulWidget {
  const CorrectAnswerOverlay({
    super.key,
    required this.player,
    required this.streak,
    required this.onDone,
  });

  final Player player;
  final int streak;
  final VoidCallback onDone;

  @override
  State<CorrectAnswerOverlay> createState() => _CorrectAnswerOverlayState();
}

class _CorrectAnswerOverlayState extends State<CorrectAnswerOverlay>
    with SingleTickerProviderStateMixin {
  static const _hold = Duration(milliseconds: 2500);

  late final AnimationController _bar = AnimationController(
    vsync: this,
    duration: _hold,
  )..forward();

  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer(_hold, widget.onDone);
  }

  @override
  void dispose() {
    _timer?.cancel();
    _bar.dispose();
    super.dispose();
  }

  void _advanceNow() {
    _timer?.cancel();
    widget.onDone();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: _advanceNow,
      child: Container(
        color: T.zeminDerin.withValues(alpha: 0.97),
        child: SafeArea(
          child: Column(
            children: [
              const Spacer(),
              const Text(
                'DOĞRU',
                style: TextStyle(
                  fontFamily: T.fontNumeral,
                  fontSize: T.t96,
                  color: T.yesil,
                  height: 1,
                ),
              ),
              const SizedBox(height: T.s2xl),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: T.s2xl),
                child: Text(
                  widget.player.displayName,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontFamily: T.fontUi,
                    fontSize: T.t24,
                    color: T.beyaz100,
                  ),
                ),
              ),
              const SizedBox(height: T.sMd),
              Text(
                'SERİ ${widget.streak}',
                style: const TextStyle(
                  fontFamily: T.fontUi,
                  fontSize: T.t15,
                  color: T.turuncu,
                ),
              ),
              const Spacer(),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: T.s2xl),
                child: AnimatedBuilder(
                  animation: _bar,
                  builder: (_, __) => ClipRRect(
                    borderRadius: BorderRadius.circular(T.sHairline),
                    child: LinearProgressIndicator(
                      value: 1 - _bar.value,
                      minHeight: 4,
                      backgroundColor: T.beyaz012,
                      valueColor: const AlwaysStoppedAnimation(T.yesil),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: T.s2xl),
            ],
          ),
        ),
      ),
    );
  }
}
