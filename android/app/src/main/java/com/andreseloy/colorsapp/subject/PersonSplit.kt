// Port literal de apple/SubjectKit/Sources/SubjectKit/PersonSplit.swift:
// separación de instancias que juntan a varias personas (en Android: una
// máscara interactiva o de pose que contiene a la vecina), con semillas de
// pose y de cara, evidencia corporal obligatoria para las de cara sin pose,
// y la geometría de reparto en el motor C (ce_mask_split_instance).
// Constantes y desempates idénticos a los del Swift (ver su cabecera).
package com.andreseloy.colorsapp.subject

import com.andreseloy.colorsapp.engine.ColorEngine
import com.andreseloy.colorsapp.engine.Joint
import com.andreseloy.colorsapp.engine.PersonSeed
import com.andreseloy.colorsapp.engine.Pose
import com.andreseloy.colorsapp.engine.SPLIT_MAX_SEEDS
import kotlin.math.abs
import kotlin.math.ceil
import kotlin.math.floor
import kotlin.math.max
import kotlin.math.min
import kotlin.math.sqrt

/** Origen de una semilla. */
enum class SeedKind(val raw: String) { POSE("pose"), FACE("face") }

/** Qué acredita que detrás de una semilla hay un cuerpo. */
enum class SeedBodyEvidence(val raw: String) {
    POSE("pose"), HUMAN_RECTANGLE("humanRectangle"), POSE_JOINTS("poseJoints"), NONE("none"),
}

/** Umbrales de la separación (SplitOptions de SubjectKit). */
data class SplitOptions(
    val enabled: Boolean = true,
    val minSplitCoverage: Double = 0.005,
    val maxPeople: Int = 8,
    val requireBodyForFaceSeeds: Boolean = true,
    val faceSeedBodyBelow: Double = 1.0,
    val faceSeedBodyTopAbove: Double = 1.0,
    val faceSeedBodyTopBelow: Double = 0.5,
    val faceSeedMinPoseJoints: Int = 2,
)

/** Semilla de persona con su origen (pose y/o cara). */
data class SubjectSeed(
    val seed: PersonSeed,
    val kind: SeedKind,
    val pose: Pose? = null,
    val face: FaceLandmarkPoints? = null,
    val faceWidth: Double,
    val poseIndex: Int? = null,
    val faceIndex: Int? = null,
    var bodyEvidence: SeedBodyEvidence = SeedBodyEvidence.POSE,
) {
    /** Punto superior del eje (cuello o base de la cara). */
    val top: Pt get() = Pt(seed.x0, seed.y0)
}

/** Una instancia que se separó (trazabilidad, como InstanceSplit). */
data class InstanceSplit(
    val instanceId: Int,
    val seeds: List<SubjectSeed>,
    val segments: List<PersonSeed>,
    val segmentOwner: List<Int>,
    val labels: ByteArray,
    val labelPixels: List<Int>,
    val personIdBySeed: List<Int?>,
    val personIds: List<Int>,
    val step: MaskStep,
)

/** Resultado de aplicar la separación a las instancias (SplitOutcome). */
data class SplitOutcome(
    val people: List<PersonDetection>,
    val faces: List<FaceLandmarkPoints?>,
    val splits: List<InstanceSplit>,
    val seeds: List<SubjectSeed>,
    val seedInstance: List<Int?>,
    val absorbedInstances: List<Int>,
    val unassignedPoses: Int,
    val unassignedFaces: Int,
    val faceSeedsWithoutBody: List<SubjectSeed>,
)

object PersonSplitter {
    const val POSE_HALF_WIDTH_FACTOR = 0.55
    const val POSE_MIN_HALF_WIDTH_FACE_FACTOR = 0.6
    const val HIP_EXTRAPOLATION_FACTOR = 1.6
    const val FACE_AXIS_FACTOR = 3.0
    const val FACE_HALF_WIDTH_FACTOR = 1.1
    const val FACE_MATCH_FACTOR = 0.8
    const val DILATION_FACE_FACTOR = 0.25

