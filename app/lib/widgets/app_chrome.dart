import 'package:flutter/material.dart';

import '../theme/tokens.dart';
import 'match_chrome.dart' show playerInitials;
import 'screen_background.dart' show UndoButton;

/// The furniture shared by the front-door screens: Ana Sayfa (4:4), the
/// leaderboards (51:567, 51:860), Profil (53:469), Ayarlar (51:1088),
/// Arkadaşlar (92:230 / 97:190), the username screen (92:190) and
/// Maç Aranıyor (12:95).

/// A Figma export from assets/img/, with a stand-in when the file is not
/// there yet. The cloud session that built these screens could not reach
/// figma.com, so every new export is listed in tools/fetch_assets.ps1 and
/// fetched on the PC — until then the screen still works, it just shows
/// [fallback] in the slot.
class FigmaAsset extends StatelessWidget {
  const FigmaAsset(
    this.name, {
    super.key,
    required this.width,
    required this.height,
    required this.fallback,
    this.fit = BoxFit.contain,
  });

  final String name;
  final double width;
  final double height;
  final Widget fallback;
  final BoxFit fit;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      height: height,
      child: Image.asset(
        'assets/img/$name',
        width: width,
        height: height,
        fit: fit,
        errorBuilder: (_, __, ___) => Center(child: fallback),
      ),
    );
  }
}

/// The two places the trophy (`Trophy`) and coin (`coin 1`) exports are drawn.
class TrophyIcon extends StatelessWidget {
  const TrophyIcon({super.key, this.width = 20.3, this.height = 24});
  final double width;
  final double height;

  @override
  Widget build(BuildContext context) => FigmaAsset(
        'trophy.png',
        width: width,
        height: height,
        fallback: Text('🏆', style: TextStyle(fontSize: height * 0.75)),
      );
}

class CoinIcon extends StatelessWidget {
  const CoinIcon({super.key, this.size = 26});
  final double size;

  @override
  Widget build(BuildContext context) =>
      Image.asset('assets/img/coin.png', width: size, height: size);
}

/// `Points` on Ana Sayfa (8:7 / 46:502): zemin/panel, beyaz/038 border,
/// radius/lg, 34 tall, an icon and a bold number.
class StatChip extends StatelessWidget {
  const StatChip({super.key, required this.icon, required this.value});

  final Widget icon;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 34,
      padding: const EdgeInsets.fromLTRB(6, 0, 12, 0),
      decoration: BoxDecoration(
        color: T.zeminPanel,
        borderRadius: BorderRadius.circular(T.rLg),
        border: Border.all(color: T.beyaz038),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          icon,
          const SizedBox(width: T.sXxs),
          Text(
            value,
            style: const TextStyle(
              fontFamily: T.fontUi,
              fontSize: T.t17,
              color: T.beyaz100,
            ),
          ),
        ],
      ),
    );
  }
}

/// "4.820" — Turkish thousands separator, as the leaderboard frames write it.
String formatThousands(int n) {
  final s = n.abs().toString();
  final b = StringBuffer(n < 0 ? '-' : '');
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) b.write('.');
    b.write(s[i]);
  }
  return b.toString();
}

/// Which bottom-nav slot a screen is.
enum NavTab { leaderboard, shop, settings, profile }

/// `Menubar` (8:16): 430x93, #0649A2, top corners 25, four 40pt icons at
/// x = 37 / 146 / 255 / 350 on the 430 frame.
class BottomNavBar extends StatelessWidget {
  const BottomNavBar({super.key, required this.onTap, this.current});

  final void Function(NavTab tab) onTap;

  /// The tab this screen is, if any. The frames draw all four icons alike,
  /// so this only stops a tap from re-opening the same screen.
  final NavTab? current;

  static const fill = Color(0xFF0649A2);
  static const height = 93.0;

