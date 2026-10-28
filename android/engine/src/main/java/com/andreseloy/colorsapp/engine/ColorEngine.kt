// Funciones del motor: conversiones y diccionario sin contexto (object
// ColorMath / WadaEngineDictionary) y la clase con contexto ColorEngine.
// Espejo de las funciones libres de ColorEngine.swift; un ce_ctx por tarea.
package com.andreseloy.colorsapp.engine

/** Valores por defecto leídos del motor una sola vez (nativeDefaults). */
internal object EngineDefaults {
    val values: DoubleArray by lazy { EngineNative.nativeDefaults() }
}

/** Versión del motor C (ce_version). */
val colorEngineVersion: String get() = EngineNative.nativeVersion()

/** Versión del diccionario embebido en el motor (ce_dict_version). */
val dictionaryVersion: String get() = EngineNative.nativeDictVersion()

/** Bytes que necesita un contexto del motor (ce_ctx_size, <= 2 MiB). */
val colorEngineContextSize: Long get() = EngineNative.nativeContextSize()

/** Máximo de hits que puede devolver el match (CE_MATCH_MAX_HITS). */
const val COLOR_ENGINE_MAX_HITS = 10

/** Máximo de swatches de una paleta (CE_PALETTE_MAX_COLORS). */
const val COLOR_ENGINE_MAX_SWATCHES = 8

/** Máximo de regiones de prenda (CE_GARMENT_MAX_REGIONS). */
const val GARMENT_MAX_REGIONS = 2

/** Semillas máximas por instancia (CE_SPLIT_MAX_SEEDS). */
const val SPLIT_MAX_SEEDS = 8

/** Etiqueta de un píxel reducido con peso 0 en los mapas de depuración (CE_LABEL_NONE). */
const val PALETTE_LABEL_NONE = 255

/** Etiqueta de un píxel cuyo cluster se descartó o se recortó (CE_LABEL_DISCARDED). */
const val PALETTE_LABEL_DISCARDED = 254

/** Matemática de color sin contexto: todo calculado por el motor C. */
object ColorMath {
    /** sRGB8 (0..255) -> CIELAB (D65). */
    fun srgbToLab(r: Int, g: Int, b: Int): Lab {
        val v = EngineNative.nativeSrgb8ToLab(r, g, b)
        return Lab(v[0], v[1], v[2])
    }

    /** CIELAB -> sRGB8 (clamp y redondeo del motor). Devuelve intArrayOf(r, g, b). */
    fun labToSrgb8(lab: Lab): IntArray = EngineNative.nativeLabToSrgb8(lab.l, lab.a, lab.b)

    /** ΔE00 (CIEDE2000) con kL = kC = kH = 1. */
    fun deltaE2000(x: Lab, y: Lab): Double =
        EngineNative.nativeDe2000(x.l, x.a, x.b, y.l, y.a, y.b)

    /** ΔE00 con factores paramétricos kL, kC, kH. */
    fun deltaE2000(x: Lab, y: Lab, kL: Double, kC: Double, kH: Double): Double =
        EngineNative.nativeDe2000K(x.l, x.a, x.b, y.l, y.a, y.b, kL, kC, kH)

    /** ΔE*ab (CIE 1976). */
    fun deltaE76(x: Lab, y: Lab): Double =
        EngineNative.nativeDe76(x.l, x.a, x.b, y.l, y.a, y.b)

    /** Dimensiones reducidas (ce_reduced_dims). Lanza Engine(ERR_DIMS) si algún arg < 1. */
    fun reducedDims(width: Int, height: Int, maxSide: Int): IntArray {
        val v = EngineNative.nativeReducedDims(width, height, maxSide)
        if (v.isEmpty()) throw EngineException.Engine(EngineException.Engine.ERR_DIMS)
        return v
    }

    /** Hash FNV-1a de una paleta (ce_swatch_hash); comparable entre plataformas. */
    fun swatchHash(swatches: List<Swatch>): Long =
        EngineNative.nativeSwatchHash(swatches.toNativeLabW(), swatches.size)

    /** Hash FNV-1a de los swatches de prenda (ce_garment_hash). */
    fun garmentHash(garments: List<GarmentSwatch>): Long {
        val labw = garments.map { it.swatch }.toNativeLabW()
        val share = DoubleArray(garments.size) { garments[it].regionShare }
        val ints = IntArray(garments.size * 2)
        garments.forEachIndexed { i, g ->
            ints[i * 2] = g.region.code
            ints[i * 2 + 1] = g.mergedClusterCount
        }
        return EngineNative.nativeGarmentHash(labw, share, ints, garments.size)
    }

