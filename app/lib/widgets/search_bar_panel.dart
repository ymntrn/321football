import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../data/name_normalizer.dart';
import '../models/models.dart';
import '../theme/tokens.dart';

/// Characters after which a new word starts, for highlight purposes.
/// Hyphens count: "Saint-Germain" should light up on "germain".
final RegExp _wordBreak = RegExp(r"[\s\-'’,]");

/// `Arama Çubuğu` (Figma 76:423 / 78:384) — 390x58 at radius/2xl over
/// zemin/panel, with a hard 4pt #040629 drop shadow, the exported magnifier
/// icon, a green caret while typing, and a round clear button.
class PracticeSearchBar extends StatelessWidget {
  const PracticeSearchBar({
    super.key,
    required this.typed,
    required this.onClear,
    this.placeholder = 'Oyuncu ara...',
  });

  final String typed;
  final VoidCallback onClear;

  /// `Oyuncu ara...` while hunting a player, `Takım ara...` in the team
  /// picker (Figma 33:85).
  final String placeholder;

  @override
  Widget build(BuildContext context) {
    final active = typed.isNotEmpty;
    return Container(
      height: 58,
      decoration: BoxDecoration(
        color: T.zeminPanel,
        borderRadius: BorderRadius.circular(T.r2xl),
        border: Border.all(
          color: active ? T.beyaz080 : T.beyaz038,
          width: active ? 2 : 1.5,
        ),
        boxShadow: const [
          BoxShadow(
            color: T.golgeCubuk,
            offset: Offset(0, 4),
            blurRadius: 0,
          ),
        ],
      ),
      padding: const EdgeInsets.symmetric(horizontal: 17),
      child: Row(
        children: [
          SvgPicture.asset('assets/img/search.svg', width: 26, height: 26),
          const SizedBox(width: T.sLg),
          Expanded(
            child: active
                ? Row(
                    children: [
                      Flexible(
                        child: Text(
                          typed,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontFamily: T.fontUi,
                            fontSize: T.t22,
                            color: T.beyaz100,
                          ),
                        ),
                      ),
                      const _Caret(),
                    ],
                  )
                : Text(
                    placeholder,
                    style: const TextStyle(
                      fontFamily: T.fontUi,
                      fontSize: T.t22,
                      color: T.beyaz050,
                    ),
                  ),
          ),
          if (active)
            GestureDetector(
              onTap: onClear,
              behavior: HitTestBehavior.opaque,
              child: Container(
                width: 30,
                height: 30,
                decoration: const BoxDecoration(
                  color: T.beyaz022,
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: const Text(
                  '✕',
                  style: TextStyle(fontSize: T.t13, color: T.beyaz080),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _Caret extends StatefulWidget {
  const _Caret();

  @override
  State<_Caret> createState() => _CaretState();
}

class _CaretState extends State<_Caret> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  )..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _c.drive(TweenSequence([
        TweenSequenceItem(tween: ConstantTween(1.0), weight: 50),
        TweenSequenceItem(tween: ConstantTween(0.0), weight: 50),
      ])),
      child: Container(
        width: 2.5,
        height: 26,
        margin: const EdgeInsets.only(left: 3),
        decoration: BoxDecoration(
          color: T.yesil,
          borderRadius: BorderRadius.circular(2),
        ),
      ),
    );
  }
}

/// `Öneriler` (Figma 79:341) — the floating suggestion panel.
///
/// The FIRST row is the highlighted one (beyaz/016 fill, 2pt green border,
/// a green ↵ affordance); the rest are quiet (beyaz/006, 1pt beyaz/012, a
/// grey ›). This is a display aid only and must never soften validateAnswer.
class SuggestionPanel extends StatelessWidget {
  const SuggestionPanel({
    super.key,
    required this.typed,
    required this.suggestions,
    required this.onTap,
    this.maxRows = 4,
  });

  final String typed;
  final List<Player> suggestions;
  final ValueChanged<Player> onTap;

  /// How many rows there is actually room for. The design shows 4 on a 932pt
  /// frame; shorter viewports get fewer rather than a panel that overflows
  /// and hides its own top row behind the club cards.
  final int maxRows;

  /// Height of one row plus its gap, used by the caller to work out [maxRows].
  /// 38pt avatar + 8pt padding top and bottom + 2pt border + 8pt gap.
  static const rowExtent = 64.0;

  /// Panel chrome: 12pt padding top and bottom, header, header gap.
  static const chromeExtent = 56.0;

  @override
  Widget build(BuildContext context) {
    if (suggestions.isEmpty) return const SizedBox.shrink();
    final rows = suggestions.take(maxRows.clamp(1, 4)).toList();
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
            'ÖNERİLER',
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
            _SuggestionRow(
              player: rows[i],
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

class _SuggestionRow extends StatelessWidget {
  const _SuggestionRow({
    required this.player,
    required this.typed,
    required this.highlighted,
    required this.onTap,
  });

  final Player player;
  final String typed;
  final bool highlighted;
  final VoidCallback onTap;

  String get _initials {
    final words = player.displayName
        .replaceAll(RegExp(r'[^\w\s]'), ' ')
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty)
        .toList();
    if (words.isEmpty) return '?';
    if (words.length == 1) {
      final w = words.first;
      return (w.length >= 2 ? w.substring(0, 2) : w).toUpperCase();
    }
    // Given-name initial then surname initial, as the design's "GB" for
    // Gabriel Batistuta.
    return (words.first[0] + words.last[0]).toUpperCase();
  }

  /// The design's second line reads "Forvet · 1988–2005" — position and
  /// career span. The database has NO position column, so this shows
  /// nationality instead, with the career span derived from the player's
  /// spells. Add a position column upstream and this line can match exactly.
  String get _subtitle {
    final years = (player.firstYear != null && player.lastYear != null)
        ? '${player.firstYear}–${player.lastYear}'
        : (player.firstYear != null ? '${player.firstYear}–' : null);
    final parts = [
      if (player.nationality != null) player.nationality!,
      if (years != null) years,
    ];
    return parts.join(' · ');
  }

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
            color: highlighted
                ? T.yesil.withValues(alpha: 0.85)
                : T.beyaz012,
            width: highlighted ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: T.zeminPanel,
                shape: BoxShape.circle,
                border: Border.all(color: T.beyaz030),
              ),
              alignment: Alignment.center,
              child: Text(
                _initials,
                style: const TextStyle(
                  fontFamily: T.fontUi,
                  fontSize: T.t13,
                  color: T.beyaz080,
                ),
              ),
            ),
            const SizedBox(width: T.sLg),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  HighlightedName(name: player.displayName, typed: typed),
                  if (_subtitle.isNotEmpty) ...[
                    const SizedBox(height: T.sHairline),
                    Text(
                      _subtitle,
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

/// Green-tints the part of a name already typed.
///
/// Shared by the player suggestions and the team picker, which want exactly
/// the same behaviour — the team list tints "Ba" inside "FC Barcelona" the
/// same way the player list tints "Rein" inside "Alois Reinhardt".
///
/// Checked at every WORD START, not just the front of the string:
/// suggestions come from `player_aliases`, where a bare surname is one of a
/// player's aliases, so "rein" legitimately surfaces "Alois Reinhardt" with
/// the match in the second word. Club names need it even more often, since
/// most of them begin with a throwaway "FC" or "AC".
///
/// Matching runs on folded text so "ozil" hits inside "Mesut Özil", but the
/// slice comes from the ORIGINAL string so accents survive on screen.
/// Folding can change length (ß to ss, stripped punctuation), so the end is
/// grown a character at a time rather than assuming indices line up.
class HighlightedName extends StatelessWidget {
  const HighlightedName({
    super.key,
    required this.name,
    required this.typed,
    this.fontSize = T.t17,
  });

  final String name;
  final String typed;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    // fontFamily must be explicit: RichText does NOT inherit the ambient
    // DefaultTextStyle the way Text does.
    final base = TextStyle(
      fontFamily: T.fontUi,
      fontSize: fontSize,
      color: T.beyaz100,
    );
    final hit = TextStyle(
      fontFamily: T.fontUi,
      fontSize: fontSize,
      color: T.yesil,
    );

    final needle = normalizeName(typed);
    if (needle.isEmpty) {
      return Text(name, style: base, maxLines: 1, overflow: TextOverflow.ellipsis);
    }

    final starts = <int>[0];
    for (var i = 0; i < name.length - 1; i++) {
      if (_wordBreak.hasMatch(name[i])) starts.add(i + 1);
    }

    for (final start in starts) {
      for (var end = start + 1; end <= name.length; end++) {
        final folded = normalizeName(name.substring(start, end));
        if (folded.length < needle.length) continue;
        if (folded == needle) {
          return RichText(
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            text: TextSpan(children: [
              TextSpan(text: name.substring(0, start), style: base),
              TextSpan(text: name.substring(start, end), style: hit),
              TextSpan(text: name.substring(end), style: base),
            ]),
          );
        }
        break; // overshot this word without matching - try the next one
      }
    }

    return Text(name, style: base, maxLines: 1, overflow: TextOverflow.ellipsis);
  }
}
