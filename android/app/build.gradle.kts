import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// 正式签名：仓库里不放密钥，本机 `android/key.properties` 存在时才启用。
// 格式（四行，键名固定）：
//   storeFile=../keys/upload.jks
//   storePassword=...
//   keyAlias=upload
//   keyPassword=...
val releaseKeyFile = rootProject.file("key.properties")
val releaseKeyProps = Properties().apply {
    if (releaseKeyFile.exists()) {
        releaseKeyFile.inputStream().use { load(it) }
    }
}

android {
    namespace = "com.tooldeer.app_worddeer"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.tooldeer.app_worddeer"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (releaseKeyFile.exists()) {
            create("release") {
                storeFile = rootProject.file(releaseKeyProps["storeFile"] as String)
                storePassword = releaseKeyProps["storePassword"] as String
                keyAlias = releaseKeyProps["keyAlias"] as String
                keyPassword = releaseKeyProps["keyPassword"] as String
            }
        }
    }

    buildTypes {
        release {
            // 有 key.properties 就用正式签名，没有就退回 debug 签名
            // （`flutter run --release` 本机调试要能跑），但会在构建日志里大声警告：
            // debug 签名的包上不了架，也没法和正式包覆盖安装。
            signingConfig = if (releaseKeyFile.exists()) {
                signingConfigs.getByName("release")
            } else {
                logger.warn(
                    "==============================================================\n" +
                    "  [!] 未找到 android/key.properties，release 包正在用 debug 签名。\n" +
                    "      这个包不能上架，也不能覆盖安装正式版。\n" +
                    "      补上上传密钥后再构建发布包。\n" +
                    "=============================================================="
                )
                signingConfigs.getByName("debug")
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
