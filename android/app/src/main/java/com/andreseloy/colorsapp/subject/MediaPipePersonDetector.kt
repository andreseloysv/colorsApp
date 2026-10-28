// Detector de personas de Android (el "VisionDetector" de esta plataforma):
// produce exactamente lo que iOS entrega a la cadena — hasta 8 personas con
// máscara de instancia, pose de 15 puntos, caja de cara y muestra de piel
// en píxeles del raster <=1024 — con modelos empaquetados y sin red
// (docs/research/android-subject.md §4, el pipeline recomendado):
//   Pose Landmarker Full float16 (numPoses=8, tres confianzas 0,3, máscaras)
//   MagicTouch legacy por InteractiveSegmenter (un punto cuello->raíz
//     por pose; si el AAR/modelo no lo acepta o la máscara es absurda, se usa
//     la máscara de la pose: verificado en el emulador, informe del carril)
//   YuNet (caras a cualquier distancia) por TFLite (W6; antes ORT)
//   EfficientDet-Lite2 `person` como rectángulos de persona (evidencia)
//   SelfieMulticlass SOLO como respaldo de la muestra de piel (clase 3)
// EfficientDet y SelfieMulticlass corren PEREZOSOS (W6): solo cuando una
// decisión posterior los puede necesitar (semilla de cara sin cuerpo,
// rescate, respaldo de piel, fantasma sin evidencia); las tareas
// MediaPipe se reutilizan calientes entre fotos bajo el mutex.
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
    /**
     * Delegado GPU: DESACTIVADO por defecto (medido por W6 en el Galaxy
     * A14, Mali + tasks 0.10.35): InteractiveSegmenter y EfficientDet con
     * GPU mueren con abort NATIVO (SIGABRT en la conversión de resultado
     * y en tensors_to_detections), sin excepción Java que capturar, así
     * que no hay respaldo posible en tiempo de ejecución. El mecanismo
     * (GPU primero, lista negra por modelo, CPU XNNPACK detrás) queda
     * detrás de este flag para revisarlo en otro hardware/versión.
     */
    private val preferGpu: Boolean = false,
    /**
     * Lado máximo del bitmap que ven las tareas MediaPipe (W6); 0 = el
     * raster entero (≤1024). Medido en el A14 con 640: SIN ganancia
     * clara de tiempo y rompiendo puertas (foto 07: 7→6 personas y otro
     * top-3; 08: orden del top-3; ΔIoU hasta −0,216). Desactivado; el
     * mecanismo queda por si una futura medición lo justifica.
     */
    private val detectMaxSide: Int = 0,
) : DetailedPersonDetector {

    override val modelDescription: String =
        "mediapipe-tasks-vision-0.10.35 pose_landmarker_full@0.3x8 + magic_touch-legacy" +
            " + yunet-2023mar-tflite + efficientdet_lite2 + selfie_multiclass(solo-piel)"

    @Volatile private var interactiveFailed = false
    @Volatile private var multiclassFailed = false
    private val yuNet by lazy { YuNetFaceDetector(context.applicationContext) }

    /** Modelos cuya tarea GPU falló al crear o al ejecutar: van en CPU. */
    private val gpuBlacklist = HashSet<String>()

    private fun base(asset: String, delegate: Delegate): BaseOptions =
        BaseOptions.builder().setModelAssetPath(asset).setDelegate(delegate).build()

    /**
     * Crea una tarea con el delegado preferido; si era GPU y la creación
     * muere, el modelo queda en la lista negra y se recrea en CPU.
     */
    private fun <T> createWithFallback(asset: String, allowGpu: Boolean = true, make: (Delegate) -> T): T {
        val first = if (preferGpu && allowGpu && asset !in gpuBlacklist) Delegate.GPU else Delegate.CPU
        return try {
            make(first)
        } catch (e: Exception) {
            if (first == Delegate.GPU) {
                Log.w(TAG, "GPU no acepta $asset ($e); ese modelo va en CPU")
                gpuBlacklist.add(asset)
                make(Delegate.CPU)
            } else {
                throw e
            }
        }
    }

    // Tareas MediaPipe CALIENTES, reutilizadas entre fotos (carril W6):
    // crear la tarea (cargar el modelo y compilar el grafo) costaba en el
    // Galaxy A14 una parte grande de cada vision.* (los timings del
    // informe W2 ya lo incluían). La reutilización es segura aquí porque
    // detectSync corre siempre bajo detectMutex (una detección a la vez,
    // nunca concurrente) y la versión fijada (0.10.35) acepta detect()
    // repetidos en modo IMAGE (la fragilidad de "Packet timestamp
    // mismatch" era de la 1.1.1, descartada por W2). Red de seguridad: si
    // una tarea reutilizada muere, se invalida su caché, se anota
    // warmReuseFailed en los tiempos y se recrea una fresca en el acto;
    // el comportamiento cae al de antes (una tarea por foto) sin perder
    // la foto. La primera foto paga la inicialización (calentamiento).
    /** Tamaños (ancho<<32|alto) donde la máscara float de pose muere. */
    private val poseMasksBadSizes = HashSet<Long>()
    private var poseTaskCache: PoseLandmarker? = null
    private var poseNoMasksTaskCache: PoseLandmarker? = null
    private var interactiveTaskCache: InteractiveSegmenter? = null
    private var objectsTaskCache: ObjectDetector? = null
    private var multiclassTaskCache: ImageSegmenter? = null

    private fun createPose(withMasks: Boolean = true): PoseLandmarker =
        createWithFallback(POSE_MODEL) { delegate ->
            val options = PoseLandmarker.PoseLandmarkerOptions.builder()
                .setBaseOptions(base(POSE_MODEL, delegate))
                .setRunningMode(RunningMode.IMAGE)
                .setNumPoses(8)
                .setMinPoseDetectionConfidence(0.3f)
                .setMinPosePresenceConfidence(0.3f)
                .setMinTrackingConfidence(0.3f)
                .setOutputSegmentationMasks(withMasks)
                .build()
            PoseLandmarker.createFromOptions(context, options)
        }

    /** Pose caliente (con o sin máscaras): se crea una vez y se reusa. */
    private fun poseTask(withMasks: Boolean): PoseLandmarker {
        if (withMasks) {
            poseTaskCache?.let { return it }
            return createPose(true).also { poseTaskCache = it }
        }
        poseNoMasksTaskCache?.let { return it }
        return createPose(false).also { poseNoMasksTaskCache = it }
    }

    /** Invalida la caché de pose (la tarea ha muerto y se recreará). */
    private fun dropPoseCache(withMasks: Boolean) {
        if (withMasks) {
            runCatching { poseTaskCache?.close() }
            poseTaskCache = null
        } else {
            runCatching { poseNoMasksTaskCache?.close() }
            poseNoMasksTaskCache = null
        }
    }

    private fun createInteractive(): InteractiveSegmenter? {
        if (interactiveFailed) return null
        return try {
            // MagicTouch SIEMPRE en CPU: con el delegado GPU el proceso
            // muere con abort nativo al convertir el resultado en el
            // Galaxy A14 (Mali, tasks 0.10.35; medido por W6, sin
            // excepción Java que capturar). Sin fallback posible.
            createWithFallback(MAGIC_TOUCH_MODEL, allowGpu = false) { delegate ->
                val options = InteractiveSegmenter.InteractiveSegmenterOptions.builder()
                    .setBaseOptions(base(MAGIC_TOUCH_MODEL, delegate))
                    .setOutputCategoryMask(true)
                    .setOutputConfidenceMasks(false)
                    .build()
                InteractiveSegmenter.createFromOptions(context, options)
            }
        } catch (e: Exception) {
            // El chequeo del §7.1 del informe: si este AAR no acepta el
            // magic_touch legacy, la instancia sale de la máscara de la pose.
            Log.w(TAG, "InteractiveSegmenter no acepta $MAGIC_TOUCH_MODEL: $e")
            interactiveFailed = true
            null
        }
    }

    /** InteractiveSegmenter caliente; null si el AAR no acepta el modelo. */
    private fun interactiveOrNull(): InteractiveSegmenter? {
        interactiveTaskCache?.let { return it }
        return createInteractive()?.also { interactiveTaskCache = it }
    }

    /** Invalida el interactivo caliente (falló en un punto; se recreará). */
    private fun dropInteractiveCache() {
        runCatching { interactiveTaskCache?.close() }
        interactiveTaskCache = null
    }

    private fun createObjects(): ObjectDetector? {
        return try {
            createWithFallback(EFFICIENTDET_MODEL) { delegate ->
                val options = ObjectDetector.ObjectDetectorOptions.builder()
                    .setBaseOptions(base(EFFICIENTDET_MODEL, delegate))
                    .setRunningMode(RunningMode.IMAGE)
                    .setScoreThreshold(0.3f)
                    .setCategoryAllowlist(listOf("person"))
                    .setMaxResults(-1)
                    .build()
                ObjectDetector.createFromOptions(context, options)
            }
        } catch (e: Exception) {
            Log.w(TAG, "EfficientDet no disponible: $e")
            null
        }
    }

    /** EfficientDet caliente; se invalida si su detect() falla. */
    private fun objectsTask(): ObjectDetector? {
        objectsTaskCache?.let { return it }
        return createObjects()?.also { objectsTaskCache = it }
    }

    private fun dropObjectsCache() {
        runCatching { objectsTaskCache?.close() }
        objectsTaskCache = null
    }

    private fun createMulticlass(): ImageSegmenter? {
        if (multiclassFailed) return null
        return try {
            createWithFallback(MULTICLASS_MODEL) { delegate ->
                val options = ImageSegmenter.ImageSegmenterOptions.builder()
                    .setBaseOptions(base(MULTICLASS_MODEL, delegate))
                    .setRunningMode(RunningMode.IMAGE)
                    .setOutputCategoryMask(true)
                    .setOutputConfidenceMasks(false)
                    .build()
                ImageSegmenter.createFromOptions(context, options)
            }
        } catch (e: Exception) {
            Log.w(TAG, "SelfieMulticlass no disponible: $e")
            multiclassFailed = true
            null
        }
    }

    /** SelfieMulticlass caliente; se invalida si su segment() falla. */
    private fun multiclassTask(): ImageSegmenter? {
        multiclassTaskCache?.let { return it }
        return createMulticlass()?.also { multiclassTaskCache = it }
    }

    private fun dropMulticlassCache() {
        runCatching { multiclassTaskCache?.close() }
        multiclassTaskCache = null
    }

    // Los grafos de MediaPipe no conviven en paralelo (SIGBUS nativo
    // comprobado en el AVD con 2 detecciones concurrentes): la detección se
    // serializa con este mutex y el resto del análisis (cadena + motor de
    // otra foto) sigue en paralelo, como el TaskGroup de 3 de iOS donde el
    // cuello era Vision. Un ce_ctx por tarea no se comparte nunca.
    private val detectMutex = kotlinx.coroutines.sync.Mutex()

    override suspend fun detectDetailed(image: EngineImage): PeopleDetectionResult =
        detectMutex.withLock { withContext(Dispatchers.Default) { detectSync(image) } }

    private fun detectSync(image: EngineImage): PeopleDetectionResult = detectSyncBody(image)

    private fun detectSyncBody(image: EngineImage): PeopleDetectionResult {
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
        // Bitmap de detección (≤ detectMaxSide): lo único que cambia para
        // la cadena es la resolución a la que corren los modelos; poses
        // (normalizadas) y máscaras (reescaladas abajo) vuelven al raster.
        val (dw, dh) = if (detectMaxSide > 0) {
            SubjectRaster.targetSize(width, height, detectMaxSide)
        } else {
            width to height
        }
        val detectBitmap: Bitmap = if (dw == width && dh == height) {
            bitmap
        } else {
            timed("vision.raster") { SubjectRaster.scaleTo(bitmap, dw, dh) }
        }
        val mpImage = BitmapImageBuilder(detectBitmap).build()

        // 1) Pose Landmarker Full @0,3 con máscaras por pose. En algunos
        // tamaños de raster, tasks-visión 1.1.1 muere al empaquetar la
        // máscara float ("ImageFrame must store data contiguously" en
        // getSegmentationMasks, comprobado en el AVD con 02/03/05): se
        // reintenta sin máscaras de pose y la instancia sale solo de
        // MagicTouch (la fuente preferida del informe igualmente).
        // El fallo al empaquetar la máscara float es determinista por
        // tamaño de raster (comprobado: una tarea recién creada muere
        // igual en 02/03/05), NO es la reutilización; pero la excepción
        // deja la tarea caliente tocada (las fotos siguientes fallaban
        // también): se descarta y se recrea, y el tamaño queda
        // memorizado para ir directo a la variante sin máscaras en las
        // siguientes fotos del mismo tamaño.
        fun detectPoseNoMasks() = try {
            timed("vision.pose") { poseTask(withMasks = false).detect(mpImage) }
        } catch (e: Exception) {
            // Aquí sí pudo morir la tarea reutilizada: una fresca y listo.
            Log.w(TAG, "pose sin máscaras falló ($e); reintento con tarea fresca")
            gpuBlacklist.add(POSE_MODEL)
            dropPoseCache(withMasks = false)
            timings["warmReuseFailed"] = 1.0
            timed("vision.pose") { poseTask(withMasks = false).detect(mpImage) }
        }
        val sizeKey = (dw.toLong() shl 32) or dh.toLong()
        var poseMasksAvailable = sizeKey !in poseMasksBadSizes
        val poseResult = if (poseMasksAvailable) {
            try {
                timed("vision.pose") { poseTask(withMasks = true).detect(mpImage) }
            } catch (e: Exception) {
                // Dos causas conviven tras la misma excepción (visto en
                // logcat): el empaquetado de la máscara float en algunos
                // tamaños y el "Packet timestamp mismatch" transitorio al
                // reutilizar la tarea. Se reintenta UNA vez con tarea
                // fresca: si va, era transitorio; si muere también, el
                // tamaño queda memorizado y se sigue sin máscaras.
                Log.w(TAG, "pose con máscaras falló ($e); reintento con tarea fresca")
                dropPoseCache(withMasks = true)
                try {
                    timed("vision.pose") { poseTask(withMasks = true).detect(mpImage) }
                } catch (e2: Exception) {
                    Log.w(TAG, "pose con máscaras falló también en fresco ($e2); sin máscaras")
                    dropPoseCache(withMasks = true)
                    poseMasksBadSizes.add(sizeKey)
                    poseMasksAvailable = false
                    timings["poseMaskUnavailable"] = 1.0
                    detectPoseNoMasks()
                }
            }
        } else {
            timings["poseMaskUnavailable"] = 1.0
            detectPoseNoMasks()
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

        // 2) Caras YuNet. EfficientDet y SelfieMulticlass quedan como
        // funciones perezosas (carril W6): solo corren cuando la cadena
        // los necesita de verdad, que es el papel que el informe les daba
        // (EfficientDet: evidencia/rescate; multiclass: respaldo de piel y
        // último rescate). Antes corrían SIEMPRE (~1,1 s + ~1,2 s en el
        // A14) aunque su salida no cambiara ninguna decisión posterior.
        // YuNet en serie tras la pose, como el código original: correrlo
        // en paralelo a la pose se midió PEOR en el A14 (2 núcleos
        // grandes; MediaPipe/XNNPACK ya satura la CPU y el hilo extra
        // solo roba ciclos a pose y máscaras).
        val faces: List<FaceLandmarkPoints> = timed("vision.face") {
            runCatching { yuNet.detect(bitmap).map { it.toFaceLandmarks() } }
                .onFailure { Log.w(TAG, "YuNet falló: $it") }
                .getOrDefault(emptyList())
        }
        if (poses.isEmpty() && faces.isEmpty()) {
            // Sin poses ni caras no hay instancias que rescatar ni
            // fantasmas que juzgar: el resto de la cadena devolvería
            // exactamente "sin personas" (caso mayoritario del carrete).
            return PeopleDetectionResult(emptyList(), emptyList(), timings)
        }

        var humanBoxesCache: List<RectD>? = null
        fun humanBoxes(): List<RectD> {
            humanBoxesCache?.let { return it }
            val boxes: List<RectD> = timed("vision.humanRectangles") {
                val det = objectsTask()
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
                                // Cajas en píxeles del bitmap de detección
                                // (dw×dh): al raster del motor.
                                val sx = width.toDouble() / dw
                                val sy = height.toDouble() / dh
                                RectD(
                                    r.left * sx, r.top * sy,
                                    (r.right - r.left) * sx, (r.bottom - r.top) * sy,
                                )
                            }
                    }.onFailure {
                        Log.w(TAG, "EfficientDet falló: $it")
                        gpuBlacklist.add(EFFICIENTDET_MODEL)
                        dropObjectsCache()
                    }.getOrDefault(emptyList())
                }
            }
            humanBoxesCache = boxes
            return boxes
        }

        var multiclassTried = false
        var multiclassCache: ByteArray? = null
        fun multiclassRaw(): ByteArray? {
            if (multiclassTried) return multiclassCache
            multiclassTried = true
            multiclassCache = timed("vision.multiclass") {
                val seg = multiclassTask()
                if (seg == null) {
                    null
                } else {
                    runCatching {
                        seg.segment(mpImage).categoryMask().orElse(null)
                            ?.let { categoryMaskBytes(it, width, height) }
                    }.onFailure {
                        Log.w(TAG, "Multiclass falló: $it")
                        gpuBlacklist.add(MULTICLASS_MODEL)
                        dropMulticlassCache()
                    }.getOrNull()
                }
            }
            return multiclassCache
        }

        var semanticCache: MaskBuffer? = null
        fun semanticMap(): MaskBuffer? {
            semanticCache?.let { return it }
            val raw = multiclassCache ?: return null
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
            return MaskBuffer(width, height, mapped).also { semanticCache = it }
        }

        // 3) Máscaras de instancia: MagicTouch por pose, con rescate por la
        // máscara de la pose si el interactivo falla o es absurdo (IoU < 0,3).
        val instances = ArrayList<PersonDetection>()
        val floorPx = max(1, kotlin.math.ceil(RegionPlanning.MIN_PERSON_COVERAGE * width * height).toInt())
        var nextId = 1
        var interactiveSeg = if (poses.isNotEmpty() || faces.isNotEmpty()) {
            timed("vision.interactiveInit") { interactiveOrNull() }
        } else {
            null
        }
        if (interactiveSeg == null) timings["interactiveUnavailable"] = 1.0
        var interactiveRecreated = false

        fun segmentOnce(seg: InteractiveSegmenter, nx: Double, ny: Double): ByteArray? {
            // OJO (medido en el AVD): aunque la clase se llama
            // NormalizedKeypoint, el grafo Android del segmentador
            // interactivo legacy interpreta el punto en PÍXELES del
            // raster: con valores 0..1 el segmento sale siempre en la
            // esquina (0,0), idéntico para cualquier punto. En Python
            // el mismo modelo sí va normalizado (proto2 del carril B).
            val roi = InteractiveSegmenter.RegionOfInterest.create(
                NormalizedKeypoint.create(
                    (nx * dw).toFloat().coerceIn(0f, (dw - 1).toFloat()),
                    (ny * dh).toFloat().coerceIn(0f, (dh - 1).toFloat()),
                ),
            )
            // MPImage nueva por punto, como el código original de W2:
            // compartir la del raster no ahorró nada medible en el A14
            // (la copia cara ocurre dentro del grafo, no en el builder).
            val result = seg.segment(BitmapImageBuilder(detectBitmap).build(), roi)
            val mask = result.categoryMask().orElse(null) ?: return null
            val raw = categoryMaskBytes(mask, width, height)
            // Polaridad del modelo legacy: 0 = objeto señalado, 255 = fondo.
            return ByteArray(raw.size) { if (raw[it] == 0.toByte()) -1 else 0 }
        }

        fun interactiveMask(nx: Double, ny: Double): ByteArray? {
            val seg = interactiveSeg ?: return null
            return try {
                segmentOnce(seg, nx, ny)
            } catch (e: Exception) {
                Log.w(TAG, "MagicTouch falló en un punto: $e")
                // La tarea caliente pudo morir al reutilizarse (o la GPU
                // al ejecutarla): se recrea UNA vez — en CPU si iba en
                // GPU — y se reintenta el punto; solo si la fresca
                // también muere se marca el fallo permanente de antes.
                gpuBlacklist.add(MAGIC_TOUCH_MODEL)
                dropInteractiveCache()
                if (interactiveRecreated) {
                    interactiveFailed = true
                    interactiveSeg = null
                    null
                } else {
                    interactiveRecreated = true
                    timings["warmReuseFailed"] = 1.0
                    val fresh = interactiveOrNull()
                    interactiveSeg = fresh
                    if (fresh == null) {
                        null
                    } else {
                        try {
                            segmentOnce(fresh, nx, ny)
                        } catch (e2: Exception) {
                            Log.w(TAG, "MagicTouch falló también recién creado: $e2")
                            dropInteractiveCache()
                            interactiveFailed = true
                            interactiveSeg = null
                            null
                        }
                    }
                }
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
                    // El mapa semántico se adjunta al final solo si el
                    // multiclass llegó a correr (respaldo/rescate).
                    semanticMap = null,
                    id = nextId++,
                ),
            )
        }

        // 4) Semillas y rescate: caras con cuerpo y sin pose cuya instancia no
        // existe aún crean una (punto interactivo bajo la cara o multiclass
        // dentro de su caja de persona). Es el cierre medible para grupos.
        val seeds = timed("associate") { PersonSplitter.seeds(poses, faces) }
        val poseSeedFaces = seeds.mapNotNull { if (it.kind == SeedKind.POSE) it.faceIndex else null }.toSet()

        // ¿Necesita alguien las cajas de EfficientDet? Solo dos decisiones
        // las leen antes de la separación, y ambas se pueden prejuzgar sin
        // cajas (carril W6):
        //  - una semilla de cara sin evidencia corporal por articulaciones:
        //    screenFaceSeeds la descartaría sin su rectángulo de cuerpo;
        //  - el rescate de una cara huérfana, que exige su caja de cuerpo.
        // Si ninguna ocurre, pasar la lista vacía a la separación da
        // exactamente el mismo resultado (con cajas, bodyEvidence podría
        // etiquetar HUMAN_RECTANGLE donde ya había POSE_JOINTS, pero la
        // semilla se conserva igualmente y la etiqueta no decide nada más).
        val hasOrphanFace = faces.indices.any { fi ->
            fi !in poseSeedFaces &&
                PersonSplitter.box(faces[fi]) != null &&
                instances.none {
                    MaskOps.value(it.instanceMask.bytes, width, height, faces[fi].center.x, faces[fi].center.y) >= 128
                }
        }
        val seedPoseIdx = seeds.mapNotNull { if (it.kind == SeedKind.POSE) it.poseIndex else null }.toSet()
        val otherPoses = poses.filterIndexed { i, _ -> i !in seedPoseIdx }
        val faceSeedNeedsBoxes = splitOptions.requireBodyForFaceSeeds && seeds.any {
            it.kind == SeedKind.FACE &&
                PersonSplitter.bodyEvidence(it, emptyList(), otherPoses, splitOptions) == SeedBodyEvidence.NONE
        }
        val boxesForSplit: List<RectD> = if (hasOrphanFace || faceSeedNeedsBoxes) {
            humanBoxes()
        } else {
            timings["humanBoxesSkipped"] = 1.0
            emptyList()
        }
        for ((fi, face) in faces.withIndex()) {
            if (fi in poseSeedFaces) continue
            val fb = PersonSplitter.box(face) ?: continue
            val body = boxesForSplit.firstOrNull { PersonSplitter.rectangleIsBody(fb, it, splitOptions) }
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
            if (rescue == null) {
                // Último recurso del rescate: el multiclass dentro de la
                // caja de cuerpo. Solo aquí (y en el respaldo de piel de
                // abajo) corre el modelo (carril W6).
                val mc = multiclassRaw()
                if (mc != null) {
                    val m = ByteArray(width * height)
                    val x0 = max(0, body.minX.roundToInt())
                    val x1 = min(width - 1, body.maxX.roundToInt())
                    val y0 = max(0, body.minY.roundToInt())
                    val y1 = min(height - 1, body.maxY.roundToInt())
                    for (y in y0..y1) {
                        val row = y * width
                        for (x in x0..x1) if (mc[row + x] != 0.toByte()) m[row + x] = -1
                    }
                    if (MaskOps.nonZero(m) >= floorPx) rescue = m
                }
            }
            val resc = rescue ?: continue
            instances.add(
                PersonDetection(
                    instanceMask = MaskBuffer(width, height, resc),
                    face = PersonSplitter.detectedFaceOf(face),
                    semanticMap = semanticMap(),
                    id = nextId++,
                    faceLandmarks = face,
                ),
            )
        }

        // 5) Separación de fusionadas + asociación (PersonSplit de iOS).
        val outcome: SplitOutcome = timed("associate") {
            if (instances.isEmpty()) {
                SplitOutcome(
                    emptyList(), emptyList(), emptyList(), seeds,
                    List(seeds.size) { null }, emptyList(), poses.size, faces.size, emptyList(),
                )
            } else {
                PersonSplitter.apply(instances, poses, faces, seeds, width, height, boxesForSplit, splitOptions)
            }
        }

        // 6) Muestra de piel de respaldo (multiclass clase 3) si FaceSample
        // no dio. El modelo solo corre si alguna persona lo necesita; si
        // no corrió en toda la foto se anota multiclassSkipped.
        val anyNeedsBackup = outcome.people.any {
            SubjectChain.samplePixels(it.faceSampleMask?.bytes) < SubjectChain.MIN_SKIN_SAMPLES &&
                it.faceBox != null
        }
        val mcRaw = if (anyNeedsBackup) multiclassRaw() else multiclassCache
        if (!multiclassTried) timings["multiclassSkipped"] = 1.0
        val semMap = semanticMap()
        val withSamples = outcome.people.map { p0 ->
            var p = p0
            val own = p.faceSampleMask?.bytes
            val have = SubjectChain.samplePixels(own)
            val fb = p.faceBox
            if (have < SubjectChain.MIN_SKIN_SAMPLES && mcRaw != null && fb != null) {
                val backup = skinBackup(mcRaw, fb, p.instanceMask.bytes, width, height)
                if (SubjectChain.samplePixels(backup) > have) {
                    timings["skinBackupUsed"] = 1.0
                    p = PersonDetection(
                        instanceMask = p.instanceMask, pose = p.pose, face = p.face,
                        semanticMap = p.semanticMap, confidence = p.confidence, id = p.id,
                        faceSampleMask = MaskBuffer(width, height, backup),
                        faceLandmarks = p.faceLandmarks, splitFrom = p.splitFrom,
                    )
                }
            }
            if (semMap != null && p.semanticMap == null) {
                p = PersonDetection(
                    instanceMask = p.instanceMask, pose = p.pose, face = p.face,
                    semanticMap = semMap, confidence = p.confidence, id = p.id,
                    faceSampleMask = p.faceSampleMask,
                    faceLandmarks = p.faceLandmarks, splitFrom = p.splitFrom,
                )
            }
            p
        }

        // 7) Evidencia corporal anti-fantasmas. Con los umbrales por
        // defecto, pose con torso o cara ya son evidencia sin cajas; una
        // caja de persona solo puede AÑADIR evidencia (rescatar un NONE),
        // nunca quitarla. Por eso, si EfficientDet no ha corrido aún, se
        // juzga primero sin cajas y solo se le llama si alguien quedó
        // rechazado y una caja podría salvarlo: mismo resultado final.
        var phantom = timed("associate") {
            PersonEvidenceOps.rejectPhantoms(withSamples, width, height, phantomOptions, boxesForSplit)
        }
        if (phantom.second.isNotEmpty() && humanBoxesCache == null &&
            phantomOptions.enabled && phantomOptions.humanRectangles
        ) {
            val boxes = humanBoxes()
            timings["humanBoxesForPhantom"] = 1.0
            if (boxes.isNotEmpty()) {
                phantom = timed("associate") {
                    PersonEvidenceOps.rejectPhantoms(withSamples, width, height, phantomOptions, boxes)
                }
            }
        }
        val (kept, rejected) = phantom
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
        // Se cierran las tareas calientes reutilizadas y la sesión YuNet.
        dropPoseCache(withMasks = true)
        dropPoseCache(withMasks = false)
        dropInteractiveCache()
        dropObjectsCache()
        dropMulticlassCache()
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
