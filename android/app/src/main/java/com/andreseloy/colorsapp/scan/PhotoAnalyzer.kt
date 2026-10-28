// Análisis de una foto para el escaneo (y para quien lo necesite sin UI):
// el flujo de ScanAnalyzer de iOS sin capas de depuración — rasterizar una
// vez (sRGB <=1024), cadena de sujeto (SubjectChainSegmenter) sobre ese
// mismo raster y, con mapa de prendas, ce_analyze_garments; sin pose, el
// camino clásico ce_analyze. Un ColorEngine (ce_ctx) por llamada. Las
// opciones de match son las de la app: las del motor con la hipótesis de
// iluminante desactivada (ADR-009; AnalysisPolicy.current = 1).
package com.andreseloy.colorsapp.scan

import android.graphics.Bitmap
import com.andreseloy.colorsapp.data.GarmentEntry
import com.andreseloy.colorsapp.data.UuidV7
import com.andreseloy.colorsapp.data.PaletteEntry
import com.andreseloy.colorsapp.data.ScanRecord
import com.andreseloy.colorsapp.data.ScanSource
import com.andreseloy.colorsapp.engine.AnalysisResult
import com.andreseloy.colorsapp.engine.ColorEngine
import com.andreseloy.colorsapp.engine.EngineImage
import com.andreseloy.colorsapp.engine.GARMENT_MAX_REGIONS
import com.andreseloy.colorsapp.engine.GarmentOptions
import com.andreseloy.colorsapp.engine.GarmentSwatch
import com.andreseloy.colorsapp.engine.MatchOptions
import com.andreseloy.colorsapp.engine.PaletteOptions
import com.andreseloy.colorsapp.engine.colorEngineVersion
import com.andreseloy.colorsapp.engine.dictionaryVersion
import com.andreseloy.colorsapp.subject.SubjectMaskResult
import com.andreseloy.colorsapp.subject.SubjectOptions
import com.andreseloy.colorsapp.subject.SubjectRaster
import com.andreseloy.colorsapp.subject.SubjectSegmenter
import java.util.Locale

/** Resultado de analizar una foto en el escaneo. */
class PhotoAnalysis(
    val result: AnalysisResult,
    /** Colores por prenda (vacío en el camino clásico), orden de result.swatches. */
    val garments: List<GarmentSwatch>,
    /** Regiones del mapa entregado al motor (2 con pose); null en el clásico. */
    val garmentRegionCount: Int?,
    val subject: SubjectMaskResult,
    val subjectMs: Double,
    val engineMs: Double,
) {
    val usesGarments: Boolean get() = garments.isNotEmpty() && garmentRegionCount != null
}

object PhotoAnalyzer {
    /** Opciones de match de la app (EngineBridge.appMatchOptions de iOS). */
    fun appMatchOptions(): MatchOptions = MatchOptions.DEFAULT.copy(illuminantSearch = false)

    /** Versión de la política de análisis (AnalysisPolicy.current de iOS). */
    const val ANALYSIS_POLICY_VERSION = 1

    suspend fun analyze(
        bitmap: Bitmap,
        segmenter: SubjectSegmenter,
        options: SubjectOptions,
        topK: Int = 3,
    ): PhotoAnalysis {
        val raster = SubjectRaster.engineImage(bitmap, SubjectRaster.DEFAULT_MAX_SIDE)
        return analyze(raster, segmenter, options, topK)
    }

    suspend fun analyze(
        raster: EngineImage,
        segmenter: SubjectSegmenter,
        options: SubjectOptions,
        topK: Int = 3,
    ): PhotoAnalysis {
        val tSubject = System.nanoTime()
        val subject = segmenter.compute(raster, options)
        val subjectMs = (System.nanoTime() - tSubject) / 1_000_000.0
        val image = EngineImage(
            raster.pixels, raster.width, raster.height, raster.strideBytes,
            raster.format, subject.mask?.bytes,
        )
        val tEngine = System.nanoTime()
        var garments: List<GarmentSwatch> = emptyList()
        var regionCount: Int? = null
        val result: AnalysisResult = ColorEngine().use { engine ->
            val regions = subject.garmentRegions
            if (regions != null) {
                val r = engine.analyzeGarments(
                    image, regions.bytes, GARMENT_MAX_REGIONS,
                    PaletteOptions.DEFAULT, GarmentOptions.DEFAULT, appMatchOptions(), topK,
                )
                garments = r.garments
                regionCount = GARMENT_MAX_REGIONS
                r.analysis
            } else {
                engine.analyze(image, PaletteOptions.DEFAULT, appMatchOptions(), topK)
            }
        }
        val engineMs = (System.nanoTime() - tEngine) / 1_000_000.0
        return PhotoAnalysis(result, garments, regionCount, subject, subjectMs, engineMs)
    }

