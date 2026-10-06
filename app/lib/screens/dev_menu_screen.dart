import 'package:flutter/material.dart';

import '../models/models.dart';
import '../theme/tokens.dart';
import '../widgets/screen_background.dart';
import 'friend_match_screen.dart';
import 'match_team_select_screen.dart';
import 'practice_difficulty_screen.dart';

/// Scaffolding, not a product screen.
///
/// Off the launch path since Ana Sayfa (4:4) was built. Reachable in DEBUG
/// builds only, by long-pressing the coin chip on Ana Sayfa — kept for the
/// standalone team-picker demo.
class DevMenuScreen extends StatelessWidget {
  const DevMenuScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: ScreenBackground(
        child: SafeArea(
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Text(
                  '321',
                  style: TextStyle(
                    fontFamily: T.fontNumeral,
                    fontSize: T.t96,
                    color: T.turuncu,
                  ),
                ),
                const SizedBox(height: 40),
                _Button(
                  label: 'ALIŞTIRMA',
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const PracticeDifficultyScreen(),
                    ),
                  ),
                ),
                const SizedBox(height: T.sLg),
                _Button(
                  label: 'ARKADAŞ MAÇI',
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const FriendMatchScreen(),
                    ),
                  ),
                ),
                const SizedBox(height: T.sLg),
                _Button(
                  label: 'TAKIM SEÇME',
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const _TeamSelectDemo()),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Button extends StatelessWidget {
  const _Button({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 280,
        height: 64,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: T.zeminPanel,
          borderRadius: BorderRadius.circular(T.rLg),
          border: Border.all(color: T.beyaz038, width: 1.5),
          boxShadow: const [
            BoxShadow(
              color: T.golgeCubuk,
              offset: Offset(0, 4),
              blurRadius: 0,
            ),
          ],
        ),
        child: Text(
          label,
          style: const TextStyle(
            fontFamily: T.fontUi,
            fontSize: T.t22,
            color: T.beyaz100,
          ),
        ),
      ),
    );
  }
}

/// Runs the team picker standalone, with a 15-second window and stub match
/// state, so the screen can be checked on a device before the room exists.
class _TeamSelectDemo extends StatefulWidget {
  const _TeamSelectDemo();

  @override
  State<_TeamSelectDemo> createState() => _TeamSelectDemoState();
}

class _TeamSelectDemoState extends State<_TeamSelectDemo> {
  final DateTime _deadline =
      DateTime.now().add(const Duration(seconds: 15));

  @override
  Widget build(BuildContext context) {
    return MatchTeamSelectScreen(
      playerName: 'Oyuncuadı1',
      opponentName: 'Oyuncuadı2',
      playerScore: 0,
      opponentScore: 0,
      deadline: _deadline,
      onPicked: (Club club) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: T.zeminPanel,
            content: Text(
              'Seçildi: ${club.name}  (#${club.id})',
              style: const TextStyle(fontFamily: T.fontUi),
            ),
          ),
        );
      },
      onTimeout: () {
        if (!mounted) return;
        Navigator.of(context).maybePop();
      },
    );
  }
}
