import 'package:flutter/material.dart';

import '../models/profile.dart';
import '../net/account.dart';
import '../net/social_repository.dart';
import '../theme/tokens.dart';
import '../widgets/app_chrome.dart';
import '../widgets/screen_background.dart';
import 'nav.dart';

/// `Leaderboard - Global` (51:567) and `Leaderboard - Arkadaş` (51:860).
///
/// The two tabs differ on purpose (game-screens-ui.md): Global has the
/// pinned top-3 podium, ranks 4–100 in a scroll area and the player's own
/// row pinned above the nav; Arkadaş is one uniform list where the player is
/// just another row, highlighted green.
///
/// The frames show a country flag on every row. There is no country data
/// (profiles hold none, and the app asks for none), so the flag is left out.
class LeaderboardScreen extends StatefulWidget {
  const LeaderboardScreen({super.key});

  @override
  State<LeaderboardScreen> createState() => _LeaderboardScreenState();
}

class _LeaderboardScreenState extends State<LeaderboardScreen> {
  bool _friends = false;
  bool _loading = true;
  List<Profile> _global = const [];
  List<Profile> _friendRows = const [];
  int? _myRank;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final repo = SocialRepository.instance;
    final results = await Future.wait([
      repo.globalTop(),
      repo.friendsLeaderboard(),
      repo.myRank(),
      Account.instance.refresh(),
    ]);
    if (!mounted) return;
    setState(() {
      _global = results[0] as List<Profile>;
      _friendRows = results[1] as List<Profile>;
      _myRank = results[2] as int?;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final me = Account.instance.profile.value;
    return Scaffold(
      body: ScreenBackground(
        child: Column(
          children: [
            SafeArea(
              bottom: false,
              child: Stack(
                children: [
                  const Positioned(left: 5, top: 0, child: UndoButton()),
                  Column(
                    children: [
                      const SizedBox(height: 16),
                      Center(
                        child: _TabToggle(
                          friends: _friends,
                          onChanged: (v) => setState(() => _friends = v),
                        ),
                      ),
                      const SizedBox(height: T.sSm),
                      ScreenTitle(_friends ? 'Arkadaş' : 'Global'),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: T.sLg),
            Expanded(
              child: _loading
                  ? const Center(
                      child: CircularProgressIndicator(color: T.turuncu),
                    )
                  : me == null
                      ? const _Offline()
                      : _friends
                          ? _FriendsBoard(rows: _friendRows, me: me)
                          : _GlobalBoard(rows: _global, me: me, myRank: _myRank),
            ),
            const TabNavBar(current: NavTab.leaderboard),
          ],
        ),
      ),
    );
  }
}

class _Offline extends StatelessWidget {
  const _Offline();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Text(
        'Bağlantı kurulamadı',
        style: TextStyle(
          fontFamily: T.fontUi,
          fontSize: T.t17,
          color: T.beyaz065,
        ),
      ),
    );
  }
}

/// The Global / Arkadaş switch (51:581): 235x55, the violet fill, and a
/// #8244FF half at 38% marking the live tab; earth and people icons.
class _TabToggle extends StatelessWidget {
  const _TabToggle({required this.friends, required this.onChanged});

  final bool friends;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 235,
      height: 55,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(T.rLg),
        border: Border.all(color: T.beyaz030),
        gradient: T.morGradient(0.82),
      ),
      child: Stack(
        children: [
          AnimatedPositioned(
            duration: const Duration(milliseconds: 160),
            left: friends ? 113 : -1,
            top: -1,
            child: Container(
              width: 121,
              height: 55,
              decoration: BoxDecoration(
                color: const Color(0xFF8244FF).withValues(alpha: 0.38),
                borderRadius: BorderRadius.circular(T.rLg),
                border: Border.all(color: T.beyaz030),
              ),
            ),
          ),
          Positioned.fill(child: T.insetTop(T.rLg)),
          Row(
            children: [
              Expanded(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => onChanged(false),
                  child: const Center(
                    child: FigmaAsset(
                      'lb_earth.png',
                      width: 41,
                      height: 42,
                      fallback: Text('🌍', style: TextStyle(fontSize: 28)),
                    ),
                  ),
                ),
              ),
              Expanded(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => onChanged(true),
                  child: const Center(
                    child: FigmaAsset(
                      'lb_people.png',
                      width: 43,
                      height: 42,
                      fallback: Text('👥', style: TextStyle(fontSize: 28)),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// A row's trophy count: gold for the player and the podium, white else.
Widget _trophies(int n, {Color color = T.beyaz100}) => Text(
      formatThousands(n),
      style: TextStyle(fontFamily: T.fontUi, fontSize: T.t17, color: color),
    );

class _GlobalBoard extends StatelessWidget {
  const _GlobalBoard({
    required this.rows,
    required this.me,
    required this.myRank,
  });

  final List<Profile> rows;
  final Profile me;
  final int? myRank;

  static const _medals = [
    T.altin, // gold
    Color(0xFFCCD4E0), // silver
    Color(0xFFCC8540), // bronze
  ];

  @override
  Widget build(BuildContext context) {
    final podium = rows.take(3).toList();
    final rest = rows.length > 3 ? rows.sublist(3) : const <Profile>[];
    final width = MediaQuery.sizeOf(context).width;
    final side = width * 18 / 430;

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: side),
      child: Column(
        children: [
          // `İlk Üç (Sabit)` (105:195).
          if (podium.isNotEmpty)
            Container(
              padding: const EdgeInsets.all(T.sMd),
              decoration: BoxDecoration(
                color: T.beyaz006,
                borderRadius: BorderRadius.circular(T.rXl),
                border: Border.all(color: T.beyaz016, width: 1.5),
              ),
              child: Column(
                children: [
                  for (var i = 0; i < podium.length; i++) ...[
                    if (i > 0) const SizedBox(height: T.sSm),
                    PlayerRow(
                      name: podium[i].username,
                      tag: podium[i].tag,
                      medal: _medals[i],
                      avatarSize: 40,
                      padding: const EdgeInsets.fromLTRB(8, 8, 12, 8),
                      leading: _Medal(rank: i + 1, color: _medals[i]),
                      trailing: [_trophies(podium[i].trophies, color: _medals[i])],
                    ),
                  ],
                ],
              ),
            ),
          const SizedBox(height: T.sLg),
          if (rest.isNotEmpty)
            const Align(
              alignment: Alignment.centerLeft,
              child: Padding(
                padding: EdgeInsets.only(left: 6, bottom: T.sSm),
                child: SectionCaption('4 – 100. SIRA'),
              ),
            ),
          // `Kaydırılabilir Liste` (106:191).
          Expanded(
            child: ListView.separated(
              padding: EdgeInsets.zero,
              itemCount: rest.length,
              separatorBuilder: (_, __) => const SizedBox(height: T.sSm),
              itemBuilder: (context, i) {
                final p = rest[i];
                final mine = p.id == me.id;
                return PlayerRow(
                  name: p.username,
                  tag: p.tag,
                  highlight: mine,
                  leading: RankCell(i + 4, mine: mine),
                  trailing: [
                    _trophies(p.trophies, color: mine ? T.altin : T.beyaz100),
                  ],
                );
              },
            ),
          ),
          const SizedBox(height: T.sLg),
          // `Kendi Sıran (Sabit)` (106:256), pinned above the nav.
          Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(T.rLg),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.5),
                  offset: const Offset(0, -4),
                  blurRadius: 22,
                ),
              ],
            ),
            child: PlayerRow(
              name: me.username,
              tag: me.tag,
              highlight: true,
              leading: RankCell(myRank ?? 0, mine: true),
              trailing: [_trophies(me.trophies, color: T.altin)],
            ),
          ),
          const SizedBox(height: T.sLg),
        ],
      ),
    );
  }
}

/// `Madalya` (105:197): a 32pt disc in the medal colour, the rank in
/// near-black.
class _Medal extends StatelessWidget {
  const _Medal({required this.rank, required this.color});

  final int rank;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(color: T.beyaz050),
      ),
      alignment: Alignment.center,
      child: Text(
        '$rank',
        style: const TextStyle(
          fontFamily: T.fontUi,
          fontSize: T.t17,
          color: Color(0xFF0F0D05),
        ),
      ),
    );
  }
}

class _FriendsBoard extends StatelessWidget {
  const _FriendsBoard({required this.rows, required this.me});

  final List<Profile> rows;
  final Profile me;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final side = width * 18 / 430;
    final friends = rows.where((p) => p.id != me.id).length;

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: side),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 6, bottom: T.sSm),
            child: SectionCaption('$friends ARKADAŞ'),
          ),
          Expanded(
            child: friends == 0
                ? const Center(
                    child: Text(
                      'Henüz arkadaşın yok.\nArkadaşlar ekranından ekleyebilirsin.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontFamily: T.fontUi,
                        fontSize: T.t15,
                        color: T.beyaz050,
                      ),
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.only(bottom: T.sLg),
                    itemCount: rows.length,
                    separatorBuilder: (_, __) => const SizedBox(height: T.sSm),
                    itemBuilder: (context, i) {
                      final p = rows[i];
                      final mine = p.id == me.id;
                      return PlayerRow(
                        name: p.username,
                        tag: p.tag,
                        highlight: mine,
                        leading: RankCell(i + 1, mine: mine, width: 30),
                        trailing: [
                          _trophies(p.trophies,
                              color: mine ? T.altin : T.beyaz100),
                        ],
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
