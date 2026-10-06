import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../data/app_database.dart';
import '../legal/legal_text.dart';
import '../net/identity.dart';
import '../theme/tokens.dart';
import '../widgets/app_chrome.dart';
import '../widgets/screen_background.dart';
import 'settings_screen.dart';

/// `Destek & İletişim` (Figma 92:310).
///
/// As the frame: `SIKÇA SORULAN SORULAR` — an accordion of `SSS` cards (the
/// open one on beyaz/012 with a beyaz/022 border and `−`, closed ones on
/// beyaz/006 / beyaz/012 with `+`) — then `BİZE ULAŞ`: the blue
/// `İletişim Kartı` with the e-mail row (tap copies it) and the orange
/// `SORUN BİLDİR` (opens the mail app, pre-filled), then the
/// `Kimlik · Sürüm · Veri` line.
///
/// Differences, all deliberate:
///  * Answers are real; the frame only writes the first one.
///  * The fourth question reads `Altınlarım kayboldu` without "satın alma
///    gelmedi": there are no purchases.
///  * `SORUN BİLDİR` is the shared [WideButton] (radius/xl, 18pt padding)
///    rather than a one-off copy at radius/lg, 14pt.
///  * `Veri:` shows the bundled database version (AppDatabase.assetVersion).
///  * Body text is PoetsenOne; M PLUS 1p is not bundled.
class SupportScreen extends StatelessWidget {
  const SupportScreen({super.key, this.footer});

  /// Extra content under the contact card (the account deletion action).
  final Widget? footer;

  static const faq = <LegalSection>[
    LegalSection(
      'Bir futbolcu neden kabul edilmedi?',
      'Cevaplar tam ad veya kayıtlı takma adla eşleşmelidir; yakın yazımlar '
          'kabul edilmez. Çok yaygın soyadlarını tek başına yazarsan hangi '
          'oyuncuyu kastettiğin anlaşılmaz — adını da yaz.',
    ),
    LegalSection(
      'Eksik bir transfer buldum, ne yapmalıyım?',
      'Transfer arşivi Wikidata\'dan derleniyor. SORUN BİLDİR ile '
          'futbolcunun ve kulübün adını yaz; bir sonraki veri güncellemesinde '
          'düzeltiriz.',
    ),
    LegalSection(
      'Kupa puanları nasıl hesaplanıyor?',
      'Yalnızca Hemen Oyna (sıralı maç) kupa verir: galibiyet +30, '
          'mağlubiyet −20 (kupan 0\'ın altına inmez). Arkadaş Maçı '
          'istatistiklerine sayılır ama kupa ve altın vermez. Eşleştirme önce '
          '±100 kupa içinde rakip arar ve aralığı her 5 saniyede 100 '
          'genişletir.',
    ),
    LegalSection(
      'Altınlarım kayboldu',
      'Altın sıralı maçlardan gelir (galibiyet +10, mağlubiyet +2; '
          'galibiyetten sonra 2X Altın reklamıyla bir kez ikiye katlanır) ve '
          'Alıştırma\'da Cevap için harcanır (3 altın). Bakiyen sunucuda, '
          'hesabında tutulur: uygulamayı silip yeniden yüklersen yeni bir '
          'hesap açılır ve eski bakiye eski hesapta kalır. Başka bir sorun '
          'görürsen kullanıcı adın ve etiketinle SORUN BİLDİR.',
    ),
    LegalSection(
      'Hesabımı nasıl silerim?',
      'Bu ekranın en altındaki "Hesabımı sil" ile. Onayladığında profilin, '
          'istatistiklerin, kupa ve altınların ve arkadaşlıkların hemen ve '
          'kalıcı olarak silinir; geri alınamaz.',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: ScreenBackground(
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.only(bottom: 30),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SubPageHeader(title: 'Destek & İletişim'),
                const SizedBox(height: 20),
                const Padding(
                  padding: EdgeInsets.only(left: 24),
                  child: SectionCaption('SIKÇA SORULAN SORULAR',
                      color: T.beyaz050),
                ),
                const SizedBox(height: T.sSm),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 20),
                  child: _Faq(items: faq),
                ),
                const SizedBox(height: 26),
                const Padding(
                  padding: EdgeInsets.only(left: 24),
                  child: SectionCaption('BİZE ULAŞ', color: T.beyaz050),
                ),
                const SizedBox(height: T.sSm),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 20),
                  child: _ContactCard(),
                ),
                const SizedBox(height: 22),
                Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Text(
                      'Kimlik: ${Identity.instance.handle}   ·   '
                      'Sürüm: ${SettingsScreen.version}   ·   '
                      'Veri: v${AppDatabase.assetVersion}',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontFamily: T.fontUi,
                        fontSize: T.t11,
                        color: T.beyaz038,
                      ),
                    ),
                  ),
                ),
                if (footer != null) ...[
                  const SizedBox(height: 30),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: footer!,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// `SSS` (99:192): one question open at a time; the first starts open, as
/// drawn.
class _Faq extends StatefulWidget {
  const _Faq({required this.items});

  final List<LegalSection> items;

  @override
  State<_Faq> createState() => _FaqState();
}

class _FaqState extends State<_Faq> {
  int? _open = 0;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (var i = 0; i < widget.items.length; i++) ...[
          if (i > 0) const SizedBox(height: T.sSm),
          _FaqCard(
            item: widget.items[i],
            open: _open == i,
            onTap: () => setState(() => _open = _open == i ? null : i),
          ),
        ],
      ],
    );
  }
}

