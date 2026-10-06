import 'package:flutter/material.dart';

import '../theme/tokens.dart';

/// The two buttons on the match-end screen. Placeholder styling, like the
/// screen itself — `Maç Sonu Kazanma` (46:352) and `Kaybetme` (48:534) still
/// want building from Figma.
class EndButton extends StatelessWidget {
  const EndButton({
    super.key,
    required this.label,
    required this.filled,
    required this.onTap,
  });

  final String label;
  final bool filled;
  final Future<void> Function() onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        width: 240,
        height: 64,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: filled ? null : T.zeminPanel,
          gradient: filled ? T.yesilGradient : null,
          borderRadius: BorderRadius.circular(T.rLg),
          border: Border.all(color: T.beyaz038, width: 1.5),
        ),
        child: Text(
          label,
          style: const TextStyle(
            fontFamily: T.fontUi,
            fontSize: T.t19,
            color: T.beyaz100,
          ),
        ),
      ),
    );
  }
}