  static const _slots = <(NavTab, String, IconData, double)>[
    (NavTab.leaderboard, 'nav_leaderboard.png', Icons.leaderboard_rounded, 37),
    (NavTab.shop, 'nav_shop.png', Icons.storefront_rounded, 146),
    (NavTab.settings, 'nav_settings.png', Icons.settings_rounded, 255),
    (NavTab.profile, 'nav_person.png', Icons.person_rounded, 350),
  ];

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    return Container(
      height: height + bottomInset * 0.5,
      decoration: const BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.vertical(top: Radius.circular(25)),
      ),
      child: LayoutBuilder(
        builder: (context, box) {
          final sx = box.maxWidth / 430;
          return Stack(
            children: [
              for (final (tab, asset, icon, x) in _slots)
                Positioned(
                  left: x * sx - 10,
                  top: 22 - 10,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: tab == current ? null : () => onTap(tab),
                    child: Padding(
                      padding: const EdgeInsets.all(10),
                      child: FigmaAsset(
                        asset,
                        width: 40,
                        height: 40,
                        fallback: Icon(icon, size: 36, color: T.beyaz100),
                      ),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

/// The big menu buttons on Ana Sayfa (`Gender/Default`, 46:487, 46:490):
/// a radial fill, beyaz/030 border, radius/lg, the inset top shadow, and a
/// type/34 label. Full width — never sized to the label.
class MenuButton extends StatelessWidget {
  const MenuButton({
    super.key,
    required this.label,
    required this.gradient,
    required this.height,
    this.onTap,
    this.fontSize = 32,
  });

  final String label;
  final Gradient gradient;
  final double height;
  final VoidCallback? onTap;
  final double fontSize;

  /// Hemen Oyna — #EA3235 → #F55B1F → #FF840A at 84%.
  static final hemenOyna = RadialGradient(
    radius: 0.5,
    transform: T.wideRadial,
    colors: [
      for (final c in const [
        Color(0xFFEA3235),
        Color(0xFFF55B1F),
        Color(0xFFFF840A),
      ])
        c.withValues(alpha: 0.84),
    ],
    stops: const [0, 0.5, 1],
  );

  /// Alıştırma Yap — green, the first stop held to 21.6%.
  static final alistirma = RadialGradient(
    radius: 0.5,
    transform: T.wideRadial,
    colors: [
      T.yesil.withValues(alpha: 0.82),
      T.yesilKoyu.withValues(alpha: 0.82),
    ],
    stops: const [0.21635, 1],
  );

  /// Arkadaş Maçı — #765AFF → #6145E5 → #4C2FCB.
  static const arkadas = RadialGradient(
    radius: 0.5,
    transform: T.wideRadial,
    colors: [Color(0xFF765AFF), Color(0xFF6145E5), Color(0xFF4C2FCB)],
    stops: [0.21635, 0.60817, 1],
  );

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        height: height,
        width: double.infinity,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(T.rLg),
          border: Border.all(color: T.beyaz030),
          gradient: gradient,
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
                  style: TextStyle(
                    fontFamily: T.fontUi,
                    fontSize: fontSize,
                    color: T.beyaz100,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The translucent violet cards of Ayarlar and Profil (53:414, 53:527):
/// the Friend Match violet at 28%, beyaz/030 border, radius/lg, inset top.
class GlassPanel extends StatelessWidget {
  const GlassPanel({super.key, required this.child, this.padding, this.onTap});

  final Widget child;
  final EdgeInsetsGeometry? padding;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final panel = Container(
      width: double.infinity,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(T.rLg),
        border: Border.all(color: T.beyaz030),
        gradient: T.morGradient(0.28),
      ),
      child: Stack(
        children: [
          Positioned.fill(child: T.insetTop(T.rLg)),
          Padding(padding: padding ?? EdgeInsets.zero, child: child),
        ],
      ),
    );
    if (onTap == null) return panel;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: panel,
    );
  }
}

/// The wide primary buttons: `Buton/Devam Et` (93:201, orange) and
/// `Buton/Arkadaş Ekle` (95:202, green). 390 wide on the frame, radius/xl,
/// beyaz/038 border, a hard 5pt shadow (blur 0).
class WideButton extends StatelessWidget {
  const WideButton({
    super.key,
    required this.label,
    required this.tone,
    this.onTap,
    this.leading,
    this.fontSize = T.t24,
  });

  final String label;
  final WideButtonTone tone;
  final VoidCallback? onTap;
  final String? leading;
  final double fontSize;

  static const _orange = RadialGradient(
    radius: 0.5,
    transform: T.wideRadial,
    colors: [Color(0xFFFFAD29), Color(0xFFEE8C18), Color(0xFFDE6B08)],
    stops: [0, 0.5, 1],
  );

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    final orange = tone == WideButtonTone.orange;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Opacity(
        // 93:201 draws the disabled DEVAM ET at 45%.
        opacity: enabled ? 1 : 0.45,
        child: Container(
          width: double.infinity,
          padding: EdgeInsets.symmetric(vertical: orange ? 18 : 15),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(T.rXl),
            border: Border.all(color: T.beyaz038, width: 1.5),
            gradient: orange ? _orange : T.yesilGradient,
            boxShadow: [
              BoxShadow(
                color: orange ? const Color(0xFF803D05) : T.golgeGonder,
                offset: const Offset(0, 5),
                blurRadius: 0,
              ),
            ],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (leading != null) ...[
                Text(
                  leading!,
                  style: const TextStyle(
                    fontFamily: T.fontUi,
                    fontSize: T.t24,
                    color: T.beyaz100,
                  ),
                ),
                const SizedBox(width: T.sMd),
              ],
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    label,
                    style: TextStyle(
                      fontFamily: T.fontUi,
                      fontSize: fontSize,
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

enum WideButtonTone { orange, green }

/// A square avatar with initials: zemin/avatar, radius scaled to size.
class InitialsAvatar extends StatelessWidget {
  const InitialsAvatar({
    super.key,
    required this.name,
    required this.size,
    required this.radius,
    this.border = T.beyaz022,
    this.borderWidth = 1,
    this.fontSize,
    this.single = true,
  });

  final String name;
  final double size;
  final double radius;
  final Color border;
  final double borderWidth;
  final double? fontSize;

  /// The leaderboard and friends frames show one letter; the match screens
  /// use [playerInitials].
  final bool single;

  @override
  Widget build(BuildContext context) {
    final trimmed = name.trim();
    final text = single
        ? (trimmed.isEmpty ? '?' : trimmed.characters.first.toUpperCase())
        : playerInitials(name);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: T.zeminAvatar,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: border, width: borderWidth),
      ),
      alignment: Alignment.center,
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Text(
          text,
          style: TextStyle(
            fontFamily: T.fontUi,
            fontSize: fontSize ?? size * 0.42,
            color: T.beyaz100,
          ),
        ),
      ),
    );
  }
}

/// One player row from the leaderboards and the friends list (106:193,
/// 96:192): beyaz/006 fill, beyaz/012 border, radius/lg, then
/// [leading] · avatar · name over #tag · [trailing].
class PlayerRow extends StatelessWidget {
  const PlayerRow({
    super.key,
    required this.name,
    required this.tag,
    this.leading,
    this.trailing = const [],
    this.highlight = false,
    this.avatarSize = 36,
    this.padding = const EdgeInsets.fromLTRB(10, 8, 12, 8),
    this.medal,
  });

  final String name;
  final String tag;
  final Widget? leading;
  final List<Widget> trailing;

  /// The player's own row: `Sen/4` (118:38) — #3340D9 → #1A1F8C, a 2pt
  /// green border, the rank in green.
  final bool highlight;
  final double avatarSize;
  final EdgeInsets padding;

  /// Gold / silver / bronze for the Global podium (105:196).
  final Color? medal;

  static const _youFrom = Color(0xFF3340D9);
  static const _youTo = Color(0xFF1A1F8C);

  @override
  Widget build(BuildContext context) {
    final BoxDecoration deco;
    if (highlight) {
      deco = BoxDecoration(
        borderRadius: BorderRadius.circular(T.rLg),
        border: Border.all(color: T.yesil.withValues(alpha: 0.8), width: 2),
        gradient: const LinearGradient(colors: [_youFrom, _youTo]),
      );
    } else if (medal != null) {
      deco = BoxDecoration(
        borderRadius: BorderRadius.circular(T.rLg),
        border: Border.all(color: medal!.withValues(alpha: 0.65), width: 1.5),
        gradient: LinearGradient(colors: [
          medal!.withValues(alpha: 0.28),
          medal!.withValues(alpha: 0.06),
        ]),
      );
    } else {
      deco = BoxDecoration(
        color: T.beyaz006,
        borderRadius: BorderRadius.circular(T.rLg),
        border: Border.all(color: T.beyaz012),
      );
    }

    return Container(
      width: double.infinity,
      padding: padding,
      decoration: deco,
      child: Row(
        children: [
          if (leading != null) ...[leading!, const SizedBox(width: T.sMd)],
          InitialsAvatar(
            name: name,
            size: avatarSize,
            radius: avatarSize >= 42 ? T.rMd : T.rSm,
            border: medal != null
                ? medal!.withValues(alpha: 0.8)
                : highlight
                    ? T.beyaz050
                    : T.beyaz022,
            borderWidth: medal != null ? 1.5 : 1,
            fontSize: avatarSize >= 42 ? T.t19 : (avatarSize >= 40 ? T.t17 : T.t15),
          ),
          const SizedBox(width: T.sMd),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontFamily: T.fontUi,
                    fontSize: T.t17,
                    color: T.beyaz100,
                  ),
                ),
                const SizedBox(height: T.sHairline),
                Text(
                  '#$tag',
                  maxLines: 1,
                  style: const TextStyle(
                    fontFamily: T.fontUi,
                    fontSize: T.t11,
                    color: T.beyaz050,
                  ),
                ),
              ],
            ),
          ),
          for (final w in trailing) ...[const SizedBox(width: T.sMd), w],
        ],
      ),
    );
  }
}

/// The rank column of a row: 34 wide (30 on Arkadaş), centred, type/17.
class RankCell extends StatelessWidget {
  const RankCell(this.rank, {super.key, this.mine = false, this.width = 34});

