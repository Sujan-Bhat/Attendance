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

