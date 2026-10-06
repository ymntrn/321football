import 'package:flutter/material.dart';
import 'package:sqflite/sqflite.dart';

import 'club_card.dart' show clubTint;

/// Each club's two colours, loaded once at boot from `clubs.color_a` /
/// `clubs.color_b` (written by curate.py from the Wikipedia home kit plus a
/// hand-curated list). Looked up by id where a screen has one, by display
/// name where it only has the name (the match room stores names).
class ClubColours {
  ClubColours._();
  static final ClubColours instance = ClubColours._();

  final Map<int, (Color, Color)> _byId = {};
  final Map<String, (Color, Color)> _byName = {};

  Future<void> load(Database db) async {
    try {
      final rows = await db.rawQuery(
        'SELECT club_id, canonical_name, color_a, color_b FROM clubs '
        'WHERE color_a IS NOT NULL AND color_b IS NOT NULL',
      );
      for (final r in rows) {
        final pair = (_hex(r['color_a'] as String), _hex(r['color_b'] as String));
        _byId[r['club_id'] as int] = pair;
        _byName[(r['canonical_name'] as String).toLowerCase()] = pair;
      }
    } catch (e) {
      // An older database without the colour columns: every crest falls
      // back to the name-derived pair below. Never a reason to fail boot.
      debugPrint('club colours unavailable: $e');
    }
  }

  /// The club's pair, or a stable fallback derived from its name.
  (Color, Color) of({int? id, required String name}) =>
      (id != null ? _byId[id] : null) ??
      _byName[name.toLowerCase()] ??
      (clubTint(name), const Color(0xFFFFFFFF));

  static Color _hex(String h) => Color(0xFF000000 | int.parse(h, radix: 16));
}

/// The club crest: a gold-rimmed shield with a dark navy inner ring and the
/// club's two colours split down the middle. No real crests (trademarks) -
/// decided 11 Sep 2026; the look was set on 6 Oct 2026.
///
/// [size] is the shield's WIDTH; it is 1.15x as tall.
class ClubCrest extends StatelessWidget {
  const ClubCrest({super.key, required this.name, this.id, this.size = 40});

  final String name;
  final int? id;
  final double size;

  @override
  Widget build(BuildContext context) {
    final (a, b) = ClubColours.instance.of(id: id, name: name);
    return Semantics(
      label: name,
      child: SizedBox(
        width: size,
        height: size * 1.15,
        child: CustomPaint(painter: _CrestPainter(a, b)),
      ),
    );
  }
}

class _CrestPainter extends CustomPainter {
  _CrestPainter(this.a, this.b);

  final Color a;
  final Color b;

  static const _navy = Color(0xFF0B1033);

  /// The shield outline in a w x h box: a gently arched top with rounded
  /// shoulders, sides that swell then sweep to a point.
  static Path _shield(double w, double h) => Path()
    ..moveTo(w * 0.06, h * 0.13)
    ..quadraticBezierTo(w * 0.06, h * 0.05, w * 0.15, h * 0.045)
    ..quadraticBezierTo(w * 0.50, h * -0.005, w * 0.85, h * 0.045)
    ..quadraticBezierTo(w * 0.94, h * 0.05, w * 0.94, h * 0.13)
    ..cubicTo(w * 0.95, h * 0.52, w * 0.82, h * 0.80, w * 0.50, h * 0.985)
    ..cubicTo(w * 0.18, h * 0.80, w * 0.05, h * 0.52, w * 0.06, h * 0.13)
    ..close();

  /// The outline shrunk by [f] about a point a little above the middle, so
  /// the rings stay even all the way down to the tip.
  static Path _inset(double w, double h, double f) {
    final cx = w * 0.5, cy = h * 0.46;
    final m = Matrix4.identity()
      ..translateByDouble(cx, cy, 0, 1)
      ..scaleByDouble(f, f, 1, 1)
      ..translateByDouble(-cx, -cy, 0, 1);
    return _shield(w, h).transform(m.storage);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final outer = _shield(w, h);
    final rect = Offset.zero & size;

    // Soft drop shadow so the gold lifts off the navy screens.
    canvas.drawShadow(outer, Colors.black, w * 0.04, false);

    // Gold rim: light at the top-left, deep at the bottom-right.
    canvas.drawPath(
      outer,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFFFF1A8), Color(0xFFE2B33C), Color(0xFFB07D18), Color(0xFF7A520C)],
          stops: [0.0, 0.35, 0.7, 1.0],
        ).createShader(rect),
    );

    // Dark navy ring.
    canvas.drawPath(_inset(w, h, 0.86), Paint()..color = _navy);

    // The field: colour A on the left half, colour B on the right.
    final field = _inset(w, h, 0.72);
    canvas.save();
    canvas.clipPath(field);
    canvas.drawRect(Rect.fromLTWH(0, 0, w / 2, h), Paint()..color = a);
    canvas.drawRect(Rect.fromLTWH(w / 2, 0, w / 2, h), Paint()..color = b);
    // A faint sheen across the top so flat colours read as a badge.
    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.white.withValues(alpha: 0.18), Colors.transparent],
          stops: const [0.0, 0.45],
        ).createShader(rect),
    );
    canvas.restore();

    // Thin highlight along the rim's top edge.
    canvas.drawPath(
      outer,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = (w * 0.012).clamp(0.6, 2.0)
        ..color = const Color(0x66FFFFFF),
    );
  }

  @override
  bool shouldRepaint(_CrestPainter old) => old.a != a || old.b != b;
}
