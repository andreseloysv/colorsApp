// Flujo de una captura: espejo de ios/ColorsApp/Views/Feed/ScanAnalyzer.swift
// y de ScanPhotoStore.swift. Rasteriza UNA vez (EngineRaster, sRGB <= 1024),
// ejecuta la cadena de sujeto del contrato (subject/SubjectSegmenter: hasta
// que W2 la implemente es WholePhotoSubjectSegmenter = foto completa) y
// despues el motor con UN ColorEngine por analisis, en Dispatchers.Default:
// con mapa de regiones de prenda -> analyzeGarmentsWithLayers; sin el ->
// analyzeWithLayers (las capas alimentan los alfileres y el inspector).
// run() ademas guarda el scan y la copia JPEG de la foto (fuente != carrete).
package com.andreseloy.colorsapp.feature.extract

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Matrix
import android.media.ExifInterface
import android.net.Uri
import com.andreseloy.colorsapp.app.AppContainer
import com.andreseloy.colorsapp.data.ScanRecord
import com.andreseloy.colorsapp.data.ScanSource
import com.andreseloy.colorsapp.engine.AnalysisResult
import com.andreseloy.colorsapp.engine.ColorEngine
import com.andreseloy.colorsapp.engine.EngineImage
import com.andreseloy.colorsapp.engine.EngineRaster
import com.andreseloy.colorsapp.engine.GARMENT_MAX_REGIONS
import com.andreseloy.colorsapp.engine.GarmentDebugLayers
import com.andreseloy.colorsapp.engine.GarmentSwatch
import com.andreseloy.colorsapp.engine.PALETTE_LABEL_DISCARDED
import com.andreseloy.colorsapp.engine.PALETTE_LABEL_NONE
import com.andreseloy.colorsapp.engine.PaletteDebugLayers
import com.andreseloy.colorsapp.engine.PixelFormat
import com.andreseloy.colorsapp.subject.SubjectMaskResult
import com.andreseloy.colorsapp.subject.SubjectOptions
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.io.File
import java.security.SecureRandom
import java.util.UUID

/** Tiempos de un analisis en ms (AnalysisTimings de iOS). */
data class AnalysisTimings(
    val rasterMs: Double = 0.0,
    val visionMs: Double = 0.0,
    val maskMs: Double = 0.0,
    val engineMs: Double = 0.0,
    val totalMs: Double = 0.0,
)

/** Mapas de la capa de prendas sobre la imagen reducida (GarmentLayerMaps). */
class GarmentLayerMaps(
    val garmentMap: ByteArray,
    val regionMap: ByteArray,
    val reducedWidth: Int,
    val reducedHeight: Int,
)

/** Resultado completo de una captura (ScanOutcome de iOS). */
class ScanOutcome(
    /** Foto vertical que se ensena (ya reducida a <= 1024 por EngineRaster si hacia falta). */
    val bitmap: Bitmap,
    /** Raster exacto que vio el motor. */
    val raster: EngineImage,
    val result: AnalysisResult,
    val scan: ScanRecord,
    val subjectOptions: SubjectOptions,
    val subject: SubjectMaskResult,
    val debug: PaletteDebugLayers?,
    val garments: List<GarmentSwatch> = emptyList(),
    val garmentRegionCount: Int? = null,
    val garmentLayers: GarmentLayerMaps? = null,
    val timings: AnalysisTimings = AnalysisTimings(),
) {
    val id: String get() = scan.id
    val usesGarments: Boolean get() = garments.isNotEmpty() && garmentRegionCount != null
    val maskApplied: Boolean get() = subject.mask != null
    val elapsedMs: Long get() = timings.totalMs.toLong()

    fun garmentRegionAt(index: Int) = garments.getOrNull(index)?.region

    val garmentInfo: ScanGarmentInfo?
        get() = if (usesGarments) ScanGarmentInfo(garments, garmentRegionCount) else null
}

