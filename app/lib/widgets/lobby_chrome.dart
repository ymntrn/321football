import 'package:flutter/material.dart';

import '../theme/tokens.dart';

/// The pieces of `Arkadaş Maçı - Oda Kur` / `Odaya Katıl` (Figma 51:471,
/// 51:524). Both screens are the same furniture with a different panel body,
/// so it all lives here and the screen just arranges it.

/// One of the two mode buttons at the top. 306x63.748 in the design; the
/// height is that odd number because the frame was scaled, and it is kept
/// rather than rounded so the two buttons stack at the spacing drawn.
class LobbyTabButton extends StatelessWidget {
  const LobbyTabButton({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  static const height = 63.748;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        height: height,
        // Without this the Container sizes to the label and the button comes
        // out about a third of the width the design draws. The caller decides
        // how wide "full" is, by its padding.
        width: double.infinity,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(T.rLg),
          border: Border.all(
            // The design draws both buttons identically; the app needs to say
            // which mode is live, so the selected one takes a brighter, wider
            // border. Everything else is unchanged.
            color: selected ? T.beyaz080 : T.beyaz030,
            width: selected ? 2 : 1,
          ),
          gradient: T.morGradient(selected ? 0.95 : 0.6),
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            Positioned.fill(child: T.insetTop(T.rLg)),
            Text(
              label,
              style: const TextStyle(
                fontFamily: T.fontUi,
                fontSize: T.t34,
                color: T.beyaz100,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The big violet room panel, 364x506 at radius/lg.
class LobbyPanel extends StatelessWidget {
  const LobbyPanel({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(T.rLg),
        border: Border.all(color: T.beyaz030),
        gradient: T.morGradient(0.49),
      ),
      child: Stack(
        children: [
          Positioned.fill(child: T.insetTop(T.rLg)),
          Padding(
            padding: const EdgeInsets.fromLTRB(19, 30, 15, 21),
            child: child,
          ),
        ],
      ),
    );
  }
}

/// A player's name on the orange (host) or green (guest) block from the
/// scoreboard, reused here so the lobby and the match agree on which colour
/// each player is.
class PlayerNameStrip extends StatelessWidget {
  const PlayerNameStrip({
    super.key,
    required this.name,
    required this.host,
    this.waiting = false,
  });

  final String name;
  final bool host;

  /// No second player yet: the block is dimmed and the name is a placeholder.
  final bool waiting;

  static const _hostFill = Color(0xFFFF840A);
  static const _guestFill = Color(0xFF39C831);

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: waiting ? 0.35 : 1,
      child: Container(
        height: 43,
        width: host ? 154 : 157,
        decoration: BoxDecoration(
          color: host ? _hostFill : _guestFill,
          // The Figma frame draws these as hard-cornered rectangles with a
          // 1pt black stroke, straight off the scoreboard. Rounded here at
          // Yaman's call (13 Sep): every other surface in the lobby — the
          // panel, the tab buttons, the avatars, the action button — is
          // rounded, and the square corners were the one thing that read as
          // pasted in from somewhere else.
          borderRadius: BorderRadius.circular(T.rSm),
          border: Border.all(color: Colors.black),
        ),
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.symmetric(horizontal: T.sXl),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
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
      ),
    );
  }
}

/// The 52pt square avatar. A present player gets a green border; an empty
/// seat gets the quiet white one and faded initials.
class LobbyAvatar extends StatelessWidget {
  const LobbyAvatar({super.key, required this.initials, required this.present});

  final String initials;
  final bool present;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 52,
      height: 52,
      decoration: BoxDecoration(
        color: T.zeminAvatar,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: present ? T.yesil.withValues(alpha: 0.9) : T.beyaz030,
          width: present ? 2 : 1.5,
        ),
      ),
      alignment: Alignment.center,
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Text(
          initials,
          style: TextStyle(
            fontFamily: T.fontUi,
            fontSize: T.t19,
            color: present ? T.beyaz100 : T.beyaz050,
          ),
        ),
      ),
    );
  }
}

/// The 341x90 action button at the foot of the panel. Green when it does
/// something, orange when it is only reporting a state — which is how the
/// design distinguishes the host's `Başlat` from the guest's
/// `Başlatma Bekleniyor`.
class LobbyButton extends StatelessWidget {
  const LobbyButton({
    super.key,
    required this.label,
    this.onTap,
    this.tone = LobbyButtonTone.go,
  });

  final String label;
  final VoidCallback? onTap;
  final LobbyButtonTone tone;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Opacity(
        opacity: enabled || tone == LobbyButtonTone.waiting ? 1 : 0.45,
        child: Container(
          height: 90,
          width: double.infinity, // see the note on LobbyTabButton
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(T.rLg),
            border: Border.all(color: T.beyaz030),
            gradient: tone == LobbyButtonTone.go
                ? T.yesilGradient
                : T.turuncuGradient,
          ),
          child: Stack(
            alignment: Alignment.center,
            children: [
              Positioned.fill(child: T.insetTop(T.rLg)),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: T.sLg),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    label,
                    style: const TextStyle(
                      fontFamily: T.fontUi,
                      fontSize: T.t40,
                      color: T.beyaz100,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

enum LobbyButtonTone { go, waiting }
