import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../theme/tokens.dart';
import '../widgets/screen_background.dart';

/// `Versus` (Figma 27:42) — the two-second beat between "the match is on"
/// and the first team pick.
///
/// Three exported vectors on the usual backdrop: the top `Oyuncu Kartı`
/// banner (32:73), the bottom one (32:74, the same shape mirrored), and the
/// orange-to-red `VS` glyph (32:78), with the mode line under it (110:30).
///
/// The vectors are the Figma exports in assets/img/ (fetched by
/// tools/fetch_assets.ps1) and are placed at their frame positions, scaled
/// by the viewport width. Positions are measured from the frame's centre
/// (215, 466) so the composition stays centred on any height.
///
/// Departures from the frame, all deliberate:
///  * the banners are blank white placeholders in Figma (player card art is
///    still to come, per game-screens-ui.md); each carries its player's name
///    here, since an empty white card says nothing in a real match;
///  * the caption reads `ARKADAŞ MAÇI · İLK N GOL` — the frame's
///    `SIRALI MAÇ` is the ranked mode, which this is not.
class MatchVersusScreen extends StatelessWidget {
  const MatchVersusScreen({
    super.key,
    required this.playerName,
    required this.opponentName,
    required this.targetGoals,
  });

  final String playerName;
  final String opponentName;
  final int targetGoals;

  static const bannerTop = 'assets/img/versus_banner_top.svg';
  static const bannerBottom = 'assets/img/versus_banner_bottom.svg';
  static const vsGlyph = 'assets/img/versus_vs.svg';

  // Frame geometry (430 x 932).
  static const _frameW = 430.0;
  static const _centreY = 466.0;
  static const _bannerW = 386.829;
  static const _bannerH = 109.278;
  static const _topBannerY = 100.0;
  static const _bottomBannerY = 676.0;
  static const _bottomBannerX = 45.0;

  /// The VS export carries its drop shadow inside the file, so its viewBox
  /// is larger than the 210 x 186 glyph box: the frame's insets are
  /// -7.55% / -7.19% horizontally and -0.9% / -11.78% vertically.
  static const _vsBoxW = 210.0 * (1 + 0.0755 + 0.0719);
  static const _vsBoxH = 186.0 * (1 + 0.009 + 0.1178);
  static const _vsLeft = (_frameW - 210) / 2 - 210 * 0.0755;
  static const _vsTop = _centreY - 93 - 186 * 0.009;
  static const _captionY = 603.0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: ScreenBackground(
        child: LayoutBuilder(
          builder: (context, box) {
            final s = box.maxWidth / _frameW;
            final cy = box.maxHeight / 2;
            double y(double frameY) => cy + (frameY - _centreY) * s;

            return Stack(
              children: [
                Positioned(
                  left: 0,
                  top: y(_topBannerY),
                  width: _bannerW * s,
                  height: _bannerH * s,
                  child: _Banner(
                    asset: bannerTop,
                    name: playerName,
                    scale: s,
                    alignment: Alignment.centerLeft,
                  ),
                ),
                Positioned(
                  left: _bottomBannerX * s,
                  top: y(_bottomBannerY),
                  width: _bannerW * s,
                  height: _bannerH * s,
                  child: _Banner(
                    asset: bannerBottom,
                    name: opponentName,
                    scale: s,
                    alignment: Alignment.centerRight,
                    // 32:74 is drawn rotated 180° and flipped vertically,
                    // which nets out to a horizontal mirror.
                    mirror: true,
                  ),
                ),
                Positioned(
                  left: _vsLeft * s,
                  top: y(_vsTop),
                  width: _vsBoxW * s,
                  height: _vsBoxH * s,
                  child: SvgPicture.asset(
                    vsGlyph,
                    fit: BoxFit.contain,
                    errorBuilder: (_, __, ___) => const _MissingVs(),
                  ),
                ),
                Positioned(
                  left: 0,
                  right: 0,
                  top: y(_captionY) - 9 * s,
                  child: Text(
                    'ARKADAŞ MAÇI · İLK $targetGoals GOL',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontFamily: T.fontUi,
                      fontSize: T.t13 * s,
                      color: T.beyaz050,
                      letterSpacing: 1.04 * s,
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner({
    required this.asset,
    required this.name,
    required this.scale,
    required this.alignment,
    this.mirror = false,
  });

  final String asset;
  final String name;
  final double scale;
  final Alignment alignment;
  final bool mirror;

  @override
  Widget build(BuildContext context) {
    Widget art = SvgPicture.asset(
      asset,
      fit: BoxFit.fill,
      // Missing export (tools/fetch_assets.ps1 not run): draw nothing rather
      // than throw, so the match still runs. The name stays readable on the
      // backdrop.
      errorBuilder: (_, __, ___) => const SizedBox.expand(),
    );
    if (mirror) {
      art = Transform.flip(flipX: true, child: art);
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        art,
        Padding(
          // Clear of the banner's curved end, which sits on the inner side.
          padding: EdgeInsets.symmetric(horizontal: 40 * scale),
          child: Align(
            alignment: alignment,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                name,
                maxLines: 1,
                style: TextStyle(
                  fontFamily: T.fontUi,
                  fontSize: T.t34 * scale,
                  color: T.zeminAna,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Shown only if versus_vs.svg is missing, so a forgotten asset fetch is
/// obvious on the emulator instead of leaving a hole in the middle.
class _MissingVs extends StatelessWidget {
  const _MissingVs();

  @override
  Widget build(BuildContext context) {
    return const FittedBox(
      child: Text(
        'VS',
        style: TextStyle(
          fontFamily: T.fontNumeral,
          fontSize: T.t96,
          color: T.kirmizi,
        ),
      ),
    );
  }
}