/** Parte pura del analisis, sin base de datos (ScanAnalyzer.Analysis). */
class ScanAnalysis(
    val raster: EngineImage,
    val options: SubjectOptions,
    val subject: SubjectMaskResult,
    val result: AnalysisResult,
    val debug: PaletteDebugLayers?,
    val garments: List<GarmentSwatch>,
    val garmentRegionCount: Int?,
    val garmentLayers: GarmentLayerMaps?,
    val timings: AnalysisTimings,
) {
    val usesGarments: Boolean get() = garments.isNotEmpty() && garmentRegionCount != null
    val garmentInfo: ScanGarmentInfo?
        get() = if (usesGarments) ScanGarmentInfo(garments, garmentRegionCount) else null
}

object ScanAnalyzer {

    /**
     * Id de scan UUIDv7 en minusculas (mismo formato que ios UUIDv7: 48 bits
     * de epoch ms + version 7 + variante RFC + aleatorio). W1 trae el UUIDv7
     * canonico del paquete data/; este es compatible en formato.
     */
    fun newScanId(nowMs: Long = System.currentTimeMillis()): String {
        val random = SecureRandom()
        val msb = (nowMs shl 16) or 0x7000L or (random.nextInt(0x1000).toLong())
        val lsb = (Long.MIN_VALUE) or (random.nextLong() and 0x3FFF_FFFF_FFFF_FFFFL)
        return UUID(msb, lsb).toString()
    }

    /** Bitmap visible del raster del motor (para miniaturas y capas). */
    fun bitmapFromRaster(raster: EngineImage): Bitmap {
        val w = raster.width
        val h = raster.height
        val out = Bitmap.createBitmap(w, h, Bitmap.Config.ARGB_8888)
        val pixels = IntArray(w * h)
        val bpp = raster.format.bytesPerPixel
        for (y in 0 until h) {
            var src = y * raster.strideBytes
            for (x in 0 until w) {
                val r = raster.pixels[src].toInt() and 0xFF
                val g = raster.pixels[src + 1].toInt() and 0xFF
                val b = raster.pixels[src + 2].toInt() and 0xFF
                pixels[y * w + x] = (0xFF shl 24) or (r shl 16) or (g shl 8) or b
                src += bpp
            }
        }
        out.setPixels(pixels, 0, w, 0, 0, w, h)
        return out
    }

