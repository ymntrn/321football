import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The Titreşim switch must turn off EVERY vibration. That holds only while
/// all of them go through `Haptics` in lib/settings/app_settings.dart, so a
/// raw HapticFeedback call anywhere else under lib/ fails this test.
void main() {
  test('no HapticFeedback call bypasses the Titreşim setting', () {
    final offenders = <String>[];
    for (final f in Directory('lib').listSync(recursive: true)) {
      if (f is! File || !f.path.endsWith('.dart')) continue;
      if (f.path.replaceAll('\\', '/').endsWith('settings/app_settings.dart')) {
        continue;
      }
      final lines = f.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        if (lines[i].contains('HapticFeedback.')) {
          offenders.add('${f.path}:${i + 1}');
        }
      }
    }
    expect(offenders, isEmpty);
  });
}
