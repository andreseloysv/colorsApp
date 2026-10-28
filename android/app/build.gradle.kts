import java.io.File
import java.net.URL
import java.security.MessageDigest

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

/* ------------------------------------------------------------------ */
/* Carril W2: modelos de sujeto empaquetados (sin descargas en runtime) */
/* ------------------------------------------------------------------ */
// Los modelos NO se versionan: esta tarea los baja de las URL fijadas del
// inventario del carril B (docs/research/android-subject.md §8.3), verifica
// su sha256 y los deja en build/generated/subjectModels/assets/models, que
// se añade a los assets de la app. Antes de bajar nada se busca en cachés
// locales: $CHROMASOL_MODELS_CACHE y, si existe, la carpeta de modelos que
// el carril B dejó en su worktree hermano (subject-research). La descarga
// es solo en tiempo de compilación en la máquina de desarrollo; la app no
// pide INTERNET (puerta make android-lint sobre el manifiesto fusionado).
data class SubjectModel(val file: String, val url: String, val sha256: String, val bytes: Long)

val subjectModels = listOf(
    SubjectModel(
        "pose_landmarker_full.task",
        "https://storage.googleapis.com/mediapipe-models/pose_landmarker/pose_landmarker_full/float16/1/pose_landmarker_full.task",
        "5134a3aad27a58b93da0088d431f366da362b44e3ccfbe3462b3827a839011b1", 9_398_198,
    ),
    SubjectModel(
        "magic_touch.tflite",
        "https://storage.googleapis.com/mediapipe-models/interactive_segmenter/magic_touch/float32/latest/magic_touch.tflite",
        "e24338a717c1b7ad8d159666677ef400babb7f33b8ad60c4d96db4ecf694cd25", 6_227_884,
    ),
    SubjectModel(
        "selfie_multiclass_256x256.tflite",
        "https://storage.googleapis.com/mediapipe-models/image_segmenter/selfie_multiclass_256x256/float32/latest/selfie_multiclass_256x256.tflite",
        "c6748b1253a99067ef71f7e26ca71096cd449baefa8f101900ea23016507e0e0", 16_371_837,
    ),
    SubjectModel(
        "efficientdet_lite2.tflite",
        "https://storage.googleapis.com/mediapipe-models/object_detector/efficientdet_lite2/float16/1/efficientdet_lite2.tflite",
        "5d4ebec1029bc9907aeadb9e7b4ac9cb1da6a19d01ad375210a9ae18ba173302", 12_138_859,
    ),
    SubjectModel(
        "face_detection_yunet_2023mar.onnx",
        "https://github.com/opencv/opencv_zoo/raw/main/models/face_detection_yunet/face_detection_yunet_2023mar.onnx",
        "8f2383e4dd3cfbb4553ea8718107fc0423210dc964f9f4280604804ed2552fa4", 232_589,
    ),
)

val subjectModelsOut = layout.buildDirectory.dir("generated/subjectModels/assets/models")

fun sha256Hex(f: File): String {
    val md = MessageDigest.getInstance("SHA-256")
    f.inputStream().use { ins ->
        val buf = ByteArray(1 shl 16)
        while (true) {
            val n = ins.read(buf)
            if (n < 0) break
            md.update(buf, 0, n)
        }
    }
    return md.digest().joinToString("") { "%02x".format(it) }
}

