// Contenedor de dependencias manual: espejo de
// ios/ColorsApp/App/AppEnvironment.swift. Se crea una vez en ColorsApp y se
// pasa a la UI por constructor (sin framework de DI, como en iOS sin
// librerías de inyección). Datos (W1): Room + diccionario JSON; carrete,
// sujeto y escaneo siguen con los sustitutos de la fundación hasta W2.
package com.andreseloy.colorsapp.app

import android.content.Context
import com.andreseloy.colorsapp.data.EmptyPhotoLibrarySource
import com.andreseloy.colorsapp.data.EngineWadaDictionary
import com.andreseloy.colorsapp.data.FeedbackRepository
import com.andreseloy.colorsapp.data.InMemoryFeedbackRepository
import com.andreseloy.colorsapp.data.InMemoryScanRepository
import com.andreseloy.colorsapp.data.InMemorySettingsRepository
import com.andreseloy.colorsapp.data.InMemoryUnlockRepository
import com.andreseloy.colorsapp.data.JsonWadaDictionary
import com.andreseloy.colorsapp.data.PhotoLibrarySource
import com.andreseloy.colorsapp.data.db.ColorsDatabase
import com.andreseloy.colorsapp.data.db.EngineVersions
import com.andreseloy.colorsapp.data.db.RoomFeedbackRepository
import com.andreseloy.colorsapp.data.db.RoomScanRepository
import com.andreseloy.colorsapp.data.db.RoomSettingsRepository
import com.andreseloy.colorsapp.data.db.RoomUnlockRepository
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
        /** Arranque real: diccionario JSON de los assets (con los nombres
         *  curados del idioma y el chequeo dict_version contra el motor),
         *  repositorios Room sobre colors.sqlite, contador de lanzamientos
         *  y runner inerte. No pide ningún permiso. */
        fun bootstrap(context: Context): AppContainer {
            val launches = LaunchCounter.increment(context)
            val dictionary = JsonWadaDictionary.load(context)
            check(dictionary.matchesEngine) {
                "dict_version ${dictionary.dictVersion} != motor $dictionaryVersion"
            }
            val database = ColorsDatabase.open(context)
            val versions = EngineVersions.fromEngine()
            return AppContainer(
                dictionary = dictionary,
                scans = RoomScanRepository(database, versions),
                unlocks = RoomUnlockRepository(database),
                feedback = RoomFeedbackRepository(database),
                settings = RoomSettingsRepository(database),
                photoLibrary = EmptyPhotoLibrarySource(),
                subjectSegmenter = WholePhotoSubjectSegmenter(),
                scanRunner = NoopScanRunner(),
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
