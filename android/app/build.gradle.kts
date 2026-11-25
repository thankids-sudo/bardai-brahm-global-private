plugins {
    alias(libs.plugins.android.application)
    alias(libs.plugins.kotlin.android)
    alias(libs.plugins.kotlin.compose)
    alias(libs.plugins.kotlin.serialization)
}

android {
    namespace = "org.bardaibrahmglobal.app"
    compileSdk = 35

    defaultConfig {
        // Proposed application ID. It becomes permanent once published on Google Play,
        // so confirm it with the owner before the first release build.
        applicationId = "org.bardaibrahmglobal.app"
        minSdk = 26
        targetSdk = 35
        versionCode = 2
        versionName = "0.2.0-preview"

        // Backend connection. Supplied at build time (CI secrets or ~/.gradle/gradle.properties),
        // never committed. Empty values keep the app in offline preview mode.
        // The publishable key is designed to ship inside apps; database rules provide the security.
        buildConfigField("String", "SUPABASE_URL", "\"${backendSetting("SUPABASE_URL")}\"")
        buildConfigField("String", "SUPABASE_PUBLISHABLE_KEY", "\"${backendSetting("SUPABASE_PUBLISHABLE_KEY")}\"")
    }

    androidResources {
        // Generates the per-app language list for Android 13+ system settings.
        generateLocaleConfig = true
    }

    buildTypes {
        debug {
            applicationIdSuffix = ".debug"
            versionNameSuffix = "-debug"
        }
        release {
            isMinifyEnabled = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
            // No signing config: release signing is deliberately not set up in M1.
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    kotlinOptions {
        jvmTarget = "17"
    }
    buildFeatures {
        compose = true
        buildConfig = true
    }
    lint {
        abortOnError = true
        warningsAsErrors = false
        checkDependencies = false
        // Newer library versions exist; upgrading is a deliberate, tested step.
        disable += setOf("GradleDependency", "NewerVersionAvailable", "AndroidGradlePluginVersion", "OldTargetApi")
    }
    testOptions {
        unitTests.isReturnDefaultValues = true
        // Live backend tests read BBG_LIVE_* environment variables (inherited by test JVMs) and are
        // skipped when they are absent; CI sets them against a local Supabase (see supabase.yml).
    }
}

dependencies {
    implementation(libs.androidx.core.ktx)
    implementation(libs.androidx.appcompat)
    implementation(libs.androidx.lifecycle.runtime.ktx)
    implementation(libs.androidx.lifecycle.runtime.compose)
    implementation(libs.androidx.activity.compose)
    implementation(platform(libs.androidx.compose.bom))
    implementation(libs.androidx.compose.ui)
    implementation(libs.androidx.compose.ui.graphics)
    implementation(libs.androidx.compose.ui.tooling.preview)
    implementation(libs.androidx.compose.material3)
    implementation(libs.androidx.compose.material.icons.core)
    implementation(libs.androidx.navigation.compose)
    implementation(libs.androidx.lifecycle.viewmodel.ktx)
    implementation(libs.androidx.lifecycle.viewmodel.compose)
    implementation(libs.okhttp)
    implementation(libs.kotlinx.serialization.json)
    debugImplementation(libs.androidx.compose.ui.tooling)

    testImplementation(libs.junit)
    testImplementation(libs.okhttp.mockwebserver)
    testImplementation(libs.postgres.jdbc)
}

/** Reads a backend setting from a Gradle property (bbg.<name>) or an environment variable. */
fun backendSetting(name: String): String {
    val value = (project.findProperty("bbg.$name") as String?) ?: System.getenv(name) ?: ""
    require(!value.contains('"') && !value.contains('\\')) { "$name contains invalid characters" }
    return value.trim()
}
