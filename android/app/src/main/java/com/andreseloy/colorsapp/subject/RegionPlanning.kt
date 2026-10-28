// Port literal de apple/SubjectKit/Sources/SubjectKit/RegionPlanning.swift:
// caderas estimadas en planos medios, opciones de la silueta y de prendas, y
// altura del recorte de cabeza. Solo preparan ENTRADAS del motor C (puntos
// de pose, opciones, fracción); la geometría de máscaras sigue en ce.
package com.andreseloy.colorsapp.subject

import com.andreseloy.colorsapp.engine.ColorEngine
import com.andreseloy.colorsapp.engine.EngineException
import com.andreseloy.colorsapp.engine.Joint
import com.andreseloy.colorsapp.engine.Keypoint
import com.andreseloy.colorsapp.engine.Pose
import com.andreseloy.colorsapp.engine.RegionOptions
import kotlin.math.abs
import kotlin.math.max
import kotlin.math.min
import kotlin.math.sqrt

object RegionPlanning {
    /** Fracción de cutHead sin cara (y mínima con cara). */
    const val HEAD_CUT_FRACTION = 0.18

    /** Fracción máxima de cutHead (la del motor). */
    const val MAX_HEAD_CUT_FRACTION = 0.5

    /** Con cara, el corte cae en su borde inferior + este factor por su alto. */
    const val HEAD_CUT_NECK_FACTOR = 0.25

    /** Caderas estimadas: distancia hombros->caderas en anchos de hombros. */
    const val ESTIMATED_TORSO_LENGTH = 1.2

    /** Caderas estimadas: separación relativa a la de los hombros. */
    const val ESTIMATED_HIP_WIDTH = 0.75

    /** Silueta de la pose: ancho total de las cápsulas (anchos de hombros). */
    const val SILHOUETTE_LIMB_WIDTH = 1.0

    /** Silueta de la pose: margen del torso (anchos de hombros). */
    const val SILHOUETTE_TORSO_MARGIN = 0.35

    /** Detección: cobertura mínima de una instancia (fragmentos fuera). */
    const val MIN_PERSON_COVERAGE = 0.0005

    /** Regla de "punto utilizable" del motor (ce_mask_clothing_regions). */
    fun usable(k: Keypoint, minConfidence: Double): Boolean =
        k.confidence.isFinite() && k.confidence > 0 && k.confidence >= minConfidence &&
            k.x.isFinite() && k.y.isFinite() && abs(k.x) <= 1_048_576 && abs(k.y) <= 1_048_576

    private data class PairPts(val left: Pt, val right: Pt, val confidence: Double)

    /** Par izquierda/derecha con la simetría del motor (P = 2·medio - P_otro). */
    private fun pair(pose: Pose, l: Joint, r: Joint, mid: Joint, minConfidence: Double): PairPts? {
        val left = pose[l]
        val right = pose[r]
        val m = pose[mid]
        val uL = usable(left, minConfidence)
        val uR = usable(right, minConfidence)
        val uM = usable(m, minConfidence)
        if (uL && uR) return PairPts(Pt(left.x, left.y), Pt(right.x, right.y), min(left.confidence, right.confidence))
        if (uL && uM) {
            return PairPts(
                Pt(left.x, left.y), Pt(2 * m.x - left.x, 2 * m.y - left.y),
                min(left.confidence, m.confidence),
            )
        }
        if (uR && uM) {
            return PairPts(
                Pt(2 * m.x - right.x, 2 * m.y - right.y), Pt(right.x, right.y),
                min(right.confidence, m.confidence),
            )
        }
        return null
    }