  final int rank;
  final bool mine;
  final double width;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Text(
          '$rank',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontFamily: T.fontUi,
            fontSize: T.t17,
            color: mine ? T.yesil : T.beyaz050,
          ),
        ),
      ),
    );
  }
}

/// The small spaced caps label over a list (`4 – 100. SIRA`, `ARKADAŞLARIN`).
class SectionCaption extends StatelessWidget {
  const SectionCaption(this.text, {super.key, this.color = T.beyaz038});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: TextStyle(
        fontFamily: T.fontUi,
        fontSize: T.t13,
        color: color,
        letterSpacing: 1.04,
      ),
    );
  }
}

/// A square icon button the friends rows use (`Meydan Oku`, 96:202):
/// 38pt, radius/sm, green when it is an action, quiet otherwise.
class RowIconButton extends StatelessWidget {
  const RowIconButton({
    super.key,
    required this.glyph,
    required this.onTap,
    this.active = false,
  });

  final String glyph;
  final VoidCallback? onTap;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(
          color: active ? T.yesil.withValues(alpha: 0.9) : T.beyaz012,
          borderRadius: BorderRadius.circular(T.rSm),
          border: Border.all(color: active ? T.beyaz038 : T.beyaz016),
        ),
        alignment: Alignment.center,
        child: Text(
          glyph,
          style: TextStyle(
            fontFamily: T.fontUi,
            fontSize: T.t17,
            color: active ? T.yesilMurekkep : T.beyaz065,
          ),
        ),
      ),
    );
  }
}

