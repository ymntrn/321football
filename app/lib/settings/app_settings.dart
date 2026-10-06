import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Ayarlar (Figma 51:1088): sound and haptics, stored on the device.
///
/// Loaded once in main() before the first frame, so every reader below can
/// use the values synchronously.
class AppSettings {
  AppSettings._();
  static final AppSettings instance = AppSettings._();

  static const _soundKey = 'settings_sound';
  static const _hapticsKey = 'settings_haptics';

  final ValueNotifier<bool> sound = ValueNotifier(true);
  final ValueNotifier<bool> haptics = ValueNotifier(true);

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    sound.value = prefs.getBool(_soundKey) ?? true;
    haptics.value = prefs.getBool(_hapticsKey) ?? true;
  }

  Future<void> setSound(bool on) async {
    sound.value = on;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_soundKey, on);
  }

  Future<void> setHaptics(bool on) async {
    haptics.value = on;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_hapticsKey, on);
  }
}

/// THE only way the app vibrates. Every former `HapticFeedback` call goes
/// through here, so the Titreşim switch really turns all of them off.
/// (test/haptics_test.dart fails if a raw HapticFeedback call reappears
/// anywhere under lib/ outside this file.)
class Haptics {
  Haptics._();

  static bool get _on => AppSettings.instance.haptics.value;

  static void selection() {
    if (_on) HapticFeedback.selectionClick();
  }

  static void medium() {
    if (_on) HapticFeedback.mediumImpact();
  }

  static void heavy() {
    if (_on) HapticFeedback.heavyImpact();
  }
}

/// Every sound the game will make. There are no sound files yet, so
/// [Sounds.play] is wired at each moment but plays nothing.
enum Sfx { correct, wrong, goal, roundOver, win, lose, matchFound, tap }

/// THE one place sounds will be played from. When the files land, map each
/// [Sfx] to an asset here (and add an audio package); nothing else in the
/// app needs to change.
class Sounds {
  Sounds._();

  static void play(Sfx sfx) {
    if (!AppSettings.instance.sound.value) return;
    // No sound files yet (out of scope until they exist).
  }
}