    /**
     * Pose que se entrega a clothingRegions: si el motor no puede formar las
     * caderas pero sí los hombros (ancho sw >= 1 px), estima raíz y caderas a
     * 1,2·sw en la normal a la línea de hombros (lejos de la nariz; si no,
     * hacia abajo), con separación 0,75·sw, y borra rodillas y tobillos.
     * Devuelve (pose, caderasEstimadas).
     */
    fun regionPose(pose: Pose, minConfidence: Double): Pair<Pose, Boolean> {
        if (pose.joints.size != Joint.entries.size) return pose to false
        if (pair(pose, Joint.LEFT_HIP, Joint.RIGHT_HIP, Joint.ROOT, minConfidence) != null) {
            return pose to false
        }
        val s = pair(pose, Joint.LEFT_SHOULDER, Joint.RIGHT_SHOULDER, Joint.NECK, minConfidence)
            ?: return pose to false
        val dx = s.right.x - s.left.x
        val dy = s.right.y - s.left.y
        val sw = sqrt(dx * dx + dy * dy)
        if (!sw.isFinite() || sw < 1) return pose to false
        val mx = (s.left.x + s.right.x) / 2
        val my = (s.left.y + s.right.y) / 2
        var nx = -dy / sw
        var ny = dx / sw
        var oriented = false
        val nose = pose[Joint.NOSE]
        if (usable(nose, minConfidence)) {
            val side = nx * (nose.x - mx) + ny * (nose.y - my)
            if (side > 0) {
                nx = -nx
                ny = -ny
                oriented = true
            } else if (side < 0) {
                oriented = true
            }
        }
        if (!oriented && (ny < 0 || (ny == 0.0 && nx < 0))) {
            nx = -nx
            ny = -ny
        }
        val d = ESTIMATED_TORSO_LENGTH * sw
        val rx = mx + d * nx
        val ry = my + d * ny
        val conf = s.confidence
        var out = pose
        out = out.with(Joint.ROOT, Keypoint(rx, ry, conf))
        out = out.with(
            Joint.LEFT_HIP,
            Keypoint(rx + ESTIMATED_HIP_WIDTH * (s.left.x - mx), ry + ESTIMATED_HIP_WIDTH * (s.left.y - my), conf),
        )
        out = out.with(
            Joint.RIGHT_HIP,
            Keypoint(rx + ESTIMATED_HIP_WIDTH * (s.right.x - mx), ry + ESTIMATED_HIP_WIDTH * (s.right.y - my), conf),
        )
        for (j in listOf(Joint.LEFT_KNEE, Joint.RIGHT_KNEE, Joint.LEFT_ANKLE, Joint.RIGHT_ANKLE)) {
            out = out.with(j, Keypoint.MISSING)
        }
        return out to true
    }

    /** Opciones de la silueta de la pose (antebrazos si hay brazos, piernas enteras). */
    fun silhouetteOptions(o: RegionOptions): RegionOptions = RegionOptions(
        minConfidence = o.minConfidence,
        torsoMargin = max(o.torsoMargin, SILHOUETTE_TORSO_MARGIN),
        limbWidth = max(o.limbWidth, SILHOUETTE_LIMB_WIDTH),
        includeUpperArms = o.includeUpperArms,
        includeForearms = o.includeUpperArms,
        includeLegs = true,
        includeLowerLegs = true,
    )

    /** Opciones de ce_mask_garment_regions: las de la silueta. */
    fun garmentRegionOptions(o: RegionOptions): RegionOptions = silhouetteOptions(o)

    /**
     * Mapa de regiones de prenda de una persona; con caderas estimadas los 2
     * pasan a 1. Null sin región de ropa desde la pose o con CE_ERR_POSE.
     */
    fun garmentRegionMap(
        decision: RegionDecision?, region: RegionMode, mask: ByteArray, width: Int, height: Int,
    ): Pair<ByteArray, GarmentRegionStats>? {
        if (region != RegionMode.CLOTHING) return null
        val d = decision ?: return null
        if (d.source != RegionSource.POSE_REGIONS && d.source != RegionSource.POSE_SILHOUETTE) return null
        val pose = d.regionPose ?: return null
        val ro = d.regionOptions ?: return null
        val options = garmentRegionOptions(ro)
        val map = try {
            ColorEngine.garmentRegions(pose, mask, width, height, options).first
        } catch (e: EngineException.Engine) {
            if (e.code == EngineException.Engine.ERR_POSE) return null
            throw e
        }
        var upper = 0
        var lower = 0
        var merged = 0
        for (i in map.indices) {
            when (map[i].toInt()) {
                1 -> upper++
                2 -> if (d.hipsEstimated) {
                    map[i] = 1
                    upper++
                    merged++
                } else {
                    lower++
                }
            }
        }
        val stats = GarmentRegionStats(
            upperPixels = upper, lowerPixels = lower, maskPixels = MaskOps.nonZero(mask),
            lowerMergedIntoUpper = d.hipsEstimated, mergedLowerPixels = merged,
            options = options, pose = pose,
        )
        return map to stats
    }

    /** Fracción de cutHead: sin cara 0,18; con cara, hasta la barbilla + cuello. */
    fun cutHeadFraction(bodyBox: RectD, faceBox: RectD?): Double {
        val f = faceBox
        if (f == null || f.isEmpty || bodyBox.height <= 0 || !f.maxY.isFinite() || !f.height.isFinite()) {
            return HEAD_CUT_FRACTION
        }
        val chin = f.maxY + HEAD_CUT_NECK_FACTOR * f.height
        val fraction = (chin - bodyBox.minY) / bodyBox.height
        if (!fraction.isFinite()) return HEAD_CUT_FRACTION
        return min(MAX_HEAD_CUT_FRACTION, max(HEAD_CUT_FRACTION, fraction))
    }
}