    /** Ancho de cara estimado por anchura de hombros cuando la pose no tiene cara. */
    const val FACE_WIDTH_PER_SHOULDER_WIDTH = 0.45

    /** Confianza por defecto de las regiones (la de RegionOptions). */
    const val DEFAULT_MIN_CONFIDENCE = 0.3

    /** La semilla cabe en el contrato del motor (coordenadas y half_width). */
    fun engineAccepts(s: PersonSeed): Boolean {
        val limit = 1_048_576.0
        return listOf(s.x0, s.y0, s.x1, s.y1).all { it.isFinite() && abs(it) <= limit } &&
            s.halfWidth > 0 && s.halfWidth <= limit
    }

    private fun usablePt(pose: Pose, joint: Joint, minConfidence: Double): Pt? {
        val k = pose[joint]
        return if (RegionPlanning.usable(k, minConfidence)) Pt(k.x, k.y) else null
    }

    private fun distance(a: Pt, b: Pt): Double {
        val dx = a.x - b.x
        val dy = a.y - b.y
        return sqrt(dx * dx + dy * dy)
    }

    /** Rectángulo utilizable de una cara (null si es vacío o no finito). */
    internal fun box(face: FaceLandmarkPoints): RectD? {
        val b = face.boundingBox ?: return null
        if (b.isEmpty || !b.isFinite || b.width <= 0 || b.height <= 0) return null
        return b
    }

    private data class PoseAxis(val top: Pt, val shoulderWidth: Double?, val bottom: Pt?)

    /** Geometría de la pose: punto superior, anchura de hombros e inferior. */
    private fun poseAxis(pose: Pose, minConfidence: Double): PoseAxis? {
        val neck = usablePt(pose, Joint.NECK, minConfidence)
        val ls = usablePt(pose, Joint.LEFT_SHOULDER, minConfidence)
        val rs = usablePt(pose, Joint.RIGHT_SHOULDER, minConfidence)
        val top: Pt = when {
            neck != null -> neck
            ls != null && rs != null -> Pt((ls.x + rs.x) / 2, (ls.y + rs.y) / 2)
            else -> return null
        }
        var sw: Double? = null
        if (ls != null && rs != null) {
            sw = distance(ls, rs)
        } else if (neck != null && (ls ?: rs) != null) {
            sw = 2 * distance(ls ?: rs!!, neck)
        }
        if (sw != null && sw < 1) sw = null
        var bottom: Pt? = usablePt(pose, Joint.ROOT, minConfidence)
        if (bottom == null) {
            val lh = usablePt(pose, Joint.LEFT_HIP, minConfidence)
            val rh = usablePt(pose, Joint.RIGHT_HIP, minConfidence)
            if (lh != null && rh != null) bottom = Pt((lh.x + rh.x) / 2, (lh.y + rh.y) / 2)
        }
        return PoseAxis(top, sw, bottom)
    }

