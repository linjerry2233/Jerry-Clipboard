import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val signingProperties = Properties()
val signingPropertiesFile = rootProject.file("key.properties")
if (signingPropertiesFile.exists()) {
    signingPropertiesFile.inputStream().use(signingProperties::load)
}

fun signingValue(propertyName: String, environmentName: String): String? =
    signingProperties.getProperty(propertyName)?.takeIf { it.isNotBlank() }
        ?: System.getenv(environmentName)?.takeIf { it.isNotBlank() }

val releaseStoreFile = signingValue("storeFile", "JERRY_ANDROID_STORE_FILE")
val releaseStorePassword =
    signingValue("storePassword", "JERRY_ANDROID_STORE_PASSWORD")
val releaseKeyAlias = signingValue("keyAlias", "JERRY_ANDROID_KEY_ALIAS")
val releaseKeyPassword =
    signingValue("keyPassword", "JERRY_ANDROID_KEY_PASSWORD")
val hasReleaseSigning =
    listOf(
        releaseStoreFile,
        releaseStorePassword,
        releaseKeyAlias,
        releaseKeyPassword,
    ).all { it != null }

android {
    namespace = "com.jerrysuite.jerry_suite"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        // flutter_local_notifications 要求启用 core library desugaring
        isCoreLibraryDesugaringEnabled = true
    }

    defaultConfig {
        applicationId = "com.jerrysuite.jerry_suite"
        // Android 7.0+：剪贴板监听、通知渠道、WorkManager 需要
        minSdk = 24
        // Android 16；满足 2026 年 Google Play 新应用/更新要求。
        targetSdk = 36
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    dependencies {
        coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.5")
    }

    signingConfigs {
        if (hasReleaseSigning) {
            create("release") {
                storeFile = rootProject.file(releaseStoreFile!!)
                storePassword = releaseStorePassword
                keyAlias = releaseKeyAlias
                keyPassword = releaseKeyPassword
            }
        }
    }

    buildTypes {
        release {
            // 不允许发布包退回到 debug 签名。可通过 android/key.properties
            // 或 JERRY_ANDROID_* 环境变量注入正式签名；未配置时产出未签名 APK。
            // Release builds use the dedicated key when configured. A task
            // guard below rejects a missing key before any Release artifact is
            // produced, while keeping Debug builds usable on fresh checkouts.
            signingConfig =
                if (hasReleaseSigning) signingConfigs.getByName("release") else null

            // 关闭 R8 代码压缩与混淆，绕过 AGP 8.x 在 Windows 上的
            // extractReleaseAnnotations 任务 AccessDeniedException bug
            isMinifyEnabled = false
            isShrinkResources = false
        }
    }

    // 发布构建不得静默忽略 Android lint 错误。
    lint {
        abortOnError = true
        checkReleaseBuilds = true
    }
}

// Never allow a Release APK/AAB to be produced without a release signature.
// The guard runs at task execution time so `flutter build apk --debug` remains
// available for development on machines that do not hold the private key.
tasks.configureEach {
    if (name.contains("Release", ignoreCase = true)) {
        doFirst {
            if (!hasReleaseSigning) {
                throw GradleException(
                    "Release signing is required. Configure android/key.properties " +
                        "or JERRY_ANDROID_STORE_FILE/STORE_PASSWORD/KEY_ALIAS/KEY_PASSWORD.",
                )
            }
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}
