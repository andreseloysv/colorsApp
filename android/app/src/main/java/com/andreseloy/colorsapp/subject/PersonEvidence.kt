// Port literal de PersonEvidence.swift + la asociación de VisionDetector.swift
// (associatePoses/associateFacesDetailed): evidencia corporal anti-fantasmas
// (pose con torso dentro -> cara -> rectángulo de persona -> forma apagada) y
// asociación pose/cara a instancia por muestras del esqueleto/de la cara.
// En Android los "rectángulos de persona de Vision" son las cajas `person`
// de EfficientDet-Lite2 (mismo papel, mismos umbrales). Solo geometría.
package com.andreseloy.colorsapp.subject

import com.andreseloy.colorsapp.engine.Joint
import com.andreseloy.colorsapp.engine.Pose
import kotlin.math.abs
import kotlin.math.ceil
import kotlin.math.floor
import kotlin.math.max
import kotlin.math.min
import kotlin.math.sqrt

/** Umbrales de la evidencia corporal (PhantomOptions de SubjectKit). */
data class PhantomOptions(
    val enabled: Boolean = true,
    val minTorsoJoints: Int = 2,
    /** Confianza mínima de un punto (la de RegionOptions: 0,3). */
    val minConfidence: Double = 0.3,
    val jointRadius: Int = 2,
    val shapeMinCoverage: Double = 0.01,
    val shapeMaxCoverage: Double = 0.6,
    val shapeMinAspect: Double = 1.2,
    val shapeMaxAspect: Double = 6.0,
    val shapeMaxExtent: Double = 0.8,
    val shapeMaxSolidity: Double = 0.88,
    val shapeMaxHeightSpan: Double = 0.95,
    /** Regla de forma sola: false (una prenda colgada tiene forma de persona). */
    val acceptShapeOnly: Boolean = false,
    val humanRectangles: Boolean = true,
    val minHumanConfidence: Double = 0.3,
    val minHumanOverlap: Double = 0.5,
    val minHumanFill: Double = 0.1,
    /** La regla de cara exige además cuerpo (rectángulo suyo o torso dentro). */
    val requireBodyForFaceOnly: Boolean = false,
)

/** Evidencia corporal de una instancia y las medidas que la deciden. */
data class PersonEvidence(
    val kind: Kind,
    val torsoJointsInside: Int,
    val hasFace: Boolean,
    val coverage: Double,
    val aspect: Double,
    val extent: Double,
    val solidity: Double,
    val heightSpan: Double = 0.0,
    val humanBox: RectD? = null,
    val humanOverlap: Double = 0.0,
    val humanFill: Double = 0.0,
    val plausibleShape: Boolean = false,
) {
    enum class Kind(val raw: String) {
        POSE("pose"), FACE("face"), SHAPE("shape"), NONE("none"), HUMAN_RECTANGLE("humanRectangle"),
    }

    val isPerson: Boolean get() = kind != Kind.NONE
}

/** Instancia descartada por no tener evidencia corporal. */
data class RejectedPerson(val instance: PersonDetection, val evidence: PersonEvidence)

/** Evidencia corporal y asociación (SubjectExtractor de iOS, sin Vision). */
object PersonEvidenceOps {
    /** Puntos del torso que cuentan como evidencia de pose. */
    val EVIDENCE_TORSO_JOINTS: List<Joint> = listOf(
        Joint.NECK, Joint.LEFT_SHOULDER, Joint.RIGHT_SHOULDER,
        Joint.LEFT_HIP, Joint.RIGHT_HIP, Joint.ROOT,
    )

