# R8 rules for the release build (build.gradle.kts -> isMinifyEnabled).
#
# Flutter's Gradle plugin already adds its own embedding rules, and most
# plugins and Google SDKs ship consumer rules. The keeps below are belt and
# braces for the code that is reached through platform channels or
# reflection, where a stripped class only fails at run time on a RELEASE
# build. Supabase needs nothing here: it is pure Dart (in libapp.so).

# The asset-copy MethodChannel in MainActivity.kt.
-keep class com.yamanturan.football321.** { *; }

# Flutter plugins are registered by GeneratedPluginRegistrant via their
# class names: sqflite, path_provider, shared_preferences, share_plus,
# url_launcher, audioplayers, google_mobile_ads, google_sign_in.
-keep class io.flutter.plugins.** { *; }
-keep class com.tekartik.sqflite.** { *; }
-keep class xyz.luan.audioplayers.** { *; }
-keep class dev.fluttercommunity.plus.** { *; }

# Google Mobile Ads + the User Messaging Platform (consent form).
-keep class io.flutter.plugins.googlemobileads.** { *; }
-keep class com.google.android.gms.ads.** { *; }
-keep class com.google.android.ump.** { *; }

# google_sign_in 7 goes through Credential Manager; its Play services
# provider is found by reflection.
-if class androidx.credentials.CredentialManager
-keep class androidx.credentials.playservices.** { *; }
-keep class com.google.android.libraries.identity.googleid.** { *; }

# The Flutter embedding references Play Core (deferred components), which
# this app does not use or ship. Without these R8 stops with
# "Missing class com.google.android.play.core...".
-dontwarn com.google.android.play.core.**
-dontwarn io.flutter.embedding.engine.deferredcomponents.**
