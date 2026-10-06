import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/models.dart';
import '../theme/tokens.dart';
import 'club_card.dart';
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
  static const _playerFill = playerBlockFill;
  static const _opponentFill = opponentBlockFill;

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
            Expanded(
              flex: 154,
              child: MatchNameBlock(name: playerName, fill: _playerFill),
            ),
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
            Expanded(
              flex: 157,
              child: MatchNameBlock(name: opponentName, fill: _opponentFill),
            ),
            const SizedBox(width: 5.5),
          ],
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

/// The score strip's block colours, also used for the name blocks on the
/// result screens (46:362 / 46:363).
const playerBlockFill = Color(0xFFFF840A);
const opponentBlockFill = Color(0xFF39C831);

/// One player's name block: 43pt tall, filled orange (this player) or green
/// (the opponent), 1pt black stroke. Sized by its parent — give it a width
/// (the strip's Expanded, or a SizedBox) or it fills what it is given.
class MatchNameBlock extends StatelessWidget {
  const MatchNameBlock({super.key, required this.name, required this.fill});

  final String name;
  final Color fill;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MatchScoreStrip.height,
      width: double.infinity,
      decoration: BoxDecoration(
        color: fill,
        // Rounded to match the lobby's name strips and the rest of the
        // system. The exported SVGs for these blocks are plain
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
}

/// The game's display lettering: a vertical gradient fill, a heavy black
/// outline and a warm #EFD959 glow beneath. Used by the countdown numeral
/// (38:200), GOOOL (41:783), TUR BİTTİ (109:26) and Kazandın / Kaybettin
/// (46:381 / 48:552).
///
/// Drawn as two stacked Texts because a single Text cannot both stroke and
/// fill: the lower one paints the outline (and carries the glow), the upper
/// one the gradient.
class OutlinedGradientText extends StatelessWidget {
  const OutlinedGradientText(
    this.text, {
    super.key,
    required this.fontSize,
    required this.colors,
    this.stops,
    this.letterSpacing = 0,
    this.strokeRatio = 0.055,
    this.glow = const Shadow(
      color: Color(0xFFEFD959),
      blurRadius: 4,
      offset: Offset(0, 4),
    ),
    this.height,
  });

  final String text;
  final double fontSize;
  final List<Color> colors;
  final List<double>? stops;
  final double letterSpacing;

  /// Outline width as a fraction of the font size.
  final double strokeRatio;
  final Shadow glow;
  final double? height;

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.center,
      children: [
        Text(
          text,
          maxLines: 1,
          style: TextStyle(
            fontFamily: T.fontUi,
            fontSize: fontSize,
            height: height,
            letterSpacing: letterSpacing,
            shadows: [glow],
            foreground: Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = fontSize * strokeRatio
              ..strokeJoin = StrokeJoin.round
              ..color = Colors.black,
          ),
        ),
        ShaderMask(
          shaderCallback: (rect) => LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: colors,
            stops: stops,
          ).createShader(rect),
          child: Text(
            text,
            maxLines: 1,
            style: TextStyle(
              fontFamily: T.fontUi,
              fontSize: fontSize,
              height: height,
              letterSpacing: letterSpacing,
              color: Colors.white,
            ),
          ),
        ),
      ],
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
                playerInitials(name),
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

/// A player's avatar letters: "Oyuncu1" becomes "O1", "Yaman" becomes "YA".
/// The design's avatars read `O1` / `O2` for exactly that reason.
String playerInitials(String name) {
  final clean = name.trim();
  if (clean.isEmpty) return '?';
  final digits = RegExp(r'\d').allMatches(clean).map((m) => m[0]).join();
  if (digits.isNotEmpty) return '${clean[0].toUpperCase()}$digits';
  return clean.substring(0, clean.length < 2 ? 1 : 2).toUpperCase();
}

/// The player's colour (orange) and the opponent's (green), matching the two
/// blocks of [MatchScoreStrip]. Avatar fills in `Canlı Durum` (85:526 /
/// 85:535) and on the result screens.
const playerAvatarFill = Color(0xFFF08717);
const opponentAvatarFill = Color(0xFF3DD136);

/// The 34pt round avatar from `Canlı Durum` (85:526): a solid fill, a 1.5pt
/// beyaz/050 ring and the initials at type/13.
class MatchAvatar extends StatelessWidget {
  const MatchAvatar({
    super.key,
    required this.name,
    required this.fill,
    this.size = 34,
  });

  final String name;
  final Color fill;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: fill,
        shape: BoxShape.circle,
        border: Border.all(color: T.beyaz050, width: 1.5),
      ),
      alignment: Alignment.center,
      padding: const EdgeInsets.all(T.sXxs),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Text(
          playerInitials(name),
          style: TextStyle(
            fontFamily: T.fontUi,
            fontSize: T.t13 * size / 34,
            color: T.beyaz100,
          ),
        ),
      ),
    );
  }
}