    fun bodyEvidence(
        person: PersonDetection, width: Int, height: Int,
        options: PhantomOptions = PhantomOptions(), humanBox: RectD? = null,
    ): PersonEvidence {
        val mask = person.instanceMask.bytes
        val stats = MaskOps.stats(mask, width, height)
        var joints = 0
        val pose = person.pose
        if (pose != null) {
            val r = max(0, options.jointRadius)
            for (j in EVIDENCE_TORSO_JOINTS) {
                val k = pose[j]
                if (!RegionPlanning.usable(k, options.minConfidence)) continue
                if (nearMask(mask, width, height, k.x, k.y, r)) joints++
            }
        }
        val hasFace = person.faceBox != null
        var aspect = 0.0
        var extent = 0.0
        var solidity = 0.0
        var span = 0.0
        if (stats.count > 0) {
            val w = stats.bbox.width
            val h = stats.bbox.height
            aspect = h / w
            span = h / height
            extent = stats.count / (w * h)
            val hull = hullArea(mask, width, height)
            solidity = if (hull > 0) min(1.0, stats.count / hull) else 1.0
        }
        val shape = stats.count > 0 &&
            stats.coverage >= options.shapeMinCoverage && stats.coverage <= options.shapeMaxCoverage &&
            aspect >= options.shapeMinAspect && aspect <= options.shapeMaxAspect &&
            extent <= options.shapeMaxExtent && solidity <= options.shapeMaxSolidity &&
            span < options.shapeMaxHeightSpan
        var overlap = 0.0
        var fill = 0.0
        if (humanBox != null && stats.count > 0) {
            val inside = pixelsInside(mask, width, height, humanBox)
            overlap = inside.toDouble() / stats.count
            val area = humanBox.width * humanBox.height
            fill = if (area > 0) inside / area else 0.0
        }
        val human = humanBox != null && options.humanRectangles &&
            overlap >= options.minHumanOverlap && fill >= options.minHumanFill
        val faceHasBody = !options.requireBodyForFaceOnly || joints >= 1 ||
            (person.faceBox?.let { f ->
                humanBox?.let { PersonSplitter.rectangleIsBody(f, it) } ?: false
            } ?: false)
        val kind = when {
            joints >= max(1, options.minTorsoJoints) -> PersonEvidence.Kind.POSE
            hasFace && faceHasBody -> PersonEvidence.Kind.FACE
            human -> PersonEvidence.Kind.HUMAN_RECTANGLE
            options.acceptShapeOnly && shape -> PersonEvidence.Kind.SHAPE
            else -> PersonEvidence.Kind.NONE
        }
        return PersonEvidence(
            kind, joints, hasFace, stats.coverage, aspect, extent, solidity,
            heightSpan = span, humanBox = humanBox, humanOverlap = overlap,
            humanFill = fill, plausibleShape = shape,
        )
    }

    /** Separa personas con evidencia de las fantasma (orden conservado). */
    fun rejectPhantoms(
        people: List<PersonDetection>, width: Int, height: Int,
        options: PhantomOptions = PhantomOptions(), humanBoxes: List<RectD> = emptyList(),
    ): Pair<List<PersonDetection>, List<RejectedPerson>> {
        if (!options.enabled) return people to emptyList()
        val boxOf = associateHumanRectangles(
            if (options.humanRectangles) humanBoxes else emptyList(),
            people.map { it.instanceMask.bytes }, width, height,
        )
        val kept = ArrayList<PersonDetection>()
        val rejected = ArrayList<RejectedPerson>()
        for ((i, p) in people.withIndex()) {
            val e = bodyEvidence(p, width, height, options, boxOf[i]?.let { humanBoxes[it] })
            if (e.isPerson) kept.add(p) else rejected.add(RejectedPerson(p, e))
        }
        return kept to rejected
    }

    /** Para cada máscara, el índice de su rectángulo de persona (o null). */
    fun associateHumanRectangles(
        boxes: List<RectD>, masks: List<ByteArray>, width: Int, height: Int,
    ): List<Int?> {
        val result = MutableList<Int?>(masks.size) { null }
        val best = IntArray(masks.size)
        for ((bi, box) in boxes.withIndex()) {
            var target = -1
            var count = 0
            for ((mi, mask) in masks.withIndex()) {
                val c = pixelsInside(mask, width, height, box)
                if (c > count) {
                    target = mi
                    count = c
                }
            }
            if (target < 0) continue
            if (result[target] == null || count > best[target]) {
                result[target] = bi
                best[target] = count
            }
        }
        return result
    }