    /**
     * Analisis completo de un Bitmap ya vertical. Suspende en
     * Dispatchers.Default; un ColorEngine por llamada.
     */
    suspend fun analyze(
        container: AppContainer,
        bitmap: Bitmap,
        options: SubjectOptions,
        layers: Boolean = true,
        topK: Int = 3,
    ): ScanAnalysis = withContext(Dispatchers.Default) {
        val start = System.nanoTime()
        fun ms() = (System.nanoTime() - start) / 1e6
        val rasterNoMask = EngineRaster.rasterize(bitmap)
        val rasterMs = ms()
        val subjectStart = ms()
        val subject = container.subjectSegmenter.compute(rasterNoMask, options)
        val subjectMs = ms() - subjectStart
        val maskMs = subject.timingsMs["mask"] ?: 0.0
        val visionMs = maxOf(0.0, subjectMs - maskMs)
        val raster = EngineImage(
            rasterNoMask.pixels, rasterNoMask.width, rasterNoMask.height,
            rasterNoMask.strideBytes, rasterNoMask.format, subject.mask?.bytes,
        )
        val engineStart = ms()
        var debug: PaletteDebugLayers? = null
        var garments: List<GarmentSwatch> = emptyList()
        var regionCount: Int? = null
        var garmentLayers: GarmentLayerMaps? = null
        val matchOptions = EngineRaster.appMatchOptions
        val engine = ColorEngine()
        val result: AnalysisResult = try {
            val regions = subject.garmentRegions
            if (regions != null && regions.bytes.size >= raster.width * raster.height) {
                regionCount = GARMENT_MAX_REGIONS
                if (layers) {
                    val g: GarmentDebugLayers = engine.analyzeGarmentsWithLayers(
                        raster, regions.bytes, GARMENT_MAX_REGIONS,
                        matchOptions = matchOptions,
                    )
                    garments = g.result.garments
                    debug = g.layers
                    garmentLayers = GarmentLayerMaps(
                        g.garmentMap, g.regionMap,
                        g.layers.debug.reducedWidth, g.layers.debug.reducedHeight,
                    )
                    g.result.analysis
                } else {
                    val g = engine.analyzeGarments(
                        raster, regions.bytes, GARMENT_MAX_REGIONS,
                        matchOptions = matchOptions, topK = topK,
                    )
                    garments = g.garments
                    g.analysis
                }
            } else if (layers) {
                val d = engine.analyzeWithLayers(raster, matchOptions = matchOptions)
                debug = d
                if (topK < d.analysis.hits.size) {
                    d.analysis.copy(hits = d.analysis.hits.take(topK))
                } else {
                    d.analysis
                }
            } else {
                engine.analyze(raster, matchOptions = matchOptions, topK = topK)
            }
        } finally {
            engine.close()
        }
        ScanAnalysis(
            raster = raster, options = options, subject = subject, result = result,
            debug = debug, garments = garments, garmentRegionCount = regionCount,
            garmentLayers = garmentLayers,
            timings = AnalysisTimings(
                rasterMs = rasterMs, visionMs = visionMs, maskMs = maskMs,
                engineMs = ms() - engineStart, totalMs = ms(),
            ),
        )
    }

    /**
     * Flujo completo (ScanAnalyzer.run): lee los ajustes de recorte si no se
     * pasan opciones, analiza, guarda la copia de la foto (fuentes que no son
     * el carrete) y despues inserta el scan, como en iOS.
     */
    suspend fun run(
        context: Context,
        container: AppContainer,
        bitmap: Bitmap,
        source: ScanSource,
        assetId: String? = null,
        subject: SubjectOptions? = null,
        nowMs: Long = System.currentTimeMillis(),
    ): ScanOutcome {
        val options = subject ?: container.settings.subjectSettings().subjectOptions()
        val analysis = analyze(container, bitmap, options)
        val info = ScanSubjectInfo(options, analysis.subject)
        val scan = ScanJson.makeRecord(
            id = newScanId(nowMs), result = analysis.result, source = source,
            assetId = assetId, subject = info, garments = analysis.garmentInfo,
            policyVersion = AnalysisPolicy.CURRENT,
            engineVersion = container.engineVersion,
            dictVersion = container.engineDictVersion,
            nowMs = nowMs,
        )
        if (source != ScanSource.LIBRARY) {
            runCatching { ScanPhotoStore.save(context, bitmap, scan.id) }
        }
        container.scans.insert(scan)
        return ScanOutcome(
            bitmap = bitmap, raster = analysis.raster, result = analysis.result,
            scan = scan, subjectOptions = options, subject = analysis.subject,
            debug = analysis.debug, garments = analysis.garments,
            garmentRegionCount = analysis.garmentRegionCount,
            garmentLayers = analysis.garmentLayers, timings = analysis.timings,
        )
    }

    /** Opciones de recorte con las que se calculo un scan (FeedServices.subjectOptions). */
    fun subjectOptionsFor(scan: ScanRecord, fallback: SubjectOptions): SubjectOptions {
        var options = fallback
        val modeRaw = scan.subjectMode
        if (modeRaw != null) {
            val mode = com.andreseloy.colorsapp.subject.SubjectMode.fromRaw(modeRaw)
            options = options.copy(
                mode = mode,
                selectedIndex = if (mode == com.andreseloy.colorsapp.subject.SubjectMode.SELECTED_PERSON) {
                    scan.personIndex
                } else {
                    null
                },
            )
        }
        scan.regionModeOrNull()?.let { options = options.copy(region = it) }
        scan.adaptiveSkin?.let { options = options.copy(adaptiveSkin = it) }
        return options
    }
}

