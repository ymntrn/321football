import 'dart:async';

import 'package:flutter/material.dart';

import '../models/models.dart';
import '../theme/tokens.dart';
import 'career_line.dart';
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
    this.hintEnabled = true,
  });

  /// What revealing the answer costs, in coins. This is a PRICE TAG and is
  /// fixed — it does not count down. Buying an answer debits the player's
  /// coin balance on the profile (spend_coins, 007_results.sql).
  static const answerCost = 3;

  final int cost;
  final VoidCallback onBack;
  final VoidCallback onHint;

  /// False when the balance is under [cost] (or unknown, offline): the chip
  /// dims to 45% — the opacity the frames use for a disabled control — and
  /// stops responding.
  final bool hintEnabled;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
      child: Row(
        children: [
          UndoButton(onTap: onBack),
          const Spacer(),
          GestureDetector(
            onTap: hintEnabled ? onHint : null,
            behavior: HitTestBehavior.opaque,
            child: Opacity(
              opacity: hintEnabled ? 1 : 0.45,
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

// ===========================================================================
// Practice popups: Doğru Cevap (78:610), Cevap Onayı (82:338),
// Cevabı Göster (78:483)
// ===========================================================================

/// `Karartma` — the scrim the three practice popups sit on: rgba(3,3,20) at
/// 60% under Doğru, 72% under the two answer popups. Swallows taps so the
/// keyboard underneath cannot be typed on; [onTap] lets the caller dismiss.
class PopupScrim extends StatelessWidget {
  const PopupScrim({super.key, required this.opacity, this.onTap});

  final double opacity;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: ColoredBox(color: Color.fromRGBO(3, 3, 20, opacity)),
    );
  }
}

/// `Doğru Popup` (84:349) — the correct-answer card, on its scrim, over the
/// board. Holds 2.5 s (the prototype's timeout) with the `SIRADAKİ EŞLEŞME`
/// bar running down, then [onDone]; a tap anywhere skips the wait.
///
/// The streak lives in the search bar's `+1 SERİ` pill underneath
/// (ConfirmedSearchBar), not on this card.
class CorrectAnswerOverlay extends StatefulWidget {
  const CorrectAnswerOverlay({
    super.key,
    required this.player,
    required this.clubs,
    required this.onDone,
  });

  final Player player;

  /// The pair, for the career line.
  final Map<int, String> clubs;
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
    if (!(_timer?.isActive ?? false)) return;
    _timer?.cancel();
    widget.onDone();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: _advanceNow,
      behavior: HitTestBehavior.opaque,
      child: Stack(
        children: [
          const Positioned.fill(child: PopupScrim(opacity: 0.6)),
          Align(
            alignment: const Alignment(0, -0.3),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: T.s2xl),
              child: Container(
                width: 344,
                padding: const EdgeInsets.fromLTRB(20, 26, 20, 20),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Color(0xFF218C1C), Color(0xFF0B210D)],
                  ),
                  borderRadius: BorderRadius.circular(T.r2xl),
                  border: Border.all(
                    color: T.yesil.withValues(alpha: 0.9),
                    width: 2.5,
                  ),
                  boxShadow: [
                    const BoxShadow(color: Color(0x664DFF45), blurRadius: 34),
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.55),
                      offset: const Offset(0, 16),
                      blurRadius: 40,
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'DOĞRU!',
                      style: TextStyle(
                        fontFamily: T.fontUi,
                        fontSize: T.t40,
                        color: T.yesil,
                      ),
                    ),
                    const SizedBox(height: T.sMd),
                    Text(
                      widget.player.displayName,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontFamily: T.fontUi,
                        fontSize: T.t24,
                        color: T.beyaz100,
                      ),
                    ),
                    const SizedBox(height: T.sMd),
                    CareerLine(
                      playerName: widget.player.displayName,
                      clubs: widget.clubs,
                      style: const TextStyle(
                        fontFamily: T.fontUi,
                        fontSize: T.t13,
                        color: T.beyaz065,
                      ),
                    ),
                    const SizedBox(height: T.sMd),
                    const Divider(height: 1, thickness: 1, color: T.beyaz016),
                    const SizedBox(height: T.sMd),
                    const Text(
                      'SIRADAKİ EŞLEŞME',
                      style: TextStyle(
                        fontFamily: T.fontUi,
                        fontSize: T.t13,
                        color: T.beyaz065,
                        letterSpacing: 1.04,
                      ),
                    ),
                    const SizedBox(height: T.sMd),
                    AnimatedBuilder(
                      animation: _bar,
                      builder: (_, __) => ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: _bar.value,
                          minHeight: 8,
                          backgroundColor: T.beyaz016,
                          valueColor: const AlwaysStoppedAnimation(T.yesil),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The blue card both answer popups share (82:466 / 80:339): #1C26B8 to
/// #0B0E57 top to bottom, a 2pt beyaz/038 border at radius/2xl, a deep soft
/// drop, and the `Ampul Rozeti` lightbulb badge sitting on its top edge.
class _BulbPopup extends StatelessWidget {
  const _BulbPopup({
    required this.width,
    required this.padding,
    required this.gap,
    required this.children,
  });

  final double width;
  final EdgeInsets padding;
  final double gap;
  final List<Widget> children;

  static const _badge = 74.0;

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      alignment: Alignment.topCenter,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: _badge / 2),
          child: Container(
            width: width,
            padding: padding,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0xFF1C26B8), Color(0xFF0B0E57)],
              ),
              borderRadius: BorderRadius.circular(T.r2xl),
              border: Border.all(color: T.beyaz038, width: 2),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.55),
                  offset: const Offset(0, 16),
                  blurRadius: 40,
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (var i = 0; i < children.length; i++) ...[
                  if (i > 0) SizedBox(height: gap),
                  children[i],
                ],
              ],
            ),
          ),
        ),
        const _BulbBadge(size: _badge),
      ],
    );
  }
}

