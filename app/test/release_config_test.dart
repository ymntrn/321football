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
}
