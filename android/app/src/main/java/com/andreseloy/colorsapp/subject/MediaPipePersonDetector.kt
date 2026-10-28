// Detector de personas de Android (el "VisionDetector" de esta plataforma):
// produce exactamente lo que iOS entrega a la cadena — hasta 8 personas con
// máscara de instancia, pose de 15 puntos, caja de cara y muestra de piel
// en píxeles del raster <=1024 — con modelos empaquetados y sin red
// (docs/research/android-subject.md §4, el pipeline recomendado):
//   Pose Landmarker Full float16 (numPoses=8, tres confianzas 0,3, máscaras)
//   MagicTouch legacy por InteractiveSegmenter (un punto cuello->raíz
//     por pose; si el AAR/modelo no lo acepta o la máscara es absurda, se usa
//     la máscara de la pose: verificado en el emulador, informe del carril)
//   YuNet (caras a cualquier distancia) por ONNX Runtime
//   EfficientDet-Lite2 `person` como rectángulos de persona (evidencia)
//   SelfieMulticlass SOLO como respaldo de la muestra de piel (clase 3)
// Después: semillas + PersonSplitter (con rescate de caras con cuerpo sin
// pose: instancia interactiva sembrada bajo la cara, el cierre del §5.2
// para grupos como la foto 06) y PersonEvidence. La cadena de geometría y
// piel (SubjectChain) es compartida con iOS; aquí no hay lógica de color.
package com.andreseloy.colorsapp.subject

import android.content.Context
import android.graphics.Bitmap
import android.util.Log
import com.andreseloy.colorsapp.engine.EngineImage
import com.andreseloy.colorsapp.engine.Joint
import com.google.mediapipe.framework.image.BitmapImageBuilder
import com.google.mediapipe.framework.image.ByteBufferExtractor
import com.google.mediapipe.framework.image.MPImage
import com.google.mediapipe.tasks.components.containers.NormalizedKeypoint
import com.google.mediapipe.tasks.core.BaseOptions
import com.google.mediapipe.tasks.core.Delegate
import com.google.mediapipe.tasks.vision.core.RunningMode
import com.google.mediapipe.tasks.vision.imagesegmenter.ImageSegmenter
import com.google.mediapipe.tasks.vision.interactivesegmenter.InteractiveSegmenter
import com.google.mediapipe.tasks.vision.objectdetector.ObjectDetector
import com.google.mediapipe.tasks.vision.poselandmarker.PoseLandmarker
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext
import kotlin.math.max
import kotlin.math.min
import kotlin.math.roundToInt