    /** Semillas de poses y caras (poses primero, luego caras sin pose). */
    fun seeds(
        poses: List<Pose>, faces: List<FaceLandmarkPoints>,
        minConfidence: Double = DEFAULT_MIN_CONFIDENCE,
    ): List<SubjectSeed> {
        val axes = poses.map { poseAxis(it, minConfidence) }
        data class PairCand(val d: Double, val pose: Int, val face: Int)

        val pairs = ArrayList<PairCand>()
        for ((fi, face) in faces.withIndex()) {
            val fb = box(face) ?: continue
            val fw = fb.width
            for ((pi, axis) in axes.withIndex()) {
                if (axis == null) continue
                var d = Double.POSITIVE_INFINITY
                usablePt(poses[pi], Joint.NECK, minConfidence)?.let { d = min(d, distance(face.center, it)) }
                usablePt(poses[pi], Joint.NOSE, minConfidence)?.let { d = min(d, distance(face.center, it)) }
                if (d < FACE_MATCH_FACTOR * fw) pairs.add(PairCand(d, pi, fi))
            }
        }
        pairs.sortWith(compareBy({ it.d }, { it.pose }, { it.face }))
        val faceOfPose = arrayOfNulls<Int>(poses.size)
        val poseOfFace = arrayOfNulls<Int>(faces.size)
        for (p in pairs) {
            if (faceOfPose[p.pose] == null && poseOfFace[p.face] == null) {
                faceOfPose[p.pose] = p.face
                poseOfFace[p.face] = p.pose
            }
        }
        val out = ArrayList<SubjectSeed>()
        val usedFace = BooleanArray(faces.size)
        for ((pi, axis) in axes.withIndex()) {
            if (axis == null) continue
            val face = faceOfPose[pi]?.let { faces[it] }
            val fbox = face?.let { box(it) }
            val fw = fbox?.width
            val fh = fbox?.height
            val bottom: Pt
            val hw: Double
            val faceWidth: Double
            val sw = axis.shoulderWidth
            if (sw != null) {
                bottom = axis.bottom ?: Pt(axis.top.x, axis.top.y + HIP_EXTRAPOLATION_FACTOR * sw)
                var h = POSE_HALF_WIDTH_FACTOR * sw
                if (fw != null) h = max(h, POSE_MIN_HALF_WIDTH_FACE_FACTOR * fw)
                hw = h
                faceWidth = fw ?: (FACE_WIDTH_PER_SHOULDER_WIDTH * sw)
            } else if (fw != null && fh != null) {
                bottom = axis.bottom ?: Pt(axis.top.x, axis.top.y + FACE_AXIS_FACTOR * fh)
                hw = FACE_HALF_WIDTH_FACTOR * fw
                faceWidth = fw
            } else {
                continue
            }
            val seed = PersonSeed(axis.top.x, axis.top.y, bottom.x, bottom.y, hw)
            if (!engineAccepts(seed)) continue
            faceOfPose[pi]?.let { usedFace[it] = true }
            out.add(
                SubjectSeed(
                    seed, SeedKind.POSE, poses[pi], face, faceWidth,
                    poseIndex = pi, faceIndex = faceOfPose[pi], bodyEvidence = SeedBodyEvidence.POSE,
                ),
            )
        }
        for ((fi, face) in faces.withIndex()) {
            if (usedFace[fi]) continue
            val b = box(face) ?: continue
            if (!b.midX.isFinite() || !b.maxY.isFinite()) continue
            val seed = PersonSeed(
                b.midX, b.maxY, b.midX, b.maxY + FACE_AXIS_FACTOR * b.height,
                FACE_HALF_WIDTH_FACTOR * b.width,
            )
            if (!engineAccepts(seed)) continue
            out.add(
                SubjectSeed(
                    seed, SeedKind.FACE, face = face, faceWidth = b.width,
                    faceIndex = fi, bodyEvidence = SeedBodyEvidence.NONE,
                ),
            )
        }
        return out
    }

    // --- Evidencia corporal de las semillas de cara (ADR-010) ---

    /** Evidencia corporal de una semilla de cara (las de pose devuelven POSE). */
    fun bodyEvidence(
        seed: SubjectSeed, humanBoxes: List<RectD>, otherPoses: List<Pose>,
        options: SplitOptions = SplitOptions(), minConfidence: Double = DEFAULT_MIN_CONFIDENCE,
    ): SeedBodyEvidence {
        if (seed.kind == SeedKind.POSE) return SeedBodyEvidence.POSE
        val face = seed.face ?: return SeedBodyEvidence.NONE
        val b = box(face) ?: return SeedBodyEvidence.NONE
        if (humanBoxes.any { rectangleIsBody(b, it, options) }) return SeedBodyEvidence.HUMAN_RECTANGLE
        for (pose in otherPoses) {
            var joints = 0
            for (joint in Joint.entries) {
                val p = usablePt(pose, joint, minConfidence) ?: continue
                if (p.y < b.maxY) continue
                if (distanceToAxis(seed.seed, p.x, p.y) <= seed.seed.halfWidth) joints++
            }
            if (joints >= max(1, options.faceSeedMinPoseJoints)) return SeedBodyEvidence.POSE_JOINTS
        }
        return SeedBodyEvidence.NONE
    }

