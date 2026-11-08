# Flutter Proguard Rules
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.util.** { *; }
-keep class io.flutter.view.** { *; }
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }

# App native Kotlin code
-keep class com.example.attendance_app.** { *; }

# TensorFlow Lite
-keep class org.tensorflow.lite.** { *; }
-dontwarn org.tensorflow.lite.**

# Play Core deferred components
-dontwarn com.google.android.play.core.**

# Google ML Kit (Barcode Scanning, Commons, Vision Common)
-keep class com.google.mlkit.** { *; }
-keep interface com.google.mlkit.** { *; }
-keep class com.google.android.gms.internal.mlkit_** { *; }
-keep interface com.google.android.gms.internal.mlkit_** { *; }
-keep class com.google_mlkit_commons.** { *; }
-keep class com.google_mlkit_barcode_scanning.** { *; }
-keep class com.google.firebase.components.** { *; }

-keep class * implements com.google.firebase.components.ComponentRegistrar {
    public <init>();
    public *;
}

-keepclassmembers class * {
    @com.google.mlkit.** <methods>;
    @com.google.mlkit.** <fields>;
}

-dontwarn com.google.mlkit.**
-dontwarn com.google.android.gms.internal.mlkit_**
-dontwarn com.google_mlkit_commons.**
-dontwarn com.google_mlkit_barcode_scanning.**
