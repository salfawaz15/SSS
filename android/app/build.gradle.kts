import java.util.Properties
import java.io.FileInputStream

plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
    // Firebase / Google services
    id("com.google.gms.google-services")
}

// توقيع ثابت (upload key) بدل مفتاح "debug" الافتراضي العشوائي - كل مُشغِّل
// GitHub Actions يُنشئ ~/.android/debug.keystore عشوائيًا جديدًا (لا يُخزَّن
// بين التشغيلات)، فكان توقيع كل تشغيل CI يختلف عن السابق، فيرفض أندرويد
// "App not installed as package conflicts with an existing package" عند أي
// تحديث - خلل حقيقي واجهه سليمان فعليًا 2026-08-25 بتطبيق "بوابة الإرشاد"
// عند أول تشغيل CI له. الملف `key.properties` (غير موجود بالمستودع - يُكتَب
// وقت تشغيل CI فقط من GitHub Secrets، انظر deploy.yml) يوفّر مسار/كلمات
// مرور مفتاح ثابت؛ إن غاب (تطوير محلي عادي) يُستخدَم توقيع "debug" الافتراضي
// كما كان - لا يُكسَر أي بناء محلي حالي.
val keystorePropertiesFile = rootProject.file("key.properties")
val keystoreProperties = Properties()
val hasUploadKeystore = keystorePropertiesFile.exists()
if (hasUploadKeystore) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

android {
    namespace = "com.sulaiman.chat"
    // Require at least API 36 for some plugins (file_picker, lifecycle, etc.)
    compileSdk = maxOf(36, flutter.compileSdkVersion)
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.sulaiman.chat"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = maxOf(flutter.minSdkVersion, 23)
        targetSdk = maxOf(flutter.targetSdkVersion, 36)
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    flavorDimensions += "app"
    productFlavors {
        create("sulaiman") {
            dimension = "app"
            applicationId = "com.sulaiman.chat"
        }
        create("advising") {
            dimension = "app"
            applicationId = "com.taif.cba.advising"
        }
        create("advisingPortal") {
            dimension = "app"
            applicationId = "com.taif.cba.advisingportal"
        }
    }

    signingConfigs {
        if (hasUploadKeystore) {
            create("upload") {
                storeFile = file(keystoreProperties.getProperty("storeFile"))
                storePassword = keystoreProperties.getProperty("storePassword")
                keyAlias = keystoreProperties.getProperty("keyAlias")
                keyPassword = keystoreProperties.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        release {
            // مفتاح ثابت (upload) إن توفّر key.properties (دومًا بـCI)، وإلا
            // مفتاح "debug" الافتراضي كما كان (تطوير محلي بلا الملف).
            signingConfig = if (hasUploadKeystore) signingConfigs.getByName("upload") else signingConfigs.getByName("debug")
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