/// `Canlı Durum` (Figma 85:524) — the full-width strip under the matchup on
/// the PvP board: this player on the left ("Sen"), the opponent on the right
/// with what they are doing and the `Nokta` dots.
///
/// The protocol has no "typing" signal — the room row only learns about an
/// opponent's answer once it is CORRECT — so [opponentLabel] is a state the
/// caller derives from the row ("yazıyor" while the round is open, "buldu!"
/// once their time is in), not a live keystroke indicator.
class LiveStatusStrip extends StatelessWidget {
  const LiveStatusStrip({
    super.key,
    required this.playerName,
    required this.opponentName,
    required this.opponentLabel,
    this.playerLabel = 'Sen',
    this.showDots = true,
  });

  final String playerName;
  final String opponentName;
  final String playerLabel;
  final String opponentLabel;
  final bool showDots;

  @override
  Widget build(BuildContext context) {
    return Container(
      // Full width, explicitly: a Container with no width would shrink to
      // its Row and lose the space-between that pins the opponent right.
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: T.beyaz006,
        borderRadius: BorderRadius.circular(T.rXl),
        border: Border.all(color: T.beyaz016),
      ),
      child: Row(
        children: [
          MatchAvatar(name: playerName, fill: playerAvatarFill),
          const SizedBox(width: T.sSm),
          Flexible(
            child: Text(
              playerLabel,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontFamily: T.fontUi,
                fontSize: T.t15,
                color: T.beyaz080,
              ),
            ),
          ),
          const Spacer(),
          Flexible(
            flex: 2,
            child: Text(
              opponentLabel,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.right,
              // M PLUS 1p Medium in the design, not bundled — see the same
              // note on OpponentStatusChip.
              style: const TextStyle(
                fontFamily: T.fontUi,
                fontSize: T.t13,
                color: T.beyaz050,
              ),
            ),
          ),
          if (showDots) ...[
            const SizedBox(width: T.sSm),
            const _TypingDots(),
          ],
          const SizedBox(width: T.sSm),
          MatchAvatar(name: opponentName, fill: opponentAvatarFill),
        ],
      ),
    );
  }
}

/// `Eşleşme (Kompakt)` (Figma 87:190) — the one-line matchup that replaces
/// the two big club cards while the player is typing, so the suggestion
/// panel never has to cover the clubs during a ten-second round.
///
/// 390 wide at radius/xl, beyaz/006 over a 1.2pt beyaz/022 border, 14/8
/// padding, a 38pt crest each side and PoetsenOne "VS" at type/20 in red.
/// The crest is the same initials badge as [ClubCard]'s, scaled down.
class CompactMatchupStrip extends StatelessWidget {
  const CompactMatchupStrip({
    super.key,
    required this.clubA,
    required this.clubB,
  });

  final String clubA;
  final String clubB;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: T.sSm),
      decoration: BoxDecoration(
        color: T.beyaz006,
        borderRadius: BorderRadius.circular(T.rXl),
        border: Border.all(color: T.beyaz022, width: 1.2),
      ),
      child: Row(
        children: [
          Expanded(
            child: Row(
              children: [
                _MiniCrest(name: clubA),
                const SizedBox(width: T.sSm),
                Flexible(child: _name(clubA, TextAlign.left)),
              ],
            ),
          ),
          const SizedBox(width: T.sLg),
          const Text(
            'VS',
            style: TextStyle(
              fontFamily: T.fontUi,
              fontSize: T.t20,
              color: T.kirmizi,
            ),
          ),
          const SizedBox(width: T.sLg),
          Expanded(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Flexible(child: _name(clubB, TextAlign.right)),
                const SizedBox(width: T.sSm),
                _MiniCrest(name: clubB),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _name(String name, TextAlign align) {
    return Text(
      name,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      textAlign: align,
      style: const TextStyle(
        fontFamily: T.fontUi,
        fontSize: T.t17,
        color: T.beyaz100,
      ),
    );
  }
}

/// `Arma` at 38pt (87:192): beyaz/012 fill, 1.5pt beyaz/038 ring, initials
/// at type/11.
class _MiniCrest extends StatelessWidget {
  const _MiniCrest({required this.name});

  final String name;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 38,
      height: 38,
      decoration: BoxDecoration(
        color: T.beyaz012,
        shape: BoxShape.circle,
        border: Border.all(color: T.beyaz038, width: 1.5),
      ),
      alignment: Alignment.center,
      child: Text(
        clubInitials(name),
        style: TextStyle(
          fontFamily: T.fontUi,
          fontSize: T.t11,
          color: clubTint(name),
        ),
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
