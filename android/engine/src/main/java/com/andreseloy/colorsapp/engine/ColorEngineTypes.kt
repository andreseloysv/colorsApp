// API Kotlin del motor de color: espejo de
// engine/Sources/ColorEngine/ColorEngine.swift. Sin lógica de color aquí:
// cada función valida tamaños (como el Swift) y delega en el C11 vía JNI.
package com.andreseloy.colorsapp.engine

/** Color en CIELAB (D65). L en [0, 100]; a y b sin acotar. */
data class Lab(val l: Double, val a: Double, val b: Double)

/** Error de la API del motor (espejo de ColorEngineError en Swift). */
sealed class EngineException(message: String) : Exception(message) {
    /** El buffer es más corto que (height - 1) * stride + width * bpp. */
    class BufferTooSmall(val required: Int, val actual: Int) :
        EngineException("bufferTooSmall(required=$required, actual=$actual)")

    /** La máscara tiene menos de width * height bytes. */
    class MaskTooSmall(val required: Int, val actual: Int) :
        EngineException("maskTooSmall(required=$required, actual=$actual)")

    /** El motor devolvió un ce_status negativo (ver ce.h). */
    class Engine(val code: Int) : EngineException("engine(code=$code)") {
        companion object {
            const val ERR_ARG = -1
            const val ERR_CTX = -2
            const val ERR_DIMS = -3
            const val ERR_STRIDE = -4
            const val ERR_FORMAT = -5
            const val ERR_OPTS = -6
            const val ERR_POSE = -8
            const val ERR_SKIN_SAMPLES = -9
        }
    }
}

/** Formato de píxel de entrada (ce_pixel_format): 8 bits/canal sRGB, alpha ignorada. */
enum class PixelFormat(val code: Int, val bytesPerPixel: Int) {
    RGBA8(0, 4),
    RGBX8(1, 4),
    RGB8(2, 3),
}

/**
 * Swatch de la paleta: Lab (D65), sRGB8 (Lab -> sRGB8 con clamp en el motor) y
 * peso relativo; la suma de pesos de una paleta es 1.
 */
data class Swatch(val lab: Lab, val r: Int, val g: Int, val b: Int, val weight: Double) {
    /** "#rrggbb" en minúsculas, como el Swift. Solo formato, sin conversión. */
    val hex: String get() = "#%02x%02x%02x".format(r, g, b)

    /** Color ARGB empaquetado (0xFFrrggbb) para pintar en Compose/views. */
    val argb: Int get() = (0xFF shl 24) or (r shl 16) or (g shl 8) or b
}

/** Opciones de ce_palette_extract (rangos en ce.h). centerSigma <= 0 = uniforme. */
data class PaletteOptions(
    val kInit: Int,
    val maxIters: Int,
    val maxColors: Int,
    val maxSide: Int,
    val centerSigma: Double,
    val mergeDeltaE: Double,
    val minWeight: Double,
    val skinRule: Boolean,
    // Experimento desactivado por defecto (0): fusión de sombras (ver ce.h).
    val mergeLightDeltaE: Double = 0.0,
) {
    internal fun toNative() = doubleArrayOf(
        kInit.toDouble(), maxIters.toDouble(), maxColors.toDouble(), maxSide.toDouble(),
        centerSigma, mergeDeltaE, minWeight, if (skinRule) 1.0 else 0.0, mergeLightDeltaE,
    )

    companion object {
        /** Valores de ce_palette_opts_default, leídos del propio motor. */
        val DEFAULT: PaletteOptions by lazy {
            val d = EngineDefaults.values
            PaletteOptions(
                kInit = d[0].toInt(), maxIters = d[1].toInt(), maxColors = d[2].toInt(),
                maxSide = d[3].toInt(), centerSigma = d[4], mergeDeltaE = d[5],
                minWeight = d[6], skinRule = d[7] != 0.0, mergeLightDeltaE = d[8],
            )
        }
    }
}

