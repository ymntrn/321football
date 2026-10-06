import 'package:flutter/material.dart';

import '../settings/app_settings.dart';
import '../theme/tokens.dart';
import '../widgets/app_chrome.dart';
import '../widgets/screen_background.dart';
import 'nav.dart';
import 'privacy_screen.dart';
import 'support_screen.dart';

/// `Ayarlar` (Figma 51:1088).
///
/// The frame has Müzik, SFX, Titreşim and a separate Bildirimler card. The
/// decision is sound on/off and haptics on/off, so the first card carries
/// two switches — `Ses` and `Titreşim` — and Bildirimler is left out (there
/// are no notifications). Gizlilik and Destek are drawn as in the frame and
/// open their own screens (92:270, 92:310).
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  /// Keep in step with `version:` in pubspec.yaml (the Figma frame's
  /// "V 1.0.2026" was placeholder text).
  static const version = 'V 1.0.0';

  @override
  Widget build(BuildContext context) {
    final s = AppSettings.instance;
    return Scaffold(
      body: ScreenBackground(
        child: Column(
          children: [
            Expanded(
              child: SafeArea(
                bottom: false,
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  child: Column(
                    children: [
                      Stack(
                        children: [
                          const Positioned(left: -9, top: 0, child: UndoButton()),
                          const Center(
                            child: Padding(
                              padding: EdgeInsets.only(top: 20),
                              child: ScreenTitle('Ayarlar'),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 30),
                      GlassPanel(
                        padding: const EdgeInsets.fromLTRB(28, 22, 28, 22),
                        child: Column(
                          children: [
                            _SwitchRow(
                              label: 'Ses',
                              value: s.sound,
                              onChanged: (on) async {
                                await s.setSound(on);
                                // Heard only when switching ON.
                                Sounds.play(Sfx.tap);
                              },
                            ),
                            const SizedBox(height: 28),
                            _SwitchRow(
                              label: 'Titreşim',
                              value: s.haptics,
                              onChanged: (on) async {
                                await s.setHaptics(on);
                                // Felt only when switching ON — the proof
                                // that the switch works both ways.
                                Haptics.selection();
                              },
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 17),
                      _LinkCard(
                        label: 'Gizlilik & Kullanım Şartları',
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute(builder: (_) => const PrivacyScreen()),
                        ),
                      ),
                      const SizedBox(height: 17),
                      _LinkCard(
                        label: 'Destek & İletişim',
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute(builder: (_) => const SupportScreen()),
                        ),
                      ),
                      const SizedBox(height: 30),
                      const Text(
                        version,
                        style: TextStyle(
                          fontFamily: T.fontUi,
                          fontSize: T.t13,
                          color: T.beyaz050,
                        ),
                      ),
                      const SizedBox(height: 20),
                    ],
                  ),
                ),
              ),
            ),
            const TabNavBar(current: NavTab.settings),
          ],
        ),
      ),
    );
  }
}

class _SwitchRow extends StatelessWidget {
  const _SwitchRow({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final ValueNotifier<bool> value;
  final Future<void> Function(bool) onChanged;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: value,
      builder: (context, on, _) => GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => onChanged(!on),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: const TextStyle(
                  fontFamily: T.fontUi,
                  fontSize: T.t24,
                  color: T.beyaz100,
                ),
              ),
            ),
            _Toggle(on: on),
          ],
        ),
      ),
    );
  }
}

/// The switch (53:428 + 53:430): a 65x35 grey pill, radius/md, a 2pt black
/// border, and a 35pt green knob on the right when on. Off moves the knob to
/// the left and greys it — the frame only draws the on state.
class _Toggle extends StatelessWidget {
  const _Toggle({required this.on});

  final bool on;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 65,
      height: 35,
      child: Stack(
        children: [
          Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(T.rMd),
              border: Border.all(color: Colors.black, width: 2),
              gradient: const LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0xFFD9D9D9), Color(0xFFD9D9D9), Color(0xFF737373)],
                stops: [0, 0.39423, 1],
              ),
            ),
          ),
          AnimatedAlign(
            duration: const Duration(milliseconds: 140),
            alignment: on ? Alignment.centerRight : Alignment.centerLeft,
            child: Container(
              width: 35,
              height: 35,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: on ? const Color(0xFF39C831) : const Color(0xFF9A9A9A),
                border: Border.all(color: Colors.black, width: 2),
                gradient: on
                    ? const RadialGradient(
                        colors: [T.yesil, T.yesilKoyu],
                      )
                    : null,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LinkCard extends StatelessWidget {
  const _LinkCard({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 72,
      child: GlassPanel(
        onTap: onTap,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: T.sLg),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                label,
                style: const TextStyle(
                  fontFamily: T.fontUi,
                  fontSize: T.t24,
                  color: T.beyaz100,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