/// The input field of the username screen and the Arkadaş Ekle popup
/// (93:195, 97:309): zemin/panel, radius/lg, beyaz/038 idle and beyaz/080
/// while focused, hard 4pt shadow, type/22 PoetsenOne.
///
/// Uses the SYSTEM keyboard, deliberately: the custom Turkish keyboard has
/// no digits, no `_` and no `#`, and both a username ("harf, rakam ve _")
/// and a friend's `Kerem_07#B3D2` need them. Same reasoning as the room-code
/// entry in friend_match_screen.dart.
class PanelTextField extends StatefulWidget {
  const PanelTextField({
    super.key,
    required this.controller,
    required this.hint,
    this.onChanged,
    this.onSubmitted,
    this.trailing,
    this.height = 64,
    this.fontSize = T.t22,
    this.autofocus = false,
    this.maxLength,
    this.textInputAction = TextInputAction.done,
  });

  final TextEditingController controller;
  final String hint;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final Widget? trailing;
  final double height;
  final double fontSize;
  final bool autofocus;
  final int? maxLength;
  final TextInputAction textInputAction;

  @override
  State<PanelTextField> createState() => _PanelTextFieldState();
}

class _PanelTextFieldState extends State<PanelTextField> {
  final FocusNode _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _focus.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final focused = _focus.hasFocus;
    return Container(
      height: widget.height,
      width: double.infinity,
      decoration: BoxDecoration(
        color: T.zeminPanel,
        borderRadius: BorderRadius.circular(T.rLg),
        border: Border.all(
          color: focused ? T.beyaz080 : T.beyaz038,
          width: focused ? 2.5 : 1.5,
        ),
        boxShadow: const [
          BoxShadow(color: T.golgeCubuk, offset: Offset(0, 4), blurRadius: 0),
        ],
      ),
      padding: const EdgeInsets.only(left: 19.5, right: 12),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: widget.controller,
              focusNode: _focus,
              autofocus: widget.autofocus,
              autocorrect: false,
              enableSuggestions: false,
              maxLength: widget.maxLength,
              textInputAction: widget.textInputAction,
              cursorColor: T.yesil,
              cursorWidth: 2.5,
              onChanged: widget.onChanged,
              onSubmitted: widget.onSubmitted,
              style: TextStyle(
                fontFamily: T.fontUi,
                fontSize: widget.fontSize,
                color: T.beyaz100,
              ),
              decoration: InputDecoration(
                counterText: '',
                border: InputBorder.none,
                isDense: true,
                hintText: widget.hint,
                hintStyle: TextStyle(
                  fontFamily: T.fontUi,
                  fontSize: widget.fontSize,
                  color: T.beyaz038,
                ),
              ),
            ),
          ),
          if (widget.trailing != null) widget.trailing!,
        ],
      ),
    );
  }
}

