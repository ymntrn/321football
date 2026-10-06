import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/profile.dart';
import '../models/room.dart';
import '../net/account.dart';
import '../net/identity.dart';
import '../net/room_repository.dart';
import '../net/server_clock.dart';
import '../settings/app_settings.dart';
import '../theme/tokens.dart';
import '../widgets/app_chrome.dart';
import '../widgets/screen_background.dart';
import 'match_screen.dart';

/// `Maç Aranıyor` (Figma 12:95) — ranked "Hemen Oyna".
///
/// Polls find_match (009_matchmaking.sql) once a second. When a room comes
/// back it is a ranked room already in round 1, and it is handed to the
/// existing MatchScreen unchanged.
///
/// Two things are painted rather than exported: the curved title (a
/// text-path in Figma, 13:123, with no exportable asset) and the loader (a
/// still of a Lottie animation, 13:114 — a still frame of a spinner reads
/// as frozen, so it is drawn as the moving thing it depicts).
class MatchmakingScreen extends StatefulWidget {
  const MatchmakingScreen({super.key});

  @override
  State<MatchmakingScreen> createState() => _MatchmakingScreenState();
}

class _MatchmakingScreenState extends State<MatchmakingScreen> {
  RoomRepository? _rooms;
  ServerClock? _clock;
  Timer? _poll;
  Timer? _tick;
  final Stopwatch _waited = Stopwatch();
  bool _polling = false;
  bool _leaving = false;
  String? _error;
  Room? _found;