    /** Hash FNV-1a de un resultado completo (ce_result_hash). */
    fun resultHash(result: AnalysisResult): Long {
        val ids = IntArray(result.hits.size) { result.hits[it].comboId }
        val scores = DoubleArray(result.hits.size) { result.hits[it].score }
        return EngineNative.nativeResultHash(
            result.swatches.toNativeLabW(), result.swatches.size,
            ids, scores, result.hits.size, if (result.ambiguous) 1 else 0,
        )
    }
}

/** Diccionario de Sanzo Wada embebido en el motor (sin contexto). */
object WadaEngineDictionary {
    val colorCount: Int get() = EngineNative.nativeDictNumColors()
    val comboCount: Int get() = EngineNative.nativeDictNumCombos()

    /** sRGB8 del color [index] como intArrayOf(r, g, b), o null fuera de rango. */
    fun colorRgb(index: Int): IntArray? =
        EngineNative.nativeDictColorRgb(index).takeIf { it.isNotEmpty() }

    /** Nombre en inglés (Ridgway) del color, o null fuera de rango. */
    fun colorName(index: Int): String? = EngineNative.nativeDictColorName(index)

    /** CIELAB del color calculado por el motor, o null fuera de rango (NaN en C). */
    fun colorLab(index: Int): Lab? {
        if (index < 0 || index >= colorCount) return null
        val v = EngineNative.nativeDictColorLab(index)
        return Lab(v[0], v[1], v[2])
    }

    /** Índices de color de la combinación [id] (1..348), o null si no existe. */
    fun combo(id: Int): IntArray? =
        EngineNative.nativeDictCombo(id).takeIf { it.isNotEmpty() }

    /** Color del diccionario más cercano a [lab] por ΔE00: (índice, distancia). */
    fun nearestColor(lab: Lab): Pair<Int, Double> {
        val v = EngineNative.nativeNearestColor(lab.l, lab.a, lab.b)
        return v[0].toInt() to v[1]
    }
}

internal fun List<Swatch>.toNativeLabW() = DoubleArray(size * 4) { i ->
    val s = this[i / 4]
    when (i % 4) {
        0 -> s.lab.l
        1 -> s.lab.a
        2 -> s.lab.b
        else -> s.weight
    }
}

internal fun checkEngine(code: Int): Int {
    if (code < 0) throw EngineException.Engine(code)
    return code
}

/** Validación de imagen igual que validateMask/validateRGBA del Swift. */
internal fun validateImage(image: EngineImage) {
    if (image.width < 1 || image.height < 1) {
        throw EngineException.Engine(EngineException.Engine.ERR_DIMS)
    }
    val bpp = image.format.bytesPerPixel
    if (image.strideBytes < image.width * bpp) {
        throw EngineException.Engine(EngineException.Engine.ERR_STRIDE)
    }
    val required = (image.height - 1) * image.strideBytes + image.width * bpp
    if (image.pixels.size < required) {
        throw EngineException.BufferTooSmall(required, image.pixels.size)
    }
    val mask = image.mask
    if (mask != null && mask.size < image.width * image.height) {
        throw EngineException.MaskTooSmall(image.width * image.height, mask.size)
    }
}

internal fun validateMask(mask: ByteArray, width: Int, height: Int) {
    if (mask.size < width * height) {
        throw EngineException.MaskTooSmall(width * height, mask.size)
    }
}

/**
 * Contexto del motor (ce_ctx): uno por tarea, NO compartible entre hilos,
 * igual que en iOS. Llamar a [close] al terminar (o usar `use {}`).
 * Las funciones sin contexto del Swift (máscaras, piel) cuelgan también de
 * esta clase como funciones compañeras para no dispersar la API.
 */
class ColorEngine : AutoCloseable {
    private var handle: Long = EngineNative.nativeCreateContext()

    init {
        if (handle == 0L) throw EngineException.Engine(EngineException.Engine.ERR_CTX)
    }

    override fun close() {
        if (handle != 0L) {
            EngineNative.nativeDestroyContext(handle)
            handle = 0L
        }
    }

    private fun requireHandle(): Long {
        if (handle == 0L) throw EngineException.Engine(EngineException.Engine.ERR_CTX)
        return handle
    }

