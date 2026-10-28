// Tests JVM de la geometría portada de SubjectKit (sin motor ni modelos):
// los mismos casos sintéticos que ChainTests/SplitTests/PhantomEvidenceTests
// de Swift, reducidos a lo que no necesita el C. La cadena con motor y el
// detector se prueban en el emulador (SubjectPeopleDeviceTest).
package com.andreseloy.colorsapp.subject

import com.andreseloy.colorsapp.engine.Joint
import com.andreseloy.colorsapp.engine.Keypoint
import com.andreseloy.colorsapp.engine.Pose
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import kotlin.math.abs

private fun mask(w: Int, h: Int, fill: (Int, Int) -> Boolean): ByteArray =
    ByteArray(w * h) { i -> if (fill(i % w, i / w)) -1 else 0 }

private fun poseOf(vararg joints: Pair<Joint, Triple<Double, Double, Double>>): Pose {
    var p = Pose()
    for ((j, t) in joints) p = p.with(j, Keypoint(t.first, t.second, t.third))
    return p
}

class MaskOpsTest {
    @Test
    fun statsCoverageAndBbox() {
        val m = mask(10, 8) { x, y -> x in 2..4 && y in 1..2 }
        val s = MaskOps.stats(m, 10, 8)
        assertEquals(6, s.count)
        assertEquals(6.0 / 80, s.coverage, 1e-12)
        assertEquals(RectD(2.0, 1.0, 3.0, 2.0), s.bbox)
    }

    @Test
    fun binarizeUsesThreshold128() {
        val m = byteArrayOf(0, 127, -128, -1) // 0,127,128,255
        val b = MaskOps.binarize(m)
        assertEquals(listOf(0, 0, 255, 255), b.map { MaskOps.u(it) })
    }

    @Test
    fun dilateChebyshev() {
        val m = mask(9, 9) { x, y -> x == 4 && y == 4 }
        val d = MaskOps.dilate(m, 9, 9, 2)
        assertEquals(25, MaskOps.nonZero(d))
    }

    @Test
    fun geodesicGrowStaysConnected() {
        // Semilla en (0,0); camino permitido solo por la primera fila.
        val seeds = mask(6, 3) { x, y -> x == 0 && y == 0 }
        val allowed = mask(6, 3) { _, y -> y == 0 }
        val grown = MaskOps.geodesicGrow(seeds, allowed, 6, 3, 3)
        assertEquals(3, MaskOps.nonZero(grown))
        assertEquals(255, MaskOps.u(grown[3]))
        assertEquals(0, MaskOps.u(grown[4]))
    }

    @Test
    fun convexHullAndPointInPolygon() {
        val hull = MaskOps.convexHull(listOf(Pt(0.0, 0.0), Pt(4.0, 0.0), Pt(4.0, 3.0), Pt(0.0, 3.0), Pt(2.0, 1.0)))
        assertEquals(4, hull.size)
        assertTrue(MaskOps.pointInConvexPolygon(Pt(2.0, 1.5), hull))
        assertFalse(MaskOps.pointInConvexPolygon(Pt(5.0, 1.5), hull))
    }

    @Test
    fun fillConvexWithErodedClip() {
        val clip = mask(10, 10) { _, _ -> true }
        val poly = listOf(listOf(Pt(2.0, 2.0), Pt(7.0, 2.0), Pt(7.0, 7.0), Pt(2.0, 7.0)))
        val filled = MaskOps.fillConvexPolygons(poly, 10, 10, clip, clipErosion = 2)
        // Con erosión 2, el borde a <2px del límite del clip queda fuera.
        assertTrue(MaskOps.u(filled[4 * 10 + 4]) == 255)
        assertEquals(0, MaskOps.u(filled[2 * 10 + 2]) and 0)
    }
}

class RegionPlanningTest {
    @Test
    fun estimatedHipsFromShoulders() {
        val pose = poseOf(
            Joint.NOSE to Triple(100.0, 40.0, 0.9),
            Joint.NECK to Triple(100.0, 60.0, 0.9),
            Joint.LEFT_SHOULDER to Triple(80.0, 60.0, 0.9),
            Joint.RIGHT_SHOULDER to Triple(120.0, 60.0, 0.8),
            Joint.LEFT_KNEE to Triple(80.0, 200.0, 0.9),
        )
        val (out, estimated) = RegionPlanning.regionPose(pose, 0.3)
        assertTrue(estimated)
        // sw=40; raíz a 1,2*40=48 px bajo el punto medio (lejos de la nariz).
        assertEquals(100.0, out[Joint.ROOT].x, 1e-9)
        assertEquals(108.0, out[Joint.ROOT].y, 1e-9)
        assertEquals(85.0, out[Joint.LEFT_HIP].x, 1e-9)
        assertEquals(115.0, out[Joint.RIGHT_HIP].x, 1e-9)
        assertEquals(0.8, out[Joint.ROOT].confidence, 1e-9)
        assertEquals(0.0, out[Joint.LEFT_KNEE].confidence, 0.0)
    }

