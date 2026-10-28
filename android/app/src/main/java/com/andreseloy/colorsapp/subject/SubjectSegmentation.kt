// Contrato de segmentación de sujeto para Android: la interfaz contra la que
// programa la ola 2 y donde enchufa el resultado de la investigación del
// carril B (máscaras de instancia de persona, pose, caras y, si el modelo lo
// da, clases piel/ropa). Espejo de los tipos públicos de SubjectKit
// (apple/SubjectKit/Sources/SubjectKit/SubjectTypes.swift): la plataforma
// APORTA detección (Vision en iOS; el modelo que elija el carril B aquí) y la
// geometría/estadística de la cadena vive en el motor C, igual en las dos
// plataformas. La implementación de la cadena (SubjectChain) es de la ola 2.
package com.andreseloy.colorsapp.subject

import com.andreseloy.colorsapp.engine.EngineImage
import com.andreseloy.colorsapp.engine.Pose
import com.andreseloy.colorsapp.engine.RegionOptions
import com.andreseloy.colorsapp.engine.SkinOptions

/** Qué persona(s) se usan (SubjectMode de SubjectKit; raw = valor en la BD). */
enum class SubjectMode(val raw: String) {
    OFF("off"),
    ALL_PEOPLE("allPeople"),
    LARGEST_PERSON("largestPerson"),
    SELECTED_PERSON("selectedPerson");

    companion object {
        fun fromRaw(raw: String?): SubjectMode = entries.firstOrNull { it.raw == raw } ?: LARGEST_PERSON
    }
}

/** Qué parte de la persona se usa (RegionMode de SubjectKit). */
enum class RegionMode(val raw: String) {
    WHOLE_PERSON("wholePerson"),
    CLOTHING("clothing");

    companion object {
        fun fromRaw(raw: String?): RegionMode = entries.firstOrNull { it.raw == raw } ?: CLOTHING
    }
}

/** Pasos y retornos de la cadena (MaskFallback de SubjectKit; raw = JSON en scans.mask_steps). */
enum class MaskStep(val raw: String) {
    NONE("none"),
    NO_PEOPLE("noPeople"),
    POSE_REGIONS("poseRegions"),
    HEAD_CUT("headCut"),
    WHOLE_PERSON("wholePerson"),
    SKIN_EXCLUDED("skinExcluded"),
    SKIN_GUARD("skinGuard"),
    VISION_UNAVAILABLE("visionUnavailable"),
    REJECTED_PHANTOM("rejectedPhantom"),
    GARMENT_REGIONS("garmentRegions"),
    SPLIT_BY_POSE("splitByPose"),
    SPLIT_BY_FACE("splitByFace");

    companion object {
        fun fromRaw(raw: String): MaskStep? = entries.firstOrNull { it.raw == raw }
    }
}

/** Máscara empaquetada width*height bytes 0..255, sin stride (formato del motor). */
class MaskBuffer(val width: Int, val height: Int, val bytes: ByteArray) {
    init {
        require(width >= 1 && height >= 1 && bytes.size >= width * height) {
            "MaskBuffer ${width}x$height con ${bytes.size} bytes"
        }
    }

    /** Fracción de píxeles >= 128 (cobertura como la cuenta SubjectKit). */
    fun coverage(): Double {
        if (width * height == 0) return 0.0
        var n = 0
        for (i in 0 until width * height) {
            if ((bytes[i].toInt() and 0xFF) >= 128) n++
        }
        return n.toDouble() / (width * height)
    }
}

/** Cara detectada: caja en píxeles del raster y, si el detector los da, sus
 *  puntos (mejillas para la muestra de piel). Coordenadas origen arriba-izquierda. */
data class DetectedFace(
    val left: Float,
    val top: Float,
    val right: Float,
    val bottom: Float,
    val confidence: Float = 1f,
    /** Muestra de piel ya rasterizada (mejillas), si la cadena la construye. */
    val skinSampleMask: MaskBuffer? = null,
)

/** Clases semánticas por píxel que un modelo de parsing puede aportar (carril B).
 *  La cadena puede usarlas como evidencia, pero la exclusión de piel oficial
 *  sigue siendo la del motor (modelo gaussiano): ningún resultado depende de
 *  una clase que otro modelo no dé. */
enum class SemanticClass(val code: Int) {
    BACKGROUND(0), SKIN(1), UPPER_GARMENT(2), LOWER_GARMENT(3),
    HAIR(4), FACE(5), OTHER_PERSON_PART(6),
}