    /** Extrae la paleta dominante (ce_palette_extract), ordenada por peso desc. */
    fun extractPalette(
        image: EngineImage,
        options: PaletteOptions = PaletteOptions.DEFAULT,
    ): List<Swatch> {
        validateImage(image)
        val labw = DoubleArray(COLOR_ENGINE_MAX_SWATCHES * 4)
        val rgb = IntArray(COLOR_ENGINE_MAX_SWATCHES * 3)
        val n = checkEngine(
            EngineNative.nativeExtractPalette(
                requireHandle(), image.pixels, image.width, image.height,
                image.strideBytes, image.format.code, image.mask, options.toNative(), labw, rgb,
            ),
        )
        return buildSwatches(labw, rgb, n)
    }

    /** Puntúa las 348 combinaciones frente a [swatches] (ce_match). */
    fun match(
        swatches: List<Swatch>,
        options: MatchOptions = MatchOptions.DEFAULT,
        topK: Int = COLOR_ENGINE_MAX_HITS,
    ): Pair<List<Hit>, Boolean> {
        val ids = IntArray(COLOR_ENGINE_MAX_HITS)
        val scores = DoubleArray(COLOR_ENGINE_MAX_HITS)
        val meta = IntArray(1)
        val n = checkEngine(
            EngineNative.nativeMatch(
                requireHandle(), swatches.toNativeLabW(), swatches.size,
                options.toNative(), topK, ids, scores, meta,
            ),
        )
        return buildHits(ids, scores, n) to (meta[0] != 0)
    }

    /**
     * Paleta + match en un solo contexto (ce_analyze). El motor calcula
     * siempre los 10 mejores; se devuelven los [topK] primeros y el hash se
     * recalcula sobre ellos, como en el Swift (ce_result_hash con n_hits=K).
     */
    fun analyze(
        image: EngineImage,
        paletteOptions: PaletteOptions = PaletteOptions.DEFAULT,
        matchOptions: MatchOptions = MatchOptions.DEFAULT,
        topK: Int = 3,
    ): AnalysisResult {
        if (topK !in 1..COLOR_ENGINE_MAX_HITS) {
            throw EngineException.Engine(EngineException.Engine.ERR_ARG)
        }
        validateImage(image)
        val labw = DoubleArray(COLOR_ENGINE_MAX_SWATCHES * 4)
        val rgb = IntArray(COLOR_ENGINE_MAX_SWATCHES * 3)
        val ids = IntArray(COLOR_ENGINE_MAX_HITS)
        val scores = DoubleArray(COLOR_ENGINE_MAX_HITS)
        val meta = IntArray(3)
        val hash = LongArray(1)
        checkEngine(
            EngineNative.nativeAnalyze(
                requireHandle(), image.pixels, image.width, image.height,
                image.strideBytes, image.format.code, image.mask,
                paletteOptions.toNative(), matchOptions.toNative(),
                labw, rgb, ids, scores, meta, hash,
            ),
        )
        val nHits = minOf(topK, meta[1])
        val full = AnalysisResult(
            buildSwatches(labw, rgb, meta[0]), buildHits(ids, scores, nHits),
            meta[2] != 0, hash[0],
        )
        return if (nHits == meta[1]) full else full.copy(hash = ColorMath.resultHash(full))
    }

    /** Paleta por prenda (ce_palette_extract_garments): un color por prenda lisa. */
    fun extractGarments(
        image: EngineImage,
        regionMap: ByteArray? = null,
        regionCount: Int = 0,
        paletteOptions: PaletteOptions = PaletteOptions.DEFAULT,
        garmentOptions: GarmentOptions = GarmentOptions.DEFAULT,
    ): List<GarmentSwatch> {
        validateImage(image)
        if (regionMap != null) validateMask(regionMap, image.width, image.height)
        val labw = DoubleArray(COLOR_ENGINE_MAX_SWATCHES * 4)
        val rgb = IntArray(COLOR_ENGINE_MAX_SWATCHES * 3)
        val share = DoubleArray(COLOR_ENGINE_MAX_SWATCHES)
        val ints = IntArray(COLOR_ENGINE_MAX_SWATCHES * 2)
        val n = checkEngine(
            EngineNative.nativeExtractGarments(
                requireHandle(), image.pixels, image.width, image.height,
                image.strideBytes, image.format.code, image.mask, regionMap, regionCount,
                paletteOptions.toNative(), garmentOptions.toNative(), labw, rgb, share, ints,
            ),
        )
        return buildGarments(labw, rgb, share, ints, n)
    }