    @Test
    fun noEstimationWhenHipsFormable() {
        val pose = poseOf(
            Joint.LEFT_SHOULDER to Triple(80.0, 60.0, 0.9),
            Joint.RIGHT_SHOULDER to Triple(120.0, 60.0, 0.9),
            Joint.LEFT_HIP to Triple(85.0, 120.0, 0.9),
            Joint.RIGHT_HIP to Triple(115.0, 120.0, 0.9),
        )
        val (out, estimated) = RegionPlanning.regionPose(pose, 0.3)
        assertFalse(estimated)
        assertEquals(pose, out)
    }

    @Test
    fun cutHeadFractionFromFace() {
        val body = RectD(0.0, 100.0, 50.0, 200.0)
        val face = RectD(10.0, 110.0, 30.0, 40.0)
        // (150 + 0,25*40 - 100)/200 = 0,3
        assertEquals(0.3, RegionPlanning.cutHeadFraction(body, face), 1e-9)
        assertEquals(0.18, RegionPlanning.cutHeadFraction(body, null), 0.0)
    }
}

class FaceSampleTest {
    @Test
    fun polygonsFromYuNetPoints() {
        // Cara frontal: ojos en (40,40) y (60,40); boca (50,62) por comisuras.
        val lm = YuNetFace(
            x = 20.0, y = 10.0, width = 60.0, height = 70.0,
            points = listOf(
                Pt(40.0, 40.0), Pt(60.0, 40.0), Pt(50.0, 50.0), Pt(42.0, 62.0), Pt(58.0, 62.0),
            ),
            score = 0.9,
        ).toFaceLandmarks()
        val polys = FaceSample.polygons(lm)
        assertNotNull(polys)
        assertEquals(3, polys!!.size)
        val person = mask(100, 100) { _, _ -> true }
        val sample = FaceSample.mask(lm, 100, 100, person)!!
        assertTrue(SubjectChain.samplePixels(sample) >= 50)
    }

    @Test
    fun degenerateFrameReturnsNull() {
        val lm = FaceLandmarkPoints(
            leftEye = listOf(Pt(10.0, 10.0)), rightEye = listOf(Pt(10.0, 10.0)),
            outerLips = listOf(Pt(10.0, 10.0)),
        )
        assertNull(FaceSample.polygons(lm))
    }
}

class PersonSplitGeometryTest {
    private fun faceLm(box: RectD) = FaceLandmarkPoints(
        leftEye = listOf(Pt(box.minX + box.width * 0.35, box.minY + box.height * 0.4)),
        rightEye = listOf(Pt(box.minX + box.width * 0.65, box.minY + box.height * 0.4)),
        outerLips = listOf(Pt(box.midX, box.minY + box.height * 0.8)),
        boundingBox = box,
    )

    @Test
    fun rectangleIsBodyRules() {
        val face = RectD(40.0, 10.0, 20.0, 20.0)
        assertTrue(PersonSplitter.rectangleIsBody(face, RectD(20.0, 8.0, 60.0, 90.0)))
        // Empieza demasiado arriba (es el cuerpo de otra persona).
        assertFalse(PersonSplitter.rectangleIsBody(face, RectD(20.0, -40.0, 60.0, 140.0)))
        // No baja un alto de cara por debajo.
        assertFalse(PersonSplitter.rectangleIsBody(face, RectD(20.0, 10.0, 60.0, 30.0)))
    }

    @Test
    fun faceSeedWithoutBodyIsScreened() {
        val face = faceLm(RectD(40.0, 10.0, 20.0, 20.0))
        val seeds = PersonSplitter.seeds(emptyList(), listOf(face))
        assertEquals(1, seeds.size)
        val (kept, rejected) = PersonSplitter.screenFaceSeeds(seeds, emptyList(), emptyList())
        assertTrue(kept.isEmpty())
        assertEquals(1, rejected.size)
        val (kept2, _) = PersonSplitter.screenFaceSeeds(
            seeds, listOf(RectD(20.0, 8.0, 60.0, 90.0)), emptyList(),
        )
        assertEquals(1, kept2.size)
        assertEquals(SeedBodyEvidence.HUMAN_RECTANGLE, kept2[0].bodyEvidence)
    }

    @Test
    fun poseSeedAxisAndHalfWidth() {
        val pose = poseOf(
            Joint.NECK to Triple(50.0, 20.0, 0.9),
            Joint.LEFT_SHOULDER to Triple(40.0, 20.0, 0.9),
            Joint.RIGHT_SHOULDER to Triple(60.0, 20.0, 0.9),
            Joint.ROOT to Triple(50.0, 60.0, 0.9),
        )
        val seeds = PersonSplitter.seeds(listOf(pose), emptyList())
        assertEquals(1, seeds.size)
        assertEquals(0.55 * 20, seeds[0].seed.halfWidth, 1e-9)
        assertEquals(60.0, seeds[0].seed.y1, 1e-9)
    }

    @Test
    fun membershipCountsAxis() {
        val m = mask(100, 100) { x, _ -> x in 40..60 }
        val seed = SubjectSeed(
            com.andreseloy.colorsapp.engine.PersonSeed(50.0, 10.0, 50.0, 90.0, 11.0),
            SeedKind.POSE, faceWidth = 20.0,
        )
        val mem = PersonSplitter.membership(seed, m, 100, 100)
        assertTrue(mem.counts)
        assertEquals(1.0, mem.axisInside, 1e-9)
    }
}