/** Copias JPEG de las fotos analizadas (ScanPhotoStore de iOS: lado <= 1024, calidad 0.86). */
object ScanPhotoStore {
    const val MAX_SIDE = 1024
    private const val JPEG_QUALITY = 86

    private fun directory(context: Context): File =
        File(context.filesDir, "scan-photos").apply { mkdirs() }

    fun file(context: Context, scanId: String): File = File(directory(context), "$scanId.jpg")

    fun save(context: Context, bitmap: Bitmap, scanId: String) {
        val scaled = scaleDown(bitmap, MAX_SIDE)
        file(context, scanId).outputStream().use { out ->
            scaled.compress(Bitmap.CompressFormat.JPEG, JPEG_QUALITY, out)
        }
        if (scaled !== bitmap) scaled.recycle()
    }

    /** Foto guardada de un scan reducida a [maxSide]; null si no hay copia. */
    fun image(context: Context, scanId: String, maxSide: Int = MAX_SIDE): Bitmap? {
        val f = file(context, scanId)
        if (!f.exists()) return null
        return runCatching { decodeSampled(f.absolutePath, maxSide) }.getOrNull()
    }

    fun remove(context: Context, scanId: String) {
        runCatching { file(context, scanId).delete() }
    }

    fun scaleDown(bitmap: Bitmap, maxSide: Int): Bitmap {
        val (tw, th) = EngineRaster.targetSize(bitmap.width, bitmap.height, maxSide)
            .let { it[0] to it[1] }
        if (tw == bitmap.width && th == bitmap.height) return bitmap
        return Bitmap.createScaledBitmap(bitmap, tw, th, true)
    }

    private fun decodeSampled(path: String, maxSide: Int): Bitmap? {
        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        BitmapFactory.decodeFile(path, bounds)
        val opts = BitmapFactory.Options().apply { inSampleSize = sampleSize(bounds, maxSide) }
        return BitmapFactory.decodeFile(path, opts)
    }

    internal fun sampleSize(bounds: BitmapFactory.Options, maxSide: Int): Int {
        var sample = 1
        var w = bounds.outWidth
        var h = bounds.outHeight
        while (maxOf(w, h) / 2 >= maxSide && w / 2 >= 1 && h / 2 >= 1) {
            w /= 2
            h /= 2
            sample *= 2
        }
        return sample
    }
}

/** Carga de imagenes elegidas/capturadas: decodifica con muestreo y aplica EXIF. */
object PhotoLoading {

    /** Bitmap vertical de una Uri (picker, camara o MediaStore), lado <= [maxSide]*2 al decodificar. */
    fun loadUpright(context: Context, uri: Uri, maxSide: Int = 2048): Bitmap? {
        val resolver = context.contentResolver
        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        // decodeStream con inJustDecodeBounds devuelve null siempre: no encadenar
        // el ?: sobre su resultado, solo sobre la apertura del stream.
        val boundsStream = resolver.openInputStream(uri) ?: return null
        boundsStream.use { BitmapFactory.decodeStream(it, null, bounds) }
        if (bounds.outWidth <= 0 || bounds.outHeight <= 0) return null
        val opts = BitmapFactory.Options().apply {
            inSampleSize = ScanPhotoStore.sampleSize(bounds, maxSide)
        }
        val bitmap = resolver.openInputStream(uri)?.use {
            BitmapFactory.decodeStream(it, null, opts)
        } ?: return null
        val rotation = runCatching {
            resolver.openInputStream(uri)?.use { input ->
                val exif = ExifInterface(input)
                when (exif.getAttributeInt(ExifInterface.TAG_ORIENTATION, ExifInterface.ORIENTATION_NORMAL)) {
                    ExifInterface.ORIENTATION_ROTATE_90 -> 90f
                    ExifInterface.ORIENTATION_ROTATE_180 -> 180f
                    ExifInterface.ORIENTATION_ROTATE_270 -> 270f
                    else -> 0f
                }
            } ?: 0f
        }.getOrDefault(0f)
        if (rotation == 0f) return bitmap
        val matrix = Matrix().apply { postRotate(rotation) }
        val rotated = Bitmap.createBitmap(bitmap, 0, 0, bitmap.width, bitmap.height, matrix, true)
        if (rotated !== bitmap) bitmap.recycle()
        return rotated
    }
}

