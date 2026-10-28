// Contenedor de dependencias manual: espejo de
// ios/ColorsApp/App/AppEnvironment.swift. Se crea una vez en ColorsApp y se
// pasa a la UI por constructor (sin framework de DI, como en iOS sin
// librerías de inyección). La ola 2 sustituye las implementaciones en
// memoria por Room/MediaStore/modelo de sujeto sin tocar las vistas.
package com.andreseloy.colorsapp.app

import android.content.Context
import com.andreseloy.colorsapp.data.EmptyPhotoLibrarySource
import com.andreseloy.colorsapp.data.EngineWadaDictionary
import com.andreseloy.colorsapp.data.FeedbackRepository
import com.andreseloy.colorsapp.data.InMemoryFeedbackRepository
import com.andreseloy.colorsapp.data.InMemoryScanRepository
import com.andreseloy.colorsapp.data.InMemorySettingsRepository
import com.andreseloy.colorsapp.data.InMemoryUnlockRepository
import com.andreseloy.colorsapp.data.PhotoLibrarySource
import com.andreseloy.colorsapp.data.ScanRepository
import com.andreseloy.colorsapp.data.SettingsRepository
import com.andreseloy.colorsapp.data.UnlockRepository
import com.andreseloy.colorsapp.data.WadaDictionary
import com.andreseloy.colorsapp.engine.colorEngineVersion
import com.andreseloy.colorsapp.engine.dictionaryVersion
import com.andreseloy.colorsapp.scan.NoopScanRunner
import com.andreseloy.colorsapp.scan.ScanProgress
import com.andreseloy.colorsapp.scan.ScanRunning
import com.andreseloy.colorsapp.subject.SubjectSegmenter
import com.andreseloy.colorsapp.subject.WholePhotoSubjectSegmenter
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import java.io.File

/** Contador de lanzamientos (LaunchCounter de iOS: fichero en filesDir). */
object LaunchCounter {
    private fun file(context: Context) = File(context.filesDir, "launches.txt")

    /** Incrementa y devuelve el total (0 si no se puede escribir). */
    fun increment(context: Context): Int {
        val next = read(context) + 1
        runCatching { file(context).writeText(next.toString()) }
        return read(context)
    }

    fun read(context: Context): Int =
        runCatching { file(context).readText().trim().toInt() }.getOrDefault(0)
}

class AppContainer(
    val dictionary: WadaDictionary,
    val scans: ScanRepository,
    val unlocks: UnlockRepository,
    val feedback: FeedbackRepository,
    val settings: SettingsRepository,
    val photoLibrary: PhotoLibrarySource,
    val subjectSegmenter: SubjectSegmenter,
    scanRunner: ScanRunning,
    val launches: Int,
) {
    var scanRunner: ScanRunning = scanRunner
        private set

    private val _scanProgress = MutableStateFlow(ScanProgress.IDLE)
    val scanProgress: StateFlow<ScanProgress> = _scanProgress

    /** ce_version() del motor C. */
    val engineVersion: String = colorEngineVersion

    /** ce_dict_version() embebida en el motor. */
    val engineDictVersion: String = dictionaryVersion

    val dictVersion: String get() = dictionary.dictVersion
    val comboCount: Int get() = dictionary.combinations.size

    init {
        attach(scanRunner)
    }

    /** Sustituye el runner del escaneo (la ola 2 pone el de MediaStore). */
    fun setScanRunner(runner: ScanRunning) {
        scanRunner = runner
        attach(runner)
    }

    private fun attach(runner: ScanRunning) {
        runner.onProgress = { _scanProgress.value = it }
    }

    companion object {
        /** Arranque real: diccionario del motor, repos en memoria (fundación;
         *  W1 pone Room), contador de lanzamientos y, desde el carril W2, el
         *  detector de personas de MediaPipe (perezoso: los modelos solo se
         *  cargan al primer análisis), la fuente MediaStore y el runner del
         *  escaneo día 0. No pide ningún permiso. */
        fun bootstrap(context: Context): AppContainer {
            val launches = LaunchCounter.increment(context)
            val dictionary = EngineWadaDictionary()
            check(dictionary.matchesEngine) {
                "dict_version ${dictionary.dictVersion} != motor $dictionaryVersion"
            }
            val scans = InMemoryScanRepository()
            val unlocks = InMemoryUnlockRepository()
            val settings = InMemorySettingsRepository()
            val appContext = context.applicationContext
            val photoLibrary = com.andreseloy.colorsapp.scan.MediaStorePhotoLibrarySource(appContext)
            val segmenter = com.andreseloy.colorsapp.subject.SubjectChainSegmenter(
                com.andreseloy.colorsapp.subject.MediaPipePersonDetector(appContext),
            )
            return AppContainer(
                dictionary = dictionary,
                scans = scans,
                unlocks = unlocks,
                feedback = InMemoryFeedbackRepository(),
                settings = settings,
                photoLibrary = photoLibrary,
                subjectSegmenter = segmenter,
                scanRunner = com.andreseloy.colorsapp.scan.MediaStoreScanRunner(
                    scans = scans,
                    unlocks = unlocks,
                    settings = settings,
                    dictionary = dictionary,
                    photoLibrary = photoLibrary,
                    segmenter = segmenter,
                ),
                launches = launches,
            )
        }

        /** Contenedor para tests y previews: todo en memoria, sin contador. */
        fun forTesting(): AppContainer = AppContainer(
            dictionary = EngineWadaDictionary(),
            scans = InMemoryScanRepository(),
            unlocks = InMemoryUnlockRepository(),
            feedback = InMemoryFeedbackRepository(),
            settings = InMemorySettingsRepository(),
            photoLibrary = EmptyPhotoLibrarySource(),
            subjectSegmenter = WholePhotoSubjectSegmenter(),
            scanRunner = NoopScanRunner(),
            launches = 0,
        )
    }
}