    /** Prendas + match (ce_analyze_garments). [topK] como en [analyze]. */
    fun analyzeGarments(
        image: EngineImage,
        regionMap: ByteArray? = null,
        regionCount: Int = 0,
        paletteOptions: PaletteOptions = PaletteOptions.DEFAULT,
        garmentOptions: GarmentOptions = GarmentOptions.DEFAULT,
        matchOptions: MatchOptions = MatchOptions.DEFAULT,
        topK: Int = 3,
    ): GarmentAnalysisResult {
        if (topK !in 1..COLOR_ENGINE_MAX_HITS) {
            throw EngineException.Engine(EngineException.Engine.ERR_ARG)
        }
        validateImage(image)
        if (regionMap != null) validateMask(regionMap, image.width, image.height)
        val labw = DoubleArray(COLOR_ENGINE_MAX_SWATCHES * 4)
        val rgb = IntArray(COLOR_ENGINE_MAX_SWATCHES * 3)
        val share = DoubleArray(COLOR_ENGINE_MAX_SWATCHES)
        val ints = IntArray(COLOR_ENGINE_MAX_SWATCHES * 2)
        val ids = IntArray(COLOR_ENGINE_MAX_HITS)
        val scores = DoubleArray(COLOR_ENGINE_MAX_HITS)
        val meta = IntArray(3)
        val hash = LongArray(1)
        checkEngine(
            EngineNative.nativeAnalyzeGarments(
                requireHandle(), image.pixels, image.width, image.height,
                image.strideBytes, image.format.code, image.mask, regionMap, regionCount,
                paletteOptions.toNative(), garmentOptions.toNative(), matchOptions.toNative(),
                labw, rgb, share, ints, ids, scores, meta, hash,
            ),
        )
        val nHits = minOf(topK, meta[1])
        var analysis = AnalysisResult(
            buildSwatches(labw, rgb, meta[0]), buildHits(ids, scores, nHits),
            meta[2] != 0, hash[0],
        )
        if (nHits != meta[1]) analysis = analysis.copy(hash = ColorMath.resultHash(analysis))
        return GarmentAnalysisResult(analysis, buildGarments(labw, rgb, share, ints, meta[0]))
    }

    /** Explica el score de una combinación frente a una paleta (ce_match_explain_combo). */
    fun explainMatch(
        swatches: List<Swatch>,
        comboId: Int,
        options: MatchOptions = MatchOptions.DEFAULT,
    ): MatchExplanation {
        val main = DoubleArray(5)
        val ints = IntArray(3)
        val psIdx = IntArray(COLOR_ENGINE_MAX_SWATCHES)
        val psDe = DoubleArray(COLOR_ENGINE_MAX_SWATCHES)
        val pcIdx = IntArray(7)
        val pcSw = IntArray(7)
        val pcDe = DoubleArray(7)
        checkEngine(
            EngineNative.nativeExplain(
                requireHandle(), swatches.toNativeLabW(), swatches.size,
                options.toNative(), comboId, main, ints, psIdx, psDe, pcIdx, pcSw, pcDe,
            ),
        )
        return MatchExplanation(
            comboId = comboId, score = main[0], fitTerm = main[1], coverageTerm = main[2],
            hypothesisPenalty = main[3], exposureEv = main[4], illuminant = ints[0],
            perSwatch = List(ints[1]) { SwatchExplanation(psIdx[it], psDe[it]) },
            perColor = List(ints[2]) { ColorExplanation(pcIdx[it], pcSw[it], pcDe[it]) },
        )
    }

    /** Resumen de la última extracción de este contexto (ce_palette_debug_info). */
    fun paletteDebug(): PaletteDebug {
        val ints = IntArray(5)
        val dbls = DoubleArray(3)
        val clLabw = DoubleArray(64 * 4)
        val clRgb = IntArray(64 * 3)
        val clInts = IntArray(64 * 3)
        checkEngine(
            EngineNative.nativePaletteDebugInfo(
                requireHandle(), ints, dbls, clLabw, clRgb, clInts,
            ),
        )
        val nCl = ints[2]
        return PaletteDebug(
            reducedWidth = ints[0], reducedHeight = ints[1],
            clusters = List(nCl) { i ->
                ClusterDebug(
                    Lab(clLabw[i * 4], clLabw[i * 4 + 1], clLabw[i * 4 + 2]),
                    clRgb[i * 3], clRgb[i * 3 + 1], clRgb[i * 3 + 2], clLabw[i * 4 + 3],
                    ClusterFate.fromCode(clInts[i * 3]),
                    clInts[i * 3 + 1].takeIf { it >= 0 }, clInts[i * 3 + 2],
                )
            },
            lloydIterations = ints[3], totalWeight = dbls[0],
            zeroWeightFraction = dbls[1], centerSigmaPx = dbls[2], swatchCount = ints[4],
        )
    }

