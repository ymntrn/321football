import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:football321/screens/match_board_screen.dart';
import 'package:football321/theme/tokens.dart';
import 'package:football321/widgets/match_chrome.dart';

/// Layout smoke tests for the PvP screens.
///
/// These do NOT prove a screen looks right — only the emulator does that —
/// but they catch the two layout bugs this project has already shipped once:
/// a widget that collapses to its text, and a fixed height that overflows
/// when the keyboard is up. Any RenderFlex overflow fails the test.
///
/// The real fonts are loaded so text is measured at its true size; the test
/// default (Ahem) would make every label a different width.
///
/// Only states that need no database are pumped. Typing on the board fires a
/// suggestion query, and sqflite does not run under `flutter test`.
Future<void> _loadFonts() async {
  for (final (family, file) in [
    (T.fontUi, 'assets/fonts/PoetsenOne-Regular.ttf'),
    (T.fontNumeral, 'assets/fonts/Jaro-Regular.ttf'),
  ]) {
    final bytes = File(file).readAsBytesSync();
    final loader = FontLoader(family)
      ..addFont(Future.value(ByteData.sublistView(bytes)));
    await loader.load();
  }
}

/// Phones to check: the 430x932 design frame, the Pixel 6 the emulator runs,
/// and a small 360x640 Android.
const _sizes = [Size(430, 932), Size(411, 914), Size(360, 640)];

Future<void> _pumpAt(WidgetTester tester, Size size, Widget child) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(theme: T.theme(), home: child));
  await tester.pump(const Duration(milliseconds: 300));
}

void main() {
  setUpAll(_loadFonts);

  for (final size in _sizes) {
    testWidgets('board idle state lays out at ${size.width}x${size.height}', (
      tester,
    ) async {
      final now = DateTime.now();
      await _pumpAt(
        tester,
        size,
        MatchBoardScreen(
          playerName: 'Oyuncuadı1',
          opponentName: 'Oyuncuadı2',
          playerScore: 2,
          opponentScore: 1,
          clubAId: 1,
          clubAName: 'Borussia Mönchengladbach',
          clubBId: 2,
          clubBName: 'FC Barcelona',
          unlockAt: now,
          deadline: now.add(const Duration(seconds: 10)),
          answerSeconds: 10,
          opponentFound: false,
          onCorrect: (_, __) async {},
        ),
      );
      expect(tester.takeException(), isNull);
      expect(find.text('10'), findsOneWidget);
      expect(find.text('yazıyor'), findsOneWidget);
      expect(find.text('GÖNDER'), findsOneWidget);

      // Full-width strips must not shrink to their contents.
      final strip = tester.getSize(find.byType(LiveStatusStrip));
      expect(strip.width, greaterThan(size.width - 2 * T.s2xl - 1));

      // Let the clock run out so the 200 ms ticker is cancelled.
      await tester.pump(const Duration(seconds: 11));
    });
  }

  testWidgets('compact matchup strip survives long names at 360', (
    tester,
  ) async {
    await _pumpAt(
      tester,
      const Size(360, 640),
      const Scaffold(
        body: Padding(
          padding: EdgeInsets.symmetric(horizontal: T.s2xl),
          child: Center(
            child: CompactMatchupStrip(
              clubA: 'Borussia Mönchengladbach',
              clubB: 'Wolverhampton Wanderers FC',
            ),
          ),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
    expect(
      tester.getSize(find.byType(CompactMatchupStrip)).width,
      360 - 2 * T.s2xl,
    );
  });
}
