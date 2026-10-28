// Motor de color (C11) para Android: JNI + API Kotlin. Sin lógica de color en
// Kotlin; todo pasa por engine/Sources/CColorEngine (ver src/main/cpp).
//
// El trabajo de copiar las fixtures de paridad reutiliza los goldens del repo
// (harness/golden y harness/wasm/fixtures) sin duplicarlos en git: se copian
// a build/ en cada compilación de tests instrumentados.
import org.gradle.api.tasks.Sync

plugins {
    alias(libs.plugins.android.library)
    alias(libs.plugins.kotlin.android)
}

val parityAssetsDir = layout.buildDirectory.dir("generated/parityAssets")

val syncParityAssets by tasks.registering(Sync::class) {
    // android/engine -> raíz del repo
    val repo = rootProject.projectDir.parentFile
    from(File(repo, "harness/golden/palettes_20.json"))
    from(File(repo, "harness/golden/match_50.json"))
    from(File(repo, "harness/golden/fixtures")) { into("golden") }
    from(File(repo, "harness/wasm/fixtures")) { into("wasm") }
    // El esperado de las fixtures WASM (wasm_expected.json, generado con el
    // CLI nativo `ce` por android/tools/gen_wasm_expected.py) vive en
    // src/androidTest/assets, junto al test que lo lee.
    into(parityAssetsDir)
}

android {
    namespace = "com.andreseloy.colorsapp.engine"
    compileSdk = 36

    defaultConfig {
        minSdk = 26
        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"
        consumerProguardFiles("consumer-rules.pro")

        ndk {
            abiFilters += listOf("arm64-v8a", "x86_64")
        }
        externalNativeBuild {
            cmake {
                arguments("-DANDROID_STL=none")
            }
        }
    }

    buildTypes {
        release {
            isMinifyEnabled = false
        }
    }

    externalNativeBuild {
        cmake {
            path = file("src/main/cpp/CMakeLists.txt")
            version = "3.22.1"
        }
    }
    ndkVersion = "29.0.14206865"

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    kotlinOptions {
        jvmTarget = "17"
    }

    sourceSets {
        getByName("androidTest") {
            assets.srcDir(parityAssetsDir)
        }
    }

    testOptions {
        unitTests.all {
            // Los tests de unidad no cargan la librería nativa (no hay .so de host).
            it.useJUnit()
        }
    }
}

// Los assets sincronizados deben existir antes de fusionar los de androidTest.
tasks.configureEach {
    if (name.contains("AndroidTest") && name.contains("Assets")) {
        dependsOn(syncParityAssets)
    }
}

dependencies {
    testImplementation(libs.junit)
    androidTestImplementation(libs.androidx.test.ext.junit)
    androidTestImplementation(libs.androidx.test.espresso.core)
}