/// `Ampul Rozeti` (82:478) with the lightbulb (82:479) inside.
///
/// The badge's export is an SVG whose glow is a blur filter, which
/// flutter_svg does not draw — so the disc and its glow are painted, in the
/// popup's own blue with the same 2pt beyaz/038 ring. The lightbulb is the
/// already-exported assets/img/lightbulb.png.
class _BulbBadge extends StatelessWidget {
  const _BulbBadge({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF2632D0), Color(0xFF1C26B8)],
        ),
        border: Border.all(color: T.beyaz038, width: 2),
        boxShadow: [
          BoxShadow(color: T.altin.withValues(alpha: 0.35), blurRadius: 24),
        ],
      ),
      alignment: Alignment.center,
      child: Image.asset(
        'assets/img/lightbulb.png',
        width: 40,
        height: 41,
        fit: BoxFit.contain,
      ),
    );
  }
}

/// `Onay Popup` (82:466) — "CEVABI GÖSTER?" with VAZGEÇ and the price
/// button.
///
/// With the `Bakiyen 120` balance chip (82:469) between the copy and the
/// buttons, now that there is a real balance (007_results.sql).
class RevealConfirmPopup extends StatelessWidget {
  const RevealConfirmPopup({
    super.key,
    required this.cost,
    required this.onCancel,
    required this.onConfirm,
    this.balance,
    this.error,
  });

  final int cost;
  final VoidCallback onCancel;
  final VoidCallback? onConfirm;

  /// The player's coins; null hides the chip.
  final int? balance;

  /// Why spending failed, if it did.
  final String? error;

