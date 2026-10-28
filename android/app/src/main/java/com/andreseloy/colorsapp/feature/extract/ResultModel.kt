// Modelo del resultado de Extraer: espejo de
// ios/ColorsApp/Views/Resultado/ResultViewModel.swift. Estado observable de
// Compose (sin AAC ViewModel: vive lo que vive la pantalla, como el
// ObservableObject de iOS): veredicto, desbloqueo, alfileres, mascara,
// personas (re-analiza con otra y actualiza el scan), guardar en el Jardin,
// copiar hex y la explicacion del match del motor.
package com.andreseloy.colorsapp.feature.extract

import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.graphics.Bitmap
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import com.andreseloy.colorsapp.R
import com.andreseloy.colorsapp.app.AppContainer
import com.andreseloy.colorsapp.data.FeedbackVerdict
import com.andreseloy.colorsapp.data.WadaDictionary
import com.andreseloy.colorsapp.engine.GarmentRegion
import com.andreseloy.colorsapp.engine.Hit
import com.andreseloy.colorsapp.engine.MatchExplanation
import com.andreseloy.colorsapp.feature.feed.ComboMatchSummary
import com.andreseloy.colorsapp.feature.feed.FeedComboName
import com.andreseloy.colorsapp.feature.feed.GardenSavedStore
import com.andreseloy.colorsapp.subject.MaskBuffer
import com.andreseloy.colorsapp.subject.SubjectMode
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

enum class UnlockState { UNKNOWN, LOCKED, UNLOCKED_NOW, ALREADY_UNLOCKED }

/** Opcion de la fila «Personas». */
sealed interface PersonChoice {
    data object All : PersonChoice
    data class Person(val index: Int) : PersonChoice
}

/** Alfiler sobre la foto: posicion normalizada en la imagen reducida. */
data class PhotoPin(
    val swatchIndex: Int,
    val x: Double,
    val y: Double,
    val color: PaletteColor,
)

/** Resumen de la paleta para la pildora («5 colores · 12,3 % de la foto»). */
data class PaletteSummaryData(
    val colorCount: Int,
    /** Regiones de prenda distintas; null en el camino clasico. */
    val garmentRegions: Int?,
    /** Cobertura de la mascara; null = foto completa. */
    val coverage: Double?,
)