    /** true si rect es EL CUERPO de la cara face (la contiene, empieza a su altura y baja). */
    fun rectangleIsBody(face: RectD, rect: RectD, options: SplitOptions = SplitOptions()): Boolean {
        if (face.isEmpty || !rect.isFinite) return false
        val h = face.height
        if (h <= 0) return false
        return rect.contains(Pt(face.midX, face.midY)) &&
            rect.maxY >= face.maxY + options.faceSeedBodyBelow * h &&
            rect.minY >= face.minY - options.faceSeedBodyTopAbove * h &&
            rect.minY <= face.minY + options.faceSeedBodyTopBelow * h
    }

    /** Distancia del punto al eje de la semilla (proyección acotada). */
    internal fun distanceToAxis(s: PersonSeed, x: Double, y: Double): Double {
        val dx = s.x1 - s.x0
        val dy = s.y1 - s.y0
        val dd = dx * dx + dy * dy
        val qx = x - s.x0
        val qy = y - s.y0
        var t = 0.0
        if (dd > 0) t = ((qx * dx + qy * dy) / dd).coerceIn(0.0, 1.0)
        val ex = qx - t * dx
        val ey = qy - t * dy
        return sqrt(ex * ex + ey * ey)
    }

    /** Marca la evidencia de cada semilla y separa las de cara sin cuerpo. */
    fun screenFaceSeeds(
        seeds: List<SubjectSeed>, humanBoxes: List<RectD>, poses: List<Pose>,
        options: SplitOptions = SplitOptions(), minConfidence: Double = DEFAULT_MIN_CONFIDENCE,
    ): Pair<List<SubjectSeed>, List<SubjectSeed>> {
        val kept = ArrayList<SubjectSeed>()
        val rejected = ArrayList<SubjectSeed>()
        val seedPoses = seeds.mapNotNull { if (it.kind == SeedKind.POSE) it.poseIndex else null }.toSet()
        val others = poses.indices.filter { it !in seedPoses }.map { poses[it] }
        for (s in seeds) {
            s.bodyEvidence = bodyEvidence(s, humanBoxes, others, options, minConfidence)
            if (options.requireBodyForFaceSeeds && s.kind == SeedKind.FACE &&
                s.bodyEvidence == SeedBodyEvidence.NONE
            ) {
                rejected.add(s)
            } else {
                kept.add(s)
            }
        }
        return kept to rejected
    }

    /** Semiancho del segmento de cabeza en anchos de cara. */
    const val HEAD_HALF_WIDTH_FACTOR = 0.5

    /** Segmento de cabeza: del centro de la cara al punto superior del eje. */
    fun headSegment(s: SubjectSeed): PersonSeed? {
        val f = s.face ?: return null
        val b = box(f) ?: return null
        val head = PersonSeed(b.midX, b.midY, s.seed.x0, s.seed.y0, HEAD_HALF_WIDTH_FACTOR * b.width)
        return if (engineAccepts(head)) head else null
    }

    // --- Semillas de cada instancia ---

    const val AXIS_SAMPLES = 17
    const val MIN_AXIS_INSIDE = 0.5

    /** Relación de una semilla con una instancia. */
    data class Membership(
        val faceInside: Boolean,
        val topInside: Boolean,
        val topDistance: Double,
        val axisInside: Double,
    ) {
        val touches: Boolean get() = faceInside || topDistance.isFinite()
        val counts: Boolean get() = touches && axisInside >= MIN_AXIS_INSIDE
    }

