// Capas del inspector de sujeto: espejo de PersonLayers/SubjectLayers/
// RegionDecision/GarmentRegionStats de SubjectTypes.swift. Las produce la
// cadena (SubjectChain.kt) y las pinta el inspector de capas (carril W4).
// Todas las máscaras son MaskBuffer (width*height, 0..255; el mapa de
// prendas usa 0/1/2).
package com.andreseloy.colorsapp.subject

import com.andreseloy.colorsapp.engine.Pose
import com.andreseloy.colorsapp.engine.RegionOptions
import com.andreseloy.colorsapp.engine.SkinModel

/** De dónde sale la región de una persona (RegionSource de SubjectKit). */
enum class RegionSource(val raw: String) {
    POSE_REGIONS("poseRegions"),
    POSE_SILHOUETTE("poseSilhouette"),
    HEAD_CUT("headCut"),
    WHOLE_PERSON("wholePerson"),
}

/** Cómo se eligió la región de una persona (para explicarlo en la capa). */
data class RegionDecision(
    val source: RegionSource,
    val bodyPixels: Int,
    val requiredPixels: Int,
    val poseRegionPixels: Int?,
    val silhouettePixels: Int?,
    val regionPixels: Int,
    val regionPose: Pose?,
    val hipsEstimated: Boolean,
    val headCutFraction: Double?,
    val regionOptions: RegionOptions? = null,
    val upperArmsDropped: Boolean = false,
    val armPixels: Int? = null,
    val armSkinPixels: Int? = null,
    val bareArmsDropped: Boolean = false,
    val legPixels: Int? = null,
    val legSkinPixels: Int? = null,
    val sleevePixels: Int? = null,
    val sleeveMatchPixels: Int? = null,
    val sleevesKept: Boolean = false,
)

/** Recuentos del mapa de regiones de prenda de una persona. */
data class GarmentRegionStats(
    val upperPixels: Int,
    val lowerPixels: Int,
    val maskPixels: Int,
    val lowerMergedIntoUpper: Boolean,
    val mergedLowerPixels: Int,
    val options: RegionOptions,
    val pose: Pose,
)

/** Capas de una persona a lo largo de la cadena (mismas dimensiones que el raster). */
class PersonLayers(
    val personIndex: Int,
    val instanceId: Int,
    /** Máscara BINARIA de la persona (entrada de la cadena). */
    val personMask: MaskBuffer,
    /** Pose en píxeles del raster (para dibujar el esqueleto); la del motor va en regionDecision. */
    val pose: Pose?,
    /** Región de ropa antes de la piel; null con WHOLE_PERSON. */
    val regionMask: MaskBuffer?,
    /** Muestra de piel de la cara usada para el modelo. */
    val faceSampleMask: MaskBuffer?,
    /** 255 donde se quitó piel (exclusión, crecimiento y halo). */
    val skinRemovedMask: MaskBuffer?,
    /** Máscara de esta persona al final de su cadena (antes del suelo). */
    val finalMask: MaskBuffer,
    val steps: List<MaskStep>,
    /** Modelo de piel con el que se excluyó (el aprendido si lo hubo). */
    val skinModel: SkinModel?,
    /** Píxeles que la exclusión de piel pasó a 0 (crecimiento y halo incluidos). */
    val skinExcludedPixels: Int,
    /** Por qué no se aplicó la piel teniendo muestra (p. ej. "tooFewSkinSamples"). */
    val skinNote: String?,
    val regionDecision: RegionDecision? = null,
    /** false si esta persona no aporta a la máscara final. */
    val usedInMask: Boolean = true,
    /** Índice de la persona cuya cara dio la muestra de piel (compartida o propia). */
    val skinSampleSource: Int? = null,
    val silhouetteMask: MaskBuffer? = null,
    /** Brazos probados (piel desnuda o mangas). */
    val armsMask: MaskBuffer? = null,
    /** Con paso WHOLE_PERSON: qué máscara se usó en lugar de la final. */
    val fallbackSource: RegionSource? = null,
    /** Muestras ampliadas con la piel del cuerpo, una por pasada aceptada. */
    val learnedSampleMasks: List<MaskBuffer> = emptyList(),
    val skinLearningPixels: List<Int> = emptyList(),
    /** Máscara justo después de excluir la piel, antes de crecimiento/halo. */
    val skinExcludedMask: MaskBuffer? = null,
    val skinHaloPixels: Int = 0,
    /** Torso usado en la prueba de mangas. */
    val sleeveTorsoMask: MaskBuffer? = null,
    val legsMask: MaskBuffer? = null,
    val skinGrownPixels: Int = 0,
    val skinGrownMask: MaskBuffer? = null,
    /** Candidatos del crecimiento (a Mahalanobis débil) antes de conectar. */
    val skinGrowCandidatePixels: Int? = null,
    /** Mapa de prendas de esta persona (0 fuera, 1 arriba, 2 abajo). */
    val garmentRegions: MaskBuffer? = null,
    val garmentRegionStats: GarmentRegionStats? = null,
)

/** Capas visuales del recorte completo. */
class SubjectLayers(
    val width: Int,
    val height: Int,
    /** Una entrada con largest/selected; una por persona con allPeople. */
    val persons: List<PersonLayers>,
    /** Id de persona por píxel (0 = fondo), para pintar cada persona de un color. */
    val allPeopleOverlay: MaskBuffer,
    /** Máscara que se entrega al motor (== SubjectMaskResult.mask). */
    val finalMask: MaskBuffer?,
) {
    /** Capas de la persona elegida (la primera entrada). */
    val primary: PersonLayers? get() = persons.firstOrNull()
}
