import 'package:flutter/material.dart';

import '../widgets/app_chrome.dart';
import 'leaderboard_screen.dart';
import 'profile_screen.dart';
import 'settings_screen.dart';

/// The bottom nav's one routing rule.
///
/// The frames give every nav screen the `Undo` arrow and no home icon, so
/// Ana Sayfa stays at the bottom of the stack: from Ana Sayfa a tab is
/// pushed, and from one tab to another the current tab is REPLACED — Undo
/// therefore always lands back on Ana Sayfa rather than walking back
/// through every tab visited.
Future<void> openTab(
  BuildContext context,
  NavTab tab, {
  bool fromTab = false,
}) async {
  final Widget screen;
  switch (tab) {
    case NavTab.leaderboard:
      screen = const LeaderboardScreen();
    case NavTab.settings:
      screen = const SettingsScreen();
    case NavTab.profile:
      screen = const ProfileScreen();
    case NavTab.shop:
      // The shop waits on art (out of scope). The icon stays as drawn.
      showToast(context, 'Mağaza yakında');
      return;
  }
  final route = MaterialPageRoute<void>(builder: (_) => screen);
  final nav = Navigator.of(context);
  if (fromTab) {
    await nav.pushReplacement(route);
  } else {
    await nav.push(route);
  }
}

/// The nav bar as a tab screen uses it.
class TabNavBar extends StatelessWidget {
  const TabNavBar({super.key, this.current});

  final NavTab? current;

  @override
  Widget build(BuildContext context) => BottomNavBar(
        current: current,
        onTap: (tab) => openTab(context, tab, fromTab: true),
      );
}
