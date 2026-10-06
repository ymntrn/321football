import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../models/profile.dart';
import '../net/account.dart';
import '../net/social_repository.dart';
import '../theme/tokens.dart';
import '../widgets/app_chrome.dart';
import '../widgets/screen_background.dart';
import 'dev_menu_screen.dart';
import 'friend_match_screen.dart';
import 'friends_screen.dart';
import 'matchmaking_screen.dart';
import 'nav.dart';
import 'practice_difficulty_screen.dart';

/// `Ana Sayfa` (Figma 4:4) — coins, trophies, the friends button, the three
/// modes, and the bottom nav.
///
/// The dev menu is no longer on the launch path. In DEBUG builds only, a
/// long press on the coin chip still opens it.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _requests = 0;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  /// Coins, trophies and the friend-request badge change while the player
  /// is elsewhere (a match, the friends screen), so they are re-read every
  /// time Ana Sayfa comes back into view.
  Future<void> _refresh() async {
    await Account.instance.refresh();
    final n = await SocialRepository.instance.incomingRequestCount();
    if (mounted) setState(() => _requests = n);
  }

  Future<void> _open(Widget screen) async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));
    if (mounted) _refresh();
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final inset = width * 40 / 430;

    return Scaffold(
      body: ScreenBackground(
        glowCentre: const Offset(218, 227.5),
        child: Column(
          children: [
            SafeArea(
              bottom: false,
              child: Padding(
                padding: EdgeInsets.fromLTRB(width * 33 / 430, 12, width * 32 / 430, 0),
                child: ValueListenableBuilder<Profile?>(
                  valueListenable: Account.instance.profile,
                  builder: (context, p, _) => Row(
                    children: [
                      GestureDetector(
                        onLongPress: kDebugMode
                            ? () => _open(const DevMenuScreen())
                            : null,
                        child: StatChip(
                          icon: const CoinIcon(),
                          value: p == null ? '–' : '${p.coins}',
                        ),
                      ),
                      const Spacer(),
                      StatChip(
                        icon: const Padding(
                          padding: EdgeInsets.only(left: 4),
                          child: TrophyIcon(),
                        ),
                        value: p == null ? '–' : '${p.trophies}',
                      ),
                      SizedBox(width: width * 36 / 430),
                      _FriendsButton(
                        requests: _requests,
                        onTap: () => _open(const FriendsScreen()),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const Spacer(flex: 5),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: inset),
              child: Column(
                children: [
                  MenuButton(
                    label: 'Hemen Oyna',
                    gradient: MenuButton.hemenOyna,
                    height: 95,
                    onTap: () => _open(const MatchmakingScreen()),
                  ),
                  const SizedBox(height: 18),
                  MenuButton(
                    label: 'Alıştırma Yap',
                    gradient: MenuButton.alistirma,
                    height: 71,
                    fontSize: T.t34,
                    onTap: () => _open(const PracticeDifficultyScreen()),
                  ),
                  const SizedBox(height: 17),
                  MenuButton(
                    label: 'Arkadaş Maçı',
                    gradient: MenuButton.arkadas,
                    height: 66,
                    onTap: () => _open(const FriendMatchScreen()),
                  ),
                ],
              ),
            ),
            const Spacer(flex: 2),
            BottomNavBar(
              onTap: (tab) async {
                await openTab(context, tab);
                if (mounted) _refresh();
              },
            ),
          ],
        ),
      ),
    );
  }
}

/// `Arkadaşlar Butonu` (104:190): 48pt, zemin/panel, radius/md, a hard 3pt
/// shadow, 👥, and the green `İstek Rozeti` with the pending-request count.
class _FriendsButton extends StatelessWidget {
  const _FriendsButton({required this.requests, required this.onTap});

  final int requests;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        width: 48 + 8,
        height: 48 + 8,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned(
              left: 0,
              top: 8,
              child: Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: T.zeminPanel,
                  borderRadius: BorderRadius.circular(T.rMd),
                  border: Border.all(color: T.beyaz038),
                  boxShadow: const [
                    BoxShadow(
                      color: T.golgeCubuk,
                      offset: Offset(0, 3),
                      blurRadius: 0,
                    ),
                  ],
                ),
                alignment: Alignment.center,
                child: const Text('👥', style: TextStyle(fontSize: T.t22)),
              ),
            ),
            if (requests > 0)
              Positioned(
                left: 32,
                top: 1,
                child: Container(
                  width: 22,
                  height: 22,
                  decoration: BoxDecoration(
                    color: T.yesil,
                    shape: BoxShape.circle,
                    border: Border.all(color: T.zeminAna, width: 2),
                  ),
                  alignment: Alignment.center,
                  child: FittedBox(
                    child: Text(
                      requests > 9 ? '9+' : '$requests',
                      style: const TextStyle(
                        fontFamily: T.fontUi,
                        fontSize: T.t13,
                        color: T.yesilMurekkep,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
