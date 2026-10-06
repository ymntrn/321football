import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'ads/rewarded_coins_ad.dart';
import 'data/app_database.dart';
import 'net/account.dart';
import 'net/identity.dart';
import 'net/supabase_config.dart';
import 'screens/home_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/username_screen.dart';
import 'settings/app_settings.dart';
import 'theme/tokens.dart';
import 'widgets/club_crest.dart';
import 'widgets/screen_background.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);

  // Supabase is started here but NOT awaited before the first frame: it used
  // to block runApp for a couple of seconds of blank screen on every launch,
  // even for offline Practice. _Boot waits for it alongside the database open,
  // so both run in parallel. A failure is logged and swallowed - only Friend
  // Match needs the network, and it reports its own connection errors.
  await Identity.load();
  await AppSettings.instance.load();
  supabaseReady = _initSupabase();

  runApp(const App());

  // Ad consent (EEA/UK only, when required) and the Mobile Ads SDK, in the
  // background. Only "2X Altın" on a ranked win uses them.
  unawaited(RewardedCoinsAd.initialize());
}

/// Completes once Supabase.initialize has finished (or failed). Never throws.
late final Future<void> supabaseReady;

Future<void> _initSupabase() async {
  try {
    await Supabase.initialize(
      url: SupabaseConfig.url,
      publishableKey: SupabaseConfig.publishableKey,
    );
    Account.instance.backendAvailable = true;
  } catch (e) {
    debugPrint('Supabase init failed (online modes will be unavailable): $e');
    return;
  }
  // The anonymous sign-in (or the restored session) and the profile. Bounded
  // by a timeout inside boot(), and never throws: offline, Practice runs on
  // the on-device fallback id.
  await Account.instance.boot();
}

class App extends StatelessWidget {
  const App({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '321 Football Challenge',
      debugShowCheckedModeBanner: false,
      theme: T.theme(),
      home: const _Boot(),
    );
  }
}

/// Opens the database before anything can query it. The first launch copies a
/// 62 MB asset out of the bundle, so this is the one screen that legitimately
/// takes a moment — and shows how far along that copy is.
class _Boot extends StatefulWidget {
  const _Boot();

  @override
  State<_Boot> createState() => _BootState();
}

class _BootState extends State<_Boot> {
  late final Future<void> _ready = Future.wait([
    AppDatabase.instance.open().then(ClubColours.instance.load),
    supabaseReady,
  ]);

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<void>(
      future: _ready,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Scaffold(
            backgroundColor: T.zeminAna,
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(T.s2xl),
                child: Text(
                  'Veritabanı açılamadı.\n${snapshot.error}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: T.kirmizi, fontSize: T.t15),
                ),
              ),
            ),
          );
        }
        if (snapshot.connectionState != ConnectionState.done) {
          return const _Splash();
        }
        // First launch asks for a username (92:190); every later launch
        // goes straight to Ana Sayfa (4:4). The dev menu is reachable only
        // in debug builds, by long-pressing the coin chip on Ana Sayfa.
        return Identity.instance.hasUsername
            ? const HomeScreen()
            : const UsernameScreen();
      },
    );
  }
}

/// `Yükleme ekranı` (Figma 48:570): the backdrop, `Yükleniyor` over a
/// 354x14 bar (#0B0D2E track, #5F114C → #000FDA fill), and the version at
/// the foot.
///
/// The bar is REAL during the first-launch database copy — it follows
/// AppDatabase.progress, fed by the streamed copy in MainActivity.kt — and
/// the label then reads "Veritabanı hazırlanıyor… %NN". On every later
/// launch the open is near-instant and the bar just sweeps.
class _Splash extends StatelessWidget {
  const _Splash();

  @override
  Widget build(BuildContext context) {
    final db = AppDatabase.instance;
    return Scaffold(
      body: ScreenBackground(
        child: SafeArea(
          child: Column(
            children: [
              const Spacer(),
              ValueListenableBuilder<bool>(
                valueListenable: db.copying,
                builder: (context, copying, _) =>
                    ValueListenableBuilder<double?>(
                  valueListenable: db.progress,
                  builder: (context, value, _) => Text(
                    !copying
                        ? 'Yükleniyor'
                        : value == null
                            ? 'Veritabanı hazırlanıyor…'
                            : 'Veritabanı hazırlanıyor… %${(value * 100).round()}',
                    style: const TextStyle(
                      fontFamily: T.fontUi,
                      fontSize: T.t15,
                      color: T.beyaz100,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 13),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 38),
                child: ValueListenableBuilder<double?>(
                  valueListenable: db.progress,
                  builder: (context, value, _) => _LoadingBar(value: value),
                ),
              ),
              const SizedBox(height: 100),
              const Text(
                SettingsScreen.version,
                style: TextStyle(
                  fontFamily: T.fontUi,
                  fontSize: T.t13,
                  color: T.beyaz050,
                ),
              ),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }
}

/// `bar` (48:580). Determinate when [value] is known; otherwise the 105pt
/// fill the frame draws sweeps across the track.
class _LoadingBar extends StatefulWidget {
  const _LoadingBar({required this.value});

  final double? value;

  @override
  State<_LoadingBar> createState() => _LoadingBarState();
}

class _LoadingBarState extends State<_LoadingBar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _sweep = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  )..repeat();

  static const _track = Color(0xFF0B0D2E);
  static const _fill = LinearGradient(
    colors: [Color(0xFF5F114C), Color(0xFF000FDA)],
  );

  @override
  void dispose() {
    _sweep.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 14,
      child: LayoutBuilder(
        builder: (context, box) {
          final w = box.maxWidth;
          final value = widget.value;
          return ClipRRect(
            borderRadius: BorderRadius.circular(50),
            child: Stack(
              children: [
                const Positioned.fill(child: ColoredBox(color: _track)),
                if (value != null)
                  Container(
                    width: (w * value).clamp(14.0, w),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(50),
                      gradient: _fill,
                    ),
                  )
                else
                  AnimatedBuilder(
                    animation: _sweep,
                    builder: (_, __) {
                      final seg = w * 105 / 354;
                      return Positioned(
                        left: (w + seg) * _sweep.value - seg,
                        top: 0,
                        bottom: 0,
                        width: seg,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(50),
                            gradient: _fill,
                          ),
                        ),
                      );
                    },
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}