    fun membership(s: SubjectSeed, mask: ByteArray, width: Int, height: Int): Membership {
        if (width < 1 || height < 1 || mask.size < width * height) {
            return Membership(false, false, Double.POSITIVE_INFINITY, 0.0)
        }
        fun inside(x: Double, y: Double): Boolean =
            MaskOps.value(mask, width, height, x, y) >= MaskOps.INSIDE_THRESHOLD
        var faceIn = false
        s.face?.let { faceIn = inside(it.center.x, it.center.y) }
        val tx = s.seed.x0
        val ty = s.seed.y0
        val topIn = inside(tx, ty)
        var dist = if (topIn) 0.0 else Double.POSITIVE_INFINITY
        val r = max(0.0, DILATION_FACE_FACTOR * s.faceWidth)
        if (!topIn && tx.isFinite() && ty.isFinite() && r.isFinite() &&
            abs(tx) < 1e7 && abs(ty) < 1e7 && r < 1e7
        ) {
            val x0 = max(0, floor(tx - r - 1).toInt())
            val x1 = min(width - 1, ceil(tx + r + 1).toInt())
            val y0 = max(0, floor(ty - r - 1).toInt())
            val y1 = min(height - 1, ceil(ty + r + 1).toInt())
            if (x0 <= x1 && y0 <= y1) {
                for (y in y0..y1) {
                    for (x in x0..x1) {
                        if (MaskOps.u(mask[y * width + x]) < MaskOps.INSIDE_THRESHOLD) continue
                        val dx = x + 0.5 - tx
                        val dy = y + 0.5 - ty
                        val d = sqrt(dx * dx + dy * dy)
                        if (d <= r && d < dist) dist = d
                    }
                }
            }
        }
        var total = 0
        var hits = 0
        for (i in 0 until AXIS_SAMPLES) {
            val t = i.toDouble() / (AXIS_SAMPLES - 1)
            val x = s.seed.x0 + t * (s.seed.x1 - s.seed.x0)
            val y = s.seed.y0 + t * (s.seed.y1 - s.seed.y0)
            if (!x.isFinite() || !y.isFinite() || x < 0 || y < 0 || x >= width || y >= height) continue
            total++
            if (inside(x, y)) hits++
        }
        return Membership(faceIn, topIn, dist, if (total > 0) hits.toDouble() / total else 0.0)
    }

    /** counted[s][i]: la semilla s frente a la instancia i. */
    fun countedSeeds(
        seeds: List<SubjectSeed>, masks: List<ByteArray>, width: Int, height: Int,
    ): List<List<Membership>> = seeds.map { s -> masks.map { membership(s, it, width, height) } }

    /** Instancia principal de cada semilla (más eje dentro; desempates del Swift). */
    private fun primaryInstance(ms: List<Membership>): Int? {
        var best: Int? = null
        for ((i, m) in ms.withIndex()) {
            if (!m.counts) continue
            val b = best
            if (b != null) {
                val bm = ms[b]
                // Clave tupla (axisInside, faceInside, topInside, -topDistance), mayor gana.
                val cmp = compareValuesBy(
                    m, bm, { it.axisInside }, { if (it.faceInside) 1 else 0 },
                    { if (it.topInside) 1 else 0 }, { -it.topDistance },
                )
                if (cmp <= 0) continue
            }
            best = i
        }
        return best
    }

    // --- Separación ---