    /** Píxeles >=128 cuyo centro cae dentro de box (bordes incluidos). */
    internal fun pixelsInside(mask: ByteArray, width: Int, height: Int, box: RectD): Int {
        if (mask.size < width * height || !box.isFinite) return 0
        val x0 = max(0, ceil(box.minX - 0.5).toInt())
        val x1 = min(width - 1, floor(box.maxX - 0.5).toInt())
        val y0 = max(0, ceil(box.minY - 0.5).toInt())
        val y1 = min(height - 1, floor(box.maxY - 0.5).toInt())
        if (x0 > x1 || y0 > y1) return 0
        var n = 0
        for (y in y0..y1) {
            val row = y * width
            for (x in x0..x1) if (MaskOps.u(mask[row + x]) >= MaskOps.INSIDE_THRESHOLD) n++
        }
        return n
    }

    /** true si algún píxel >=128 cae a Chebyshev <= radius del píxel de (x,y). */
    internal fun nearMask(mask: ByteArray, width: Int, height: Int, x: Double, y: Double, radius: Int): Boolean {
        if (!x.isFinite() || !y.isFinite() || abs(x) > 1_048_576 || abs(y) > 1_048_576) return false
        if (mask.size < width * height) return false
        val ix = floor(x).toInt()
        val iy = floor(y).toInt()
        for (yy in (iy - radius)..(iy + radius)) {
            if (yy < 0 || yy >= height) continue
            val row = yy * width
            for (xx in (ix - radius)..(ix + radius)) {
                if (xx < 0 || xx >= width) continue
                if (MaskOps.u(mask[row + xx]) >= MaskOps.INSIDE_THRESHOLD) return true
            }
        }
        return false
    }

    /** Área de la envolvente convexa de los píxeles >=128 (cuadrados de lado 1). */
    internal fun hullArea(mask: ByteArray, width: Int, height: Int): Double {
        if (mask.size < width * height) return 0.0
        val pts = ArrayList<Pt>()
        for (y in 0 until height) {
            val row = y * width
            var first = -1
            var last = -1
            for (x in 0 until width) if (MaskOps.u(mask[row + x]) >= MaskOps.INSIDE_THRESHOLD) {
                if (first < 0) first = x
                last = x
            }
            if (first >= 0) {
                pts.add(Pt(first.toDouble(), y.toDouble()))
                pts.add(Pt(last + 1.0, y.toDouble()))
                pts.add(Pt(first.toDouble(), y + 1.0))
                pts.add(Pt(last + 1.0, y + 1.0))
            }
        }
        val hull = MaskOps.convexHull(pts)
        if (hull.size < 3) return 0.0
        var area = 0.0
        for (i in hull.indices) {
            val a = hull[i]
            val b = hull[(i + 1) % hull.size]
            area += a.x * b.y - b.x * a.y
        }
        return abs(area) / 2
    }

    // --- Asociación pose/cara a instancia (VisionDetector.swift) ---

    private val TORSO_JOINTS: List<Joint> = EVIDENCE_TORSO_JOINTS
    private val TORSO_SEGMENTS: List<Pair<Joint, Joint>> = listOf(
        Joint.LEFT_SHOULDER to Joint.RIGHT_SHOULDER,
        Joint.LEFT_SHOULDER to Joint.LEFT_HIP,
        Joint.RIGHT_SHOULDER to Joint.RIGHT_HIP,
        Joint.LEFT_HIP to Joint.RIGHT_HIP,
        Joint.NECK to Joint.ROOT,
    )
    private val LIMB_SEGMENTS: List<Pair<Joint, Joint>> = listOf(
        Joint.NOSE to Joint.NECK,
        Joint.LEFT_SHOULDER to Joint.LEFT_ELBOW,
        Joint.LEFT_ELBOW to Joint.LEFT_WRIST,
        Joint.RIGHT_SHOULDER to Joint.RIGHT_ELBOW,
        Joint.RIGHT_ELBOW to Joint.RIGHT_WRIST,
        Joint.LEFT_HIP to Joint.LEFT_KNEE,
        Joint.LEFT_KNEE to Joint.LEFT_ANKLE,
        Joint.RIGHT_HIP to Joint.RIGHT_KNEE,
        Joint.RIGHT_KNEE to Joint.RIGHT_ANKLE,
    )
    private const val SEGMENT_SAMPLES = 8