class PersonEvidenceTest {
    private fun person(maskBytes: ByteArray, w: Int, h: Int, pose: Pose? = null, faceBox: RectD? = null) =
        PersonDetection(
            instanceMask = MaskBuffer(w, h, maskBytes),
            pose = pose,
            face = faceBox?.let {
                DetectedFace(it.minX.toFloat(), it.minY.toFloat(), it.maxX.toFloat(), it.maxY.toFloat())
            },
            id = 1,
        )

    @Test
    fun poseWithTorsoInsideIsEvidence() {
        val w = 100
        val h = 100
        val m = mask(w, h) { x, y -> x in 30..70 && y in 10..90 }
        val pose = poseOf(
            Joint.NECK to Triple(50.0, 20.0, 0.9),
            Joint.LEFT_SHOULDER to Triple(40.0, 20.0, 0.9),
            Joint.RIGHT_SHOULDER to Triple(60.0, 20.0, 0.9),
            Joint.ROOT to Triple(50.0, 50.0, 0.9),
        )
        val e = PersonEvidenceOps.bodyEvidence(person(m, w, h, pose), w, h)
        assertEquals(PersonEvidence.Kind.POSE, e.kind)
        assertTrue(e.torsoJointsInside >= 2)
    }

    @Test
    fun garmentShapeAloneIsPhantom() {
        val w = 100
        val h = 100
        // Silueta plausible (un vestido colgado) sin pose, cara ni rectángulo.
        val m = mask(w, h) { x, y -> x in 35..65 && y in 10..80 }
        val e = PersonEvidenceOps.bodyEvidence(person(m, w, h), w, h)
        assertEquals(PersonEvidence.Kind.NONE, e.kind)
        val (kept, rejected) = PersonEvidenceOps.rejectPhantoms(listOf(person(m, w, h)), w, h)
        assertTrue(kept.isEmpty())
        assertEquals(1, rejected.size)
    }

    @Test
    fun humanRectangleIsEvidence() {
        val w = 100
        val h = 100
        val m = mask(w, h) { x, y -> x in 35..65 && y in 10..80 }
        val box = RectD(30.0, 5.0, 40.0, 85.0)
        val e = PersonEvidenceOps.bodyEvidence(person(m, w, h), w, h, PhantomOptions(), box)
        assertEquals(PersonEvidence.Kind.HUMAN_RECTANGLE, e.kind)
    }
}

class BlazePoseMappingTest {
    @Test
    fun mapsIndicesAndMidpoints() {
        val lm = List(33) { BlazeLandmark(it / 100.0, it / 50.0, 0.9) }
        val pose = BlazePoseMapping.toCePose(lm, 200, 100)
        assertEquals(0.11 * 200, pose[Joint.LEFT_SHOULDER].x, 1e-9)
        assertEquals(0.11 * 2 * 100 / 2 + 0.12 * 2 * 100 / 2, pose[Joint.NECK].y, 1e-6)
        assertTrue(abs(pose[Joint.ROOT].x - (0.23 + 0.24) / 2 * 200) < 1e-9)
        assertEquals(0.28 * 200, pose[Joint.RIGHT_ANKLE].x, 1e-9)
    }
}

class YuNetDecodeTest {
    @Test
    fun decodesOneFaceAndNms() {
        // Una celda stride 8 en (fila 35, col 40) con score alto, como la
        // medida real de la foto 01 en el prototipo de validación.
        fun out(name: String, stride: Int): FloatArray {
            val grid = 640 / stride
            val n = grid * grid
            return when {
                name.startsWith("cls") || name.startsWith("obj") -> FloatArray(n)
                name.startsWith("bbox") -> FloatArray(n * 4)
                else -> FloatArray(n * 10)
            }
        }
        val outputs = HashMap<String, FloatArray>()
        for (s in YuNetDecode.STRIDES) {
            for (kind in listOf("cls", "obj", "bbox", "kps")) outputs["${kind}_$s"] = out(kind, s)
        }
        val idx = 35 * 80 + 40
        outputs["cls_8"]!![idx] = 4f
        outputs["obj_8"]!![idx] = 4f
        outputs["bbox_8"]!!.also {
            it[idx * 4] = 0.273f; it[idx * 4 + 1] = 0.424f
            it[idx * 4 + 2] = 1.123f; it[idx * 4 + 3] = 1.573f
        }
        outputs["kps_8"]!!.also {
            it[idx * 10] = 0.78f; it[idx * 10 + 1] = -0.36f
        }
        val scale = 640.0 / 1024
        val faces = YuNetDecode.decode(outputs, scale)
        assertEquals(1, faces.size)
        val f = faces[0]
        // Centro en 640: (322,2, 283,4); al raster 1024x682 -> caja vecina a la real.
        assertTrue(abs(f.x + f.width / 2 - 322.2 / scale) < 1.0)
        assertTrue(f.score > 0.9)
        assertEquals(5, f.points.size)
    }
}
