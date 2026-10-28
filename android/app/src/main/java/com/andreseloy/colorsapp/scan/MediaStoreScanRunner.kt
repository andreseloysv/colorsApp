// Escaneo del carrete día 0 con MediaStore: el PhotoKitScanRunner de iOS
// (PLAN §7.6) en Android. Miniaturas de 256 px, 3 análisis en paralelo (un
// ce_ctx por tarea, dentro de PhotoAnalyzer), scans + unlocks persistidos
// (top-1 con score <= unlockMaxScore del ajuste, 12 por defecto), progreso
// publicado por onProgress y resumen tipo Wrapped (topCombos, topColors,
// color firma). Acceso limitado (API 34+): no se puede enumerar; resumen
// vacío con needsPicker y la UI ofrece el selector de fotos del sistema
// (sin permiso), cuyas fotos entran por scanUris/scanBitmaps. El permiso lo
// pide la UI en contexto antes de llamar (este runner no tiene Activity).
package com.andreseloy.colorsapp.scan

import android.graphics.Bitmap
import android.net.Uri
import android.util.Log
import com.andreseloy.colorsapp.data.LibraryAccess
import com.andreseloy.colorsapp.data.LibraryPhoto
import com.andreseloy.colorsapp.data.PhotoLibrarySource
import com.andreseloy.colorsapp.data.ScanRepository
import com.andreseloy.colorsapp.data.ScanSource
import com.andreseloy.colorsapp.data.SettingsRepository
import com.andreseloy.colorsapp.data.UnlockRepository
import com.andreseloy.colorsapp.data.WadaDictionary
import com.andreseloy.colorsapp.engine.AnalysisResult
import com.andreseloy.colorsapp.subject.SubjectSegmenter
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.async
import kotlinx.coroutines.awaitAll
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.sync.Semaphore
import kotlinx.coroutines.sync.withPermit
import java.time.Instant

/** Política del escaneo (ScanPolicy de iOS). */
data class ScanPolicy(
    /** Score máximo del top-1 para desbloquear (ajuste unlock_max_score). */
    val unlockMaxScore: Double = 12.0,
    /** Lado de la miniatura pedida para analizar (256 px, PLAN §7.6). */
    val targetSide: Int = 256,
    /** Análisis concurrentes (un ce_ctx y una detección por tarea). */
    val concurrency: Int = 3,
    /** Hits guardados por scan (top1..top3). */
    val topK: Int = 3,
) {
    /** Combinación a desbloquear con este resultado, o null. */
    fun unlockCandidate(result: AnalysisResult): Int? {
        val top = result.hits.firstOrNull() ?: return null
        return if (top.score <= unlockMaxScore) top.comboId else null
    }
}

