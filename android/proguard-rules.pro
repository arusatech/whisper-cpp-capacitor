# Keep JNI native methods
-keepclasseswithmembernames class * {
    native <methods>;
}

# Capacitor
-keep class com.getcapacitor.** { *; }
