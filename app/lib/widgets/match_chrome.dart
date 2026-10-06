import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/models.dart';
import '../theme/tokens.dart';
import 'club_search_panel.dart';

/// `Skor Şeridi` — the scoreboard across the top of every PvP screen
/// (Figma 33:105 / 33:107 / 33:111).
///
/// Three stacked rectangles in the design, and the exported SVGs give the
/// exact values: a 379x43 `#D9D9D9` plate, a 154x43 `#FF840A` block for the
/// player and a 157x43 `#39C831` block for the opponent, each with a 1pt
/// black stroke. The grey showing through between them is the score field —
/// there are no separate digit tiles, the two Jaro numerals sit straight on
/// the plate.
///
/// The blocks are laid out proportionally rather than at fixed widths so the
/// strip survives a viewport narrower than the 430pt design frame.
class MatchScoreStrip extends StatelessWidget {
  const MatchScoreStrip({
    super.key,
    required this.playerName,
    required this.opponentName,
    required this.playerScore,
    required this.opponentScore,
  });

  final String playerName;
  final String opponentName;
  final int playerScore;
  final int opponentScore;

  static const height = 43.0;

  static const _plateFill = Color(0xFFD9D9D9);
  static const _playerFill = Color(0xFFFF840A);
  static const _opponentFill = Color(0xFF39C831);

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      child: Container(
        decoration: BoxDecoration(
          color: _plateFill,
          borderRadius: BorderRadius.circular(T.rSm),
        ),
        // The blocks run the full height of the plate, so without clipping
        // their corners would sit outside its curve at both ends.
        clipBehavior: Clip.antiAlias,
        child: Row(
          children: [
            const SizedBox(width: 4.5),
            Expanded(flex: 154, child: _block(playerName, _playerFill)),
            SizedBox(
              width: 58,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _digit(playerScore),
                  const SizedBox(width: T.sXxs),
                  _digit(opponentScore),
                ],
              ),
            ),
            Expanded(flex: 157, child: _block(opponentName, _opponentFill)),
            const SizedBox(width: 5.5),
          ],
        ),
      ),
    );
  }

  Widget _block(String name, Color fill) {
    return Container(
      height: height,
      decoration: BoxDecoration(
        color: fill,
        // Rounded to match the lobby's name strips and the rest of the
        // system. The exported SVGs for these two blocks are plain
        // square-cornered rects (`M153.5 0.5V42.5H0.5V0.5H153.5Z`), so this
        // is a deliberate departure from the frame, not a transcription of
        // it — worth knowing if the Figma file is ever the arbiter again.
        borderRadius: BorderRadius.circular(T.rSm),
        border: Border.all(color: Colors.black),
      ),
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(horizontal: T.sXs),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Text(
          name,
          maxLines: 1,
          style: const TextStyle(
            fontFamily: T.fontUi,
            fontSize: T.t20,
            color: T.beyaz100,
          ),
        ),
      ),
    );
  }

  /// Jaro at type/34, black on the plate. The glyphs are taller than the
  /// 43pt strip, so they are scaled down rather than clipped.
  Widget _digit(int value) {
    return FittedBox(
      fit: BoxFit.scaleDown,
      child: Text(
        '$value',
        style: const TextStyle(
          fontFamily: T.fontNumeral,
          fontSize: T.t34,
          color: Colors.black,
          height: 1,
        ),
      ),
    );
  }
}

/// The round clock: a single red Jaro numeral (Figma 33:103).
///
/// Both PvP clocks are drawn this way — 15 seconds to pick a club, 10 to find
/// the player. The numeral turns over on whole seconds, so the value passed
/// in should already be the ceiling of the remaining time.
class RoundTimer extends StatelessWidget {
  const RoundTimer({super.key, required this.seconds, this.urgent = false});

  final int seconds;

  /// The last few seconds pulse. Off by default so the pick phase stays calm.
  final bool urgent;

  @override
  Widget build(BuildContext context) {
    final text = Text(
      '$seconds',
      style: TextStyle(
        fontFamily: T.fontNumeral,
        fontSize: T.t96,
        height: 1.1,
        color: urgent ? T.kirmizi : T.kirmizi,
      ),
    );
    if (!urgent) return text;
    return _Pulse(child: text);
  }
}

class _Pulse extends StatefulWidget {
  const _Pulse({required this.child});

  final Widget child;

  @override
  State<_Pulse> createState() => _PulseState();
}

class _PulseState extends State<_Pulse> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 500),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ScaleTransition(
      scale: Tween(begin: 1.0, end: 1.12).animate(
        CurvedAnimation(parent: _c, curve: Curves.easeOut),
      ),
      child: widget.child,
    );
  }
}

/// `Takım Seçici` (Figma 85:420) — the 132pt dashed crest slot and its label.
///
/// Empty it shows a dashed ring around a `?` and reads "Takımını seç". Once a
/// club is picked the ring fills with that club's badge and the label becomes
/// the club name, so the same slot carries both states.
class TeamPickerSlot extends StatelessWidget {
  const TeamPickerSlot({
    super.key,
    required this.club,
    this.onTap,
    this.label,
  });