class MediaStoreScanRunner(
    private val scans: ScanRepository,
    private val unlocks: UnlockRepository,
    private val settings: SettingsRepository,
    private val dictionary: WadaDictionary,
    private val photoLibrary: PhotoLibrarySource,
    private val segmenter: SubjectSegmenter,
    private val policy: ScanPolicy = ScanPolicy(),
) : ScanRunning {

    override var progress: ScanProgress = ScanProgress.IDLE
        private set
    override var onProgress: ((ScanProgress) -> Unit)? = null

    /** Último resumen y recuento de pasos (diagnósticos, como en iOS). */
    var lastSummary: ScanSummary? = null
        private set
    var lastStepCounts: Map<String, Int> = emptyMap()
        private set
    var lastDurationMs: Long = 0
        private set

    private fun publish(p: ScanProgress) {
        progress = p
        onProgress?.invoke(p)
    }

    override suspend fun runInitialScan(limit: Int): ScanSummary {
        val startedAt = System.currentTimeMillis()
        publish(ScanProgress(phase = ScanProgress.Phase.REQUESTING_ACCESS, startedAtMs = startedAt))
        when (photoLibrary.access()) {
            LibraryAccess.FULL, LibraryAccess.DENIED -> {
                // DENIED sin enumerar daría 0 fotos: se trata igual que en
                // iOS se distinguiría tras pedir el permiso en la UI.
                if (photoLibrary.access() == LibraryAccess.DENIED) {
                    publish(progress.copy(phase = ScanProgress.Phase.FAILED))
                    throw ScanException.AccessDenied()
                }
            }
            LibraryAccess.LIMITED -> {
                val total = unlocks.count()
                publish(progress.copy(phase = ScanProgress.Phase.FINISHED))
                Log.i(TAG, "scan.limited: acceso limitado a Fotos, se ofrece el picker")
                return ScanSummary.empty(needsPicker = true, totalUnlocked = total, nowMs = startedAt)
                    .also { lastSummary = it }
            }
            LibraryAccess.NOT_DETERMINED -> {
                publish(progress.copy(phase = ScanProgress.Phase.FAILED))
                throw ScanException.AccessDenied()
            }
        }
        publish(progress.copy(phase = ScanProgress.Phase.FETCHING))
        val photos = photoLibrary.recentPhotos(limit)
        val inputs = photos.map { Input.Library(it) }
        return scan(inputs, ScanSource.LIBRARY, startedAt, markInitialDone = true)
    }

    /** Fotos elegidas con el selector del sistema (acceso limitado). */
    suspend fun scanUris(uris: List<Uri>): ScanSummary {
        val startedAt = System.currentTimeMillis()
        val inputs = uris.map { uri ->
            Input.Library(LibraryPhoto(id = uri.toString(), uri = uri, dateTakenMs = 0, width = 0, height = 0))
        }
        return scan(inputs, ScanSource.PICKER, startedAt, markInitialDone = false, fullSize = true)
    }

    /** Bitmaps ya decodificados (tests y otras rutas de la app). */
    suspend fun scanBitmaps(images: List<Pair<String?, Bitmap>>, source: ScanSource = ScanSource.LIBRARY): ScanSummary {
        val startedAt = System.currentTimeMillis()
        return scan(images.map { Input.BitmapInput(it.first, it.second) }, source, startedAt, markInitialDone = false)
    }

    private sealed class Input(val id: String?) {
        class Library(val photo: LibraryPhoto) : Input(photo.id)
        class BitmapInput(id: String?, val bitmap: Bitmap) : Input(id)
    }

    private sealed class WorkerResult {
        class Analyzed(val id: String?, val analysis: PhotoAnalysis) : WorkerResult()
        class Skipped(val id: String?) : WorkerResult()
        class Failed(val id: String?, val error: String) : WorkerResult()
    }

    private suspend fun scan(
        inputs: List<Input>,
        source: ScanSource,
        startedAt: Long,
        markInitialDone: Boolean,
        fullSize: Boolean = false,
    ): ScanSummary {
        var state = ScanProgress(
            phase = ScanProgress.Phase.ANALYZING, processed = 0,
            total = inputs.size, skipped = 0, unlocked = 0, startedAtMs = startedAt,
        )
        publish(state)
        val subjectSettings = runCatching { settings.subjectSettings() }
            .getOrElse { com.andreseloy.colorsapp.subject.SubjectSettings() }
        val effectivePolicy = policy.copy(unlockMaxScore = subjectSettings.unlockMaxScore)
        val subjectOptions = subjectSettings.subjectOptions()

        suspend fun work(input: Input): WorkerResult {
            val bitmap: Bitmap? = when (input) {
                is Input.Library -> if (fullSize) {
                    photoLibrary.loadBitmap(input.photo, 1024)
                } else {
                    photoLibrary.loadThumbnail(input.photo, effectivePolicy.targetSide)
                }
                is Input.BitmapInput -> input.bitmap
            }
            if (bitmap == null) return WorkerResult.Skipped(input.id)
            return try {
                val analysis = PhotoAnalyzer.analyze(bitmap, segmenter, subjectOptions, effectivePolicy.topK)
                WorkerResult.Analyzed(input.id, analysis)
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                WorkerResult.Failed(input.id, e.message ?: e.javaClass.simpleName)
            }
        }

        var scanned = 0
        var failed = 0
        val newUnlocks = ArrayList<Int>()
        val comboCounts = HashMap<Int, Int>()
        val stepCounts = HashMap<String, Int>()
        try {
            coroutineScope {
                val gate = Semaphore(max(1, effectivePolicy.concurrency))
                val jobs = inputs.map { input ->
                    async(Dispatchers.Default) { gate.withPermit { work(input) } }
                }
                // Se persisten en el orden de finalización observable (await
                // en orden de lanzamiento basta para el progreso y para iOS
                // solo importan los recuentos, no el orden de inserción).
                for (job in jobs) {
                    when (val result = job.await()) {
                        is WorkerResult.Analyzed -> {
                            for (step in result.analysis.subject.steps) {
                                stepCounts[step.raw] = (stepCounts[step.raw] ?: 0) + 1
                            }
                            val record = PhotoAnalyzer.makeScanRecord(
                                result.analysis, source, result.id, subjectOptions,
                            )
                            scans.insert(record)
                            scanned++
                            result.analysis.result.hits.firstOrNull()?.let {
                                comboCounts[it.comboId] = (comboCounts[it.comboId] ?: 0) + 1
                            }
                            val candidate = effectivePolicy.unlockCandidate(result.analysis.result)
                            if (candidate != null &&
                                unlocks.unlock(candidate, source, result.id, record.id)
                            ) {
                                newUnlocks.add(candidate)
                            }
                        }
                        is WorkerResult.Skipped -> state = state.copy(skipped = state.skipped + 1)
                        is WorkerResult.Failed -> {
                            failed++
                            Log.e(TAG, "scan.fail ${result.id}: ${result.error}")
                        }
                    }
                    state = state.copy(processed = state.processed + 1, unlocked = newUnlocks.size)
                    publish(state)
                }
            }
        } catch (e: CancellationException) {
            publish(state.copy(phase = ScanProgress.Phase.FAILED))
            throw ScanException.Cancelled()
        } catch (e: Exception) {
            publish(state.copy(phase = ScanProgress.Phase.FAILED))
            throw e
        }

        val finishedAt = System.currentTimeMillis()
        val totalUnlocked = unlocks.count()
        val colors = colorCounts(comboCounts, dictionary)
        val summary = ScanSummary(
            scanned = scanned,
            skipped = state.skipped,
            failed = failed,
            newUnlocks = newUnlocks,
            totalUnlocked = totalUnlocked,
            topCombos = sortedCounts(comboCounts).map { ComboCount(it.key, it.value) },
            startedAtMs = startedAt,
            finishedAtMs = finishedAt,
            topColors = colors.map { ColorCount(it.key, it.value) },
            signatureColorIndex = colors.firstOrNull()?.key,
            needsPicker = false,
        )
        lastSummary = summary
        lastStepCounts = stepCounts
        lastDurationMs = finishedAt - startedAt
        if (markInitialDone) {
            settings.setBool(SettingsRepository.Key.INITIAL_SCAN_DONE, true)
            settings.set(
                SettingsRepository.Key.INITIAL_SCAN_AT,
                Instant.ofEpochMilli(finishedAt).toString(),
            )
            settings.setInt(SettingsRepository.Key.INITIAL_SCAN_COUNT, scanned)
        }
        publish(state.copy(phase = ScanProgress.Phase.FINISHED))
        Log.i(
            TAG,
            "scan.done $scanned en ${finishedAt - startedAt}ms (omitidas ${state.skipped}, " +
                "fallidas $failed, nuevas ${newUnlocks.size}, total $totalUnlocked, " +
                "pasos ${stepsText(stepCounts)})",
        )
        return summary
    }

    companion object {
        private const val TAG = "MediaStoreScanRunner"

        /** Recuentos ordenados por valor descendente, desempate por clave. */
        fun sortedCounts(counts: Map<Int, Int>): List<Map.Entry<Int, Int>> =
            counts.entries.sortedWith(compareByDescending<Map.Entry<Int, Int>> { it.value }.thenBy { it.key })

        /** Colores del diccionario en los top-1, ponderados por fotos. */
        fun colorCounts(comboCounts: Map<Int, Int>, dictionary: WadaDictionary): List<Map.Entry<Int, Int>> {
            val counts = HashMap<Int, Int>()
            for ((comboId, n) in comboCounts) {
                val combo = dictionary.combo(comboId) ?: continue
                for (index in combo.colors) counts[index] = (counts[index] ?: 0) + n
            }
            return sortedCounts(counts)
        }

        /** "headCut 3, noPeople 17" (orden alfabético), como en iOS. */
        fun stepsText(counts: Map<String, Int>): String =
            if (counts.isEmpty()) "-" else counts.entries
                .sortedBy { it.key }
                .joinToString(", ") { "${it.key} ${it.value}" }

        private fun max(a: Int, b: Int): Int = if (a > b) a else b
    }
}