/// The green ✓ disc in the username field (94:214, `Uygun`).
class OkDisc extends StatelessWidget {
  const OkDisc({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 30,
      height: 30,
      decoration: const BoxDecoration(color: T.yesil, shape: BoxShape.circle),
      alignment: Alignment.center,
      child: const Text(
        '✓',
        style: TextStyle(
          fontFamily: T.fontUi,
          fontSize: T.t17,
          color: T.yesilMurekkep,
        ),
      ),
    );
  }
}

/// `Arkadaş Ekle Popup` (97:306): #1C26B8 → #0B0E57, 2pt beyaz/038 border,
/// radius/2xl, a deep soft drop shadow, a type/24 title. Used for adding a
/// friend and for editing the username on Profil.
class AppPopup extends StatelessWidget {
  const AppPopup({super.key, required this.title, required this.children});

  final String title;
  final List<Widget> children;

  /// Shows [popup] over the 75% `Karartma` scrim (97:305).
  static Future<R?> show<R>(BuildContext context, Widget popup) {
    return showGeneralDialog<R>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'kapat',
      barrierColor: const Color(0xBF030314),
      pageBuilder: (context, _, __) => SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: EdgeInsets.only(
              left: 27,
              right: 27,
              bottom: MediaQuery.viewInsetsOf(context).bottom,
            ),
            child: Material(type: MaterialType.transparency, child: popup),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(18, 26, 18, 20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(T.r2xl),
        border: Border.all(color: T.beyaz038, width: 2),
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF1C26B8), Color(0xFF0B0E57)],
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.55),
            offset: const Offset(0, 16),
            blurRadius: 40,
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontFamily: T.fontUi,
              fontSize: T.t24,
              color: T.beyaz100,
            ),
          ),
          for (final c in children) ...[const SizedBox(height: T.sXl), c],
        ],
      ),
    );
  }
}

/// `Buton/Kapat` (97:320): beyaz/012, beyaz/030 border, radius/lg, full width.
class QuietButton extends StatelessWidget {
  const QuietButton({super.key, required this.label, this.onTap});

  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: T.beyaz012,
          borderRadius: BorderRadius.circular(T.rLg),
          border: Border.all(color: T.beyaz030, width: 1.5),
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: const TextStyle(
            fontFamily: T.fontUi,
            fontSize: T.t17,
            color: T.beyaz080,
          ),
        ),
      ),
    );
  }
}

/// `Buton/Ekle` (97:318): a small green pill.
class SmallGoButton extends StatelessWidget {
  const SmallGoButton({super.key, required this.label, this.onTap});

  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Opacity(
        opacity: onTap == null ? 0.45 : 1,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
          decoration: BoxDecoration(
            color: T.yesil,
            borderRadius: BorderRadius.circular(T.rMd),
            border: Border.all(color: T.beyaz038),
          ),
          child: Text(
            label,
            style: const TextStyle(
              fontFamily: T.fontUi,
              fontSize: T.t15,
              color: T.yesilMurekkep,
            ),
          ),
        ),
      ),
    );
  }
}

/// A screen title at type/40 (`Global`, `Profil`, `Ayarlar`, `Arkadaşlar`).
class ScreenTitle extends StatelessWidget {
  const ScreenTitle(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) {
    return FittedBox(
      fit: BoxFit.scaleDown,
      child: Text(
        text,
        style: const TextStyle(
          fontFamily: T.fontUi,
          fontSize: T.t40,
          color: T.beyaz100,
        ),
      ),
    );
  }
}

/// The top of the sub-pages Gizlilik (92:270) and Destek (92:310): Undo
/// at the top-left, a centred type/34 title, and an optional type/13 line
/// under it in beyaz/038.
class SubPageHeader extends StatelessWidget {
  const SubPageHeader({super.key, required this.title, this.subtitle});

  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        const Positioned(left: 5, top: -9, child: UndoButton()),
        Padding(
          padding: const EdgeInsets.fromLTRB(60, 18, 60, 0),
          child: Center(
            child: Column(
              children: [
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    title,
                    style: const TextStyle(
                      fontFamily: T.fontUi,
                      fontSize: T.t34,
                      color: T.beyaz100,
                    ),
                  ),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: T.sXs),
                  Text(
                    subtitle!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontFamily: T.fontUi,
                      fontSize: T.t13,
                      color: T.beyaz038,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// A one-line message at the foot of the screen.
void showToast(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        backgroundColor: T.zeminPanel,
        duration: const Duration(seconds: 2),
        content: Text(message, style: const TextStyle(fontFamily: T.fontUi)),
      ),
    );
}