  @override
  Widget build(BuildContext context) {
    return _BulbPopup(
      width: 340,
      padding: const EdgeInsets.fromLTRB(20, 34, 20, 20),
      gap: T.sXl,
      children: [
        const Text(
          'CEVABI GÖSTER?',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontFamily: T.fontUi,
            fontSize: T.t24,
            color: T.beyaz100,
          ),
        ),
        Text(
          'Olası cevapları görmek $cost altına mal olur. '
          'Seri sayacın sıfırlanmaz.',
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontFamily: T.fontUi,
            fontSize: T.t13,
            height: 20 / 13,
            color: T.beyaz065,
          ),
        ),
        if (balance != null) _BalanceChip(balance: balance!),
        if (error != null)
          Text(
            error!,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontFamily: T.fontUi,
              fontSize: T.t13,
              color: T.kirmizi,
            ),
          ),
        Row(
          children: [
            Expanded(
              child: _PopupButton(
                label: 'VAZGEÇ',
                onTap: onCancel,
                color: T.beyaz012,
                border: T.beyaz030,
                shadow: const Color(0xFF05082E),
                shadowOffset: 4,
              ),
            ),
            const SizedBox(width: T.sMd),
            Expanded(
              child: _PopupButton(
                label: '$cost ALTIN HARCA',
                onTap: onConfirm,
                gradient: const RadialGradient(
                  radius: 0.5,
                  transform: T.wideRadial,
                  colors: [
                    Color(0xFFFFB82B),
                    Color(0xFFF29A1C),
                    Color(0xFFE57D0D),
                  ],
                  stops: [0, 0.5, 1],
                ),
                border: T.beyaz038,
                shadow: const Color(0xFF8C4705),
                shadowOffset: 5,
                highlight: true,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// `Bakiye` (82:469): beyaz/012, beyaz/022 border, radius/lg —
/// "Bakiyen", a 20pt coin, the balance.
class _BalanceChip extends StatelessWidget {
  const _BalanceChip({required this.balance});

  final int balance;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: T.beyaz012,
        borderRadius: BorderRadius.circular(T.rLg),
        border: Border.all(color: T.beyaz022),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'Bakiyen',
            style: TextStyle(
              fontFamily: T.fontUi,
              fontSize: T.t13,
              color: T.beyaz050,
            ),
          ),
          const SizedBox(width: T.sXs),
          Image.asset('assets/img/coin.png', width: 20, height: 20),
          const SizedBox(width: T.sXs),
          Text(
            '$balance',
            style: const TextStyle(
              fontFamily: T.fontUi,
              fontSize: T.t17,
              color: T.beyaz100,
            ),
          ),
        ],
      ),
    );
  }
}

/// `Cevap Popup` (80:339) — OLASI CEVAPLAR: every mutual player, numbered,
/// each with its career line, then the spend note and DEVAM.
///
/// The frame shows four rows. A pair can have dozens of answers, so the
/// list scrolls inside the card once it runs out of screen.
class RevealAnswersPopup extends StatelessWidget {
  const RevealAnswersPopup({
    super.key,
    required this.players,
    required this.clubs,
    required this.cost,
    required this.onContinue,
  });

  final List<Player> players;
  final Map<int, String> clubs;
  final int cost;
  final VoidCallback onContinue;

  @override
  Widget build(BuildContext context) {
    final maxList = MediaQuery.sizeOf(context).height * 0.42;
    return _BulbPopup(
      width: 376,
      padding: const EdgeInsets.fromLTRB(18, 30, 18, 22),
      gap: T.sXl,
      children: [
        const Text(
          'OLASI CEVAPLAR',
          style: TextStyle(
            fontFamily: T.fontUi,
            fontSize: T.t24,
            color: T.beyaz100,
          ),
        ),
        const Text(
          'İki takımda da forma giyen futbolcular',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontFamily: T.fontUi,
            fontSize: T.t13,
            color: T.beyaz050,
          ),
        ),
        ConstrainedBox(
          constraints: BoxConstraints(maxHeight: maxList),
          child: ListView.separated(
            shrinkWrap: true,
            padding: EdgeInsets.zero,
            itemCount: players.length,
            separatorBuilder: (_, __) => const SizedBox(height: T.sSm),
            itemBuilder: (_, i) =>
                _AnswerRow(index: i + 1, player: players[i], clubs: clubs),
          ),
        ),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '-$cost',
              style: const TextStyle(
                fontFamily: T.fontUi,
                fontSize: T.t15,
                color: T.beyaz080,
              ),
            ),
            const SizedBox(width: T.sXs),
            Image.asset('assets/img/coin.png', width: 20, height: 20),
            const SizedBox(width: T.sXs),
            const Text(
              'altın harcandı',
              style: TextStyle(
                fontFamily: T.fontUi,
                fontSize: T.t13,
                color: T.beyaz050,
              ),
            ),
          ],
        ),
        SizedBox(
          width: double.infinity,
          child: _PopupButton(
            label: 'DEVAM',
            onTap: onContinue,
            gradient: T.yesilGradient,
            border: T.beyaz038,
            shadow: T.golgeGonder,
            shadowOffset: 5,
            highlight: true,
            fontSize: T.t22,
            verticalPadding: 14,
          ),
        ),
      ],
    );
  }
}

