import 'package:flutter/material.dart';

import '../models/room.dart';
import '../theme/tokens.dart';
import '../widgets/match_chrome.dart';
import '../widgets/screen_background.dart';

/// `Maç - Geri Sayım` (Figma 38:200).
///
/// The numeral counts down to [unlockAt], an instant taken from the room and
/// converted to this device's clock — NOT a three-second timer started when a
/// "go" message arrived. Two phones that start local timers on receipt drift
/// apart by whatever their latency differs by; two phones counting down to the
/// same instant do not.
///
/// The design's bottom slots show matchmaking state ("Rakip — aranıyor…").
/// By this point in a Friend Match both players and both clubs are known, so
/// the slots carry each player's chosen club instead — the thing that matters
/// in the two seconds before the clock starts.
class MatchCountdownScreen extends StatelessWidget {
  const MatchCountdownScreen({
    super.key,
    required this.room,
    required this.seat,
    required this.unlockAt,
  });

  final Room room;
  final Seat seat;
  final DateTime? unlockAt;

  int get _remaining {
    final target = unlockAt;
    if (target == null) return room.countdownSeconds;
    final ms = target.difference(DateTime.now()).inMilliseconds;
    if (ms <= 0) return 0;
    return (ms / 1000).ceil();
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final n = _remaining;

    return Scaffold(
      body: ScreenBackground(
        child: SafeArea(
          bottom: false,
          child: Column(
            children: [
              const SizedBox(height: T.sLg),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: MatchScoreStrip(
                  playerName: room.nameOf(seat),
                  opponentName: room.nameOf(seat.other),
                  playerScore: room.scoreOf(seat),
                  opponentScore: room.scoreOf(seat.other),
                ),
              ),
              Expanded(
                child: Center(
                  child: n > 0
                      ? _Numeral(value: n, width: width)
                      : const _Go(),
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(bottom: 40),
                child: _Slots(room: room, seat: seat),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The giant numeral: PoetsenOne at 400 on a 430 frame, filled with a vertical
/// orange-to-red gradient, outlined in black, and given the design's warm
/// glow.
///
/// Drawn as two stacked Texts because a single Text cannot both stroke and
/// fill: the lower one paints the outline, the upper one the gradient. The
/// size scales with the viewport — 400pt hard-coded would be clipped on a
/// 411pt screen.
class _Numeral extends StatelessWidget {
  const _Numeral({required this.value, required this.width});

  final int value;
  final double width;

  static const _fillTop = Color(0xFFFF840A);
  static const _fillBottom = Color(0xFFEA3235);
  static const _glow = Color(0xFFEFD959);

  @override
  Widget build(BuildContext context) {
    final size = 400 * width / 430;
    final text = '$value';

    return TweenAnimationBuilder<double>(
      // Each numeral lands with a small punch, so the count reads as three
      // beats rather than one number quietly changing.
      key: ValueKey(value),
      tween: Tween(begin: 1.25, end: 1.0),
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutBack,
      builder: (context, scale, child) =>
          Transform.scale(scale: scale, child: child),
      child: Stack(
        alignment: Alignment.center,
        children: [
          Text(
            text,
            style: TextStyle(
              fontFamily: T.fontUi,
              fontSize: size,
              height: 1,
              shadows: const [
                Shadow(color: _glow, blurRadius: 28, offset: Offset(0, 4)),
              ],
              foreground: Paint()
                ..style = PaintingStyle.stroke
                ..strokeWidth = size * 0.055
                ..strokeJoin = StrokeJoin.round
                ..color = Colors.black,
            ),
          ),
          ShaderMask(
            shaderCallback: (rect) => const LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [_fillTop, _fillBottom],
            ).createShader(rect),
            child: Text(
              text,
              style: TextStyle(
                fontFamily: T.fontUi,
                fontSize: size,
                height: 1,
                color: Colors.white,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Go extends StatelessWidget {
  const _Go();

  @override
  Widget build(BuildContext context) {
    return const Text(
      'BAŞLA!',
      style: TextStyle(
        fontFamily: T.fontUi,
        fontSize: T.t40,
        color: T.yesil,
      ),
    );
  }
}

/// `Eşleşme Yuvaları` (116:8) — the two player slots either side of VS.
class _Slots extends StatelessWidget {
  const _Slots({required this.room, required this.seat});

  final Room room;
  final Seat seat;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: _Slot(room: room, seat: seat, mine: true)),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: T.sXl),
          child: Text(
            'VS',
            style: TextStyle(
              fontFamily: T.fontUi,
              fontSize: T.t22,
              color: T.kirmizi,
            ),
          ),
        ),
        Expanded(child: _Slot(room: room, seat: seat.other, mine: false)),
      ],
    );
  }
}

class _Slot extends StatelessWidget {
  const _Slot({required this.room, required this.seat, required this.mine});

  final Room room;
  final Seat seat;
  final bool mine;

  @override
  Widget build(BuildContext context) {
    final name = room.nameOf(seat);
    final club = room.clubNameOf(seat);
    final initial = name.isEmpty ? '?' : name[0].toUpperCase();

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 58,
          height: 58,
          decoration: BoxDecoration(
            color: T.zeminAvatar,
            borderRadius: BorderRadius.circular(T.rLg),
            border: Border.all(
              color: mine
                  ? T.altin.withValues(alpha: 0.8)
                  : T.beyaz030,
              width: 2,
            ),
          ),
          alignment: Alignment.center,
          child: Text(
            initial,
            style: const TextStyle(
              fontFamily: T.fontUi,
              fontSize: T.t24,
              color: T.beyaz100,
            ),
          ),
        ),
        const SizedBox(height: T.sXs),
        Text(
          name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontFamily: T.fontUi,
            fontSize: T.t17,
            color: T.beyaz100,
          ),
        ),
        const SizedBox(height: T.sXxs),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: T.sSm),
          child: Text(
            club ?? '—',
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: T.t11, color: T.beyaz050),
          ),
        ),
      ],
    );
  }
}