val downloadSubjectModels = tasks.register("downloadSubjectModels") {
    description = "Descarga (con sha256) los modelos de sujeto a los assets generados"
    val outDir = subjectModelsOut.get().asFile
    outputs.dir(outDir)
    inputs.property("models", subjectModels.joinToString("|") { "${it.file}:${it.sha256}" })
    doLast {
        val repoRoot = rootProject.projectDir.parentFile
        val cacheDirs = listOfNotNull(
            System.getenv("CHROMASOL_MODELS_CACHE")?.let { File(it) },
            File(
                repoRoot,
                "../subject-research/harness/out/android-subject/models",
            ),
            File(repoRoot, "build-android/models-cache"),
        )
        outDir.mkdirs()
        for (m in subjectModels) {
            val dest = File(outDir, m.file)
            if (dest.isFile && dest.length() == m.bytes && sha256Hex(dest) == m.sha256) continue
            var done = false
            for (dir in cacheDirs) {
                val cand = File(dir, m.file)
                if (cand.isFile && cand.length() == m.bytes && sha256Hex(cand) == m.sha256) {
                    cand.copyTo(dest, overwrite = true)
                    logger.lifecycle("modelo ${m.file}: desde caché ${cand.path}")
                    done = true
                    break
                }
            }
            if (!done) {
                logger.lifecycle("modelo ${m.file}: descargando ${m.url}")
                val tmp = File(outDir, m.file + ".part")
                URL(m.url).openStream().use { ins ->
                    tmp.outputStream().use { ins.copyTo(it) }
                }
                check(tmp.length() == m.bytes) { "${m.file}: ${tmp.length()} bytes != ${m.bytes}" }
                check(sha256Hex(tmp) == m.sha256) { "${m.file}: sha256 no coincide" }
                tmp.renameTo(dest)
            }
        }
        // Licencias resumidas junto a los modelos (inventario completo en
        // docs/research/android-subject.md §8.3).
        File(outDir, "MODELS.md").writeText(
            "# Modelos de sujeto (generado en compilación; no versionar)\n\n" +
                subjectModels.joinToString("\n") {
                    "- ${it.file} (${it.bytes} B, sha256 ${it.sha256})\n  ${it.url}"
                } +
                "\n\nLicencias: modelos MediaPipe Apache-2.0; YuNet MIT (OpenCV Zoo).\n",
        )
    }
}

// Assets de tests del carril W2: fotos CC0 de harness/people y, si está, la
// referencia iOS regenerada por el carril B (instances_split/garments PGM).
val subjectTestAssetsOut = layout.buildDirectory.dir("generated/subjectTestAssets")
val syncSubjectTestAssets = tasks.register<Sync>("syncSubjectTestAssets") {
    val repoRoot = rootProject.projectDir.parentFile
    from(File(repoRoot, "harness/people")) {
        include("0*.png", "synthetic_tight_selfie.png", "expected.json")
        into("people")
    }
    val iosRef = listOf(
        System.getenv("CHROMASOL_IOS_REF")?.let { File(it) },
        File(repoRoot, "../subject-research/harness/out/android-subject/ios-ref"),
    ).firstOrNull { it != null && it.isDirectory }
    if (iosRef != null) {
        from(iosRef) {
            include("*.instances_split.pgm", "*.garments.pgm", "*.json")
            into("ios-ref")
        }
    }
    into(subjectTestAssetsOut)
}

android {
    sourceSets {
        getByName("main") { assets.srcDir(subjectModelsOut.get().asFile.parentFile) }
        getByName("androidTest") { assets.srcDir(subjectTestAssetsOut) }
    }
}
tasks.configureEach {
    // Todo lo que lee los assets (merge, lint) depende de generarlos antes.
    if ((name.startsWith("merge") && name.endsWith("Assets")) || name.contains("lint", ignoreCase = true)) {
        dependsOn(downloadSubjectModels, syncSubjectTestAssets)
    }
}

dependencies {
    implementation(project(":engine"))

    // Carril W2: detección de personas (modelos empaquetados, sin red).
    // OJO: tasks-visión arrastra datatransport (telemetría de Google) y su
    // manifiesto inyecta INTERNET/ACCESS_NETWORK_STATE. No se puede excluir
    // sin romper TaskRunner (TasksStatsProtoLogger -> RemoteLoggingClient
    // -> CCTDestination al crear cualquier tarea; NoClassDefFoundError
    // comprobado en el AVD excluyendo el grupo y solo el backend CCT).
    // Neutralización: el AndroidManifest elimina ambos permisos en la
    // fusión (tools:node="remove") y make android-lint verifica el APK
    // release sin permisos de red. Quitar las clases del todo exigiría
    // LiteRT a pelo (informe §2.4): decisión anotada para el dueño.
    implementation(libs.mediapipe.tasks.vision)
    implementation(libs.onnxruntime.android)

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
