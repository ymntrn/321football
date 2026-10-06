import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../models/profile.dart';
import '../net/account.dart';
import '../net/identity.dart';
import '../theme/tokens.dart';
import '../widgets/app_chrome.dart';
import '../widgets/screen_background.dart';
import 'match_end_screens.dart' show formatSeconds;
import 'nav.dart';

/// `Profil` (Figma 53:469).
///
/// Differences from the frame, all deliberate:
///  * The coin balance sits beside the trophies — the decisions put coins on
///    the profile and the frame has no slot for them.
///  * `Şu Anki Seri` carries the best streak as a second line, for the same
///    reason.
///  * The avatar is the initials on the frame's #2200CF square until the
///    avatar art lands.
///  * `Apple ile Giriş Yap` is Apple's own button asset, shown exactly as
///    exported and DISABLED (real sign-in comes later). Never restyle it.
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  @override
  void initState() {
    super.initState();
    Account.instance.refresh();
  }

  Future<void> _edit(Profile p) async {
    await AppPopup.show<void>(context, _RenamePopup(current: p.username));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: ScreenBackground(
        child: Column(
          children: [
            Expanded(
              child: SafeArea(
                bottom: false,
                child: ValueListenableBuilder<Profile?>(
                  valueListenable: Account.instance.profile,
                  builder: (context, p, _) => SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(20, 0, 18, 20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Stack(
                          children: [
                            const Positioned(
                              left: -15,
                              top: 0,
                              child: UndoButton(),
                            ),
                            const Center(
                              child: Padding(
                                padding: EdgeInsets.only(top: 20),
                                child: ScreenTitle('Profil'),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: T.sMd),
                        _Header(profile: p, onEdit: p == null ? null : () => _edit(p)),
                        const SizedBox(height: 46),
                        const _AppleButton(),
                        const SizedBox(height: 38),
                        _Stats(profile: p),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            const TabNavBar(current: NavTab.profile),
          ],
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.profile, required this.onEdit});

  final Profile? profile;
  final VoidCallback? onEdit;

  @override
  Widget build(BuildContext context) {
    final p = profile;
    final name = p?.username ?? Identity.instance.name;
    final tag = p?.tag ?? Identity.instance.tag;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // `Ava 1` (53:506): 146pt, radius 36, #2200CF.
        Container(
          width: 146,
          height: 146,
          decoration: BoxDecoration(
            color: const Color(0xFF2200CF),
            borderRadius: BorderRadius.circular(36),
            border: Border.all(color: T.beyaz030),
          ),
          alignment: Alignment.center,
          child: Text(
            name.isEmpty ? '?' : name.characters.first.toUpperCase(),
            style: const TextStyle(
              fontFamily: T.fontUi,
              fontSize: 64,
              color: T.beyaz100,
            ),
          ),
        ),
        const SizedBox(width: 13),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(
                        name,
                        style: const TextStyle(
                          fontFamily: T.fontUi,
                          fontSize: T.t34,
                          color: T.beyaz100,
                        ),
                      ),
                    ),
                  ),
                  _Tap(
                    onTap: onEdit,
                    child: const FigmaAsset(
                      'pencil.png',
                      width: 24,
                      height: 24,
                      fallback: Icon(Icons.edit, size: 22, color: T.beyaz100),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: T.sXs),
              Row(
                children: [
                  Expanded(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(
                        tag == null ? '#••••' : '#$tag',
                        style: const TextStyle(
                          fontFamily: T.fontUi,
                          fontSize: T.t24,
                          color: T.beyaz100,
                        ),
                      ),
                    ),
                  ),
                  if (tag != null) ...[
                    _Tap(
                      onTap: () async {
                        await Clipboard.setData(
                          ClipboardData(text: '$name#$tag'),
                        );
                        if (context.mounted) {
                          showToast(context, 'Kimliğin kopyalandı');
                        }
                      },
                      child: Image.asset(
                        'assets/img/copy.png',
                        width: 29,
                        height: 27,
                      ),
                    ),
                    const SizedBox(width: 3),
                    _Tap(
                      onTap: () => SharePlus.instance.share(
                        ShareParams(
                          text: '321 Football\'da beni ekle: $name#$tag',
                        ),
                      ),
                      child: Image.asset(
                        'assets/img/share.png',
                        width: 31,
                        height: 27,
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: T.sSm),
              Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: T.sXs,
                runSpacing: T.sXs,
                children: [
                  Text(
                    p == null ? '–' : '${p.trophies}',
                    style: const TextStyle(
                      fontFamily: T.fontUi,
                      fontSize: T.t34,
                      color: T.beyaz100,
                    ),
                  ),
                  const TrophyIcon(width: 37, height: 45),
                  const SizedBox(width: T.sSm),
                  StatChip(
                    icon: const CoinIcon(),
                    value: p == null ? '–' : '${p.coins}',
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Tap extends StatelessWidget {
  const _Tap({required this.child, this.onTap});
  final Widget child;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Padding(padding: const EdgeInsets.all(2), child: child),
      );
}

/// `image 9` (53:582): Apple's official "Apple ile Giriş Yap" button,
/// 385x56, exactly as exported. Disabled until real sign-in exists — it is
/// dimmed by opacity only, never redrawn or recoloured.
class _AppleButton extends StatelessWidget {
  const _AppleButton();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Opacity(
        opacity: 0.45,
        child: IgnorePointer(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Image.asset(
              'assets/img/apple_signin.png',
              width: 385,
              height: 56,
              fit: BoxFit.contain,
              // Until tools/fetch_assets.ps1 has run, the slot stays empty
              // rather than showing an imitation of Apple's button.
              errorBuilder: (_, __, ___) =>
                  const SizedBox(width: 385, height: 56),
            ),
          ),
        ),
      ),
    );
  }
}

class _Stats extends StatelessWidget {
  const _Stats({required this.profile});

  final Profile? profile;

  @override
  Widget build(BuildContext context) {
    final p = profile;
    final fastest = p?.fastestAnswerMs;
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _StatCard(
                icon: 'stat_matches.png',
                fallback: '🏟',
                iconWidth: 56,
                iconHeight: 42,
                label: 'Toplam Maç',
                value: p == null ? '–' : '${p.matchesPlayed}',
              ),
            ),
            const SizedBox(width: 19),
            Expanded(
              child: _StatCard(
                icon: 'stat_winrate.png',
                fallback: '🥇',
                iconWidth: 32,
                iconHeight: 52,
                label: 'Kazanma Oranı',
                value: p == null ? '–' : '%${p.winRatePercent}',
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),
        Row(
          children: [
            Expanded(
              child: _StatCard(
                icon: 'stat_streak.png',
                fallback: '🔥',
                iconWidth: 45,
                iconHeight: 43,
                label: 'Şu Anki Seri',
                value: p == null ? '–' : '${p.currentStreak}',
                sub: p == null ? null : 'En iyi: ${p.bestStreak}',
              ),
            ),
            const SizedBox(width: 19),
            Expanded(
              child: _StatCard(
                icon: 'stat_fastest.png',
                fallback: '⚡',
                iconWidth: 49,
                iconHeight: 54,
                label: 'En Hızlı Cevap',
                value: fastest == null ? '–' : formatSeconds(fastest),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// One of the four 180x150 cards (53:527 …): icon top-left, a two-line
/// type/20 label beside it, the value at type/40 below.
class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.icon,
    required this.fallback,
    required this.iconWidth,
    required this.iconHeight,
    required this.label,
    required this.value,
    this.sub,
  });

  final String icon;
  final String fallback;
  final double iconWidth;
  final double iconHeight;
  final String label;
  final String value;
  final String? sub;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 150,
      child: GlassPanel(
        padding: const EdgeInsets.fromLTRB(18, 13, 10, 8),
        child: Column(
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                FigmaAsset(
                  icon,
                  width: iconWidth,
                  height: iconHeight,
                  fit: BoxFit.cover,
                  fallback: Text(fallback, style: const TextStyle(fontSize: 30)),
                ),
                const SizedBox(width: T.sMd),
                Expanded(
                  child: Text(
                    label,
                    maxLines: 2,
                    style: const TextStyle(
                      fontFamily: T.fontUi,
                      fontSize: T.t20,
                      color: T.beyaz100,
                      height: 1.15,
                    ),
                  ),
                ),
              ],
            ),
            Expanded(
              child: Center(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    value,
                    style: const TextStyle(
                      fontFamily: T.fontUi,
                      fontSize: T.t40,
                      color: T.beyaz100,
                    ),
                  ),
                ),
              ),
            ),
            if (sub != null)
              Text(
                sub!,
                style: const TextStyle(
                  fontFamily: T.fontUi,
                  fontSize: T.t13,
                  color: T.beyaz050,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Editing the username, in the Arkadaş Ekle popup's shell (97:306). The
/// tag is shown but cannot be changed.
class _RenamePopup extends StatefulWidget {
  const _RenamePopup({required this.current});

  final String current;

  @override
  State<_RenamePopup> createState() => _RenamePopupState();
}

class _RenamePopupState extends State<_RenamePopup> {
  late final TextEditingController _field =
      TextEditingController(text: widget.current);
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _field.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _field.text.trim();
    if (name == widget.current) {
      Navigator.of(context).pop();
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await Account.instance.rename(name);
      if (mounted) Navigator.of(context).pop();
    } on AccountException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final valid = Profile.validUsername(_field.text.trim());
    final tag = Identity.instance.tag;
    return AppPopup(
      title: 'KULLANICI ADI',
      children: [
        Text(
          tag == null
              ? '3–16 karakter · harf, rakam ve _'
              : 'Etiketin #$tag değişmez · 3–16 karakter · harf, rakam ve _',
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontFamily: T.fontUi,
            fontSize: T.t13,
            color: T.beyaz050,
          ),
        ),
        PanelTextField(
          controller: _field,
          hint: 'Kullanıcı adın',
          height: 58,
          fontSize: T.t20,
          autofocus: true,
          maxLength: 16,
          onChanged: (_) => setState(() => _error = null),
          onSubmitted: (_) => _save(),
          trailing: valid ? const OkDisc() : null,
        ),
        if (_error != null)
          Text(
            _error!,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontFamily: T.fontUi,
              fontSize: T.t13,
              color: T.kirmizi,
            ),
          ),
        WideButton(
          label: 'KAYDET',
          tone: WideButtonTone.green,
          fontSize: T.t22,
          onTap: valid && !_busy ? _save : null,
        ),
        QuietButton(label: 'KAPAT', onTap: () => Navigator.of(context).pop()),
      ],
    );
  }
}
