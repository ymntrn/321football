import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:football321/settings/app_settings.dart';

/// Every sound effect must have its file, and the folder must be bundled -
/// otherwise Sounds.play fails silently on the device and nobody notices.
void main() {
  test('every Sfx has a non-empty file under assets/', () {
    final missing = <String>[];
    for (final sfx in Sfx.values) {
      final f = File('assets/${Sounds.assetFor(sfx)}');
      if (!f.existsSync() || f.lengthSync() < 44) missing.add('$sfx -> ${f.path}');
    }
    expect(missing, isEmpty);
  });

  test('every Sfx maps to its own file', () {
    final paths = Sfx.values.map(Sounds.assetFor).toSet();
    expect(paths.length, Sfx.values.length);
  });

  test('assets/audio/ is listed in pubspec.yaml', () {
    expect(File('pubspec.yaml').readAsStringSync(), contains('- assets/audio/'));
  });

  test('the sound files stay small', () {
    var total = 0;
    for (final sfx in Sfx.values) {
      total += File('assets/${Sounds.assetFor(sfx)}').lengthSync();
    }
    expect(total, lessThan(400 * 1024));
  });

  test('no audio package is used outside Sounds', () {
    final offenders = <String>[];
    for (final f in Directory('lib').listSync(recursive: true)) {
      if (f is! File || !f.path.endsWith('.dart')) continue;
      if (f.path.replaceAll('\\', '/').endsWith('settings/app_settings.dart')) {
        continue;
      }
      if (f.readAsStringSync().contains('package:audioplayers')) {
        offenders.add(f.path);
      }
    }
    expect(offenders, isEmpty);
  });
}
