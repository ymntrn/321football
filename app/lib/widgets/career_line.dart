import 'package:flutter/material.dart';

import '../data/app_database.dart';
import '../data/game_queries.dart';

/// `Takım 1 (2009–13) → Takım 2 (2013–17)` — a mutual player's spells at the
/// two clubs of the pair, in career order.
///
/// Used wherever the design names a correct answer: GOOOL (108:193), the
/// practice Doğru popup (84:352) and each row of the answer list (80:348).
/// It reads the database itself, so a caller only needs the player's display
/// name and the pair. Nothing is shown until the line is ready, and nothing
/// at all if the query fails — the line is a nicety, never a blocker.
class CareerLine extends StatefulWidget {
  const CareerLine({
    super.key,
    required this.playerName,
    required this.clubs,
    required this.style,
    this.textAlign = TextAlign.center,
    this.maxLines = 2,
  });

  final String playerName;

  /// The pair's two clubs, id to display name.
  final Map<int, String> clubs;
  final TextStyle style;
  final TextAlign textAlign;
  final int maxLines;

  @override
  State<CareerLine> createState() => _CareerLineState();
}

class _CareerLineState extends State<CareerLine> {
  late final Future<String?> _line = _load();

  Future<String?> _load() async {
    if (widget.clubs.length != 2) return null;
    final ids = widget.clubs.keys.toList();
    try {
      final spells = await GameQueries(AppDatabase.instance.db)
          .mutualSpells(widget.playerName, ids[0], ids[1]);
      if (spells.isEmpty) return null;
      return spells
          .map(
            (s) => '${widget.clubs[s.clubId]} (${careerYears(s.from, s.to)})',
          )
          .join(' → ');
    } catch (e) {
      debugPrint('career line failed: $e');
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String?>(
      future: _line,
      builder: (context, snap) {
        final text = snap.data;
        if (text == null) return const SizedBox.shrink();
        return Text(
          text,
          textAlign: widget.textAlign,
          maxLines: widget.maxLines,
          overflow: TextOverflow.ellipsis,
          style: widget.style,
        );
      },
    );
  }
}

/// 2009–13; 2018– for a spell still running; the full end year when the
/// century changes (1998–2001).
String careerYears(int? from, int? to) {
  final a = from?.toString() ?? '?';
  if (to == null) return '$a–';
  if (from != null && from ~/ 100 == to ~/ 100) {
    return '$a–${(to % 100).toString().padLeft(2, '0')}';
  }
  return '$a–$to';
}
