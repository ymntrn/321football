import 'package:flutter/material.dart';

import '../legal/legal_text.dart';
import '../theme/tokens.dart';
import '../widgets/app_chrome.dart';
import '../widgets/screen_background.dart';

/// `Gizlilik & Kullanım Şartları` (Figma 92:270).
///
/// As the frame: Undo, `Gizlilik & Şartlar` at type/34, the update date at
/// type/13, then one scrolling column of `Bölüm` cards (beyaz/006 fill,
/// beyaz/012 border, radius/lg, 16x14 padding, a type/17 heading over
/// type/13 body at a 20pt line) with the thin `Kaydırma` scrollbar.
///
/// Differences, all deliberate:
///  * The text is new (lib/legal/legal_text.dart) — it describes what the
///    app really stores; the frame's placeholder copy mentions Apple sign-in
///    and coin packs, neither of which exists.
///  * A `TASLAK` card leads the list until the text is reviewed.
///  * Two documents share the screen, so `GİZLİLİK POLİTİKASI` and
///    `KULLANIM ŞARTLARI` captions (the Destek frame's caption style)
///    separate them.
///  * Body text is PoetsenOne; M PLUS 1p is not bundled.
class PrivacyScreen extends StatelessWidget {
  const PrivacyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: ScreenBackground(
        child: SafeArea(
          child: Column(
            children: [
              const SubPageHeader(
                title: 'Gizlilik & Şartlar',
                subtitle: 'Son güncelleme: ${LegalText.lastUpdated}',
              ),
              const SizedBox(height: T.sLg),
              Expanded(
                child: RawScrollbar(
                  thumbColor: T.beyaz016,
                  thickness: 4,
                  radius: const Radius.circular(2),
                  thumbVisibility: true,
                  padding: const EdgeInsets.only(right: 10),
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 30),
                    children: [
                      const _DraftCard(),
                      const SizedBox(height: T.s2xl),
                      const SectionCaption('GİZLİLİK POLİTİKASI',
                          color: T.beyaz050),
                      const SizedBox(height: T.sSm),
                      for (final s in LegalText.privacy) ...[
                        LegalCard(section: s),
                        const SizedBox(height: T.sLg),
                      ],
                      const SizedBox(height: T.sSm),
                      const SectionCaption('KULLANIM ŞARTLARI',
                          color: T.beyaz050),
                      const SizedBox(height: T.sSm),
                      for (final s in LegalText.terms) ...[
                        LegalCard(section: s),
                        const SizedBox(height: T.sLg),
                      ],
                    ],
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

/// `Bölüm/...` (98:194): a heading over a paragraph.
class LegalCard extends StatelessWidget {
  const LegalCard({super.key, required this.section});

  final LegalSection section;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: T.beyaz006,
        borderRadius: BorderRadius.circular(T.rLg),
        border: Border.all(color: T.beyaz012),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            section.title,
            style: const TextStyle(
              fontFamily: T.fontUi,
              fontSize: T.t17,
              color: T.beyaz100,
            ),
          ),
          const SizedBox(height: T.sXs),
          Text(
            section.body,
            style: const TextStyle(
              fontFamily: T.fontUi,
              fontSize: T.t13,
              height: 20 / 13,
              color: T.beyaz050,
            ),
          ),
        ],
      ),
    );
  }
}

/// Not in the frame: the text is a draft until a lawyer has read it.
class _DraftCard extends StatelessWidget {
  const _DraftCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: T.turuncu.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(T.rLg),
        border: Border.all(color: T.turuncu, width: 1.5),
      ),
      child: const Text(
        LegalText.draftNotice,
        style: TextStyle(
          fontFamily: T.fontUi,
          fontSize: T.t13,
          height: 20 / 13,
          color: T.turuncu,
        ),
      ),
    );
  }
}
