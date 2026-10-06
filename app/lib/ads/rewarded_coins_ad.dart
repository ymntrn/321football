import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import 'ad_config.dart';

/// The one rewarded ad behind "2X Altın".
///
/// [load] fetches an ad; [ready] turns true when one is in hand. [show] plays
/// it and completes with true only if the player earned the reward. Anything
/// that goes wrong — no fill, no network, the plugin missing, the ad closed
/// early — leaves [ready] false or returns false, and the caller simply keeps
/// the button hidden: the normal reward always stands.
///
/// The doubling itself is NOT done here. The caller asks the server
/// (double_match_coins, 010) after a true [show].
class RewardedCoinsAd {
  RewardedCoinsAd();

  final ValueNotifier<bool> ready = ValueNotifier(false);
  RewardedAd? _ad;
  bool _disposed = false;

  static Future<bool>? _init;

  /// Consent first, then the Mobile Ads SDK — once; safe to call repeatedly.
  /// Completes with whether ads may be requested at all.
  ///
  /// Google's User Messaging Platform shows the consent message configured
  /// in AdMob (Privacy & messaging) to players in the EEA/UK and only when
  /// one is required; elsewhere this returns at once. Called at launch from
  /// main(), so the message (if any) appears then rather than over a result
  /// screen.
  static Future<bool> initialize() {
    if (!AdConfig.adsEnabled || !_supported) return Future.value(false);
    return _init ??= _consentThenStart().catchError((Object e) {
      debugPrint('ads unavailable: $e');
      return false;
    });
  }

  static Future<bool> _consentThenStart() async {
    final updated = Completer<void>();
    ConsentInformation.instance.requestConsentInfoUpdate(
      ConsentRequestParameters(),
      () => updated.complete(),
      (error) {
        // Still try: canRequestAds() reflects any consent already stored.
        debugPrint('consent info update failed: ${error.message}');
        updated.complete();
      },
    );
    await updated.future;
    final shown = Completer<void>();
    await ConsentForm.loadAndShowConsentFormIfRequired((error) {
      if (error != null) debugPrint('consent form: ${error.message}');
      shown.complete();
    });
    await shown.future;
    if (!await ConsentInformation.instance.canRequestAds()) return false;
    await MobileAds.instance.initialize();
    return true;
  }

  /// Android only (the app ships on Android), and never under flutter test,
  /// where the plugin's channel does not exist.
  static bool get _supported =>
      !kIsWeb &&
      Platform.isAndroid &&
      !Platform.environment.containsKey('FLUTTER_TEST');

  void load() {
    if (!AdConfig.adsEnabled || !_supported || _ad != null) return;
    unawaited(_load());
  }

  Future<void> _load() async {
    try {
      if (!await initialize()) return;
      await RewardedAd.load(
        adUnitId: AdConfig.rewardedUnitAndroid,
        request: const AdRequest(),
        rewardedAdLoadCallback: RewardedAdLoadCallback(
          onAdLoaded: (ad) {
            if (_disposed) {
              ad.dispose();
              return;
            }
            _ad = ad;
            _setReady(true);
          },
          onAdFailedToLoad: (error) {
            debugPrint('rewarded ad failed to load: $error');
            _setReady(false);
          },
        ),
      );
    } catch (e) {
      debugPrint('rewarded ad unavailable: $e');
      _setReady(false);
    }
  }

  /// Load callbacks can land after the match screen is gone.
  void _setReady(bool value) {
    if (!_disposed) ready.value = value;
  }

  /// Plays the ad. True when the reward was earned (the player watched it
  /// through); false when it could not be shown or was closed early.
  Future<bool> show() async {
    final ad = _ad;
    if (ad == null) return false;
    _ad = null;
    _setReady(false);

    final done = Completer<bool>();
    var earned = false;
    ad.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (ad) {
        ad.dispose();
        if (!done.isCompleted) done.complete(earned);
      },
      onAdFailedToShowFullScreenContent: (ad, error) {
        debugPrint('rewarded ad failed to show: $error');
        ad.dispose();
        if (!done.isCompleted) done.complete(false);
      },
    );
    try {
      await ad.show(onUserEarnedReward: (_, _) => earned = true);
    } catch (e) {
      debugPrint('rewarded ad show failed: $e');
      ad.dispose();
      return false;
    }
    return done.future;
  }

  void dispose() {
    _disposed = true;
    _ad?.dispose();
    _ad = null;
    ready.dispose();
  }
}