    internal data class Sample(val x: Double, val y: Double, val torso: Boolean)

    /** Muestras del esqueleto: 8 por segmento utilizable + puntos sueltos. */
    internal fun skeletonSamples(pose: Pose, minConfidence: Double): List<Sample> {
        val out = ArrayList<Sample>()
        val inTorsoSegment = HashSet<Int>()
        val inAnySegment = HashSet<Int>()
        val n = SEGMENT_SAMPLES
        for ((list, torso) in listOf(TORSO_SEGMENTS to true, LIMB_SEGMENTS to false)) {
            for ((a, b) in list) {
                val pa = pose[a]
                val pb = pose[b]
                if (!RegionPlanning.usable(pa, minConfidence)) continue
                if (!RegionPlanning.usable(pb, minConfidence)) continue
                for (j in listOf(a, b)) {
                    inAnySegment.add(j.ordinal)
                    if (torso) inTorsoSegment.add(j.ordinal)
                }
                for (k in 0 until n) {
                    val t = (k + 0.5) / n
                    out.add(Sample(pa.x + t * (pb.x - pa.x), pa.y + t * (pb.y - pa.y), torso))
                }
            }
        }
        for (joint in Joint.entries) {
            val k = pose[joint]
            if (!RegionPlanning.usable(k, minConfidence)) continue
            if (joint in TORSO_JOINTS) {
                if (joint.ordinal !in inTorsoSegment) out.add(Sample(k.x, k.y, true))
            } else if (joint.ordinal !in inAnySegment) {
                out.add(Sample(k.x, k.y, false))
            }
        }
        return out
    }

    /**
     * Para cada máscara, el índice de la pose asociada (o null): la pose va a
     * la instancia con más muestras dentro (torso doble, >=1 de torso); si
     * varias poses eligen la misma, gana más torso, más score, torso mayor.
     */
    fun associatePoses(
        poses: List<Pose>, masks: List<ByteArray>, width: Int, height: Int,
        minConfidence: Double = 0.3,
    ): List<Int?> {
        data class Claim(val torso: Int, val score: Int, val extent: Double, val pose: Int)

        val claims = List(masks.size) { ArrayList<Claim>() }
        for ((pi, pose) in poses.withIndex()) {
            val samples = skeletonSamples(pose, minConfidence)
            if (samples.isEmpty()) continue
            var bestMask = -1
            var bestTorso = 0
            var bestScore = 0
            for ((mi, mask) in masks.withIndex()) {
                var torso = 0
                var limb = 0
                for (p in samples) {
                    if (MaskOps.value(mask, width, height, p.x, p.y) >= MaskOps.INSIDE_THRESHOLD) {
                        if (p.torso) torso++ else limb++
                    }
                }
                if (torso < 1) continue
                val score = 2 * torso + limb
                // Swift: si (b.score, b.torso) >= (score, torso) se conserva la anterior.
                if (bestMask >= 0 && (bestScore > score || (bestScore == score && bestTorso >= torso))) continue
                bestMask = mi
                bestTorso = torso
                bestScore = score
            }
            if (bestMask >= 0) {
                claims[bestMask].add(Claim(bestTorso, bestScore, torsoExtent(pose, minConfidence), pi))
            }
        }
        return claims.map { list ->
            list.minWithOrNull(Comparator { a, b ->
                when {
                    a.torso != b.torso -> b.torso - a.torso
                    a.score != b.score -> b.score - a.score
                    a.extent != b.extent -> if (a.extent > b.extent) -1 else 1
                    else -> a.pose - b.pose
                }
            })?.pose
        }
    }

