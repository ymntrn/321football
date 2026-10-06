import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'data/app_database.dart';
import 'net/identity.dart';
import 'net/supabase_config.dart';
import 'screens/dev_menu_screen.dart';
import 'theme/tokens.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);

  // Supabase is initialised before the app runs, but NOT awaited on anything
  // Practice needs: Practice is entirely offline and must keep working with no
  // network at all. A failure here is logged and swallowed for that reason —
  // only Friend Match cares, and it reports its own connection errors.
  try {
    await Supabase.initialize(
      url: SupabaseConfig.url,
      publishableKey: SupabaseConfig.publishableKey,
    );
  } catch (e) {
    debugPrint('Supabase init failed (Friend Match will be unavailable): $e');
  }
  await Identity.load();

  runApp(const App());
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
  late final Future<void> _ready = AppDatabase.instance.open();

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
        // Ana Sayfa (Figma 4:4) is not built yet, so this lands on the dev
        // menu instead of straight into Practice. Swap it for the real home
        // screen when that exists.
        return const DevMenuScreen();
      },
    );
  }
}

/// The boot splash: the Jaro wordmark and a progress bar.
///
/// The bar is REAL during the first-launch database copy — it follows
/// AppDatabase.progress, fed by the streamed copy in MainActivity.kt — with
/// a percentage and a line saying what is happening. On every later launch
/// the open is near-instant and the bar stays indeterminate.
class _Splash extends StatelessWidget {
  const _Splash();

  @override
  Widget build(BuildContext context) {
    final db = AppDatabase.instance;
    return Scaffold(
      backgroundColor: T.zeminAna,
      body: Center(
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
            const SizedBox(height: T.s2xl),
            ValueListenableBuilder<double?>(
              valueListenable: db.progress,
              builder: (context, value, _) => SizedBox(
                width: 180,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(2),
                  child: LinearProgressIndicator(
                    value: value,
                    minHeight: 4,
                    backgroundColor: T.beyaz012,
                    valueColor: const AlwaysStoppedAnimation(T.turuncu),
                  ),
                ),
              ),
            ),
            const SizedBox(height: T.sLg),
            ValueListenableBuilder<bool>(
              valueListenable: db.copying,
              builder: (context, copying, _) => ValueListenableBuilder<double?>(
                valueListenable: db.progress,
                builder: (context, value, _) => Text(
                  !copying
                      ? ''
                      : value == null
                          ? 'Veritabanı hazırlanıyor…'
                          : 'Veritabanı hazırlanıyor… %${(value * 100).round()}',
                  style: const TextStyle(
                    fontFamily: T.fontUi,
                    fontSize: T.t13,
                    color: T.beyaz050,
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