/** Opciones de ce_match (rangos y fórmula en ce.h). */
data class MatchOptions(
    val kL: Double,
    val kC: Double,
    val kH: Double,
    val coverageLambda: Double,
    val ambiguousGap: Double,
    val exposureEvMax: Double,
    val exposurePenalty: Double,
    val illuminantSearch: Boolean,
    val illuminantPenalty: Double,
) {
    internal fun toNative() = doubleArrayOf(
        kL, kC, kH, coverageLambda, ambiguousGap, exposureEvMax, exposurePenalty,
        if (illuminantSearch) 1.0 else 0.0, illuminantPenalty,
    )

    companion object {
        /** Valores de ce_match_opts_default, leídos del propio motor. */
        val DEFAULT: MatchOptions by lazy {
            val d = EngineDefaults.values
            MatchOptions(
                kL = d[9], kC = d[10], kH = d[11], coverageLambda = d[12],
                ambiguousGap = d[13], exposureEvMax = d[14], exposurePenalty = d[15],
                illuminantSearch = d[16] != 0.0, illuminantPenalty = d[17],
            )
        }
    }
}

/** Un candidato del match: id de combinación (1..348) y score (menor = mejor). */
data class Hit(val comboId: Int, val score: Double)

/** Resultado completo de ce_analyze, con su hash FNV-1a comparable entre plataformas. */
data class AnalysisResult(
    val swatches: List<Swatch>,
    val hits: List<Hit>,
    val ambiguous: Boolean,
    val hash: Long,
)

/** Opciones de la paleta por prenda (ce_garment_opts; ver ce.h). */
data class GarmentOptions(
    val shadeKL: Double,
    val shadeMergeDeltaE: Double,
    val litLowPercentile: Double,
    val litHighPercentile: Double,
    val secondaryMinShare: Double,
    val maxColorsPerRegion: Int,
) {
    internal fun toNative() = doubleArrayOf(
        shadeKL, shadeMergeDeltaE, litLowPercentile, litHighPercentile,
        secondaryMinShare, maxColorsPerRegion.toDouble(),
    )

    companion object {
        val DEFAULT: GarmentOptions by lazy {
            val d = EngineDefaults.values
            GarmentOptions(d[18], d[19], d[20], d[21], d[22], d[23].toInt())
        }
    }
}

/** Región de prenda de un swatch (CE_GARMENT_REGION_*). */
enum class GarmentRegion(val code: Int) {
    NONE(0), UPPER(1), LOWER(2), WHOLE(3);

    companion object {
        fun fromCode(code: Int): GarmentRegion = entries.firstOrNull { it.code == code } ?: NONE
    }
}

/** Swatch de prenda: un color por prenda lisa, con su región y cuota. */
data class GarmentSwatch(
    val swatch: Swatch,
    val region: GarmentRegion,
    val regionShare: Double,
    val mergedClusterCount: Int,
)

/** Resultado de ce_analyze_garments: el análisis y los swatches con región. */
data class GarmentAnalysisResult(
    val analysis: AnalysisResult,
    val garments: List<GarmentSwatch>,
)

/** Articulaciones de la pose, en el orden de ce_joint / VNHumanBodyPoseObservation. */
enum class Joint {
    NOSE, NECK, LEFT_SHOULDER, RIGHT_SHOULDER, LEFT_ELBOW, RIGHT_ELBOW,
    LEFT_WRIST, RIGHT_WRIST, LEFT_HIP, RIGHT_HIP, LEFT_KNEE, RIGHT_KNEE,
    LEFT_ANKLE, RIGHT_ANKLE, ROOT,
}

/** Punto de la pose en píxeles de la máscara. confidence <= 0 = ausente. */
data class Keypoint(val x: Double, val y: Double, val confidence: Double) {
    companion object {
        val MISSING = Keypoint(0.0, 0.0, 0.0)
    }
}

/** Pose completa: un Keypoint por Joint, en el orden del enum. */
data class Pose(val joints: List<Keypoint> = List(Joint.entries.size) { Keypoint.MISSING }) {
    operator fun get(joint: Joint): Keypoint = joints[joint.ordinal]

    fun with(joint: Joint, keypoint: Keypoint): Pose =
        Pose(joints.mapIndexed { i, k -> if (i == joint.ordinal) keypoint else k })

    internal fun toNative() = DoubleArray(joints.size * 3) { i ->
        val k = joints[i / 3]
        when (i % 3) {
            0 -> k.x
            1 -> k.y
            else -> k.confidence
        }
    }
}

