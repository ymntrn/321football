import 'package:flutter/material.dart';

import '../models/models.dart';
import '../theme/tokens.dart';
import '../widgets/screen_background.dart';
import 'practice_board_screen.dart';

/// `Alıştırma - Zorluk Seçme` (Figma 11:62).
///
/// Three full-width gradient pills, 341x90 at radius/lg on a 430pt frame,
/// labels at type/40. Positions in the frame: title centred at y=110, buttons
/// at y=303 / 421 / 539 — an even 118pt pitch.
class PracticeDifficultyScreen extends StatelessWidget {
  const PracticeDifficultyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: ScreenBackground(
        child: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              // Buttons are 341 wide on a 430 frame — keep that ratio rather
              // than a fixed width, so they breathe correctly on other sizes.
              final buttonWidth =
                  (constraints.maxWidth * 341 / ScreenBackground.designWidth)
                      .clamp(240.0, 341.0);
              return Stack(
                children: [
                  const Positioned(left: 6, top: 21, child: UndoButton()),
                  Positioned(
                    left: 0,
                    right: 0,
                    top: 88,
                    child: Text(
                      'Seviye Seç',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontFamily: T.fontUi,
                        fontSize: T.t40,
                        color: T.beyaz100,
                      ),
                    ),
                  ),
                  Positioned(
                    left: 0,
                    right: 0,
                    top: 281,
                    child: Column(
                      children: [
                        _Pill(
                          label: 'Kolay',
                          stops: T.kolayStops,
                          width: buttonWidth,
                          difficulty: Difficulty.easy,
                        ),
                        const SizedBox(height: 28),
                        _Pill(
                          label: 'Orta',
                          stops: T.ortaStops,
                          width: buttonWidth,
                          difficulty: Difficulty.medium,
                        ),
                        const SizedBox(height: 28),
                        _Pill(
                          label: 'Zor',
                          stops: T.zorStops,
                          width: buttonWidth,
                          difficulty: Difficulty.hard,
                        ),
                      ],
                    ),
                  ),
                  const Align(
                    alignment: Alignment.bottomCenter,
                    child: HomeIndicator(),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({
    required this.label,
    required this.stops,
    required this.width,
    required this.difficulty,
  });

  final String label;
  final List<Color> stops;
  final double width;
  final Difficulty difficulty;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => PracticeBoardScreen(difficulty: difficulty),
        ),
      ),
      child: SizedBox(
        width: width,
        height: 90,
        child: Stack(
          alignment: Alignment.center,
          children: [
            Container(
              decoration: T.difficultyFill(stops, T.rLg),
            ),
            // inset 0 4px 4px rgba(0,0,0,0.25) — Flutter has no inset shadow,
            // so this is the same darkening painted as a top-edge gradient.
            Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(T.rLg),
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withValues(alpha: 0.25),
                    Colors.transparent,
                  ],
                  stops: const [0, 0.12],
                ),
              ),
            ),
            Text(
              label,
              style: const TextStyle(
                fontFamily: T.fontUi,
                fontSize: T.t40,
                color: T.beyaz100,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
