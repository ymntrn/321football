import 'package:flutter/material.dart';

import '../models/models.dart';
import '../theme/tokens.dart';
import 'search_bar_panel.dart';

/// `TAKIMLAR` — the team-picker suggestion panel (Figma 86:190).
///
/// The same shape as the player `ÖNERİLER` panel: first row highlighted with
/// a green border and a ↵ affordance, the rest quiet with a grey ›. What
/// differs is the content — a three-letter crest badge instead of an avatar,
/// and a `Türkiye · Süper Lig` sub-line instead of nationality and years.
///
/// Unlike the player panel this one is NOT merely a display aid: tapping a
/// row is how a club is chosen, so a tap commits the pick.
class ClubSuggestionPanel extends StatelessWidget {
  const ClubSuggestionPanel({
    super.key,
    required this.typed,
    required this.clubs,
    required this.onTap,
    this.maxRows = 4,
  });

  final String typed;
  final List<Club> clubs;
  final ValueChanged<Club> onTap;
  final int maxRows;

  /// Height of one row plus its gap: 40pt badge + 8pt padding top and bottom
  /// + 2pt border + 8pt gap.
  static const rowExtent = 66.0;

  /// Panel chrome: 12pt padding top and bottom, header, header gap.
  static const chromeExtent = 56.0;

  @override
  Widget build(BuildContext context) {
    if (clubs.isEmpty) return const SizedBox.shrink();
    final rows = clubs.take(maxRows.clamp(1, 4)).toList();
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xF50B0F47), // rgba(11,15,71,0.96)
        borderRadius: BorderRadius.circular(T.rXl),
        border: Border.all(color: T.beyaz022, width: 1.5),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.45),
            offset: const Offset(0, 10),
            blurRadius: 24,
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'TAKIMLAR',
            style: TextStyle(
              fontFamily: T.fontUi,
              fontSize: T.t13,
              color: T.beyaz050,
              letterSpacing: 1.04,
            ),
          ),
          const SizedBox(height: T.sSm),
          for (var i = 0; i < rows.length; i++) ...[
            if (i > 0) const SizedBox(height: T.sSm),
            _ClubRow(
              club: rows[i],
              typed: typed,
              highlighted: i == 0,
              onTap: () => onTap(rows[i]),
            ),
          ],
        ],
      ),
    );
  }
}

class _ClubRow extends StatelessWidget {
  const _ClubRow({
    required this.club,
    required this.typed,
    required this.highlighted,
    required this.onTap,
  });

  final Club club;
  final String typed;
  final bool highlighted;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.only(left: 10, right: 12, top: 8, bottom: 8),
        decoration: BoxDecoration(
          color: highlighted ? T.beyaz016 : T.beyaz006,
          borderRadius: BorderRadius.circular(T.rMd),
          border: Border.all(
            color: highlighted ? T.yesil.withValues(alpha: 0.85) : T.beyaz012,
            width: highlighted ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            ClubBadge(club: club, size: 40),
            const SizedBox(width: T.sLg),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  HighlightedName(name: club.name, typed: typed),
                  if (club.subtitle.isNotEmpty) ...[
                    const SizedBox(height: T.sHairline),
                    Text(
                      club.subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: T.t11,
                        color: T.beyaz050,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: T.sSm),
            Text(
              highlighted ? '↵' : '›',
              style: TextStyle(
                fontFamily: T.fontUi,
                fontSize: T.t19,
                color: highlighted ? T.yesil : T.beyaz038,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The circular three-letter crest stand-in (`BAR`, `BAY`, `BAŞ`).
///
/// Real crests are deferred and will not be the clubs' actual badges — the
/// decision was two stripes in the club's colours, to sidestep the trademark
/// problem. Until then this is the same deterministic device `club_card.dart`
/// uses on the board: initials on a colour hashed from the club name, so a
/// club looks the same everywhere it appears.
class ClubBadge extends StatelessWidget {
  const ClubBadge({super.key, required this.club, this.size = 40});

  final Club club;
  final double size;

  /// Deterministic hue from the name. Saturation and lightness are fixed so
  /// no badge can come out near-white and swallow the letters.
  Color get _fill {
    var hash = 0;
    for (final unit in club.name.codeUnits) {
      hash = (hash * 31 + unit) & 0x7fffffff;
    }
    return HSLColor.fromAHSL(1, (hash % 360).toDouble(), 0.42, 0.38).toColor();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: _fill,
        shape: BoxShape.circle,
        border: Border.all(color: T.beyaz030),
      ),
      alignment: Alignment.center,
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: size * 0.12),
          child: Text(
            club.badgeLetters,
            style: TextStyle(
              fontFamily: T.fontUi,
              fontSize: size * 0.32,
              color: T.beyaz100,
            ),
          ),
        ),
      ),
    );
  }
}
