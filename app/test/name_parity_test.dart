import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:football321/data/name_normalizer.dart';

/// The Dart normalizer must agree with the Python one that produced every
/// `normalized_*` column in the shipped database. If it drifts, real answers
/// stop matching and the player is told "we don't have that player" about
/// someone we plainly do have.
///
/// The fixture is exported straight out of assets/db/321_football.db by
/// tools/export_name_fixture.py, so this is checked against ground truth
/// rather than against hand-written expectations.
void main() {
  test('normalizeName matches the database values', () {
    final file = File('test/fixtures/name_parity.tsv');
    expect(
      file.existsSync(),
      isTrue,
      reason: 'Run tools/export_name_fixture.py to generate the fixture.',
    );

    final lines = file.readAsLinesSync().where((l) => l.isNotEmpty);
    final samples = <String>[];
    var mismatches = 0;
    var checked = 0;

    for (final line in lines) {
      final parts = line.split('\t');
      if (parts.length != 2) continue;
      final raw = parts[0];
      final expected = parts[1];
      final actual = normalizeName(raw);
      checked++;
      if (actual != expected) {
        mismatches++;
        if (samples.length < 20) {
          samples.add('  "$raw"  python="$expected"  dart="$actual"');
        }
      }
    }

    expect(checked, greaterThan(30000), reason: 'fixture looks truncated');

    if (mismatches > 0) {
      fail('$mismatches of $checked names normalize differently '
          '(first ${samples.length} shown):\n${samples.join('\n')}');
    }
  });

  test('the cases names.py calls out by hand', () {
    expect(normalizeName('Wesley Sneijder'), 'wesley sneijder');
    expect(normalizeName('Mesut Özil'), 'mesut ozil');
    expect(normalizeName('İlkay Gündoğan'), 'ilkay gundogan');
    expect(normalizeName("N'Golo Kanté"), 'ngolo kante');
    expect(normalizeName('Gheorghe Hagi '), 'gheorghe hagi');
    expect(normalizeName('Hakan Şükür'), 'hakan sukur');
    expect(normalizeName(''), '');
    expect(normalizeName(null), '');
  });

  test('every casing of the same name folds together', () {
    for (final variant in ['Özil', 'OZIL', 'ozil', 'özil', 'Ozil']) {
      expect(normalizeName(variant), 'ozil', reason: 'variant: $variant');
    }
  });

  test('surnameKey takes the last token', () {
    expect(surnameKey('Wesley Sneijder'), 'sneijder');
    expect(surnameKey('Ronaldinho'), 'ronaldinho');
    expect(surnameKey(''), '');
  });
}
