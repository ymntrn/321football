import 'package:flutter/material.dart';

import '../theme/tokens.dart';
import 'club_crest.dart';

/// `Kulüp Kartı` (Figma 76:413) — the club card in the Eşleşme row.
///
/// 150 wide, radius/xl, 1pt beyaz/030 border over a beyaz/006 fill, 12pt
/// horizontal / 18pt vertical padding, 14pt gap. Inside sits the 88pt `Arma`
/// circle (beyaz/012 fill, 2pt beyaz/038 border) and the club name at type/19.
///
/// The Arma slot holds the club's [ClubCrest]: no real (trademarked) crests,
/// just a gold-rimmed shield in the club's two colours.
class ClubCard extends StatelessWidget {
  const ClubCard({super.key, required this.name, this.width = 150});

  final String name;
  final double width;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 18),
      decoration: BoxDecoration(
        color: T.beyaz006,
        borderRadius: BorderRadius.circular(T.rXl),
        border: Border.all(color: T.beyaz030),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _ArmaSlot(name: name),
          const SizedBox(height: T.sXl),
          Text(
            name,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontFamily: T.fontUi,
              fontSize: T.t19,
              color: T.beyaz100,
              height: 1.15,
            ),
          ),
        ],
      ),
    );
  }
}

class _ArmaSlot extends StatelessWidget {
  const _ArmaSlot({required this.name});

  final String name;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 88,
      child: ClubCrest(name: name, size: 88 / 1.15),
    );
  }
}

/// Two letters that stay stable for a club: the first letters of its two
/// most meaningful words, skipping the noise that German, Spanish and
/// Brazilian club names are full of.
///
/// Shared by [ClubCard] and the compact matchup strip on the PvP board, so a
/// club wears the same badge in both.
String clubInitials(String name) {
  const noise = {
    'fc', 'sc', 'sv', 'ac', 'as', 'af', 'cf', 'sk', 'bk', 'if', 'vfl',
    'vfb', 'tsg', 'spvgg', 'kfc', 'rfc', 'club', 'clube', 'de', 'do',
    'da', 'the', '1', 'i',
  };
  final words = name
      .replaceAll(RegExp(r'[^\w\s]'), ' ')
      .split(RegExp(r'\s+'))
      .where((w) => w.isNotEmpty)
      .toList();
  final meaty = words.where((w) => !noise.contains(w.toLowerCase())).toList();
  final source = meaty.isEmpty ? words : meaty;
  if (source.isEmpty) return '?';
  if (source.length == 1) {
    final w = source.first;
    return (w.length >= 2 ? w.substring(0, 2) : w).toUpperCase();
  }
  return (source[0][0] + source[1][0]).toUpperCase();
}

/// A colour derived from the club's name, so a given club stays visually
/// stable everywhere its badge appears.
Color clubTint(String name) {
  var hash = 0;
  for (final unit in name.codeUnits) {
    hash = (hash * 31 + unit) & 0x7FFFFFFF;
  }
  return HSLColor.fromAHSL(1, (hash % 360).toDouble(), 0.6, 0.6).toColor();
}
