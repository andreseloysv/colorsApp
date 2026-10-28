// App ChromaSol: Compose, una sola actividad, sin red en tiempo de ejecución.
// La firma de release solo se aplica si están las variables de entorno
// CHROMASOL_KEYSTORE_PATH / CHROMASOL_KEYSTORE_ALIAS / CHROMASOL_KEYSTORE_PASSWORD
// (y CHROMASOL_KEY_PASSWORD si difiere); sin ellas el AAB sale sin firmar y se
// puede firmar después con apksigner/bundletool o con Play App Signing.
plugins {
    alias(libs.plugins.android.application)
    alias(libs.plugins.kotlin.android)
    alias(libs.plugins.kotlin.compose)
    alias(libs.plugins.ksp)
}

val keystorePath: String? = System.getenv("CHROMASOL_KEYSTORE_PATH")?.takeIf { it.isNotBlank() }
val keystoreAlias: String? = System.getenv("CHROMASOL_KEYSTORE_ALIAS")?.takeIf { it.isNotBlank() }
val keystorePassword: String? = System.getenv("CHROMASOL_KEYSTORE_PASSWORD")
val keyPassword: String? = System.getenv("CHROMASOL_KEY_PASSWORD") ?: keystorePassword
val hasReleaseSigning = keystorePath != null && keystoreAlias != null && keystorePassword != null

// Diccionario de Wada como assets generados (docs/ANDROID.md §4, carril W1):
// dictionary.json sale siempre de data/wada del repo; los nombres curados
// (names.es.json es ruta protegida y names.de.json puede no estar aún en el
// HEAD de esta rama) se leen de un directorio configurable y se copian a
// build/: nunca se duplica un fichero protegido en una ruta versionada.
// Configuración, en orden: -PwadaNamesDir=<dir>, variable de entorno
// COLORSAPP_WADA_NAMES_DIR, el checkout principal hermano
// (../../colorsApp/data/wada desde un carril en colorsApp-lanes/<carril>)
// y, si ninguno trae names.de.json, data/wada del propio repo (en tiempo de
// ejecución el alemán cae entonces a los nombres en español, como en iOS).
val repoRoot = rootProject.projectDir.parentFile
val wadaRepoDir = File(repoRoot, "data/wada")
val wadaNamesCandidates = listOfNotNull(
    providers.gradleProperty("wadaNamesDir").orNull?.takeIf { it.isNotBlank() }?.let { File(it) },
    System.getenv("COLORSAPP_WADA_NAMES_DIR")?.takeIf { it.isNotBlank() }?.let { File(it) },
    File(repoRoot, "../../colorsApp/data/wada").canonicalFile,
    wadaRepoDir,
)
val wadaNamesDir = wadaNamesCandidates.firstOrNull { File(it, "names.de.json").isFile }
    ?: wadaNamesCandidates.first()

/** Copia el diccionario y los nombres curados a `<salida>/wada/`. */
abstract class SyncWadaAssetsTask : DefaultTask() {
    @get:InputFile
    abstract val dictionaryJson: RegularFileProperty

    @get:InputFile
    abstract val namesEsJson: RegularFileProperty

    @get:InputFile
    @get:Optional
    abstract val namesDeJson: RegularFileProperty

    @get:OutputDirectory
    abstract val outputDir: DirectoryProperty

    @TaskAction
    fun copy() {
        val target = outputDir.get().dir("wada").asFile
        target.mkdirs()
        dictionaryJson.get().asFile.copyTo(File(target, "dictionary.json"), overwrite = true)
        namesEsJson.get().asFile.copyTo(File(target, "names.es.json"), overwrite = true)
        if (namesDeJson.isPresent) {
            namesDeJson.get().asFile.copyTo(File(target, "names.de.json"), overwrite = true)
        }
    }
}

val syncWadaAssets by tasks.registering(SyncWadaAssetsTask::class) {
    description = "Copia dictionary.json y los nombres curados a los assets generados"
    dictionaryJson.set(File(wadaRepoDir, "dictionary.json"))
    namesEsJson.set(File(wadaNamesDir, "names.es.json"))
    if (File(wadaNamesDir, "names.de.json").isFile) {
        namesDeJson.set(File(wadaNamesDir, "names.de.json"))
    }
    doFirst {
        check(File(wadaRepoDir, "dictionary.json").isFile) {
            "falta data/wada/dictionary.json en $wadaRepoDir"
        }
        check(File(wadaNamesDir, "names.es.json").isFile) {
            "falta names.es.json en el directorio de nombres $wadaNamesDir " +
                "(configúralo con -PwadaNamesDir o COLORSAPP_WADA_NAMES_DIR)"
        }
        logger.lifecycle("Wada: dictionary.json de $wadaRepoDir; nombres curados de $wadaNamesDir")
    }
}

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

// Assets del diccionario generados por syncWadaAssets (en build/): se
// registran por variante para que merge, lint y empaquetado declaren la
// dependencia con la tarea que los copia.
androidComponents {
    onVariants { variant ->
        variant.sources.assets?.addGeneratedSourceDirectory(syncWadaAssets) { it.outputDir }
    }
}

ksp {
    // Esquemas Room versionados junto al módulo (los usan las migraciones).
    arg("room.schemaLocation", layout.projectDirectory.dir("schemas").asFile.absolutePath)
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
    implementation(libs.androidx.room.runtime)
    implementation(libs.androidx.room.ktx)
    implementation(libs.kotlinx.serialization.json)
    ksp(libs.androidx.room.compiler)

    testImplementation(libs.junit)
    testImplementation(libs.kotlinx.coroutines.test)
    androidTestImplementation(libs.androidx.test.ext.junit)
    androidTestImplementation(libs.androidx.test.espresso.core)
    androidTestImplementation(platform(libs.androidx.compose.bom))
    androidTestImplementation(libs.androidx.compose.ui.test.junit4)
    debugImplementation(libs.androidx.compose.ui.tooling)
    debugImplementation(libs.androidx.compose.ui.test.manifest)
}