    /** Tipo de mapa de depuración (orden interno del puente JNI). */
    enum class DebugMapKind(val code: Int) {
        REDUCED_RGB(0), WEIGHT(1), LABEL(2), CLUSTER(3), GARMENT(4), REGION(5),
    }

    /** Lee un mapa de depuración de la última extracción; tamaño según PaletteDebug. */
    fun debugMap(kind: DebugMapKind, capacity: Int): ByteArray {
        val out = ByteArray(capacity)
        val n = checkEngine(EngineNative.nativeDebugMap(requireHandle(), kind.code, out))
        return out.copyOf(n)
    }

    /**
     * Análisis con todas las capas del inspector (paletteDebugLayers del Swift):
     * imagen reducida, pesos, etiquetas, clusters y explicación de cada hit.
     */
    fun analyzeWithLayers(
        image: EngineImage,
        paletteOptions: PaletteOptions = PaletteOptions.DEFAULT,
        matchOptions: MatchOptions = MatchOptions.DEFAULT,
    ): PaletteDebugLayers {
        val analysis = analyze(image, paletteOptions, matchOptions)
        val debug = paletteDebug()
        val px = debug.reducedWidth * debug.reducedHeight
        return PaletteDebugLayers(
            analysis = analysis, debug = debug,
            reducedRgb = debugMap(DebugMapKind.REDUCED_RGB, px * 3),
            weightMap = debugMap(DebugMapKind.WEIGHT, px),
            labelMap = debugMap(DebugMapKind.LABEL, px),
            clusterMap = debugMap(DebugMapKind.CLUSTER, px),
            explanations = analysis.hits.map {
                explainMatch(analysis.swatches, it.comboId, matchOptions)
            },
        )
    }

    /** Análisis por prenda con capas (garmentDebugLayers del Swift). */
    fun analyzeGarmentsWithLayers(
        image: EngineImage,
        regionMap: ByteArray? = null,
        regionCount: Int = 0,
        paletteOptions: PaletteOptions = PaletteOptions.DEFAULT,
        garmentOptions: GarmentOptions = GarmentOptions.DEFAULT,
        matchOptions: MatchOptions = MatchOptions.DEFAULT,
    ): GarmentDebugLayers {
        val result = analyzeGarments(
            image, regionMap, regionCount, paletteOptions, garmentOptions, matchOptions,
        )
        val debug = paletteDebug()
        val px = debug.reducedWidth * debug.reducedHeight
        val layers = PaletteDebugLayers(
            analysis = result.analysis, debug = debug,
            reducedRgb = debugMap(DebugMapKind.REDUCED_RGB, px * 3),
            weightMap = debugMap(DebugMapKind.WEIGHT, px),
            labelMap = debugMap(DebugMapKind.LABEL, px),
            clusterMap = debugMap(DebugMapKind.CLUSTER, px),
            explanations = result.analysis.hits.map {
                explainMatch(result.analysis.swatches, it.comboId, matchOptions)
            },
        )
        return GarmentDebugLayers(
            result = result, layers = layers,
            garmentMap = debugMap(DebugMapKind.GARMENT, px),
            regionMap = debugMap(DebugMapKind.REGION, px),
        )
    }