    /** Diagonal del rectángulo de los puntos del torso presentes (0 si < 2). */
    internal fun torsoExtent(pose: Pose, minConfidence: Double = 0.0): Double {
        val pts = TORSO_JOINTS.map { pose[it] }.filter { it.confidence > 0 && it.confidence >= minConfidence }
        if (pts.size < 2) return 0.0
        val minX = pts.minOf { it.x }
        val maxX = pts.maxOf { it.x }
        val minY = pts.minOf { it.y }
        val maxY = pts.maxOf { it.y }
        val dx = maxX - minX
        val dy = maxY - minY
        return sqrt(dx * dx + dy * dy)
    }

    private const val FACE_GRID = 7
    private const val FACE_GRID_SPAN = 0.6

    /** Muestras de una cara: rejilla 7x7 sobre el 60% central de su caja. */
    internal fun faceSamplePoints(face: FaceLandmarkPoints, below: Boolean = false): List<Pt> {
        val box = face.boundingBox
        if (box == null || box.isEmpty) return if (below) emptyList() else listOf(face.center)
        val n = FACE_GRID
        val dy = if (below) box.height else 0.0
        val out = ArrayList<Pt>()
        for (j in 0 until n) {
            for (i in 0 until n) {
                val u = (1 - FACE_GRID_SPAN) / 2 + FACE_GRID_SPAN * (i + 0.5) / n
                val v = (1 - FACE_GRID_SPAN) / 2 + FACE_GRID_SPAN * (j + 0.5) / n
                out.add(Pt(box.minX + u * box.width, box.minY + v * box.height + dy))
            }
        }
        return out
    }

    /** Asociación de una cara a una máscara: índice y si fue directa. */
    data class FaceLink(val face: Int, val direct: Boolean)

    /**
     * Para cada máscara, su cara (directa si la rejilla cae dentro; si no, la
     * rejilla un alto de cara más abajo: solo aporta la caja, sin muestra).
     */
    fun associateFacesDetailed(
        faces: List<FaceLandmarkPoints>, masks: List<ByteArray>, width: Int, height: Int,
    ): List<FaceLink?> {
        data class Key(val direct: Int, val score: Int, val landmarks: Int, val area: Double, val face: Int) :
            Comparable<Key> {
            override fun compareTo(other: Key): Int =
                compareValuesBy(this, other, { it.direct }, { it.score }, { it.landmarks }, { it.area }, { -it.face })
        }

        fun bestMask(pts: List<Pt>): Pair<Int, Int>? {
            var best = -1
            var bestScore = 0
            for ((mi, mask) in masks.withIndex()) {
                var c = 0
                for (p in pts) {
                    if (MaskOps.value(mask, width, height, p.x, p.y) >= MaskOps.INSIDE_THRESHOLD) c++
                }
                if (c > bestScore) {
                    best = mi
                    bestScore = c
                }
            }
            if (best < 0 || 4 * bestScore < pts.size) return null
            return best to bestScore
        }
        val result = MutableList<FaceLink?>(masks.size) { null }
        val bestKey = arrayOfNulls<Key>(masks.size)
        for ((fi, face) in faces.withIndex()) {
            var direct = true
            var hit = bestMask(faceSamplePoints(face))
            if (hit == null) {
                val below = faceSamplePoints(face, below = true)
                if (below.isNotEmpty()) {
                    hit = bestMask(below)
                    direct = false
                }
            }
            if (hit == null) continue
            val box = face.boundingBox
            val area = if (box == null) 0.0 else box.width * box.height
            val key = Key(
                direct = if (direct) 1 else 0, score = hit.second,
                landmarks = if (FaceSample.polygons(face) == null) 0 else 1,
                area = area, face = fi,
            )
            val k = bestKey[hit.first]
            if (k != null && k >= key) continue
            bestKey[hit.first] = key
            result[hit.first] = FaceLink(fi, direct)
        }
        return result
    }
}