    /**
     * Separa las instancias con >=2 semillas (ce_mask_split_instance, con
     * segmentos de cabeza), reasigna las partes < minSplitCoverage a la
     * vecina conservada mayor, une partes de una misma semilla entre
     * instancias pisadas, absorbe instancias ya contenidas y asocia pose y
     * cara al resto como en iOS. Personas ordenadas por cobertura, máx. 8.
     */
    fun apply(
        instances: List<PersonDetection>,
        poses: List<Pose>,
        faces: List<FaceLandmarkPoints>,
        allSeeds: List<SubjectSeed>,
        width: Int,
        height: Int,
        humanBoxes: List<RectD> = emptyList(),
        options: SplitOptions = SplitOptions(),
    ): SplitOutcome {
        val count = width * height
        val screened = screenFaceSeeds(allSeeds, humanBoxes, poses, options)
        val seeds = if (options.enabled) screened.first else emptyList()
        val masks = instances.map { it.instanceMask.bytes }
        val member = countedSeeds(seeds, masks, width, height)
        val seedInstance = member.map { primaryInstance(it) }
        val minPixels = ceil(max(0.0, options.minSplitCoverage) * count).toInt()
        val maxSeeds = min(SPLIT_MAX_SEEDS, max(1, options.maxPeople))

        data class Part(val instance: Int, val seed: Int, val mask: ByteArray, val pixels: Int)
        data class PendingSplit(
            val instance: Int, val seedsIdx: List<Int>, val segments: List<PersonSeed>,
            val owner: List<Int>, val labels: ByteArray, val pixels: List<Int>, val kept: List<Int>,
        )

        val parts = ArrayList<Part>()
        val pending = ArrayList<PendingSplit>()
        for ((ii, inst) in instances.withIndex()) {
            var mine = seeds.indices.filter { member[it][ii].counts }
            if (mine.size < 2) continue
            if (mine.size > maxSeeds) {
                mine = mine.sortedWith(
                    compareByDescending<Int> { seeds[it].seed.halfWidth }.thenBy { it },
                ).take(maxSeeds)
            }
            mine = mine.sortedWith(compareBy({ seeds[it].seed.x0 }, { seeds[it].seed.y0 }, { it }))
            val n = mine.size
            val segments = ArrayList<PersonSeed>()
            val owner = ArrayList<Int>()
            for ((j, si) in mine.withIndex()) {
                segments.add(seeds[si].seed)
                owner.add(j)
            }
            val withFace = (0 until n).filter { headSegment(seeds[mine[it]]) != null }
                .sortedWith(Comparator { a, b ->
                    val ka = faceWidthKey(seeds[mine[a]], a)
                    val kb = faceWidthKey(seeds[mine[b]], b)
                    compareValuesBy(kb, ka, { it.first }, { it.second })
                })
            for (j in withFace.take(SPLIT_MAX_SEEDS - n).sorted()) {
                segments.add(headSegment(seeds[mine[j]])!!)
                owner.add(j)
            }
            val rawLabels = ColorEngine.splitInstance(inst.instanceMask.bytes, width, height, segments).first
            val ownerOfLabel = IntArray(segments.size + 1)
            for ((k, o) in owner.withIndex()) ownerOfLabel[k + 1] = o + 1
            val lab = ByteArray(count)
            val pixels = IntArray(n + 1)
            for (i in 0 until count) {
                val o = ownerOfLabel[MaskOps.u(rawLabels[i]).coerceIn(0, segments.size)]
                lab[i] = o.toByte()
                pixels[o]++
            }
            val keptLabels = (1..n).filter { pixels[it] >= minPixels }
            if (keptLabels.size < 2) continue
            val target = IntArray(n + 1) { it }
            val small = (1..n).filter { pixels[it] > 0 && pixels[it] < minPixels }
            if (small.isNotEmpty()) {
                val touches = Array(n + 1) { BooleanArray(n + 1) }
                for (y in 0 until height) {
                    for (x in 0 until width) {
                        val a = MaskOps.u(lab[y * width + x])
                        if (a == 0) continue
                        if (x + 1 < width) {
                            val b = MaskOps.u(lab[y * width + x + 1])
                            if (b != 0 && b != a) {
                                touches[a][b] = true
                                touches[b][a] = true
                            }
                        }
                        if (y + 1 < height) {
                            val b = MaskOps.u(lab[(y + 1) * width + x])
                            if (b != 0 && b != a) {
                                touches[a][b] = true
                                touches[b][a] = true
                            }
                        }
                    }
                }
                val largest = keptLabels.maxWithOrNull(
                    compareBy<Int> { pixels[it] }.thenBy { -it },
                )!!
                for (sm in small) {
                    val neighbors = keptLabels.filter { touches[sm][it] }
                    target[sm] = neighbors.maxWithOrNull(
                        compareBy<Int> { pixels[it] }.thenBy { -it },
                    ) ?: largest
                }
            }
            for (k in keptLabels) {
                val m = ByteArray(count)
                var np = 0
                val src = inst.instanceMask.bytes
                for (i in 0 until count) {
                    val l = MaskOps.u(lab[i])
                    if (l != 0 && target[l] == k) {
                        m[i] = src[i]
                        np++
                    }
                }
                parts.add(Part(ii, mine[k - 1], m, np))
            }
            val finalTarget = IntArray(n)
            for (j in 1..n) if (pixels[j] > 0) finalTarget[j - 1] = target[j]
            pending.add(
                PendingSplit(
                    ii, mine, segments, owner, rawLabels,
                    pixels.drop(1), finalTarget.toList(),
                ),
            )
        }
        val splitInstanceIndices = pending.map { it.instance }.toSet()

        // Una persona por semilla: une sus partes y absorbe instancias sin separar.
        val seedOrder = ArrayList<Int>()
        for (p in parts) if (p.seed !in seedOrder) seedOrder.add(p.seed)
        val mergedMask = HashMap<Int, ByteArray>()
        val mergedFrom = HashMap<Int, Pair<Int, Int>>()
        for (p in parts) {
            val m = mergedMask[p.seed]
            if (m != null) {
                for (i in 0 until count) if (MaskOps.u(p.mask[i]) > MaskOps.u(m[i])) m[i] = p.mask[i]
            } else {
                mergedMask[p.seed] = p.mask
            }
            val f = mergedFrom[p.seed]
            if (f == null || f.second < p.pixels) mergedFrom[p.seed] = p.instance to p.pixels
        }
        val absorbed = HashSet<Int>()
        for ((ii, inst) in instances.withIndex()) {
            if (ii in splitInstanceIndices) continue
            val mine = seeds.indices.filter { member[it][ii].counts }
            if (mine.isEmpty() || !mine.all { mergedMask.containsKey(it) }) continue
            val host = mine.maxWithOrNull(compareBy<Int> { member[it][ii].axisInside }.thenBy { -it })!!
            val m = mergedMask[host]!!
            val src = inst.instanceMask.bytes
            for (i in 0 until count) {
                val v = MaskOps.u(src[i])
                if (v >= MaskOps.INSIDE_THRESHOLD && v > MaskOps.u(m[i])) m[i] = src[i]
            }
            absorbed.add(ii)
        }
        var nextId = (instances.maxOfOrNull { it.id } ?: 0) + 1
        val idBySeed = HashMap<Int, Int>()
        val usedPoses = HashSet<Int>()
        val usedFaces = HashSet<Int>()
        val all = ArrayList<Pair<PersonDetection, FaceLandmarkPoints?>>()
        for (si in seedOrder) {
            val s = seeds[si]
            val m = mergedMask[si]!!
            val id = nextId++
            idBySeed[si] = id
            val sample = s.face?.let { FaceSample.mask(it, width, height, m) }
            all.add(
                PersonDetection(
                    instanceMask = MaskBuffer(width, height, m),
                    pose = s.pose,
                    face = detectedFaceOf(s.face),
                    id = id,
                    faceSampleMask = sample?.let { MaskBuffer(width, height, it) },
                    faceLandmarks = s.face,
                    splitFrom = instances[mergedFrom[si]!!.first].id,
                ) to s.face,
            )
            s.poseIndex?.let { usedPoses.add(it) }
            s.faceIndex?.let { usedFaces.add(it) }
        }
        val splits = pending.map { ps ->
            val ids = ps.seedsIdx.indices.map { j ->
                if (ps.kept[j] == 0) null else idBySeed[ps.seedsIdx[ps.kept[j] - 1]]
            }
            val personIds = ArrayList<Int>()
            for (id in ids.filterNotNull()) if (id !in personIds) personIds.add(id)
            val anyFace = ps.seedsIdx.indices.any { j ->
                ps.kept[j] == j + 1 && seeds[ps.seedsIdx[j]].kind == SeedKind.FACE
            }
            InstanceSplit(
                instanceId = instances[ps.instance].id,
                seeds = ps.seedsIdx.map { seeds[it] },
                segments = ps.segments, segmentOwner = ps.owner, labels = ps.labels,
                labelPixels = ps.pixels, personIdBySeed = ids, personIds = personIds,
                step = if (anyFace) MaskStep.SPLIT_BY_FACE else MaskStep.SPLIT_BY_POSE,
            )
        }

        // Instancias sin separar: asociación de siempre con poses y caras libres.
        val rest = instances.indices.filter { it !in splitInstanceIndices && it !in absorbed }
        val freePoses = poses.indices.filter { it !in usedPoses }
        val freeFaces = faces.indices.filter { it !in usedFaces }
        val restMasks = rest.map { instances[it].instanceMask.bytes }
        val poseOf = PersonEvidenceOps.associatePoses(
            freePoses.map { poses[it] }, restMasks, width, height,
        )
        val faceLinks = PersonEvidenceOps.associateFacesDetailed(
            freeFaces.map { faces[it] }, restMasks, width, height,
        )
        for ((k, ii) in rest.withIndex()) {
            val inst = instances[ii]
            val pose = poseOf[k]?.let { poses[freePoses[it]] }
            var face: FaceLandmarkPoints? = null
            var sample: ByteArray? = null
            val link = faceLinks[k]
            if (link != null) {
                val fi = freeFaces[link.face]
                face = faces[fi]
                // Solo la cara DIRECTA da muestra de piel.
                if (link.direct) {
                    sample = FaceSample.mask(faces[fi], width, height, inst.instanceMask.bytes)
                }
                usedFaces.add(fi)
            }
            poseOf[k]?.let { usedPoses.add(freePoses[it]) }
            // La instancia conserva su pose/cara de detector si la asociación no
            // encontró otra (en Android la instancia ya nace de una pose).
            val finalPose = pose ?: inst.pose
            val finalFace = face ?: inst.faceLandmarks
            all.add(
                PersonDetection(
                    instanceMask = inst.instanceMask,
                    pose = finalPose,
                    face = detectedFaceOf(finalFace) ?: inst.face,
                    semanticMap = inst.semanticMap,
                    confidence = inst.confidence,
                    id = inst.id,
                    faceSampleMask = sample?.let { MaskBuffer(width, height, it) } ?: inst.faceSampleMask,
                    faceLandmarks = finalFace,
                    splitFrom = inst.splitFrom,
                ) to finalFace,
            )
        }
        val ordered = sortPeople(all.map { it.first }, width, height)
        val faceById = HashMap<Int, FaceLandmarkPoints>()
        for (e in all) e.second?.let { faceById[e.first.id] = it }
        val people = ordered.take(max(1, options.maxPeople))
        return SplitOutcome(
            people = people,
            faces = people.map { faceById[it.id] },
            splits = splits,
            seeds = seeds,
            seedInstance = seedInstance,
            absorbedInstances = absorbed.sorted().map { instances[it].id },
            unassignedPoses = poses.size - usedPoses.size,
            unassignedFaces = faces.size - usedFaces.size,
            faceSeedsWithoutBody = if (options.enabled) screened.second else emptyList(),
        )
    }

    /** Orden estable: cobertura descendente, desempate por id ascendente. */
    fun sortPeople(people: List<PersonDetection>, width: Int, height: Int): List<PersonDetection> {
        val withCov = people.mapIndexed { idx, p ->
            Triple(p, MaskOps.coverage(p.instanceMask.bytes, width, height), idx)
        }
        return withCov.sortedWith(
            compareByDescending<Triple<PersonDetection, Double, Int>> { it.second }
                .thenBy { it.first.id }
                .thenBy { it.third },
        ).map { it.first }
    }

    /** DetectedFace (caja + confianza) desde los landmarks. */
    fun detectedFaceOf(face: FaceLandmarkPoints?): DetectedFace? {
        val b = face?.let { box(it) } ?: return null
        return DetectedFace(
            b.minX.toFloat(), b.minY.toFloat(), b.maxX.toFloat(), b.maxY.toFloat(),
        )
    }

    /** Clave de orden de las cabezas: ancho de cara y, a igualdad, índice menor. */
    private fun faceWidthKey(s: SubjectSeed, index: Int): Pair<Double, Int> =
        (s.face?.let { box(it)?.width } ?: 0.0) to -index
}
