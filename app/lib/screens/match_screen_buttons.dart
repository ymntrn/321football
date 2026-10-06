import 'package:flutter/material.dart';

import '../theme/tokens.dart';

/// The host's BAŞLAT on the post-rematch waiting screen — the one match
/// screen with no Figma frame (a rematch returns the room to the lobby
/// phase, which the design never draws inside a match). The result screens
/// themselves use the violet LobbyButton from 46:352 / 48:534.
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