/// `Cevap/<name>` (80:343) — beyaz/012 row, the green 30pt rank disc, name at
/// type/17 over its career line at type/11.
class _AnswerRow extends StatelessWidget {
  const _AnswerRow({
    required this.index,
    required this.player,
    required this.clubs,
  });

  final int index;
  final Player player;
  final Map<int, String> clubs;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 9, 12, 9),
      decoration: BoxDecoration(
        color: T.beyaz012,
        borderRadius: BorderRadius.circular(T.rMd),
        border: Border.all(color: T.beyaz016),
      ),
      child: Row(
        children: [
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: T.yesil.withValues(alpha: 0.85),
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: Text(
              '$index',
              style: const TextStyle(
                fontFamily: T.fontUi,
                fontSize: T.t13,
                color: T.yesilMurekkep,
              ),
            ),
          ),
          const SizedBox(width: T.sLg),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  player.displayName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontFamily: T.fontUi,
                    fontSize: T.t17,
                    color: T.beyaz100,
                  ),
                ),
                const SizedBox(height: T.sHairline),
                CareerLine(
                  playerName: player.displayName,
                  clubs: clubs,
                  textAlign: TextAlign.left,
                  maxLines: 1,
                  style: const TextStyle(
                    fontFamily: T.fontUi,
                    fontSize: T.t11,
                    color: T.beyaz050,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The popups' buttons: a fill (flat or radial), a 1.5pt border at
/// radius/lg, a HARD drop shadow (zero blur), and optionally the white
/// inset highlight along the top that the green and orange buttons carry.
class _PopupButton extends StatelessWidget {
  const _PopupButton({
    required this.label,
    required this.onTap,
    required this.border,
    required this.shadow,
    required this.shadowOffset,
    this.color,
    this.gradient,
    this.highlight = false,
    this.fontSize = T.t17,
    this.verticalPadding = 13,
  });

  final String label;
  final VoidCallback? onTap;
  final Color? color;
  final Gradient? gradient;
  final Color border;
  final Color shadow;
  final double shadowOffset;
  final bool highlight;
  final double fontSize;
  final double verticalPadding;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        decoration: BoxDecoration(
          color: color,
          gradient: gradient,
          borderRadius: BorderRadius.circular(T.rLg),
          border: Border.all(color: border, width: 1.5),
          boxShadow: [
            BoxShadow(
              color: shadow,
              offset: Offset(0, shadowOffset),
              blurRadius: 0,
            ),
          ],
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            if (highlight)
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(T.rLg),
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.white.withValues(alpha: 0.35),
                        Colors.transparent,
                      ],
                      stops: const [0, 0.18],
                    ),
                  ),
                ),
              ),
            Padding(
              padding: EdgeInsets.symmetric(
                vertical: verticalPadding,
                horizontal: T.sSm,
              ),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  label,
                  maxLines: 1,
                  style: TextStyle(
                    fontFamily: T.fontUi,
                    fontSize: fontSize,
                    color: T.beyaz100,
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