/** Opciones de ce_mask_clothing_regions / ce_mask_garment_regions. */
data class RegionOptions(
    val minConfidence: Double,
    val torsoMargin: Double,
    val limbWidth: Double,
    val includeUpperArms: Boolean,
    val includeForearms: Boolean,
    val includeLegs: Boolean,
    val includeLowerLegs: Boolean,
) {
    internal fun toNative() = doubleArrayOf(
        minConfidence, torsoMargin, limbWidth,
        if (includeUpperArms) 1.0 else 0.0, if (includeForearms) 1.0 else 0.0,
        if (includeLegs) 1.0 else 0.0, if (includeLowerLegs) 1.0 else 0.0,
    )

    companion object {
        val DEFAULT: RegionOptions by lazy {
            val d = EngineDefaults.values
            RegionOptions(
                d[24], d[25], d[26], d[27] != 0.0, d[28] != 0.0, d[29] != 0.0, d[30] != 0.0,
            )
        }
    }
}

/** Modelo gaussiano de piel en Lab (ce_skin_model): media y covarianzas 3x3. */
class SkinModel(
    val mean: Lab,
    val covariance: DoubleArray,
    val inverseCovariance: DoubleArray,
    val sampleCount: Int,
) {
    internal fun toNative() = DoubleArray(21).also {
        it[0] = mean.l
        it[1] = mean.a
        it[2] = mean.b
        covariance.copyInto(it, 3, 0, 9)
        inverseCovariance.copyInto(it, 12, 0, 9)
    }
}

/** Opciones de ce_mask_exclude_skin. */
data class SkinOptions(val maxMahalanobis: Double, val maxExcludedFraction: Double) {
    internal fun toNative() = doubleArrayOf(maxMahalanobis, maxExcludedFraction)

    companion object {
        val DEFAULT: SkinOptions by lazy {
            val d = EngineDefaults.values
            SkinOptions(d[31], d[32])
        }
    }
}

/** Semilla de una persona para separar una instancia fusionada (ce_person_seed). */
data class PersonSeed(
    val x0: Double, val y0: Double, val x1: Double, val y1: Double, val halfWidth: Double,
)

/** Explicación del score de una combinación (ce_match_explain). */
data class MatchExplanation(
    val comboId: Int,
    val score: Double,
    val fitTerm: Double,
    val coverageTerm: Double,
    val hypothesisPenalty: Double,
    val exposureEv: Double,
    /** -1 sin adaptación de iluminante, o el ce_illuminant (0=A, 1=D50, 2=D65, 3=D75, 4=F2). */
    val illuminant: Int,
    val perSwatch: List<SwatchExplanation>,
    val perColor: List<ColorExplanation>,
)

data class SwatchExplanation(val nearestColorIndex: Int, val deltaE: Double)

data class ColorExplanation(val colorIndex: Int, val nearestSwatch: Int, val deltaE: Double)

/** Destino de un cluster de Lloyd (CE_FATE_*). */
enum class ClusterFate(val code: Int) {
    KEPT(0), MERGED(1), DISCARDED(2), TRUNCATED(3);

    companion object {
        fun fromCode(code: Int): ClusterFate = entries.firstOrNull { it.code == code } ?: KEPT
    }
}

data class ClusterDebug(
    val lab: Lab, val r: Int, val g: Int, val b: Int, val weight: Double,
    val fate: ClusterFate, val finalIndex: Int?, val groupHead: Int,
) {
    val hex: String get() = "#%02x%02x%02x".format(r, g, b)
}

/** Resumen de la última extracción (ce_palette_debug). */
data class PaletteDebug(
    val reducedWidth: Int,
    val reducedHeight: Int,
    val clusters: List<ClusterDebug>,
    val lloydIterations: Int,
    val totalWeight: Double,
    val zeroWeightFraction: Double,
    val centerSigmaPx: Double,
    val swatchCount: Int,
)

/** Capas de depuración de una extracción (inspector de capas). */
class PaletteDebugLayers(
    val analysis: AnalysisResult,
    val debug: PaletteDebug,
    val reducedRgb: ByteArray,
    val weightMap: ByteArray,
    val labelMap: ByteArray,
    val clusterMap: ByteArray,
    val explanations: List<MatchExplanation>,
)

/** Capas de depuración de la paleta por prenda. */
class GarmentDebugLayers(
    val result: GarmentAnalysisResult,
    val layers: PaletteDebugLayers,
    val garmentMap: ByteArray,
    val regionMap: ByteArray,
)

/** Imagen de entrada para el motor: buffer del llamante + dimensiones + máscara opcional. */
class EngineImage(
    val pixels: ByteArray,
    val width: Int,
    val height: Int,
    val strideBytes: Int,
    val format: PixelFormat = PixelFormat.RGBA8,
    val mask: ByteArray? = null,
)
