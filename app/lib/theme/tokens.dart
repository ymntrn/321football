import 'package:flutter/material.dart';

/// The `321 Tokens` Figma collection, transcribed.
///
/// Gradients are literal in Figma because a variable cannot be bound to a
/// gradient stop, but both endpoints are tokens, so they are rebuilt here
/// from `turuncu`/`turuncuKoyu` and `yesil`/`yesilKoyu`.
class T {
  T._();

  // ---- color/zemin (surfaces) ----
  static const zeminAna = Color(0xFF0A0D3B); // screen background
  static const zeminDerin = Color(0xFF0C126B); // backing rectangle
  static const zeminPanel = Color(0xFF1620A7); // cards, chips, search bar
  static const zeminKlavye = Color(0xFF0E145A); // keyboard tray
  static const zeminAvatar = Color(0xFF3321D9);

  static const halka1 = Color(0xFF0A1059);
  static const halka2 = Color(0xFF090E4E);
  static const halka3 = Color(0xFF070B43);
  static const halka4 = Color(0xFF050938);

  // ---- color/marka (brand) ----
  static const yesil = Color(0xFF4DFF44); // success, confirm, online
  static const yesilKoyu = Color(0xFF39C831);
  static const yesilMurekkep = Color(0xFF051705); // text on green
  static const turuncu = Color(0xFFFFAD2B); // primary action, active tab
  static const turuncuKoyu = Color(0xFFDE6B08);
  static const altin = Color(0xFFFFC72B); // coins, trophies, first place
  static const kirmizi = Color(0xFFFF4444); // countdowns, VS, defeat

  // ---- color/beyaz ladder ----
  // 06-16 surfaces, 22-38 borders, 50-100 text.
  static const beyaz006 = Color(0x0FFFFFFF);
  static const beyaz012 = Color(0x1FFFFFFF);
  static const beyaz016 = Color(0x29FFFFFF);
  static const beyaz022 = Color(0x38FFFFFF);
  static const beyaz030 = Color(0x4DFFFFFF);
  static const beyaz038 = Color(0x61FFFFFF);
  static const beyaz050 = Color(0x80FFFFFF);
  static const beyaz065 = Color(0xA6FFFFFF);
  static const beyaz080 = Color(0xCCFFFFFF);
  static const beyaz100 = Color(0xFFFFFFFF);

  // ---- radius/* ----
  static const rTus = 11.0;
  static const rSm = 12.0;
  static const rMd = 16.0;
  static const rLg = 20.0;
  static const rXl = 24.0;
  static const r2xl = 30.0;

  // ---- space/* ----
  static const sHairline = 2.0;
  static const sXxs = 4.0;
  static const sXs = 6.0;
  static const sSm = 8.0;
  static const sMd = 10.0;
  static const sLg = 12.0;
  static const sXl = 14.0;
  static const s2xl = 20.0;

  /// Gap between the two Friend Match mode buttons. Not a `space/*` token —
  /// the frame puts them at y=190 and y=273 with a height of 63.748, which
  /// leaves 19.25, and snapping that to 20 visibly tightens the pair.
  static const lobbyTabGap = 19.0;

  // ---- type/* ----
  // 20 is its own step: it is the keyboard letter size and must not drift.
  static const t11 = 11.0;
  static const t13 = 13.0;
  static const t15 = 15.0;
  static const t17 = 17.0;
  static const t19 = 19.0;
  static const t20 = 20.0;
  static const t22 = 22.0;
  static const t24 = 24.0;
  static const t34 = 34.0;
  static const t40 = 40.0;
  static const t96 = 96.0;

  // ---- fonts ----
  static const fontUi = 'PoetsenOne';
  static const fontNumeral = 'Jaro';

  // ---- hard drop shadows (the design uses offset, zero-blur shadows) ----
  static const golgeTus = Color(0xFF4D579E); // white key, 0 3px 0
  static const golgeKoyuTus = Color(0xFF03051C); // dark key, 0 3px 0
  static const golgeGonder = Color(0xFF176B0F); // GÖNDER key, 0 4px 0
  static const golgeCubuk = Color(0xFF040629); // search bar / pills, 0 4px 0

