import 'package:flutter/material.dart';

import '../settings/app_settings.dart';
import '../theme/tokens.dart';

/// The shared `Klavye` component (Figma 77:338).
///
/// Layout is four rows, NOT three-plus-a-bar:
///   1  QWERTYUIOPĞÜ        12 keys
///   2  ASDFGHJKLŞİ         11 keys
///   3  ZXCVBNMÖÇ + ⌫       9 keys plus a wide backspace
///   4  boşluk + GÖNDER
///
/// Key metrics from the frame: 31.3x46 at radius/tus, 4pt gaps, white face,
/// navy PoetsenOne at type/20, and a HARD 3pt drop shadow (zero blur) in
/// #4d579e. The dark keys use #03051c and GÖNDER a 4pt #176b0f.
///
/// Widths are derived from the available width rather than hard-coded to
/// 31.3: twelve 31.3pt keys plus gaps need 419pt, which overflows a 411pt
/// Pixel 6 viewport. The proportions are preserved instead.
class TurkishKeyboard extends StatelessWidget {
  const TurkishKeyboard({
    super.key,
    required this.onKey,
    required this.onSpace,
    required this.onBackspace,
    required this.onAction,
    this.actionLabel = 'GÖNDER',
    this.actionEnabled = true,
  });

  final ValueChanged<String> onKey;
  final VoidCallback onSpace;
  final VoidCallback onBackspace;
  final VoidCallback onAction;
  final String actionLabel;
  final bool actionEnabled;

  static const row1 = 'QWERTYUIOPĞÜ';
  static const row2 = 'ASDFGHJKLŞİ';
  static const row3 = 'ZXCVBNMÖÇ';

  static const keyHeight = 46.0;
  static const bottomHeight = 50.0;
  static const gap = T.sXxs; // 4
  static const trayPad = 5.0;

  /// Letters, space and backspace click. GÖNDER does not: the correct /
  /// wrong sound that follows it is its feedback.
  static void _tap(VoidCallback action) {
    Sounds.play(Sfx.tap);
    action();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // Row 1 sets the unit: 12 slots + 11 gaps must fit the tray.
        final unit =
            (constraints.maxWidth - trayPad * 2 - gap * 11) / 12;
        // Row 3 is 9 letters + a backspace that is ~1.53 units wide.
        const backspaceUnits = 48 / 31.3;

        return Container(
          width: double.infinity,
          decoration: const BoxDecoration(
            color: T.zeminKlavye,
            border: Border(
              top: BorderSide(color: T.beyaz016, width: 1.5),
            ),
            borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
          ),
          padding: const EdgeInsets.fromLTRB(trayPad, 14, trayPad, 26),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _letterRow(row1, unit),
              const SizedBox(height: T.sSm),
              _letterRow(row2, unit),
              const SizedBox(height: T.sSm),
              _row3(unit, backspaceUnits),
              const SizedBox(height: T.sSm),
              _row4(constraints.maxWidth - trayPad * 2),
            ],
          ),
        );
      },
    );
  }

  Widget _letterRow(String letters, double unit) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (var i = 0; i < letters.length; i++) ...[
          if (i > 0) const SizedBox(width: gap),
          _Key(
            width: unit,
            height: keyHeight,
            label: letters[i],
            onTap: () => _tap(() => onKey(letters[i])),
          ),
        ],
      ],
    );
  }

  Widget _row3(double unit, double backspaceUnits) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (var i = 0; i < row3.length; i++) ...[
          if (i > 0) const SizedBox(width: gap),
          _Key(
            width: unit,
            height: keyHeight,
            label: row3[i],
            onTap: () => _tap(() => onKey(row3[i])),
          ),
        ],
        const SizedBox(width: gap),
        _Key(
          width: unit * backspaceUnits,
          height: keyHeight,
          label: '⌫',
          dark: true,
          fontSize: T.t17,
          onTap: () => _tap(onBackspace),
        ),
      ],
    );
  }

  Widget _row4(double available) {
    // 286 : 128 with a 6pt gap on a 420pt tray.
    final gonderWidth = (available - T.sXs) * 128 / 414;
    final spaceWidth = available - T.sXs - gonderWidth;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _Key(
          width: spaceWidth,
          height: bottomHeight,
          label: 'boşluk',
          dark: true,
          radius: T.rSm,
          fontSize: T.t17,
          onTap: () => _tap(onSpace),
        ),
        const SizedBox(width: T.sXs),
        _Key(
          width: gonderWidth,
          height: bottomHeight,
          label: actionLabel,
          radius: T.rSm,
          fontSize: T.t19,
          gradient: T.yesilGradient,
          foreground: T.beyaz100,
          borderColor: T.beyaz038,
          borderWidth: 1.5,
          shadowColor: T.golgeGonder,
          shadowOffset: 4,
          topHighlight: true,
          enabled: actionEnabled,
          onTap: onAction,
        ),
      ],
    );
  }
}

class _Key extends StatelessWidget {
  const _Key({
    required this.width,
    required this.height,
    required this.label,
    required this.onTap,
    this.dark = false,
    this.gradient,
    this.foreground,
    this.radius = T.rTus,
    this.fontSize = T.t20,
    this.borderColor,
    this.borderWidth = 1,
    this.shadowColor,
    this.shadowOffset = 3,
    this.topHighlight = false,
    this.enabled = true,
  });

  final double width;
  final double height;
  final String label;
  final VoidCallback onTap;
  final bool dark;
  final Gradient? gradient;
  final Color? foreground;
  final double radius;
  final double fontSize;
  final Color? borderColor;
  final double borderWidth;
  final Color? shadowColor;
  final double shadowOffset;
  final bool topHighlight;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final fill = gradient != null
        ? null
        : dark
            ? T.beyaz022
            : T.beyaz100;
    final text = foreground ?? (dark ? T.beyaz080 : T.zeminAna);
    final border = borderColor ?? (dark ? T.beyaz022 : null);
    final shadow = shadowColor ?? (dark ? T.golgeKoyuTus : T.golgeTus);

    return Opacity(
      opacity: enabled ? 1 : 0.45,
      child: GestureDetector(
        onTap: enabled ? onTap : null,
        child: Container(
          width: width,
          height: height,
          decoration: BoxDecoration(
            color: fill,
            gradient: gradient,
            borderRadius: BorderRadius.circular(radius),
            border: border == null
                ? null
                : Border.all(color: border, width: borderWidth),
            // Hard shadow: zero blur, pure offset. A blurred shadow reads as
            // a completely different (softer, cheaper) keyboard.
            boxShadow: [
              BoxShadow(
                color: shadow,
                offset: Offset(0, shadowOffset),
                blurRadius: 0,
              ),
            ],
          ),
          alignment: Alignment.center,
          child: Stack(
            alignment: Alignment.center,
            children: [
              if (topHighlight)
                Positioned.fill(
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(radius),
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.white.withValues(alpha: 0.35),
                          Colors.transparent,
                        ],
                        stops: const [0, 0.18],
                      ),
                    ),
                  ),
                ),
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 3),
                  child: Text(
                    label,
                    style: TextStyle(
                      fontFamily: T.fontUi,
                      fontSize: fontSize,
                      color: text,
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
