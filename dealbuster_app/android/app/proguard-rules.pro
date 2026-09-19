# Suppress warnings for optional Play Store deferred components in Flutter embedding
-dontwarn com.google.android.play.core.**

# Keep MainActivity so Android can launch it by reflection from AndroidManifest.xml
-keep class com.dealbusterindia.app.MainActivity {
    public <init>();
}