/** Una persona detectada por la plataforma (antes de la cadena del motor). */
class PersonDetection(
    /** Máscara de instancia de la persona (0..255). */
    val instanceMask: MaskBuffer,
    /** Pose en píxeles del raster, orden ce_joint; null si el detector no da pose. */
    val pose: Pose? = null,
    /** Cara asociada, si la hay. */
    val face: DetectedFace? = null,
    /** Mapa de clases semánticas (códigos SemanticClass), si el modelo lo da. */
    val semanticMap: MaskBuffer? = null,
    /** Confianza global de la instancia [0, 1]. */
    val confidence: Float = 1f,
    // --- Aditivo (carril W2): lo que PersonInstance de SubjectKit lleva y la
    // cadena necesita; con valores por defecto para no romper a otros carriles.
    /** Id estable dentro de la foto (1..n; desempate al ordenar por cobertura). */
    val id: Int = 0,
    /** Muestra de piel de la cara (255 en mejillas/frente), si se construyó. */
    val faceSampleMask: MaskBuffer? = null,
    /** Landmarks de la cara asociada (para (re)construir la muestra de piel). */
    val faceLandmarks: FaceLandmarkPoints? = null,
    /** Id de la instancia origen si esta persona se separó de una fusionada. */
    val splitFrom: Int? = null,
) {
    /** Caja de la cara en píxeles del raster (desde [face]), o null sin cara. */
    val faceBox: RectD? get() = face?.let {
        RectD(
            it.left.toDouble(), it.top.toDouble(),
            (it.right - it.left).toDouble(), (it.bottom - it.top).toDouble(),
        )
    }

    /** Paso de separación de esta persona, como PersonInstance.splitStep. */
    val splitStep: MaskStep? get() =
        if (splitFrom == null) null else if (pose != null) MaskStep.SPLIT_BY_POSE else MaskStep.SPLIT_BY_FACE
}

/**
 * Detector de personas de plataforma (VisionDetector en SubjectKit). Lo
 * implementa la ola 2 con el modelo que decida el informe del carril B
 * (docs/research/android-subject*): todo en el dispositivo, modelo
 * empaquetado en la app, sin descargas en tiempo de ejecución.
 */
interface PersonDetector {
    /** Nombre y versión del modelo, para diagnósticos (p. ej. "modelox-1.2"). */
    val modelDescription: String

    /** Detecta personas en el raster (<= 1024 px de lado, formato RGBX8/RGB8). */
    suspend fun detect(image: EngineImage): List<PersonDetection>
}

/** Opciones de la cadena (SubjectOptions de SubjectKit; los campos tras
 *  minRegionFraction los añadió el carril W2 con los valores por defecto
 *  exactos del Swift, para que la cadena portada sea literal). */
data class SubjectOptions(
    val mode: SubjectMode = SubjectMode.LARGEST_PERSON,
    val region: RegionMode = RegionMode.CLOTHING,
    val adaptiveSkin: Boolean = true,
    val shareSkinModel: Boolean = true,
    val selectedIndex: Int? = null,
    val computeGarmentRegions: Boolean = true,
    val regionOptions: RegionOptions? = null,
    val skinOptions: SkinOptions = DEFAULT_SKIN_OPTIONS,
    val minCoverage: Double = 0.0005,
    val minRegionFraction: Double = 0.15,
    /** Fracción de píxeles de brazo que deben ser piel para quitar los brazos. */
    val bareArmsSkinFraction: Double = 0.25,
    /** Pasadas de aprendizaje de la piel del cuerpo (0 = nunca). */
    val skinLearningIterations: Int = 2,
    /** Mahalanobis de los píxeles que amplían la muestra al aprender. */
    val skinLearningMahalanobis: Double = 3.0,
    /** Halo Chebyshev (px) alrededor de la piel quitada. */
    val skinHaloRadius: Int = 2,
    /** Crecimiento de la piel en sombra: Mahalanobis débil conectado. */
    val skinGrowMahalanobis: Double = 5.0,
    /** Pasos máximos del crecimiento desde la piel quitada. */
    val skinGrowRadius: Int = 12,
    /** El crecimiento no supera esta fracción de la piel quitada. */
    val skinGrowMaxRatio: Double = 0.5,
    /** Sin modelo de piel: fracción de brazo parecida al torso para ser manga. */
    val sleeveMatchFraction: Double = 0.7,
    /** Mahalanobis de la prueba de mangas. */
    val sleeveMatchMahalanobis: Double = 2.0,
    /** Evidencia corporal anti-fantasmas (la aplica el detector). */
    val phantomOptions: PhantomOptions = PhantomOptions(),
    /** Separación de personas fusionadas (la aplica el detector). */
    val splitOptions: SplitOptions = SplitOptions(),
) {
    companion object {
        /** Preajuste de SubjectKit: Mahalanobis 2,75 (el motor trae 2,5; ADR-010). */
        val DEFAULT_SKIN_OPTIONS = SkinOptions(maxMahalanobis = 2.75, maxExcludedFraction = 0.35)
    }
}