class _FaqCard extends StatelessWidget {
  const _FaqCard({required this.item, required this.open, required this.onTap});

  final LegalSection item;
  final bool open;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
        decoration: BoxDecoration(
          color: open ? T.beyaz012 : T.beyaz006,
          borderRadius: BorderRadius.circular(T.rLg),
          border: Border.all(color: open ? T.beyaz022 : T.beyaz012),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    item.title,
                    style: const TextStyle(
                      fontFamily: T.fontUi,
                      fontSize: T.t15,
                      color: T.beyaz100,
                    ),
                  ),
                ),
                const SizedBox(width: T.sMd),
                Text(
                  open ? '−' : '+',
                  style: const TextStyle(
                    fontFamily: T.fontUi,
                    fontSize: T.t20,
                    color: T.beyaz050,
                  ),
                ),
              ],
            ),
            if (open) ...[
              const SizedBox(height: T.sSm),
              Text(
                item.body,
                style: const TextStyle(
                  fontFamily: T.fontUi,
                  fontSize: T.t13,
                  height: 20 / 13,
                  color: T.beyaz050,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// `İletişim Kartı` (99:215): a #2933C7 → #171C80 card, radius/xl, the
/// e-mail row and SORUN BİLDİR.
class _ContactCard extends StatelessWidget {
  const _ContactCard();

  Future<void> _copy(BuildContext context) async {
    await Clipboard.setData(const ClipboardData(text: SupportConfig.email));
    if (context.mounted) showToast(context, 'E-posta adresi kopyalandı');
  }

  /// Opens the mail app with the player's id and the version filled in.
  /// Without a mail app, copies the address instead.
  Future<void> _report(BuildContext context) async {
    final uri = Uri(
      scheme: 'mailto',
      path: SupportConfig.email,
      query: _query({
        'subject': '321 Football — Sorun bildirimi',
        'body': '\n\n---\nKimlik: ${Identity.instance.handle}\n'
            'Sürüm: ${SettingsScreen.version} · Veri: v${AppDatabase.assetVersion}',
      }),
    );
    var opened = false;
    try {
      opened = await launchUrl(uri);
    } catch (_) {
      opened = false;
    }
    if (!opened && context.mounted) await _copy(context);
  }

  /// mailto wants %20, not the + that Uri.queryParameters would write.
  static String _query(Map<String, String> params) => params.entries
      .map((e) => '${e.key}=${Uri.encodeComponent(e.value)}')
      .join('&');

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(T.rXl),
        border: Border.all(color: T.beyaz030, width: 1.5),
        gradient: const LinearGradient(
          colors: [Color(0xFF2933C7), Color(0xFF171C80)],
        ),
      ),
      child: Column(
        children: [
          GestureDetector(
            onTap: () => _copy(context),
            behavior: HitTestBehavior.opaque,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
              decoration: BoxDecoration(
                color: T.beyaz012,
                borderRadius: BorderRadius.circular(T.rMd),
                border: Border.all(color: T.beyaz022),
              ),
              child: const Row(
                children: [
                  Text(
                    '✉',
                    style: TextStyle(fontSize: T.t17, color: T.beyaz080),
                  ),
                  SizedBox(width: T.sMd),
                  Expanded(
                    child: Text(
                      SupportConfig.email,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontFamily: T.fontUi,
                        fontSize: T.t15,
                        color: T.beyaz100,
                      ),
                    ),
                  ),
                  SizedBox(width: T.sMd),
                  Text(
                    'kopyala',
                    style: TextStyle(
                      fontFamily: T.fontUi,
                      fontSize: T.t11,
                      color: T.beyaz038,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: T.sLg),
          WideButton(
            label: 'SORUN BİLDİR',
            tone: WideButtonTone.orange,
            fontSize: T.t19,
            onTap: () => _report(context),
          ),
        ],
      ),
    );
  }
}