class MediaPipePersonDetector(
    private val context: Context,
    private val splitOptions: SplitOptions = SplitOptions(),
    private val phantomOptions: PhantomOptions = PhantomOptions(),
) : DetailedPersonDetector {

    override val modelDescription: String =
        "mediapipe-tasks-vision-0.10.35 pose_landmarker_full@0.3x8 + magic_touch-legacy" +
            " + yunet-2023mar-ort + efficientdet_lite2 + selfie_multiclass(solo-piel)"

    @Volatile private var interactiveFailed = false
    @Volatile private var multiclassFailed = false
    private val yuNet by lazy { YuNetFaceDetector(context.applicationContext) }

    private fun base(asset: String): BaseOptions =
        BaseOptions.builder().setModelAssetPath(asset).setDelegate(Delegate.CPU).build()

    // Una tarea MediaPipe POR FOTO (se crea y se cierra en detectSync):
    //  1) Reutilizar una tarea para varias fotos es frágil entre versiones
    //     de tasks-visión (marcas de tiempo de paquetes: la 1.1.1 moría en
    //     la segunda foto con "Packet timestamp mismatch").
    //  2) Las tareas no son seguras para detect() concurrentes, y el
    //     escaneo analiza 3 fotos a la vez con el mismo detector.
    // Es el mismo patrón que Vision en iOS (un handler por llamada); el
    // coste de crear la tarea queda dentro de los timings vision.*.
    private fun pose(withMasks: Boolean = true): PoseLandmarker {
        val options = PoseLandmarker.PoseLandmarkerOptions.builder()
            .setBaseOptions(base(POSE_MODEL))
            .setRunningMode(RunningMode.IMAGE)
            .setNumPoses(8)
            .setMinPoseDetectionConfidence(0.3f)
            .setMinPosePresenceConfidence(0.3f)
            .setMinTrackingConfidence(0.3f)
            .setOutputSegmentationMasks(withMasks)
            .build()
        return PoseLandmarker.createFromOptions(context, options)
    }

    private fun interactiveOrNull(): InteractiveSegmenter? {
        if (interactiveFailed) return null
        return try {
            val options = InteractiveSegmenter.InteractiveSegmenterOptions.builder()
                .setBaseOptions(base(MAGIC_TOUCH_MODEL))
                .setOutputCategoryMask(true)
                .setOutputConfidenceMasks(false)
                .build()
            InteractiveSegmenter.createFromOptions(context, options)
        } catch (e: Exception) {
            // El chequeo del §7.1 del informe: si este AAR no acepta el
            // magic_touch legacy, la instancia sale de la máscara de la pose.
            Log.w(TAG, "InteractiveSegmenter no acepta $MAGIC_TOUCH_MODEL: $e")
            interactiveFailed = true
            null
        }
    }

    private fun objects(): ObjectDetector? {
        return try {
            val options = ObjectDetector.ObjectDetectorOptions.builder()
                .setBaseOptions(base(EFFICIENTDET_MODEL))
                .setRunningMode(RunningMode.IMAGE)
                .setScoreThreshold(0.3f)
                .setCategoryAllowlist(listOf("person"))
                .setMaxResults(-1)
                .build()
            ObjectDetector.createFromOptions(context, options)
        } catch (e: Exception) {
            Log.w(TAG, "EfficientDet no disponible: $e")
            null
        }
    }

    private fun multiclassOrNull(): ImageSegmenter? {
        if (multiclassFailed) return null
        return try {
            val options = ImageSegmenter.ImageSegmenterOptions.builder()
                .setBaseOptions(base(MULTICLASS_MODEL))
                .setRunningMode(RunningMode.IMAGE)
                .setOutputCategoryMask(true)
                .setOutputConfidenceMasks(false)
                .build()
            ImageSegmenter.createFromOptions(context, options)
        } catch (e: Exception) {
            Log.w(TAG, "SelfieMulticlass no disponible: $e")
            multiclassFailed = true
            null
        }
    }

    // Los grafos de MediaPipe no conviven en paralelo (SIGBUS nativo
    // comprobado en el AVD con 2 detecciones concurrentes): la detección se
    // serializa con este mutex y el resto del análisis (cadena + motor de
    // otra foto) sigue en paralelo, como el TaskGroup de 3 de iOS donde el
    // cuello era Vision. Un ce_ctx por tarea no se comparte nunca.
    private val detectMutex = kotlinx.coroutines.sync.Mutex()

    override suspend fun detectDetailed(image: EngineImage): PeopleDetectionResult =
        detectMutex.withLock { withContext(Dispatchers.Default) { detectSync(image) } }

    private fun detectSync(image: EngineImage): PeopleDetectionResult {
        val toClose = ArrayList<AutoCloseable>()
        try {
            return detectSyncBody(image, toClose)
        } finally {
            for (c in toClose) runCatching { c.close() }
        }
    }

    private fun detectSyncBody(image: EngineImage, toClose: MutableList<AutoCloseable>): PeopleDetectionResult {
        val width = image.width
        val height = image.height
        val timings = LinkedHashMap<String, Double>()
        fun <T> timed(key: String, block: () -> T): T {
            val t0 = System.nanoTime()
            val r = block()
            timings[key] = (timings[key] ?: 0.0) + (System.nanoTime() - t0) / 1_000_000.0
            return r
        }
        val bitmap: Bitmap = timed("vision.raster") { SubjectRaster.bitmapFrom(image) }
        val mpImage = BitmapImageBuilder(bitmap).build()

        // 1) Pose Landmarker Full @0,3 con máscaras por pose. En algunos
        // tamaños de raster, tasks-visión 1.1.1 muere al empaquetar la
        // máscara float ("ImageFrame must store data contiguously" en
        // getSegmentationMasks, comprobado en el AVD con 02/03/05): se
        // reintenta sin máscaras de pose y la instancia sale solo de
        // MagicTouch (la fuente preferida del informe igualmente).
        var poseMasksAvailable = true
        val poseResult = try {
            val poseTask = timed("vision.pose") { pose(withMasks = true).also { toClose.add(it) } }
            timed("vision.pose") { poseTask.detect(mpImage) }
        } catch (e: Exception) {
            Log.w(TAG, "pose con máscaras falló ($e); reintento sin máscaras")
            poseMasksAvailable = false
            timings["poseMaskUnavailable"] = 1.0
            val poseTask = timed("vision.pose") { pose(withMasks = false).also { toClose.add(it) } }
            timed("vision.pose") { poseTask.detect(mpImage) }
        }
        val poses = ArrayList<com.andreseloy.colorsapp.engine.Pose>()
        val poseMasks = ArrayList<ByteArray>()
        val segMasks = poseResult.segmentationMasks().orElse(emptyList())
        for ((i, landmarks) in poseResult.landmarks().withIndex()) {
            val blaze = landmarks.map {
                BlazeLandmark(
                    it.x().toDouble(), it.y().toDouble(),
                    it.visibility().orElse(0f).toDouble(), it.presence().orElse(1f).toDouble(),
                )
            }
            poses.add(BlazePoseMapping.toCePose(blaze, width, height))
            val m = segMasks.getOrNull(i)
            poseMasks.add(
                if (m != null) confidenceMaskBytes(m, width, height) else ByteArray(width * height),
            )
        }

        // 2) Caras YuNet y 3) cajas de persona EfficientDet.
        val faces: List<FaceLandmarkPoints> = timed("vision.face") {
            runCatching { yuNet.detect(bitmap).map { it.toFaceLandmarks() } }
                .onFailure { Log.w(TAG, "YuNet falló: $it") }
                .getOrDefault(emptyList())
        }
        val humanBoxes: List<RectD> = timed("vision.humanRectangles") {
            val det = objects()?.also { toClose.add(it) }
            if (det == null) {
                emptyList()
            } else {
                runCatching {
                    det.detect(mpImage).detections()
                        .filter {
                            it.categories().firstOrNull()?.categoryName() == "person" &&
                                (it.categories().firstOrNull()?.score() ?: 0f) >= phantomOptions.minHumanConfidence
                        }
                        .map {
                            val r = it.boundingBox()
                            RectD(
                                r.left.toDouble(), r.top.toDouble(),
                                (r.right - r.left).toDouble(), (r.bottom - r.top).toDouble(),
                            )
                        }
                }.onFailure { Log.w(TAG, "EfficientDet falló: $it") }.getOrDefault(emptyList())
            }
        }
        // 4) Multiclass (solo respaldo de piel y rescate).
        val multiclassRaw: ByteArray? = timed("vision.multiclass") {
            val seg = multiclassOrNull()?.also { toClose.add(it) }
            if (seg == null) {
                null
            } else {
                runCatching {
                    seg.segment(mpImage).categoryMask().orElse(null)
                        ?.let { categoryMaskBytes(it, width, height) }
                }.onFailure { Log.w(TAG, "Multiclass falló: $it") }.getOrNull()
            }
        }
        val semanticMap = multiclassRaw?.let { raw ->
            val mapped = ByteArray(raw.size)
            for (i in raw.indices) {
                mapped[i] = when (MaskOps.u(raw[i])) {
                    1 -> SemanticClass.HAIR.code.toByte()
                    2 -> SemanticClass.SKIN.code.toByte()
                    3 -> SemanticClass.FACE.code.toByte()
                    4 -> SemanticClass.UPPER_GARMENT.code.toByte()
                    5 -> SemanticClass.OTHER_PERSON_PART.code.toByte()
                    else -> 0
                }
            }
            MaskBuffer(width, height, mapped)
        }

        // 5) Máscaras de instancia: MagicTouch por pose, con rescate por la
        // máscara de la pose si el interactivo falla o es absurdo (IoU < 0,3).
        val instances = ArrayList<PersonDetection>()
        val floorPx = max(1, kotlin.math.ceil(RegionPlanning.MIN_PERSON_COVERAGE * width * height).toInt())
        var nextId = 1
        val interactiveSeg = timed("vision.interactiveInit") {
            interactiveOrNull()?.also { toClose.add(it) }
        }
        if (interactiveSeg == null) timings["interactiveUnavailable"] = 1.0

        fun interactiveMask(nx: Double, ny: Double): ByteArray? {
            val seg = interactiveSeg ?: return null
            return try {
                // OJO (medido en el AVD): aunque la clase se llama
                // NormalizedKeypoint, el grafo Android del segmentador
                // interactivo legacy interpreta el punto en PÍXELES del
                // raster: con valores 0..1 el segmento sale siempre en la
                // esquina (0,0), idéntico para cualquier punto. En Python
                // el mismo modelo sí va normalizado (proto2 del carril B).
                val roi = InteractiveSegmenter.RegionOfInterest.create(
                    NormalizedKeypoint.create(
                        (nx * width).toFloat().coerceIn(0f, (width - 1).toFloat()),
                        (ny * height).toFloat().coerceIn(0f, (height - 1).toFloat()),
                    ),
                )
                val result = seg.segment(BitmapImageBuilder(bitmap).build(), roi)
                val mask = result.categoryMask().orElse(null) ?: return null
                val raw = categoryMaskBytes(mask, width, height)
                // Polaridad del modelo legacy: 0 = objeto señalado, 255 = fondo.
                ByteArray(raw.size) { if (raw[it] == 0.toByte()) -1 else 0 }
            } catch (e: Exception) {
                Log.w(TAG, "MagicTouch falló en un punto: $e")
                interactiveFailed = true
                null
            }
        }

        for ((i, cePose) in poses.withIndex()) {
            val neck = cePose[Joint.NECK]
            val root = cePose[Joint.ROOT]
            var maskBytes = poseMasks[i]
            if (interactiveSeg != null && (neck.confidence > 0 || root.confidence > 0)) {
                val px = (neck.x + root.x) / 2 / width
                val py = (neck.y + root.y) / 2 / height
                val cand = timed("vision.masks") { interactiveMask(px, py) }
                val seedInside = cand != null && MaskOps.value(
                    cand, width, height, (neck.x + root.x) / 2, (neck.y + root.y) / 2,
                ) >= 128
                if (cand != null && MaskOps.nonZero(cand) >= floorPx && seedInside &&
                    (!poseMasksAvailable || MaskOps.nonZero(maskBytes) == 0 || iouBinary(cand, maskBytes) >= 0.3)
                ) {
                    maskBytes = cand
                }
            }
            if (MaskOps.stats(maskBytes, width, height).count < floorPx) continue
            instances.add(
                PersonDetection(
                    instanceMask = MaskBuffer(width, height, maskBytes),
                    pose = cePose,
                    semanticMap = semanticMap,
                    id = nextId++,
                ),
            )
        }

        // 6) Semillas y rescate: caras con cuerpo y sin pose cuya instancia no
        // existe aún crean una (punto interactivo bajo la cara o multiclass
        // dentro de su caja de persona). Es el cierre medible para grupos.
        val seeds = timed("associate") { PersonSplitter.seeds(poses, faces) }
        val poseSeedFaces = seeds.mapNotNull { if (it.kind == SeedKind.POSE) it.faceIndex else null }.toSet()
        for ((fi, face) in faces.withIndex()) {
            if (fi in poseSeedFaces) continue
            val fb = PersonSplitter.box(face) ?: continue
            val body = humanBoxes.firstOrNull { PersonSplitter.rectangleIsBody(fb, it, splitOptions) }
                ?: continue
            val insideAny = instances.any {
                MaskOps.value(it.instanceMask.bytes, width, height, face.center.x, face.center.y) >= 128
            }
            if (insideAny) continue
            var rescue: ByteArray? = null
            if (interactiveSeg != null) {
                val px = fb.midX / width
                val py = min(height - 1.0, fb.maxY + fb.height) / height
                rescue = timed("vision.masks") { interactiveMask(px, py) }
                    ?.takeIf { MaskOps.nonZero(it) >= floorPx }
            }
            if (rescue == null && multiclassRaw != null) {
                val m = ByteArray(width * height)
                val x0 = max(0, body.minX.roundToInt())
                val x1 = min(width - 1, body.maxX.roundToInt())
                val y0 = max(0, body.minY.roundToInt())
                val y1 = min(height - 1, body.maxY.roundToInt())
                for (y in y0..y1) {
                    val row = y * width
                    for (x in x0..x1) if (multiclassRaw[row + x] != 0.toByte()) m[row + x] = -1
                }
                if (MaskOps.nonZero(m) >= floorPx) rescue = m
            }
            val resc = rescue ?: continue
            instances.add(
                PersonDetection(
                    instanceMask = MaskBuffer(width, height, resc),
                    face = PersonSplitter.detectedFaceOf(face),
                    semanticMap = semanticMap,
                    id = nextId++,
                    faceLandmarks = face,
                ),
            )
        }

        // 7) Separación de fusionadas + asociación (PersonSplit de iOS).
        val outcome: SplitOutcome = timed("associate") {
            if (instances.isEmpty()) {
                SplitOutcome(
                    emptyList(), emptyList(), emptyList(), seeds,
                    List(seeds.size) { null }, emptyList(), poses.size, faces.size, emptyList(),
                )
            } else {
                PersonSplitter.apply(instances, poses, faces, seeds, width, height, humanBoxes, splitOptions)
            }
        }

        // 8) Muestra de piel de respaldo (multiclass clase 3) si FaceSample no dio.
        val withSamples = outcome.people.map { p ->
            val own = p.faceSampleMask?.bytes
            val have = SubjectChain.samplePixels(own)
            val fb = p.faceBox
            if (have >= SubjectChain.MIN_SKIN_SAMPLES || multiclassRaw == null || fb == null) {
                p
            } else {
                val backup = skinBackup(multiclassRaw, fb, p.instanceMask.bytes, width, height)
                if (SubjectChain.samplePixels(backup) > have) {
                    PersonDetection(
                        instanceMask = p.instanceMask, pose = p.pose, face = p.face,
                        semanticMap = p.semanticMap, confidence = p.confidence, id = p.id,
                        faceSampleMask = MaskBuffer(width, height, backup),
                        faceLandmarks = p.faceLandmarks, splitFrom = p.splitFrom,
                    )
                } else {
                    p
                }
            }
        }

        // 9) Evidencia corporal anti-fantasmas.
        val (kept, rejected) = timed("associate") {
            PersonEvidenceOps.rejectPhantoms(withSamples, width, height, phantomOptions, humanBoxes)
        }
        return PeopleDetectionResult(
            people = kept,
            rejectedPhantoms = rejected.map { it.instance },
            timingsMs = timings,
        )
    }

    /** Clase 3 (piel de cara) ∩ caja de cara ∩ persona erosionada 2 px. */
    private fun skinBackup(
        multiclassRaw: ByteArray, faceBox: RectD, personMask: ByteArray, width: Int, height: Int,
    ): ByteArray {
        val out = ByteArray(width * height)
        val x0 = max(0, kotlin.math.floor(faceBox.minX).toInt())
        val x1 = min(width - 1, kotlin.math.ceil(faceBox.maxX).toInt())
        val y0 = max(0, kotlin.math.floor(faceBox.minY).toInt())
        val y1 = min(height - 1, kotlin.math.ceil(faceBox.maxY).toInt())
        if (x0 > x1 || y0 > y1) return out
        for (y in y0..y1) {
            val row = y * width
            for (x in x0..x1) {
                if (MaskOps.u(multiclassRaw[row + x]) == 3 &&
                    MaskOps.insideEroded(personMask, width, height, x, y, 2)
                ) {
                    out[row + x] = -1
                }
            }
        }
        return out
    }

    private fun iouBinary(a: ByteArray, b: ByteArray): Double {
        var inter = 0
        var union = 0
        val n = min(a.size, b.size)
        for (i in 0 until n) {
            val x = MaskOps.u(a[i]) >= 128
            val y = MaskOps.u(b[i]) >= 128
            if (x && y) inter++
            if (x || y) union++
        }
        return if (union > 0) inter.toDouble() / union else 0.0
    }

    /**
     * Máscara de confianza de la pose (float 0..1) a bytes 0..255 del raster.
     * El MPImage puede venir como VEC32F1 o como ALPHA; se distingue por el
     * formato declarado y, si no, por el tamaño del buffer.
     */
    internal fun confidenceMaskBytes(mp: MPImage, width: Int, height: Int): ByteArray {
        val mw = mp.width
        val mh = mp.height
        val props = mp.containedImageProperties.firstOrNull()
        val isFloat = props?.imageFormat == MPImage.IMAGE_FORMAT_VEC32F1
        val buffer = ByteBufferExtractor.extract(mp)
        buffer.rewind()
        val src: FloatArray
        if (isFloat || buffer.remaining() >= mw * mh * 4 && props == null) {
            val fb = buffer.asFloatBuffer()
            src = FloatArray(min(mw * mh, fb.remaining()))
            fb.get(src)
        } else {
            src = FloatArray(mw * mh) { i ->
                if (i < buffer.remaining()) MaskOps.u(buffer.get(buffer.position() + i)) / 255f else 0f
            }
        }
        if (mw == width && mh == height) {
            return ByteArray(width * height) { (src[it].coerceIn(0f, 1f) * 255f).roundToInt().toByte() }
        }
        // Reescalado bilineal (la máscara interna puede ser 256x256).
        val out = ByteArray(width * height)
        for (y in 0 until height) {
            val sy = (y + 0.5) * mh / height - 0.5
            val y0 = kotlin.math.floor(sy).toInt().coerceIn(0, mh - 1)
            val y1 = min(mh - 1, y0 + 1)
            val fy = (sy - y0).coerceIn(0.0, 1.0)
            for (x in 0 until width) {
                val sx = (x + 0.5) * mw / width - 0.5
                val x0 = kotlin.math.floor(sx).toInt().coerceIn(0, mw - 1)
                val x1 = min(mw - 1, x0 + 1)
                val fx = (sx - x0).coerceIn(0.0, 1.0)
                val v = (src[y0 * mw + x0] * (1 - fx) + src[y0 * mw + x1] * fx) * (1 - fy) +
                    (src[y1 * mw + x0] * (1 - fx) + src[y1 * mw + x1] * fx) * fy
                out[y * width + x] = (v.coerceIn(0.0, 1.0) * 255).roundToInt().toByte()
            }
        }
        return out
    }

    /**
     * Máscara de categorías (uint8) reescalada con vecino más cercano al
     * raster. El buffer nativo del MPImage puede llevar relleno por fila
     * (width_step > width): se deduce el stride de remaining/height y se
     * lee fila a fila. (BitmapExtractor no sirve aquí: solo acepta
     * MPImages creados desde Bitmap.)
     */
    internal fun categoryMaskBytes(mp: MPImage, width: Int, height: Int): ByteArray {
        val mw = mp.width
        val mh = mp.height
        val buffer = ByteBufferExtractor.extract(mp)
        buffer.rewind()
        val remaining = buffer.remaining()
        val stride = if (mh > 0 && remaining % mh == 0) max(mw, remaining / mh) else mw
        val raw = ByteArray(mw * mh)
        for (y in 0 until mh) {
            val src = y * stride
            for (x in 0 until mw) {
                raw[y * mw + x] = if (src + x < remaining) buffer.get(buffer.position() + src + x) else 0
            }
        }
        if (mw == width && mh == height) return raw
        val out = ByteArray(width * height)
        for (y in 0 until height) {
            val sy = min(mh - 1, ((y + 0.5) * mh / height).toInt())
            for (x in 0 until width) {
                val sx = min(mw - 1, ((x + 0.5) * mw / width).toInt())
                out[y * width + x] = raw[sy * mw + sx]
            }
        }
        return out
    }

    fun close() {
        // Las tareas MediaPipe se crean y cierran por foto; solo queda YuNet.
        runCatching { yuNet.close() }
    }

    companion object {
        private const val TAG = "MediaPipePersonDetector"
        const val POSE_MODEL = "models/pose_landmarker_full.task"
        const val MAGIC_TOUCH_MODEL = "models/magic_touch.tflite"
        const val MULTICLASS_MODEL = "models/selfie_multiclass_256x256.tflite"
        const val EFFICIENTDET_MODEL = "models/efficientdet_lite2.tflite"
    }
}