  /// How often find_match is called. It is also the queue heartbeat: a
  /// player silent for 15 s is dropped from the queue.
  static const _pollEvery = Duration(seconds: 1);

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    if (!await Account.instance.ensureOnline() ||
        Account.instance.profile.value == null) {
      if (mounted) setState(() => _error = 'Bağlantı kurulamadı');
      return;
    }
    final client = Supabase.instance.client;
    final clock = ServerClock(client);
    _clock = clock;
    _rooms = RoomRepository(client, clock);
    unawaited(clock.sync());
    _waited.start();
    _tick = Timer.periodic(const Duration(milliseconds: 500), (_) {
      if (mounted) setState(() {});
    });
    _poll = Timer.periodic(_pollEvery, (_) => _attempt());
    _attempt();
  }

  @override
  void dispose() {
    _poll?.cancel();
    _tick?.cancel();
    super.dispose();
  }

  Future<void> _attempt() async {
    final rooms = _rooms;
    if (rooms == null || _polling || _found != null || _leaving) return;
    _polling = true;
    try {
      final room = await rooms.findMatch();
      if (room != null && mounted && !_leaving) _enter(room);
    } catch (e) {
      debugPrint('find_match failed: $e');
    } finally {
      _polling = false;
    }
  }

  void _enter(Room room) {
    if (_found != null) return;
    final seat = room.seatOf(Identity.instance.playerId);
    if (seat == null) return;
    _poll?.cancel();
    _tick?.cancel();
    Sounds.play(Sfx.matchFound);
    Haptics.medium();
    setState(() => _found = room);
    // A beat with the opponent's name in the slot, then the match.
    Future<void>.delayed(const Duration(milliseconds: 700), () {
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => MatchScreen(
            initial: room,
            seat: seat,
            clock: _clock!,
            rooms: _rooms!,
          ),
        ),
      );
    });
  }

  /// İptal. Leaves the queue — unless a match was made in the instant
  /// before, in which case backing out would forfeit it, so it is entered.
  Future<void> _cancel() async {
    if (_leaving || _found != null) return;
    _leaving = true;
    _poll?.cancel();
    final rooms = _rooms;
    Room? late;
    if (rooms != null) {
      try {
        late = await rooms.leaveQueue();
      } catch (e) {
        debugPrint('leave_queue failed: $e');
      }
    }
    if (!mounted) return;
    if (late != null) {
      _leaving = false;
      _enter(late);
      return;
    }
    Navigator.of(context).pop();
  }

  /// The trophy window find_match is using right now: +-100, widened by
  /// 100 every 5 s of waiting.
  String _rangeText(int trophies) {
    final window = 100 + 100 * (_waited.elapsed.inSeconds ~/ 5);
    final low = math.max(0, trophies - window);
    final high = trophies + window;
    return '${formatThousands(low)} – ${formatThousands(high)} '
        'kupa aralığında eşleştiriliyorsun';
  }

  @override
  Widget build(BuildContext context) {
    final me = Account.instance.profile.value;
    final secs = _waited.elapsed.inSeconds;
    final clock = '${secs ~/ 60}:${(secs % 60).toString().padLeft(2, '0')}';
    final width = MediaQuery.sizeOf(context).width;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _cancel();
      },
      child: Scaffold(
        body: ScreenBackground(
          child: SafeArea(
            child: LayoutBuilder(
              builder: (context, box) => SingleChildScrollView(
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: box.maxHeight),
                  child: IntrinsicHeight(
                    child: Column(
                      children: [
                        const SizedBox(height: 40),
                        SizedBox(
                          width: width,
                          height: 90,
                          child: const CustomPaint(
                            painter: _ArcTitlePainter('Maç Aranıyor'),
                          ),
                        ),
                        const SizedBox(
                          width: 160,
                          height: 200,
                          child: _OrbitLoader(),
                        ),
                        const SizedBox(height: T.sLg),
                        if (_error != null)
                          Text(
                            _error!,
                            style: const TextStyle(
                              fontFamily: T.fontUi,
                              fontSize: T.t17,
                              color: T.kirmizi,
                            ),
                          )
                        else ...[
                          // `Arama Durumu` (113:8).
                          Container(
                            padding: const EdgeInsets.fromLTRB(16, 9, 18, 9),
                            decoration: BoxDecoration(
                              color: T.beyaz012,
                              borderRadius: BorderRadius.circular(T.rLg),
                              border: Border.all(color: T.beyaz022),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  _found != null
                                      ? 'Rakip bulundu'
                                      : 'Rakip aranıyor',
                                  style: const TextStyle(
                                    fontFamily: T.fontUi,
                                    fontSize: T.t15,
                                    color: T.beyaz080,
                                  ),
                                ),
                                const SizedBox(width: T.sMd),
                                Text(
                                  clock,
                                  style: const TextStyle(
                                    fontFamily: T.fontUi,
                                    fontSize: T.t17,
                                    color: Color(0xFFFF9C1A),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: T.sSm),
                          if (me != null)
                            Padding(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 20),
                              child: Text(
                                _rangeText(me.trophies),
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  fontFamily: T.fontUi,
                                  fontSize: T.t13,
                                  color: T.beyaz038,
                                ),
                              ),
                            ),
                          const SizedBox(height: T.sLg),
                          _Slots(me: me, found: _found),
                        ],
                        const Spacer(),
                        const SizedBox(height: T.s2xl),
                        // `▶ Gender/Default` (14:97): 270x120, the red radial.
                        SizedBox(
                          width: 270,
                          child: MenuButton(
                            label: 'İptal',
                            height: 120,
                            fontSize: T.t40,
                            gradient: RadialGradient(
                              radius: 0.5,
                              transform: T.wideRadial,
                              colors: [
                                T.kirmizi.withValues(alpha: 0.82),
                                const Color(0xFFE83939).withValues(alpha: 0.82),
                              ],
                            ),
                            onTap: _found == null ? _cancel : null,
                          ),
                        ),
                        const SizedBox(height: 70),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// `Eşleşme Yuvaları` (113:12): this player (gold-bordered, trophies), the
/// red VS, and the dashed `?` slot that fills when a match is made.
class _Slots extends StatelessWidget {
  const _Slots({required this.me, required this.found});

  final Profile? me;
  final Room? found;

  @override
  Widget build(BuildContext context) {
    final room = found;
    final seat = room?.seatOf(Identity.instance.playerId);
    final opponent = (room != null && seat != null) ? room.nameOf(seat.other) : null;

    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _Slot(
          name: me?.username ?? Identity.instance.name,
          sub: me == null ? '' : '${formatThousands(me!.trophies)} 🏆',
          filled: true,
          gold: true,
        ),
        const SizedBox(width: T.sXl),
        const Padding(
          padding: EdgeInsets.only(top: 16),
          child: Text(
            'VS',
            style: TextStyle(
              fontFamily: T.fontUi,
              fontSize: T.t22,
              color: T.kirmizi,
            ),
          ),
        ),
        const SizedBox(width: T.sXl),
        _Slot(
          name: opponent ?? 'Rakip',
          sub: opponent == null ? 'aranıyor…' : 'bulundu!',
          filled: opponent != null,
          gold: false,
        ),
      ],
    );
  }
}

class _Slot extends StatelessWidget {
  const _Slot({
    required this.name,
    required this.sub,
    required this.filled,
    required this.gold,
  });

  final String name;
  final String sub;
  final bool filled;
  final bool gold;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 80,
      child: Column(
        children: [
          if (filled)
            InitialsAvatar(
              name: name,
              size: 58,
              radius: T.rLg,
              border: gold ? T.altin.withValues(alpha: 0.8) : T.yesil,
              borderWidth: 2,
              fontSize: T.t24,
            )
          else
            const SizedBox(
              width: 58,
              height: 58,
              child: CustomPaint(
                painter: _DashedSlotPainter(),
                child: Center(
                  child: Text(
                    '?',
                    style: TextStyle(
                      fontFamily: T.fontUi,
                      fontSize: T.t24,
                      color: T.beyaz038,
                    ),
                  ),
                ),
              ),
            ),
          const SizedBox(height: T.sXs),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              name,
              maxLines: 1,
              style: TextStyle(
                fontFamily: T.fontUi,
                fontSize: T.t17,
                color: filled ? T.beyaz100 : T.beyaz050,
              ),
            ),
          ),
          const SizedBox(height: T.sXs),
          Text(
            sub,
            maxLines: 1,
            style: const TextStyle(
              fontFamily: T.fontUi,
              fontSize: T.t11,
              color: T.beyaz038,
            ),
          ),
        ],
      ),
    );
  }
}

/// The empty opponent slot (113:20): beyaz/006, a 2pt dashed beyaz/030
/// border, radius/lg.
class _DashedSlotPainter extends CustomPainter {
  const _DashedSlotPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final rrect = RRect.fromRectAndRadius(
      Offset.zero & size,
      const Radius.circular(T.rLg),
    );
    canvas.drawRRect(rrect, Paint()..color = T.beyaz006);
    final path = Path()..addRRect(rrect.deflate(1));
    final paint = Paint()
      ..color = T.beyaz030
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    for (final metric in path.computeMetrics()) {
      for (double d = 0; d < metric.length; d += 10) {
        canvas.drawPath(metric.extractPath(d, d + 6), paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// The title set on a gentle arch, as the frame's text-path draws it.
class _ArcTitlePainter extends CustomPainter {
  const _ArcTitlePainter(this.text);

  final String text;

  @override
  void paint(Canvas canvas, Size size) {
    const style = TextStyle(
      fontFamily: T.fontUi,
      fontSize: 44,
      color: T.beyaz100,
    );
    final glyphs = [
      for (final ch in text.characters)
        TextPainter(
          text: TextSpan(text: ch, style: style),
          textDirection: TextDirection.ltr,
        )..layout(),
    ];
    final total = glyphs.fold<double>(0, (w, g) => w + g.width);
    // Scale down if the phone is narrower than the title.
    final scale = math.min(1.0, (size.width - 40) / total);
    const radius = 620.0;
    final centre = Offset(size.width / 2, size.height * 0.75 + radius);
    var angle = -(total * scale) / 2 / radius;
    for (final g in glyphs) {
      final w = g.width * scale;
      final a = angle + w / 2 / radius;
      canvas.save();
      canvas.translate(
        centre.dx + radius * math.sin(a),
        centre.dy - radius * math.cos(a),
      );
      canvas.rotate(a);
      canvas.scale(scale);
      g.paint(canvas, Offset(-g.width / 2, -g.height));
      canvas.restore();
      angle += w / radius;
    }
  }

  @override
  bool shouldRepaint(covariant _ArcTitlePainter oldDelegate) =>
      oldDelegate.text != text;
}

/// The loader: five orange dots of falling size chasing round a circle,
/// after the Lottie still on the frame.
class _OrbitLoader extends StatefulWidget {
  const _OrbitLoader();

  @override
  State<_OrbitLoader> createState() => _OrbitLoaderState();
}

class _OrbitLoaderState extends State<_OrbitLoader>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  )..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (_, __) => CustomPaint(painter: _OrbitPainter(_c.value)),
    );
  }
}

class _OrbitPainter extends CustomPainter {
  _OrbitPainter(this.t);

  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    final centre = size.center(Offset.zero);
    final r = size.shortestSide * 0.3;
    final paint = Paint()..color = const Color(0xFFEE8A24);
    for (var i = 0; i < 5; i++) {
      final a = 2 * math.pi * (t - i * 0.07) - math.pi / 2;
      canvas.drawCircle(
        centre + Offset(math.cos(a), math.sin(a)) * r,
        11.0 - i * 2.0,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _OrbitPainter oldDelegate) => oldDelegate.t != t;
}
