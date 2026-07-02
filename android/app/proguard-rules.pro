# Flutter specific ProGuard rules
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }
-keep class io.flutter.embedding.** { *; }
-keep class io.flutter.embedding.engine.deferredcomponents.** { *; }

# Supabase
-keep class io.supabase.** { *; }
-keep class com.supabase.** { *; }

# Camera plugin
-keep class io.flutter.plugins.camera.** { *; }

# Mobile scanner
-keep class com.google.mlkit.** { *; }
-keep class com.google.android.gms.** { *; }

# Google Play Services (optional, keep if present)
-dontwarn com.google.android.play.core.**
-keep class com.google.android.play.core.** { *; }

# Retrofit (used by some plugins)
-keep class retrofit2.** { *; }
-keepclassmembers class * { @retrofit2.* <methods>; }

# OkHttp
-keep class okhttp3.** { *; }
-keep interface okhttp3.** { *; }

# Gson
-keep class com.google.gson.** { *; }
-keepclassmembers class * { @com.google.gson.annotations.* <fields>; }

# Remove logging
-assumenosideeffects class android.util.Log {
    public static *** d(...);
    public static *** v(...);
    public static *** i(...);
}

# Optimization
-optimizationpasses 5
-dontusemixedcaseclassnames
-allowaccessmodification
