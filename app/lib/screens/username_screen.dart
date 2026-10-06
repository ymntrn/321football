import 'package:flutter/material.dart';

import '../models/profile.dart';
import '../net/account.dart';
import '../net/identity.dart';
import '../theme/tokens.dart';
import '../widgets/app_chrome.dart';
import '../widgets/screen_background.dart';
import 'home_screen.dart';

/// `Kullanıcı Adı Oluştur` (Figma 92:190) and its typing state (94:190).
///
/// First launch only. The name is stored on the device before anything
/// touches the network, so this works offline too; the server issues the
/// tag on the next boot that reaches Supabase.
class UsernameScreen extends StatefulWidget {
  const UsernameScreen({super.key});

  @override
  State<UsernameScreen> createState() => _UsernameScreenState();
}

class _UsernameScreenState extends State<UsernameScreen> {
  final TextEditingController _field = TextEditingController();
  bool _busy = false;
  String? _tag;

  bool get _valid => Profile.validUsername(_field.text.trim());

  @override
  void dispose() {
    _field.dispose();
    super.dispose();
  }

  Future<void> _continue() async {
    if (!_valid || _busy) return;
    setState(() => _busy = true);
    await Account.instance.chooseUsername(_field.text.trim());
    if (!mounted) return;
    // Show the tag the server just issued for a moment — it is the half of
    // the identity the player did not choose, and the frame shows it here.
    final tag = Identity.instance.tag;
    if (tag != null) {
      setState(() => _tag = tag);
      await Future<void>.delayed(const Duration(milliseconds: 900));
      if (!mounted) return;
    }
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const HomeScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final typed = _field.text.trim();
    final typing = typed.isNotEmpty;
    final valid = _valid;

    return Scaffold(
      resizeToAvoidBottomInset: true,
      body: ScreenBackground(
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Column(
              children: [
                // The frame puts the wordmark centre at y=167 idle and
                // moves the whole stack up 72pt while typing (94:199).
                SizedBox(height: typing ? 20 : 70),
                const Text(
                  '321',
                  style: TextStyle(
                    fontFamily: T.fontNumeral,
                    fontSize: T.t96,
                    color: Color(0xFFFF9C1A),
                    height: 1.1,
                  ),
                ),
                const Text(
                  'FOOTBALL CHALLENGE',
                  style: TextStyle(
                    fontFamily: T.fontUi,
                    fontSize: T.t15,
                    color: T.beyaz065,
                    letterSpacing: 2.1,
                  ),
                ),
                SizedBox(height: typing ? 40 : 70),
                const Text(
                  'HOŞ GELDİN!',
                  style: TextStyle(
                    fontFamily: T.fontUi,
                    fontSize: T.t34,
                    color: T.beyaz100,
                  ),
                ),
                const SizedBox(height: T.sLg),
                const SizedBox(
                  width: 340,
                  child: Text(
                    'Kendine bir kullanıcı adı seç. Etiketin otomatik '
                    'oluşturulur ve birlikte hesap kimliğini oluşturur.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontFamily: T.fontUi,
                      fontSize: T.t13,
                      color: T.beyaz050,
                      height: 21 / 13,
                    ),
                  ),
                ),
                const SizedBox(height: 40),
                const Align(
                  alignment: Alignment.centerLeft,
                  child: SectionCaption('KULLANICI ADI', color: T.beyaz050),
                ),
                const SizedBox(height: 9),
                PanelTextField(
                  controller: _field,
                  hint: 'Kullanıcı adın',
                  maxLength: 16,
                  onChanged: (_) => setState(() {}),
                  onSubmitted: (_) => _continue(),
                  trailing: valid ? const OkDisc() : null,
                ),
                const SizedBox(height: 20),
                _TagPreview(tag: _tag, live: valid),
                const SizedBox(height: 20),
                Text(
                  valid
                      ? 'Bu kullanıcı adı uygun'
                      : '3–16 karakter · harf, rakam ve _',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: T.fontUi,
                    fontSize: T.t13,
                    color: valid
                        ? T.yesil.withValues(alpha: 0.85)
                        : (typing ? T.kirmizi.withValues(alpha: 0.8) : T.beyaz038),
                  ),
                ),
                const SizedBox(height: 28),
                WideButton(
                  label: 'DEVAM ET',
                  tone: WideButtonTone.orange,
                  onTap: valid && !_busy ? _continue : null,
                ),
                const SizedBox(height: 36),
                const SizedBox(
                  width: 340,
                  child: Text(
                    'Kullanıcı adın + etiketin senin oyun kimliğindir.\n'
                    'Arkadaşların seni bu kimlikle ekler.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontFamily: T.fontUi,
                      fontSize: T.t13,
                      color: T.beyaz038,
                      height: 19 / 13,
                    ),
                  ),
                ),
                const SizedBox(height: 24),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// `Etiket Önizleme` (93:197 / 94:206): "Etiketin #••••" until the server
/// has issued the tag, then the tag in green.
class _TagPreview extends StatelessWidget {
  const _TagPreview({required this.tag, required this.live});

  final String? tag;
  final bool live;

  @override
  Widget build(BuildContext context) {
    final has = tag != null;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
      decoration: BoxDecoration(
        color: T.beyaz006,
        borderRadius: BorderRadius.circular(T.rLg),
        border: Border.all(
          color: live || has ? T.yesil.withValues(alpha: 0.5) : T.beyaz022,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'Etiketin',
            style: TextStyle(
              fontFamily: T.fontUi,
              fontSize: T.t13,
              color: T.beyaz050,
            ),
          ),
          const SizedBox(width: T.sSm),
          Text(
            has ? '#$tag' : '#••••',
            style: TextStyle(
              fontFamily: T.fontUi,
              fontSize: T.t17,
              color: has ? T.yesil : T.beyaz038,
            ),
          ),
        ],
      ),
    );
  }
}