/**
 * Alfileres sobre la foto: centroide de los pixeles de cada swatch en el
 * labelMap, ajustado al pixel etiquetado mas cercano (PinOverlay.positions).
 * Posiciones normalizadas 0..1 sobre la imagen reducida.
 */
object PinPositions {
    fun compute(
        labelMap: ByteArray, width: Int, height: Int, swatchCount: Int,
    ): Map<Int, Pair<Double, Double>> {
        if (width <= 0 || height <= 0 || labelMap.size < width * height || swatchCount <= 0) {
            return emptyMap()
        }
        val sumX = DoubleArray(swatchCount)
        val sumY = DoubleArray(swatchCount)
        val count = IntArray(swatchCount)
        for (y in 0 until height) {
            for (x in 0 until width) {
                val label = labelMap[y * width + x].toInt() and 0xFF
                if (label == PALETTE_LABEL_NONE || label == PALETTE_LABEL_DISCARDED) continue
                if (label >= swatchCount) continue
                sumX[label] += x
                sumY[label] += y
                count[label]++
            }
        }
        val out = mutableMapOf<Int, Pair<Double, Double>>()
        for (s in 0 until swatchCount) {
            if (count[s] == 0) continue
            val cx = sumX[s] / count[s]
            val cy = sumY[s] / count[s]
            var bestD = Double.POSITIVE_INFINITY
            var bestX = 0
            var bestY = 0
            for (y in 0 until height) {
                for (x in 0 until width) {
                    if ((labelMap[y * width + x].toInt() and 0xFF) != s) continue
                    val dx = x - cx
                    val dy = y - cy
                    val d = dx * dx + dy * dy
                    if (d < bestD) {
                        bestD = d
                        bestX = x
                        bestY = y
                    }
                }
            }
            out[s] = (bestX + 0.5) / width to (bestY + 0.5) / height
        }
        return out
    }

    /** Capa que oscurece fuera de la mascara (LayerBitmaps.dimOutside: alpha (255-v)*0.78). */
    fun dimOutsideBitmap(mask: ByteArray, width: Int, height: Int): Bitmap? {
        if (mask.size < width * height) return null
        val out = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
        val pixels = IntArray(width * height)
        for (i in pixels.indices) {
            val v = mask[i].toInt() and 0xFF
            val alpha = kotlin.math.round((255 - v) * 0.78).toInt().coerceIn(0, 255)
            pixels[i] = alpha shl 24
        }
        out.setPixels(pixels, 0, width, 0, 0, width, height)
        return out
    }

    /** Capa que oscurece todo menos los pixeles del swatch [swatch] (aislar al mantener). */
    fun isolateBitmap(labelMap: ByteArray, width: Int, height: Int, swatch: Int): Bitmap? {
        if (labelMap.size < width * height) return null
        val out = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
        val pixels = IntArray(width * height)
        // dimOutside sobre la mascara 0/255 del swatch: (255 - 0) * 0,78 redondeado.
        val alpha = kotlin.math.round(255 * 0.78).toInt()
        for (i in pixels.indices) {
            val label = labelMap[i].toInt() and 0xFF
            pixels[i] = if (label == swatch) 0 else alpha shl 24
        }
        out.setPixels(pixels, 0, width, 0, 0, width, height)
        return out
    }
}
