# Flutter engine and plugin rules
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.**  { *; }
-keep class io.flutter.util.**  { *; }
-keep class io.flutter.view.**  { *; }
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }

# App main activity and package
-keep class com.dealbusterindia.app.** { *; }
-keep class * extends io.flutter.embedding.android.FlutterActivity { *; }
-keep class * extends io.flutter.embedding.android.FlutterFragmentActivity { *; }

# Firebase Messaging & Core
-dontwarn com.google.firebase.**
-keep class com.google.firebase.** { *; }
-dontwarn com.google.android.gms.**
-keep class com.google.android.gms.** { *; }

# Prevent shrinking AndroidX Activity components used for edge-to-edge
-keep class androidx.activity.** { *; }
-keep class androidx.core.view.** { *; }

# Play Core deferred components optional classes
-dontwarn com.google.android.play.core.**

