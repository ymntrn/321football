import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:football321/screens/match_board_screen.dart';
import 'package:football321/screens/match_end_screens.dart';
import 'package:football321/screens/match_versus_screen.dart';
import 'package:football321/models/models.dart';
import 'package:football321/widgets/practice_chrome.dart';
import 'package:football321/widgets/search_bar_panel.dart';
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

  for (final size in _sizes) {
    testWidgets('versus lays out at ${size.width}x${size.height}', (
      tester,
    ) async {
      await _pumpAt(
        tester,
        size,
        const MatchVersusScreen(
          playerName: 'Oyuncuadı1',
          opponentName: 'Oyuncuadı2',
          targetGoals: 3,
        ),
      );
      expect(tester.takeException(), isNull);
      expect(find.text('ARKADAŞ MAÇI · İLK 3 GOL'), findsOneWidget);
      expect(find.text('Oyuncuadı2'), findsOneWidget);
    });
  }

  for (final size in _sizes) {
    testWidgets('GOOOL lays out at ${size.width}x${size.height}', (
      tester,
    ) async {
      await _pumpAt(
        tester,
        size,
        MatchGoalScreen(
          playerName: 'Oyuncuadı1',
          opponentName: 'Oyuncuadı2',
          playerScore: 1,
          opponentScore: 0,
          scorerName: 'Oyuncuadı1',
          scorerIsMe: true,
          answer: 'Wesley Sneijder',
          elapsedMs: 1400,
          clubs: const {1: 'Inter', 2: 'Galatasaray'},
          since: DateTime.now(),
          hold: const Duration(milliseconds: 2500),
        ),
      );
      expect(tester.takeException(), isNull);
      expect(find.text('Oyuncuadı1 buldu'), findsOneWidget);
      expect(find.text('1,4 sn'), findsOneWidget);
      await tester.pump(const Duration(seconds: 3));
    });

    testWidgets('Tur Bitti lays out at ${size.width}x${size.height}', (
      tester,
    ) async {
      await _pumpAt(
        tester,
        size,
        MatchRoundVoidScreen(
          playerName: 'Oyuncuadı1',
          opponentName: 'Oyuncuadı2',
          playerScore: 0,
          opponentScore: 0,
          unplayable: false,
          clubAId: 1,
          clubBId: 2,
          since: DateTime.now(),
          hold: const Duration(milliseconds: 2500),
        ),
      );
      expect(tester.takeException(), isNull);
      expect(find.text('Puan yok'), findsOneWidget);
      await tester.pump(const Duration(seconds: 3));
    });

    for (final won in [true, false]) {
      testWidgets(
        '${won ? 'win' : 'lose'} lays out at ${size.width}x${size.height}',
        (tester) async {
          await _pumpAt(
            tester,
            size,
            MatchResultScreen(
              won: won,
              playerName: 'Oyuncuadı1',
              opponentName: 'Oyuncuadı2',
              playerScore: won ? 3 : 0,
              opponentScore: won ? 0 : 3,
              summary: const MatchSummary(
                fastestMs: 1400,
                correct: 3,
                rounds: 4,
                bestStreak: 2,
              ),
              note: won ? 'Rakip ayrıldı' : null,
              onRematch: () {},
              onHome: () {},
            ),
          );
          expect(tester.takeException(), isNull);
          expect(find.text('Tekrar Oyna'), findsOneWidget);
          expect(find.text('3/4'), findsOneWidget);
        },
      );
    }
  }

  // ---- Practice popups ------------------------------------------------
  const sneijder = Player(id: 1, displayName: 'Wesley Sneijder');
  const clubs = {1: 'Inter', 2: 'Galatasaray'};

  for (final size in _sizes) {
    testWidgets('Doğru popup lays out at ${size.width}x${size.height}', (
      tester,
    ) async {
      await _pumpAt(
        tester,
        size,
        Scaffold(
          body: Stack(
            children: [
              const Positioned(
                left: 20,
                right: 20,
                bottom: 260,
                child: ConfirmedSearchBar(name: 'Wesley Sneijder'),
              ),
              Positioned.fill(
                child: CorrectAnswerOverlay(
                  player: sneijder,
                  clubs: clubs,
                  onDone: () {},
                ),
              ),
            ],
          ),
        ),
      );
      expect(tester.takeException(), isNull);
      expect(find.text('DOĞRU!'), findsOneWidget);
      expect(find.text('+1 SERİ'), findsOneWidget);
      await tester.pump(const Duration(seconds: 3));
    });

    testWidgets('Cevap Onayı lays out at ${size.width}x${size.height}', (
      tester,
    ) async {
      await _pumpAt(
        tester,
        size,
        Scaffold(
          body: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: T.sLg),
              child: RevealConfirmPopup(
                cost: 3,
                onCancel: () {},
                onConfirm: () {},
              ),
            ),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
      expect(find.text('3 ALTIN HARCA'), findsOneWidget);
    });

    testWidgets('Cevabı Göster lays out at ${size.width}x${size.height}', (
      tester,
    ) async {
      await _pumpAt(
        tester,
        size,
        Scaffold(
          body: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: T.sLg),
              child: RevealAnswersPopup(
                // Far more answers than fit: the list must scroll, not
                // overflow the card.
                players: [
                  for (var i = 0; i < 30; i++)
                    Player(id: i, displayName: 'Oyuncu Numara $i'),
                ],
                clubs: clubs,
                cost: 3,
                onContinue: () {},
              ),
            ),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
      expect(find.text('DEVAM'), findsOneWidget);
    });
  }
}