/** Una persona tras la cadena, lista para persistir y pintar (PersonInstance). */
class PersonInstanceResult(
    val id: Int,
    val coverage: Double,
    val finalMask: MaskBuffer?,
    val garmentRegions: MaskBuffer? = null,
    // Aditivo (W2): lo que las capas y el selector de persona necesitan.
    /** Máscara de instancia original (blanda) de la que sale esta persona. */
    val instanceMask: MaskBuffer? = null,
    /** Pose asociada en píxeles del raster, si la hay. */
    val pose: Pose? = null,
    /** Id de la instancia origen si se separó de una fusionada. */
    val splitFrom: Int? = null,
    /** Pasos de la cadena de esta persona. */
    val steps: List<MaskStep> = emptyList(),
)

/** Resultado completo de la cadena (SubjectMaskResult de SubjectKit). */
class SubjectMaskResult(
    val width: Int,
    val height: Int,
    /** Personas por cobertura descendente. */
    val people: List<PersonInstanceResult>,
    /** Índice en people de la usada; null con ALL_PEOPLE, OFF o sin personas. */
    val chosenIndex: Int?,
    /** Máscara para el motor (0/255); null = analizar sin máscara. */
    val mask: MaskBuffer?,
    /** Mapa de regiones de prenda de la persona elegida (1 arriba, 2 abajo). */
    val garmentRegions: MaskBuffer? = null,
    val steps: List<MaskStep> = emptyList(),
    val timingsMs: Map<String, Double> = emptyMap(),
    // Aditivo (W2): capas del inspector y fantasmas descartadas, como en iOS.
    /** Capas por etapa (personas, pose, piel, prendas…), si se calcularon. */
    val layers: SubjectLayers? = null,
    /** Instancias descartadas sin evidencia corporal (paso REJECTED_PHANTOM). */
    val rejectedPhantoms: List<PersonInstanceResult> = emptyList(),
) {
    val maskCoverage: Double get() = mask?.coverage() ?: 0.0
}

/**
 * La cadena de sujeto completa: detector de plataforma + geometría y piel del
 * motor C. La implementa la ola 2 (SubjectChain); la fundación trae
 * [WholePhotoSubjectSegmenter] como sustituto inerte.
 */
interface SubjectSegmenter {
    suspend fun compute(image: EngineImage, options: SubjectOptions): SubjectMaskResult
}

/** Sustituto inerte: sin máscara (foto completa). Para tests y hasta la ola 2. */
class WholePhotoSubjectSegmenter : SubjectSegmenter {
    override suspend fun compute(image: EngineImage, options: SubjectOptions): SubjectMaskResult =
        SubjectMaskResult(
            width = image.width,
            height = image.height,
            people = emptyList(),
            chosenIndex = null,
            mask = null,
            steps = listOf(MaskStep.NONE),
        )
}

/** Ajustes persistidos del recorte (SubjectSettings de iOS; claves en `settings`). */
data class SubjectSettings(
    val mode: SubjectMode = SubjectMode.LARGEST_PERSON,
    val region: RegionMode = RegionMode.CLOTHING,
    val adaptiveSkin: Boolean = true,
    val unlockMaxScore: Double = 12.0,
) {
    fun subjectOptions(): SubjectOptions = SubjectOptions(
        mode = mode, region = region, adaptiveSkin = adaptiveSkin,
        computeGarmentRegions = true,
    )

    companion object {
        val SETTINGS_MODES: List<SubjectMode> =
            listOf(SubjectMode.OFF, SubjectMode.ALL_PEOPLE, SubjectMode.LARGEST_PERSON)
    }
}
