plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
}

android {
    namespace = "net.teamceleste.mayhemkart"
    compileSdk = 35

    defaultConfig {
        applicationId = "net.teamceleste.mayhemkart"
        minSdk = 26
        targetSdk = 35
        versionCode = 2600
        versionName = "26.0"

        javaCompileOptions {
            annotationProcessorOptions {
                argument("kotlin.incremental", "true")
            }
        }
    }
}

dependencies {
    implementation("androidx.core:core-ktx:1.15.0")
    implementation("androidx.appcompat:appcompat:1.7.0")
}


java {
    toolchain {
        languageVersion.set(JavaLanguageVersion.of(17))
    }
}

kotlin {
    jvmToolchain(17)
}
