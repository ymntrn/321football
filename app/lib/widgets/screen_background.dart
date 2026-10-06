import 'package:flutter/material.dart';

import '../theme/tokens.dart';

/// The shared screen backdrop: `color/zemin/derin`, the concentric ring
/// `masking` layer, and the warm ellipse glow behind the middle of the frame.
///
/// Both decorations are PAINTED rather than loaded from the exported SVGs,
/// and that is deliberate — the exports do not survive flutter_svg:
///
///  * `masking` wraps its four ellipses in `<mask mask-type="alpha">` over a
///    rect filled #0A0D3B. flutter_svg renders that mask as luminance, and
///    #0A0D3B is nearly black, so the whole layer disappeared and the
///    background came out flat.
///  * `Ellipse 5` is a single hard ellipse whose entire appearance comes from
///    `feGaussianBlur stdDeviation="100"`. flutter_svg does not implement SVG
///    filters, so it drew the unblurred ellipse — a grey blob on screen.
///
/// The geometry and colours below are taken verbatim from those two files,
/// which are kept in assets/img/ as the reference.
class ScreenBackground extends StatelessWidget {
  const ScreenBackground({super.key, required this.child});

  final Widget child;

  static const designWidth = 430.0;
  static const designHeight = 932.0;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned.fill(
          child: CustomPaint(painter: _BackdropPainter()),
        ),
        Positioned.fill(child: child),
      ],
    );
  }
}

class _BackdropPainter extends CustomPainter {
  /// masking > Ellipse 1..4, centred (215, 465.5) on the 430x932 frame.
  /// preserveAspectRatio="none", so x and y scale independently.
  static const _rings = <({double rx, double ry, int argb})>[
    (rx: 445, ry: 444.5, argb: 0xFF0A1059),
    (rx: 397, ry: 396, argb: 0xFF070B4A),
    (rx: 332, ry: 331.5, argb: 0xFF060A3F),
    (rx: 259, ry: 258.5, argb: 0xFF050938),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final sx = size.width / ScreenBackground.designWidth;
    final sy = size.height / ScreenBackground.designHeight;

    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = T.zeminDerin,
    );

    final centre = Offset(215 * sx, 465.5 * sy);
    for (final ring in _rings) {
      canvas.drawOval(
        Rect.fromCenter(
          center: centre,
          width: ring.rx * 2 * sx,
          height: ring.ry * 2 * sy,
        ),
        Paint()..color = Color(ring.argb),
      );
    }

    // Ellipse 5: #EFD959 at 20%, blurred with stdDeviation 100. Reproduced as
    // a soft radial falloff centred where the blurred ellipse sits — (213.5,
    // 471.5) — spreading roughly the ellipse radius plus twice the blur.
    final glowCentre = Offset(213.5 * sx, 471.5 * sy);
    final glowRect = Rect.fromCenter(
      center: glowCentre,
      width: (124.5 + 200) * 2 * sx,
      height: (105.5 + 200) * 2 * sy,
    );
    canvas.drawOval(
      glowRect,
      Paint()
        ..shader = RadialGradient(
          colors: [
            const Color(0xFFEFD959).withValues(alpha: 0.13),
            const Color(0xFFEFD959).withValues(alpha: 0.0),
          ],
          stops: const [0.0, 1.0],
        ).createShader(glowRect),
    );
  }

  @override
  bool shouldRepaint(covariant _BackdropPainter oldDelegate) => false;
}

/// The `Undo` control in the top-left of every sub-screen.
class UndoButton extends StatelessWidget {
  const UndoButton({super.key, this.onTap});

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap ?? () => Navigator.of(context).maybePop(),
      behavior: HitTestBehavior.opaque,
      child: Padding(
        // Enlarges the touch target without moving the glyph.
        padding: const EdgeInsets.all(T.sMd),
        child: Image.asset(
          'assets/img/undo.png',
          width: 55,
          height: 32,
          fit: BoxFit.contain,
        ),
      ),
    );
  }
}

/// The 140x5 home indicator drawn at the foot of the design frames.
class HomeIndicator extends StatelessWidget {
  const HomeIndicator({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 140,
      height: 5,
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: T.beyaz050,
        borderRadius: BorderRadius.circular(3),
      ),
    );
  }
}
