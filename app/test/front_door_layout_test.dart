import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:football321/net/identity.dart';
import 'package:football321/screens/friends_screen.dart';
import 'package:football321/screens/home_screen.dart';
import 'package:football321/screens/leaderboard_screen.dart';
import 'package:football321/screens/match_end_screens.dart';
import 'package:football321/screens/matchmaking_screen.dart';
import 'package:football321/screens/profile_screen.dart';
import 'package:football321/screens/settings_screen.dart';
import 'package:football321/screens/username_screen.dart';
import 'package:football321/settings/app_settings.dart';
import 'package:football321/theme/tokens.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Overflow tests for the front-door screens, at the design frame, the
/// Pixel 6 and a small Android. They prove nothing about how a screen looks
/// (the emulator does that) — only that nothing overflows, which is the bug
/// a widget sized to its text or a fixed-height panel produces.
///
/// No backend is reachable here (Supabase is never initialised), so every
/// online screen renders its offline state: the same path a phone with no
/// signal takes.
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

const _sizes = [Size(430, 932), Size(411, 914), Size(360, 640)];

Future<void> _pumpAt(WidgetTester tester, Size size, Widget child) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(theme: T.theme(), home: child));
  await tester.pump(const Duration(milliseconds: 300));
  await tester.pump(const Duration(milliseconds: 300));
}

void main() {
  setUpAll(() async {
    await _loadFonts();
    SharedPreferences.setMockInitialValues({'username': 'Yaman', 'tag': '7K2M'});
    await Identity.load();
    await AppSettings.instance.load();
  });

  final screens = <String, Widget Function()>{
    'username': () => const UsernameScreen(),
    'home': () => const HomeScreen(),
    'leaderboard': () => const LeaderboardScreen(),
    'profile': () => const ProfileScreen(),
    'settings': () => const SettingsScreen(),
    'friends': () => const FriendsScreen(),
    'matchmaking': () => const MatchmakingScreen(),
    'ranked win': () => MatchResultScreen(
          won: true,
          playerName: 'Oyuncuadı1',
          opponentName: 'Oyuncuadı2',
          playerScore: 3,
          opponentScore: 0,
          summary: MatchSummary.empty,
          onHome: () {},
          onRematch: () {},
          ranked: true,
          trophyDelta: 30,
          coinDelta: 10,
        ),
    'ranked loss': () => MatchResultScreen(
          won: false,
          playerName: 'Oyuncuadı1',
          opponentName: 'Oyuncuadı2',
          playerScore: 1,
          opponentScore: 3,
          summary: MatchSummary.empty,
          onHome: () {},
          onRematch: () {},
          ranked: true,
          trophyDelta: -20,
          coinDelta: 2,
        ),
  };

  for (final entry in screens.entries) {
    for (final size in _sizes) {
      testWidgets('${entry.key} lays out at ${size.width}x${size.height}',
          (tester) async {
        await _pumpAt(tester, size, entry.value());
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets('home shows the three modes and the nav', (tester) async {
    await _pumpAt(tester, _sizes[1], const HomeScreen());
    expect(find.text('Hemen Oyna'), findsOneWidget);
    expect(find.text('Alıştırma Yap'), findsOneWidget);
    expect(find.text('Arkadaş Maçı'), findsOneWidget);
  });

  testWidgets('settings: switching haptics off persists', (tester) async {
    await _pumpAt(tester, _sizes[1], const SettingsScreen());
    expect(AppSettings.instance.haptics.value, isTrue);
    await tester.tap(find.text('Titreşim'));
    await tester.pump();
    expect(AppSettings.instance.haptics.value, isFalse);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('settings_haptics'), isFalse);
    await tester.tap(find.text('Titreşim'));
    await tester.pump();
    expect(AppSettings.instance.haptics.value, isTrue);
  });
}