  // ---- difficulty button fills ----
  // Radial, elliptical, at 82% opacity over zemin/derin. Straight from the
  // Seviye Seç frame; do not substitute a linear gradient, the falloff from
  // the centre is visible at 341x90.
  static const kolayStops = [Color(0xFF4DFF44), Color(0xFF39C831)];
  static const ortaStops = [
    Color(0xFFEA3235),
    Color(0xFFF55B20),
    Color(0xFFFF840A),
  ];
  static const zorStops = [Color(0xFFFF4444), Color(0xFFE83939)];

  /// Stretches a [RadialGradient] (built with `radius: 0.5`) into an ellipse
  /// that exactly fills its box horizontally — Figma's gradientTransform.
  /// A plain RadialGradient sizes off the SHORTEST side, which on a 341x90
  /// button would leave the fill as a small circle in the middle.
  static const wideRadial = _WideRadial();

  static BoxDecoration difficultyFill(List<Color> stops, double radius) {
    return BoxDecoration(
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(color: beyaz030),
      gradient: RadialGradient(
        radius: 0.5,
        transform: wideRadial,
        colors: [
          for (final c in stops) c.withValues(alpha: 0.82),
        ],
      ),
    );
  }

  // ---- gradients (endpoints are tokens) ----
  static const yesilGradient = RadialGradient(
    radius: 0.5,
    transform: wideRadial,
    colors: [yesil, yesilKoyu],
  );

  /// The violet fill behind the Friend Match panels and their tab buttons
  /// (Figma 51:471). Four stops, not two, and the middle pair carry most of
  /// the character — dropping to a two-stop gradient flattens it visibly.
  ///
  /// These are NOT in the `321 Tokens` collection: Figma cannot bind a
  /// variable to a gradient stop, and unlike the green and orange gradients
  /// this one's endpoints are not tokens either. Values read straight off the
  /// frame.
  static const morStops = [
    Color(0xFF8244FF),
    Color(0xFF5642CC),
    Color(0xFF3F40B3),
    Color(0xFF293F99),
  ];
  static const morStopPositions = [0.0, 0.5, 0.75, 1.0];

  /// The violet fill at a given opacity — 0.82 on the buttons, 0.49 on the
  /// big room panel.
  static RadialGradient morGradient(double opacity) => RadialGradient(
        radius: 0.5,
        transform: wideRadial,
        colors: [
          for (final c in morStops) c.withValues(alpha: opacity),
        ],
        stops: morStopPositions,
      );

  /// The orange fill on the guest's disabled `Başlatma Bekleniyor` button.
  static const turuncuGradient = RadialGradient(
    radius: 0.5,
    transform: wideRadial,
    colors: [turuncu, turuncuKoyu],
  );

  /// The design puts a soft `inset 0 4px 4px rgba(0,0,0,0.25)` on every one of
  /// these panels. Flutter has no inset shadow, so it is approximated with a
  /// short dark gradient along the top edge inside the same rounded rect —
  /// the same trick `turkish_keyboard.dart` uses for its top highlight, in
  /// reverse.
  static Widget insetTop(double radius) => IgnorePointer(
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(radius),
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Colors.black.withValues(alpha: 0.25),
                Colors.transparent,
              ],
              stops: const [0, 0.06],
            ),
          ),
        ),
      );

  static ThemeData theme() {
    return ThemeData(
      useMaterial3: true,
      scaffoldBackgroundColor: zeminAna,
      fontFamily: fontUi,
      colorScheme: const ColorScheme.dark(
        primary: turuncu,
        secondary: yesil,
        surface: zeminPanel,
        error: kirmizi,
      ),
      textTheme: const TextTheme(
        bodyMedium: TextStyle(color: beyaz080, fontSize: t15),
      ),
    );
  }
}

/// Figma writes elliptical radial gradients as a gradientTransform matrix.
/// Flutter's RadialGradient is always circular against the shortest side, so
/// this scales the X axis until the circle spans the full width of the box.
class _WideRadial extends GradientTransform {
  const _WideRadial();

  @override
  Matrix4? transform(Rect bounds, {TextDirection? textDirection}) {
    final centre = bounds.center;
    final scaleX = bounds.width / bounds.shortestSide;
    return Matrix4.identity()
      ..translateByDouble(centre.dx, centre.dy, 0, 1)
      ..scaleByDouble(scaleX, 1, 1, 1)
      ..translateByDouble(-centre.dx, -centre.dy, 0, 1);
  }
}