class ResultModel(
    initialOutcome: ScanOutcome,
    private val container: AppContainer,
    private val garden: GardenSavedStore,
    context: Context,
    private val scope: CoroutineScope,
) {
    private val appContext = context.applicationContext
    private val resources get() = appContext.resources

    var outcome: ScanOutcome by mutableStateOf(initialOutcome)
        private set

    val dictionary: WadaDictionary get() = container.dictionary

    var verdict: FeedbackVerdict? by mutableStateOf(null)
        private set
    var unlockState: UnlockState by mutableStateOf(UnlockState.UNKNOWN)
        private set
    var busy: Boolean by mutableStateOf(false)
        private set
    var reanalyzing: Boolean by mutableStateOf(false)
        private set
    var errorMessage: String? by mutableStateOf(null)
    var showMask: Boolean by mutableStateOf(false)
    var selectedSwatch: Int? by mutableStateOf(null)
    var banner: String? by mutableStateOf(null)
    var isExample: Boolean = false

    var palette: List<PaletteColor> by mutableStateOf(paletteOf(initialOutcome, container.dictionary))
        private set
    var pins: List<PhotoPin> by mutableStateOf(emptyList())
        private set
    var personThumbnails: List<Bitmap> by mutableStateOf(emptyList())
        private set
    var maskOverlay: Bitmap? by mutableStateOf(null)
        private set
    var isolatedSwatch: Int? by mutableStateOf(null)
        private set
    var isolationOverlay: Bitmap? by mutableStateOf(null)
        private set
    var isSaved: Boolean by mutableStateOf(garden.isSaved(initialOutcome.scan.id))
        private set

    /* ---------------- Derivados ---------------- */

    val hits: List<Hit> get() = outcome.result.hits
    val topHit: Hit? get() = hits.firstOrNull()
    val peopleCount: Int get() = outcome.subject.people.size
    val usesGarments: Boolean get() = outcome.usesGarments
    val showsPeopleRow: Boolean get() = peopleCount >= 2
    val canChangePerson: Boolean get() = verdict == null && !busy && !reanalyzing

    val currentChoice: PersonChoice
        get() = if (outcome.subjectOptions.mode == SubjectMode.ALL_PEOPLE) {
            PersonChoice.All
        } else {
            PersonChoice.Person(outcome.subject.chosenIndex ?: 0)
        }

    val maskNotice: MaskNotice
        get() = ResultNotice.notice(outcome.subjectOptions, outcome.subject)

    val stepKinds: List<com.andreseloy.colorsapp.subject.MaskStep>
        get() = ResultNotice.stepKinds(outcome.subject)

    /** Top-3 como resúmenes (la ambigüedad solo en el primero). */
    val matches: List<ComboMatchSummary>
        get() = hits.mapIndexed { i, hit ->
            ComboMatchSummary(
                comboId = hit.comboId,
                name = FeedComboName.name(hit.comboId, dictionary),
                colors = PaletteColor.combo(hit.comboId, dictionary),
                ambiguousWithTop2 = i == 0 && outcome.result.ambiguous && hits.size >= 2,
            )
        }

    /** Explicacion del score del top-1 (de las capas del motor, si las hay). */
    val topExplanation: MatchExplanation?
        get() = outcome.debug?.explanations?.firstOrNull()

    enum class PaletteTitle { BY_GARMENT, CLOTHING, PHOTO }

    val paletteTitle: PaletteTitle
        get() = when {
            usesGarments -> PaletteTitle.BY_GARMENT
            outcome.maskApplied -> PaletteTitle.CLOTHING
            else -> PaletteTitle.PHOTO
        }

    val paletteSummary: PaletteSummaryData
        get() {
            if (!outcome.maskApplied) {
                return PaletteSummaryData(palette.size, null, null)
            }
            val regions = if (usesGarments) {
                outcome.garments.map { it.region }.distinct().size
            } else {
                null
            }
            return PaletteSummaryData(
                palette.size, regions, outcome.subject.maskCoverage,
            )
        }

    /** Region de prenda de un color de la paleta; null en el camino clasico. */
    fun garmentRegionOf(color: PaletteColor): GarmentRegion? =
        outcome.garmentRegionAt(color.id)?.takeIf { it != GarmentRegion.NONE }

    /* ---------------- Carga y acciones ---------------- */

    fun load() {
        scope.launch {
            refreshDerivedImages()
            runCatching {
                verdict = container.feedback.latest(outcome.scan.id)?.verdict
                refreshUnlockState()
            }.onFailure { errorMessage = ErrorText.describe(resources, it) }
        }
    }

    private suspend fun refreshUnlockState() {
        val top = topHit
        unlockState = if (top != null && container.unlocks.isUnlocked(top.comboId)) {
            UnlockState.ALREADY_UNLOCKED
        } else {
            UnlockState.LOCKED
        }
    }

    fun vote(newVerdict: FeedbackVerdict, onVoted: () -> Unit = {}) {
        if (verdict != null || busy || reanalyzing) return
        busy = true
        scope.launch {
            try {
                container.feedback.record(outcome.scan.id, newVerdict)
                verdict = newVerdict
                onVoted()
            } catch (e: Exception) {
                errorMessage = ErrorText.describe(resources, e)
            } finally {
                busy = false
            }
        }
    }

    fun unlock() {
        val top = topHit ?: return
        if (busy || reanalyzing) return
        busy = true
        scope.launch {
            try {
                val fresh = container.unlocks.unlock(
                    top.comboId, outcome.scan.source,
                    assetId = outcome.scan.assetId, scanId = outcome.scan.id,
                )
                unlockState = if (fresh) UnlockState.UNLOCKED_NOW else UnlockState.ALREADY_UNLOCKED
            } catch (e: Exception) {
                errorMessage = ErrorText.describe(resources, e)
            } finally {
                busy = false
            }
        }
    }

    /**
     * Re-analiza con otra persona (o todas) y actualiza el scan guardado.
     * En iOS se reutilizan las personas ya detectadas; el contrato Android
     * (SubjectSegmenter.compute) recalcula la cadena entera con las nuevas
     * opciones: mismo resultado visible, mas trabajo del detector (W2).
     */
    fun choose(choice: PersonChoice) {
        if (!canChangePerson || choice == currentChoice) return
        var options = outcome.subjectOptions
        options = when (choice) {
            PersonChoice.All -> options.copy(mode = SubjectMode.ALL_PEOPLE, selectedIndex = null)
            is PersonChoice.Person -> {
                if (choice.index !in 0 until peopleCount) return
                options.copy(mode = SubjectMode.SELECTED_PERSON, selectedIndex = choice.index)
            }
        }
        reanalyzing = true
        val current = outcome
        scope.launch {
            try {
                val analysis = ScanAnalyzer.analyze(container, current.bitmap, options)
                val info = ScanSubjectInfo(options, analysis.subject)
                val scan = ScanJson.updatedRecord(
                    old = current.scan, result = analysis.result, subject = info,
                    garments = analysis.garmentInfo,
                    policyVersion = AnalysisPolicy.CURRENT,
                    engineVersion = container.engineVersion,
                    dictVersion = container.engineDictVersion,
                    nowMs = System.currentTimeMillis(),
                )
                container.scans.update(scan)
                outcome = ScanOutcome(
                    bitmap = current.bitmap, raster = analysis.raster,
                    result = analysis.result, scan = scan, subjectOptions = options,
                    subject = analysis.subject, debug = analysis.debug,
                    garments = analysis.garments,
                    garmentRegionCount = analysis.garmentRegionCount,
                    garmentLayers = analysis.garmentLayers, timings = analysis.timings,
                )
                palette = paletteOf(outcome, dictionary)
                selectedSwatch = null
                isolatedSwatch = null
                isolationOverlay = null
                refreshDerivedImages()
                refreshUnlockState()
            } catch (e: Exception) {
                errorMessage = ErrorText.describe(resources, e)
            } finally {
                reanalyzing = false
            }
        }
    }

    /* ---------------- Copiar, guardar, aislar ---------------- */

    private fun clipboard(): ClipboardManager =
        appContext.getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager

    /** Copia los hex de la paleta; devuelve el texto del toast. */
    fun copyPalette(): String {
        val list = W3Format.hexList(palette)
        clipboard().setPrimaryClip(ClipData.newPlainText("hex", list))
        return if (palette.size == 1) {
            resources.getString(R.string.w3_copied_one, list)
        } else {
            resources.getString(R.string.w3_copied_many, palette.size)
        }
    }

    /** Copia el hex de un color (y lo selecciona); devuelve el texto del toast. */
    fun copy(color: PaletteColor): String {
        clipboard().setPrimaryClip(ClipData.newPlainText("hex", color.hex))
        selectedSwatch = color.id
        return resources.getString(R.string.w3_copied_one, color.hex)
    }

    /** «Guardar en el Jardin» ⇄ quitar; devuelve el texto del toast. */
    fun toggleSave(): String {
        isSaved = garden.toggle(outcome.scan.id)
        return resources.getString(
            if (isSaved) R.string.w3_saved_in_garden_toast else R.string.w3_removed_from_garden,
        )
    }

    /** Mantener pulsado un alfiler: aisla sus pixeles sobre la foto. */
    fun setIsolation(swatch: Int, active: Boolean) {
        if (!active) {
            if (isolatedSwatch == swatch) {
                isolatedSwatch = null
                isolationOverlay = null
            }
            return
        }
        val debug = outcome.debug ?: return
        isolatedSwatch = swatch
        selectedSwatch = swatch
        scope.launch(Dispatchers.Default) {
            val overlay = PinPositions.isolateBitmap(
                debug.labelMap, debug.debug.reducedWidth, debug.debug.reducedHeight, swatch,
            )
            withContext(Dispatchers.Main) {
                if (isolatedSwatch == swatch) isolationOverlay = overlay
            }
        }
    }

    /* ---------------- Derivados graficos ---------------- */

    private suspend fun refreshDerivedImages() {
        val o = outcome
        val colors = palette
        val derived = withContext(Dispatchers.Default) {
            val thumbs = o.subject.people.mapNotNull { person ->
                person.finalMask?.let { mask -> cropByMask(o, mask) }
            }
            val overlay = o.subject.mask?.let { mask ->
                PinPositions.dimOutsideBitmap(mask.bytes, o.raster.width, o.raster.height)
            }
            val newPins = pinsOf(o, colors)
            Triple(thumbs, overlay, newPins)
        }
        if (outcome.scan.rev != o.scan.rev) return
        personThumbnails = derived.first
        maskOverlay = derived.second
        pins = derived.third
        if (maskOverlay == null) showMask = false
    }

    /** Miniatura de una persona: recorte del raster por la caja de su mascara (pad 8 %). */
    private fun cropByMask(outcome: ScanOutcome, mask: MaskBuffer): Bitmap? {
        var minX = mask.width
        var minY = mask.height
        var maxX = -1
        var maxY = -1
        for (y in 0 until mask.height) {
            for (x in 0 until mask.width) {
                if ((mask.bytes[y * mask.width + x].toInt() and 0xFF) >= 128) {
                    if (x < minX) minX = x
                    if (x > maxX) maxX = x
                    if (y < minY) minY = y
                    if (y > maxY) maxY = y
                }
            }
        }
        if (maxX < 0) return null
        val padX = ((maxX - minX + 1) * 0.08).toInt()
        val padY = ((maxY - minY + 1) * 0.08).toInt()
        val left = maxOf(0, minX - padX)
        val top = maxOf(0, minY - padY)
        val right = minOf(mask.width, maxX + 1 + padX)
        val bottom = minOf(mask.height, maxY + 1 + padY)
        if (right <= left || bottom <= top) return null
        val base = ScanAnalyzer.bitmapFromRaster(outcome.raster)
        val crop = Bitmap.createBitmap(base, left, top, right - left, bottom - top)
        if (crop !== base) base.recycle()
        return crop
    }

    companion object {
        /** Paleta del analisis con el nombre de Wada mas cercano (motor). */
        fun paletteOf(outcome: ScanOutcome, dictionary: WadaDictionary): List<PaletteColor> =
            outcome.result.swatches.mapIndexed { i, swatch ->
                PaletteColor.fromSwatch(i, swatch, dictionary)
            }

        /** Alfileres en el centroide de cada swatch (labelMap del motor). */
        fun pinsOf(outcome: ScanOutcome, palette: List<PaletteColor>): List<PhotoPin> {
            val debug = outcome.debug ?: return emptyList()
            if (palette.isEmpty()) return emptyList()
            val positions = PinPositions.compute(
                debug.labelMap, debug.debug.reducedWidth, debug.debug.reducedHeight, palette.size,
            )
            return palette.mapNotNull { color ->
                positions[color.id]?.let { (x, y) -> PhotoPin(color.id, x, y, color) }
            }
        }
    }
}