  final Club? club;
  final VoidCallback? onTap;

  /// Overrides the caption. Used for the opponent's slot ("Rakip seçiyor").
  final String? label;

  static const diameter = 132.0;

  @override
  Widget build(BuildContext context) {
    final chosen = club;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: diameter,
            height: diameter,
            child: chosen == null
                ? CustomPaint(
                    painter: _DashedRing(),
                    child: Container(
                      decoration: const BoxDecoration(
                        color: T.beyaz006,
                        shape: BoxShape.circle,
                      ),
                      alignment: Alignment.center,
                      child: const Text(
                        '?',
                        style: TextStyle(
                          fontFamily: T.fontUi,
                          fontSize: T.t40,
                          color: T.beyaz038,
                        ),
                      ),
                    ),
                  )
                : ClubBadge(club: chosen, size: diameter),
          ),
          const SizedBox(height: T.sXl),
          SizedBox(
            width: 260,
            child: Text(
              label ?? chosen?.name ?? 'Takımını seç',
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontFamily: T.fontUi,
                fontSize: T.t24,
                color: T.beyaz100,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The 2pt dashed ring around the empty crest slot. Flutter's Border has no
/// dash support, so it is stroked arc by arc.
class _DashedRing extends CustomPainter {
  static const _dash = 10.0;
  static const _gap = 8.0;

  @override
  void paint(Canvas canvas, Size size) {
    final radius = size.width / 2;
    final rect = Rect.fromCircle(
      center: Offset(radius, radius),
      radius: radius - 1,
    );
    final paint = Paint()
      ..color = T.beyaz030
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;

    final circumference = 2 * math.pi * (radius - 1);
    final step = _dash + _gap;
    // Round the dash count so the pattern closes cleanly instead of leaving a
    // ragged joint at twelve o'clock.
    final count = math.max(1, (circumference / step).round());
    final sweep = 2 * math.pi / count;
    final dashSweep = sweep * _dash / step;

    for (var i = 0; i < count; i++) {
      canvas.drawArc(rect, i * sweep, dashSweep, false, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _DashedRing oldDelegate) => false;
}

/// `Rakip Durumu` (Figma 85:424) — the pill that says what the opponent is
/// doing, with the three-dot indicator from `Nokta`.
class OpponentStatusChip extends StatelessWidget {
  const OpponentStatusChip({
    super.key,
    required this.name,
    required this.message,
    this.avatarColor = const Color(0xFF3DD136),
    this.showDots = true,
  });

  final String name;
  final String message;
  final Color avatarColor;
  final bool showDots;

  String get _initials {
    final clean = name.trim();
    if (clean.isEmpty) return '?';
    final digits = RegExp(r'\d').allMatches(clean).map((m) => m[0]).join();
    if (digits.isNotEmpty) return '${clean[0].toUpperCase()}$digits';
    return clean.substring(0, clean.length < 2 ? 1 : 2).toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, T.sSm, 18, T.sSm),
      decoration: BoxDecoration(
        color: T.beyaz006,
        borderRadius: BorderRadius.circular(T.rLg),
        border: Border.all(color: T.beyaz022),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: avatarColor,
              shape: BoxShape.circle,
              border: Border.all(color: T.beyaz038),
            ),
            alignment: Alignment.center,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                _initials,
                style: const TextStyle(
                  fontFamily: T.fontUi,
                  fontSize: T.t13,
                  color: T.beyaz100,
                ),
              ),
            ),
          ),
          const SizedBox(width: T.sMd),
          Flexible(
            child: Text(
              message,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              // The design sets this line in M PLUS 1p Medium, which is not
              // bundled — the app ships PoetsenOne and Jaro only. Using the
              // app's UI font keeps it consistent with every other label
              // rather than falling back to the system sans.
              style: const TextStyle(
                fontFamily: T.fontUi,
                fontSize: T.t13,
                color: T.beyaz065,
              ),
            ),
          ),
          if (showDots) ...[
            const SizedBox(width: T.sMd),
            const _TypingDots(),
          ],
        ],
      ),
    );
  }
}

/// `Nokta` — three 5pt dots at 30%, 50% and 80% white, cycling so the chip
/// reads as live rather than a static caption.
class _TypingDots extends StatefulWidget {
  const _TypingDots();

  @override
  State<_TypingDots> createState() => _TypingDotsState();
}

class _TypingDotsState extends State<_TypingDots>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  )..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) {
        return SizedBox(
          width: 23,
          height: 5,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              for (var i = 0; i < 3; i++)
                Container(
                  width: 5,
                  height: 5,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white.withValues(
                      alpha: _alpha(i),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  /// Walks the 0.3 / 0.5 / 0.8 ladder around the three dots.
  double _alpha(int index) {
    const ladder = [0.3, 0.5, 0.8];
    final lead = (_c.value * 3).floor() % 3;
    return ladder[(index - lead + 3) % 3];
  }
}
