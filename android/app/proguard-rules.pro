# Flutter
# Flutter 工具链生成的代码不应被混淆
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.util.** { *; }
-keep class io.flutter.view.** { *; }
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }
-dontwarn io.flutter.embedding.**

# Flutter R8 hot reload 支持
-keep class io.flutter.util.DartUtils { *; }

# Isar 数据库（依赖反射访问 Schema 与序列化器）
-keep class isar.** { *; }
-keep class com.isar.** { *; }
-keepattributes Signature, *Annotation*
-keep class com.jerrysuite.jerry_suite.core.models.** { *; }

# WorkManager（callbackDispatcher 顶级函数被反射调用）
-keep class androidx.work.** { *; }
-keep class dev.fluttercommunity.workmanager.** { *; }
-keep class com.jerrysuite.jerry_suite.** { *; }

# flutter_local_notifications
-keep class com.dexterous.** { *; }

# url_launcher
-keep class io.flutter.plugins.urllauncher.** { *; }

# permission_handler
-keep class com.baseflow.** { *; }

# wakelock_plus
-keep class dev.fluttercommunity.plus.wakelock.** { *; }

# cryptography 包（纯 Dart，但需保留平台通道）
-keep class dev.fluttercommunity.plus.** { *; }

# 保留原生方法
-keepclasseswithmembernames class * {
    native <methods>;
}

# 保留 Parcelable 序列化
-keepclassmembers class * implements android.os.Parcelable {
    public static final android.os.Parcelable$Creator CREATOR;
}

# 保留枚举
-keepclassmembers enum * {
    public static **[] values();
    public static ** valueOf(java.lang.String);
}
