// App ChromaSol: Compose, una sola actividad, sin red en tiempo de ejecución.
// La firma de release solo se aplica si están las variables de entorno
// CHROMASOL_KEYSTORE_PATH / CHROMASOL_KEYSTORE_ALIAS / CHROMASOL_KEYSTORE_PASSWORD
// (y CHROMASOL_KEY_PASSWORD si difiere); sin ellas el AAB sale sin firmar y se
// puede firmar después con apksigner/bundletool o con Play App Signing.
plugins {
    alias(libs.plugins.android.application)
    alias(libs.plugins.kotlin.android)
    alias(libs.plugins.kotlin.compose)
}

val keystorePath: String? = System.getenv("CHROMASOL_KEYSTORE_PATH")?.takeIf { it.isNotBlank() }
val keystoreAlias: String? = System.getenv("CHROMASOL_KEYSTORE_ALIAS")?.takeIf { it.isNotBlank() }
val keystorePassword: String? = System.getenv("CHROMASOL_KEYSTORE_PASSWORD")
val keyPassword: String? = System.getenv("CHROMASOL_KEY_PASSWORD") ?: keystorePassword
val hasReleaseSigning = keystorePath != null && keystoreAlias != null && keystorePassword != null

android {
    namespace = "com.andreseloy.colorsapp"
    compileSdk = 36

    defaultConfig {
        applicationId = "com.andreseloy.colorsapp"
        minSdk = 26
        targetSdk = 36
        versionCode = 1
        versionName = "1.0.0"
        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"


        vectorDrawables {
            useSupportLibrary = true
        }

        ndk {
            // Solo los .so del motor: arm64 (dispositivos) y x86_64 (emulador).
            abiFilters += listOf("arm64-v8a", "x86_64")
        }
    }

    signingConfigs {
        if (hasReleaseSigning) {
            create("release") {
                storeFile = file(keystorePath!!)
                storePassword = keystorePassword
                keyAlias = keystoreAlias
                keyPassword = keyPassword
            }
        }
    }

    buildTypes {
        release {
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )
            if (hasReleaseSigning) {
                signingConfig = signingConfigs.getByName("release")
            }
            ndk {
                // Símbolos de depuración completos fuera del AAB público.
                debugSymbolLevel = "SYMBOL_TABLE"
            }
        }
        debug {
            applicationIdSuffix = ""
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
    }

    androidResources {
        // Español (fuente y respaldo), alemán e inglés: lo que hay en res/.
        localeFilters += listOf("es", "de", "en")
    }

    packaging {
        resources {
            excludes += "META-INF/*"
        }
    }

    lint {
        // La puerta "sin Internet" tiene su propio destino (make android-lint).
        abortOnError = true
    }
}

dependencies {
    implementation(project(":engine"))

    implementation(libs.androidx.activity.compose)
    implementation(platform(libs.androidx.compose.bom))
    implementation(libs.androidx.compose.ui)
    implementation(libs.androidx.compose.ui.graphics)
    implementation(libs.androidx.compose.ui.tooling.preview)
    implementation(libs.androidx.compose.material3)
    implementation(libs.androidx.navigation.compose)
    implementation(libs.androidx.lifecycle.viewmodel.compose)
    implementation(libs.androidx.lifecycle.runtime.compose)
    implementation(libs.kotlinx.coroutines.android)

    testImplementation(libs.junit)
    testImplementation(libs.kotlinx.coroutines.test)
    androidTestImplementation(libs.androidx.test.ext.junit)
    androidTestImplementation(libs.androidx.test.espresso.core)
    androidTestImplementation(platform(libs.androidx.compose.bom))
    androidTestImplementation(libs.androidx.compose.ui.test.junit4)
    debugImplementation(libs.androidx.compose.ui.tooling)
    debugImplementation(libs.androidx.compose.ui.test.manifest)
}
