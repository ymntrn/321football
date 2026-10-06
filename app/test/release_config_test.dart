import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:football321/ads/ad_config.dart';
import 'package:football321/net/auth_config.dart';

/// Release-facing switches that must not change by accident.
void main() {
  test('Google linking is OFF by default (no OAuth client yet)', () {
    expect(AuthConfig.googleLinkingEnabled, isFalse);
    expect(AuthConfig.googleLinkingAvailable, isFalse);
  });

  test('the ad ids are well-formed', () {
    expect(AdConfig.admobAppIdAndroid, matches(r'^ca-app-pub-\d+~\d+$'));
    expect(AdConfig.rewardedUnitAndroid, matches(r'^ca-app-pub-\d+/\d+$'));
  });

  test('Gradle can find the AdMob app id in ad_config.dart', () {
    // build.gradle.kts reads it with this regex; keep the line's shape.
    final src = File('lib/ads/ad_config.dart').readAsStringSync();
    final m = RegExp(r"static const admobAppIdAndroid\s*=\s*'([^']+)'").firstMatch(src);
    expect(m?.group(1), AdConfig.admobAppIdAndroid);
    final gradle = File('android/app/build.gradle.kts').readAsStringSync();
    expect(gradle, contains('lib/ads/ad_config.dart'));
    expect(gradle, contains(r'Regex("static const admobAppIdAndroid\\s*=\\s*'));
    final manifest =
        File('android/app/src/main/AndroidManifest.xml').readAsStringSync();
    expect(manifest, contains(r'${admobAppId}'));
  });

  test('no banner or interstitial ads anywhere', () {
    final offenders = <String>[];
    for (final f in Directory('lib').listSync(recursive: true)) {
      if (f is! File || !f.path.endsWith('.dart')) continue;
      final src = f.readAsStringSync();
      for (final kind in ['BannerAd', 'InterstitialAd', 'NativeAd', 'AppOpenAd']) {
        if (RegExp('\\b$kind\\b').hasMatch(src)) offenders.add('${f.path}: $kind');
      }
    }
    expect(offenders, isEmpty);
  });

  group('release build configuration', () {
    final gradle = File('android/app/build.gradle.kts').readAsStringSync();
    final manifest =
        File('android/app/src/main/AndroidManifest.xml').readAsStringSync();

    test('signs from key.properties, else falls back to debug', () {
      expect(gradle, contains('rootProject.file("key.properties")'));
      expect(gradle, contains('signingConfigs.getByName("release")'));
      expect(gradle, contains('signingConfigs.getByName("debug")'));
    });

    test('R8 shrinks the release build with our keep rules', () {
      expect(gradle, contains('isMinifyEnabled = true'));
      expect(gradle, contains('isShrinkResources = true'));
      final rules = File('android/app/proguard-rules.pro').readAsStringSync();
      for (final keep in [
        'com.yamanturan.football321',
        'com.tekartik.sqflite',
        'io.flutter.plugins.googlemobileads',
        'com.google.android.play.core',
      ]) {
        expect(rules, contains(keep), reason: keep);
      }
    });

    test('version comes from pubspec', () {
      expect(gradle, contains('versionCode = flutter.versionCode'));
      expect(gradle, contains('versionName = flutter.versionName'));
      expect(File('pubspec.yaml').readAsStringSync(),
          matches(RegExp(r'^version: \d+\.\d+\.\d+\+\d+$', multiLine: true)));
    });

    test('the app is labelled "321 Football" and can reach the network', () {
      expect(manifest, contains('android:label="321 Football"'));
      expect(manifest, contains('android.permission.INTERNET'));
    });

    test('no keystore or key.properties is committed', () {
      final ignore = File('../.gitignore').readAsStringSync();
      expect(ignore, contains('*.jks'));
      expect(ignore, contains('key.properties'));
      expect(File('android/key.properties').existsSync(), isFalse);
    });
  });
}
