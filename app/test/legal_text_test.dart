import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:football321/legal/legal_text.dart';

/// docs/privacy-policy.md is the copy hosted for the Play Console; the app
/// shows lib/legal/legal_text.dart. They must say the same things.
void main() {
  final doc = File('../docs/privacy-policy.md').readAsStringSync();

  test('every privacy section in the app is in docs/privacy-policy.md', () {
    final missing = [
      for (final s in LegalText.privacy)
        if (!doc.contains('## ${s.title}')) s.title,
    ];
    expect(missing, isEmpty);
  });

  test('the hosted policy carries the same date, contact and draft mark', () {
    expect(doc, contains(LegalText.lastUpdated));
    expect(doc, contains(SupportConfig.email));
    expect(doc, contains('TASLAK'));
  });

  test('the policy names what is really stored', () {
    final all = LegalText.privacy.map((s) => s.body).join('\n');
    for (final word in [
      'Anonim hesap kimliği',
      'etiket',
      'kupa',
      'altın',
      'Arkadaşlık',
      'Maç odaları',
      'Supabase',
      'AdMob',
      'Hesabımı sil',
    ]) {
      expect(all, contains(word), reason: word);
    }
  });
}
