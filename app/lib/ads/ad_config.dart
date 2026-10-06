/// Every AdMob id the app uses, in one place.
///
/// The app shows ONE ad: the rewarded "2X Altın" on a RANKED win (Figma
/// 46:352). No banners, no interstitials, anywhere.
///
/// TODO(release): replace BOTH ids below with the real ones from the AdMob
/// console before the first Play Store release (docs/release.md, step 4).
/// They are Google's official TEST ids
/// (https://developers.google.com/admob/android/test-ads): they always fill
/// and never pay. Shipping a real app on them earns nothing; testing on the
/// REAL ids risks the AdMob account, so keep the test ids in debug builds.
///
/// android/app/build.gradle.kts reads [admobAppIdAndroid] out of THIS file
/// (by name, with a regex) into the manifest's APPLICATION_ID meta-data, so
/// this stays the only place to edit. Keep that declaration on one line,
/// single-quoted, exactly as below.
class AdConfig {
  AdConfig._();

  /// The AdMob APP id (contains `~`). Google's test app id.
  static const admobAppIdAndroid = 'ca-app-pub-3940256099942544~3347511713';

  /// The rewarded ad UNIT id (contains `/`). Google's test rewarded unit.
  static const rewardedUnitAndroid = 'ca-app-pub-3940256099942544/5224354917';

  /// False turns the 2X Altın button off everywhere (the normal reward still
  /// stands) without touching any other code.
  static const adsEnabled = true;
}