    /** ScanRecord como el ScanRecord.make de iOS (JSON compacto, claves ordenadas). */
    fun makeScanRecord(
        analysis: PhotoAnalysis,
        source: ScanSource,
        assetId: String?,
        options: SubjectOptions,
        nowMs: Long = System.currentTimeMillis(),
        // UUIDv7 de W1 como en iOS (ordenables por tiempo); antes randomUUID (v4).
        id: String = UuidV7.string(nowMs),
    ): ScanRecord {
        val result = analysis.result
        val subject = analysis.subject
        return ScanRecord(
            id = id,
            assetId = assetId,
            source = source,
            top1 = result.hits.getOrNull(0)?.comboId,
            top2 = result.hits.getOrNull(1)?.comboId,
            top3 = result.hits.getOrNull(2)?.comboId,
            scoresJson = encodeScores(result.hits.map { it.score }),
            paletteJson = encodePalette(result.swatches.map {
                PaletteEntry(it.hex, listOf(it.r, it.g, it.b), listOf(it.lab.l, it.lab.a, it.lab.b), it.weight)
            }),
            ambiguous = result.ambiguous,
            engineVersion = colorEngineVersion,
            dictVersion = dictionaryVersion,
            scannedAtMs = nowMs,
            updatedAtMs = nowMs,
            subjectMode = options.mode.raw,
            regionMode = options.region.raw,
            adaptiveSkin = options.adaptiveSkin,
            peopleCount = subject.people.size,
            personIndex = subject.chosenIndex,
            maskStepsJson = encodeSteps(subject.steps.map { it.raw }),
            maskCoverage = subject.maskCoverage,
            garmentsJson = if (analysis.usesGarments) {
                encodeGarments(analysis.garments.map {
                    GarmentEntry(
                        it.swatch.hex, listOf(it.swatch.r, it.swatch.g, it.swatch.b),
                        listOf(it.swatch.lab.l, it.swatch.lab.a, it.swatch.lab.b),
                        it.swatch.weight, it.region.code, it.regionShare, it.mergedClusterCount,
                    )
                })
            } else {
                null
            },
            garmentRegions = analysis.garmentRegionCount,
            enginePolicyVersion = ANALYSIS_POLICY_VERSION,
        )
    }

    // JSON compacto con las claves en orden alfabético, como JSONCoding
    // (sortedKeys) de iOS, para que un volcado se lea igual en las dos apps.
    private fun num(v: Double): String {
        if (!v.isFinite()) return "0"
        return String.format(Locale.US, "%.17g", v).trimEnd('0').trimEnd('.').ifEmpty { "0" }
    }

    fun encodeScores(scores: List<Double>): String =
        scores.joinToString(",", "[", "]") { num(it) }

    fun encodeSteps(steps: List<String>): String =
        steps.joinToString(",", "[", "]") { "\"$it\"" }

    fun encodePalette(entries: List<PaletteEntry>): String =
        entries.joinToString(",", "[", "]") { e ->
            "{\"hex\":\"${e.hex}\",\"lab\":[${e.lab.joinToString(",") { num(it) }}]," +
                "\"rgb\":[${e.rgb.joinToString(",")}],\"weight\":${num(e.weight)}}"
        }

    fun encodeGarments(entries: List<GarmentEntry>): String =
        entries.joinToString(",", "[", "]") { e ->
            "{\"hex\":\"${e.hex}\",\"lab\":[${e.lab.joinToString(",") { num(it) }}]," +
                "\"mergedClusters\":${e.mergedClusters},\"region\":${e.region}," +
                "\"regionShare\":${num(e.regionShare)},\"rgb\":[${e.rgb.joinToString(",")}]," +
                "\"weight\":${num(e.weight)}}"
        }
}