    companion object {
        /**
         * Recorta in situ la máscara de una persona a su ropa según la pose
         * (ce_mask_clothing_regions). Devuelve los píxeles > 0 resultantes.
         * Sin contexto, como en Swift.
         */
        fun clothingRegions(
            pose: Pose, mask: ByteArray, width: Int, height: Int,
            options: RegionOptions = RegionOptions.DEFAULT,
        ): Int {
            validateMask(mask, width, height)
            return checkEngine(
                EngineNative.nativeClothingRegions(
                    pose.toNative(), options.toNative(), mask, width, height,
                ),
            )
        }

        /** Mapa de regiones de prenda (ce_mask_garment_regions) en un buffer nuevo. */
        fun garmentRegions(
            pose: Pose, personMask: ByteArray, width: Int, height: Int,
            options: RegionOptions = RegionOptions.DEFAULT,
        ): Pair<ByteArray, Int> {
            validateMask(personMask, width, height)
            val out = ByteArray(width * height)
            val n = checkEngine(
                EngineNative.nativeGarmentRegions(
                    pose.toNative(), options.toNative(), personMask, width, height, out,
                ),
            )
            return out to n
        }

        /** Fallback sin pose: anula la franja superior del bbox (ce_mask_cut_head). */
        fun cutHead(mask: ByteArray, width: Int, height: Int, fraction: Double): Int {
            validateMask(mask, width, height)
            return checkEngine(EngineNative.nativeCutHead(mask, width, height, fraction))
        }

        /** Ajusta el modelo de piel con la muestra marcada (ce_skin_model_fit). */
        fun fitSkinModel(image: EngineImage, sampleMask: ByteArray): SkinModel {
            validateImage(image.copy(mask = null))
            validateMask(sampleMask, image.width, image.height)
            val model = DoubleArray(21)
            val n = IntArray(1)
            checkEngine(
                EngineNative.nativeSkinFit(
                    image.pixels, image.width, image.height, image.strideBytes,
                    image.format.code, sampleMask, model, n,
                ),
            )
            return SkinModel(
                Lab(model[0], model[1], model[2]),
                model.copyOfRange(3, 12), model.copyOfRange(12, 21), n[0],
            )
        }

        /**
         * Quita de [mask] los píxeles de piel (ce_mask_exclude_skin) in situ.
         * Devuelve (excluidos, salvaguardaSaltó) igual que el Swift.
         */
        fun excludeSkin(
            image: EngineImage, model: SkinModel, mask: ByteArray,
            options: SkinOptions = SkinOptions.DEFAULT,
        ): Pair<Int, Boolean> {
            validateImage(image.copy(mask = null))
            validateMask(mask, image.width, image.height)
            val before = mask.count { it != 0.toByte() }
            val rc = EngineNative.nativeExcludeSkin(
                image.pixels, image.width, image.height, image.strideBytes, image.format.code,
                model.toNative(), model.sampleCount, options.toNative(), mask,
            )
            if (rc < 0) throw EngineException.Engine(rc)
            val after = mask.count { it != 0.toByte() }
            return (before - after) to (rc == 1)
        }

        /** Separa una instancia fusionada (ce_mask_split_instance): (etiquetas, conteo). */
        fun splitInstance(
            mask: ByteArray, width: Int, height: Int, seeds: List<PersonSeed>,
        ): Pair<ByteArray, Int> {
            validateMask(mask, width, height)
            if (seeds.isEmpty() || seeds.size > SPLIT_MAX_SEEDS) {
                throw EngineException.Engine(EngineException.Engine.ERR_ARG)
            }
            val flat = DoubleArray(seeds.size * 5)
            seeds.forEachIndexed { i, s ->
                flat[i * 5] = s.x0
                flat[i * 5 + 1] = s.y0
                flat[i * 5 + 2] = s.x1
                flat[i * 5 + 3] = s.y1
                flat[i * 5 + 4] = s.halfWidth
            }
            val out = ByteArray(width * height)
            val n = checkEngine(
                EngineNative.nativeSplitInstance(mask, width, height, flat, seeds.size, out),
            )
            return out to n
        }
    }
}

/** Copia sin máscara para validar solo el buffer de píxeles (piel). */
private fun EngineImage.copy(mask: ByteArray?): EngineImage =
    EngineImage(pixels, width, height, strideBytes, format, mask)

private fun buildSwatches(labw: DoubleArray, rgb: IntArray, n: Int): List<Swatch> =
    List(n) { i ->
        Swatch(
            Lab(labw[i * 4], labw[i * 4 + 1], labw[i * 4 + 2]),
            rgb[i * 3], rgb[i * 3 + 1], rgb[i * 3 + 2], labw[i * 4 + 3],
        )
    }

private fun buildHits(ids: IntArray, scores: DoubleArray, n: Int): List<Hit> =
    List(n) { Hit(ids[it], scores[it]) }

private fun buildGarments(
    labw: DoubleArray, rgb: IntArray, share: DoubleArray, ints: IntArray, n: Int,
): List<GarmentSwatch> {
    val swatches = buildSwatches(labw, rgb, n)
    return List(n) { i ->
        GarmentSwatch(
            swatches[i], GarmentRegion.fromCode(ints[i * 2]), share[i], ints[i * 2 + 1],
        )
    }
}
