// YuNet (face_detection_yunet_2023mar, OpenCV Zoo, modelo MIT) con
// TFLite: el detector de caras a cualquier distancia del §2.2 del informe
// del carril B (BlazeFace es de rango corto: 0 caras en 6 de 9 fotos).
// Runtime elegido frente a ML Kit Face Detection bundled porque YuNet da
// los 5 puntos que FaceSample necesita (ojos + comisuras), el modelo pesa
// 232.589 B con licencia MIT y la ficha de datos de Play queda sin SDK de
// Google con telemetría.
//
// Antes corría el .onnx con ONNX Runtime; el carril W6 lo convirtió a
// TFLite float32 (android/tools/convert_yunet.py, desde el ONNX fijado
// por sha256) porque libonnxruntime.so costaba 17,6 MB por ABI para un
// modelo de 232 KB. Paridad validada contra ORT sobre harness/people:
// tensores |Δ|máx 1,3e-5, mismas caras y cajas a 0,00 px (informe W6).
// El .tflite convertido va versionado en assets (no tiene URL oficial).
//
// El modelo fijado tiene entrada FIJA 640x640 (OpenCV la reescala por
// dentro al tamaño de la foto; el runtime no). Aquí la foto se encaja
// con letterbox (escala 640/max(W,H), relleno negro abajo/derecha) y las
// coordenadas se deshacen con la misma escala. El decode (priors por
// stride 8/16/32, score = sqrt(sigmoid(cls)·sigmoid(obj)), caja y 5 puntos
// desde el centro de celda, NMS 0,3) se validó en el Mac contra
// cv2.FaceDetectorYN sobre harness/people: mismas caras en 01/02/05/07 con
// cajas a ~2 px (harness/out/android/w2/yunet_probe3.py). Entrada NHWC en
// orden BGR entrelazado (el modelo se entrenó con OpenCV), valores 0..255
// sin normalizar. Solo geometría: nada de color decide aquí.
package com.andreseloy.colorsapp.subject

import android.content.Context
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import org.tensorflow.lite.Interpreter
import java.io.FileInputStream
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.nio.channels.FileChannel
import kotlin.math.exp
import kotlin.math.max
import kotlin.math.min
import kotlin.math.sqrt

/** Cara de YuNet: caja (x, y, w, h) y 5 puntos en píxeles del raster. */
data class YuNetFace(
    val x: Double, val y: Double, val width: Double, val height: Double,
    /** [ojoDer, ojoIzq, nariz, comisuraDer, comisuraIzq] como los da YuNet. */
    val points: List<Pt>,
    val score: Double,
) {
    val box: RectD get() = RectD(x, y, width, height)

    /** Landmarks para FaceSample: ojos como centroides y boca = comisuras. */
    fun toFaceLandmarks(): FaceLandmarkPoints = FaceLandmarkPoints(
        leftEye = listOf(points[1]),
        rightEye = listOf(points[0]),
        outerLips = listOf(points[3], points[4]),
        boundingBox = box,
    )
}

/** Decode puro de YuNet (testeable en JVM sin ONNX Runtime). */
object YuNetDecode {
    const val INPUT_SIZE = 640
    val STRIDES = intArrayOf(8, 16, 32)

    fun sigmoid(v: Float): Double = 1.0 / (1.0 + exp(-v.toDouble()))

    /**
     * Decodifica las 12 salidas (cls/obj/bbox/kps por stride, aplanadas como
     * las exporta el .onnx: [1, N, C]) a caras en píxeles del raster.
     * [scale] es la del letterbox (640 = raster * scale).
     */
    fun decode(
        outputs: Map<String, FloatArray>,
        scale: Double,
        scoreThreshold: Double = 0.6,
        nmsThreshold: Double = 0.3,
        topK: Int = 5000,
    ): List<YuNetFace> {
        val candidates = ArrayList<YuNetFace>()
        for (stride in STRIDES) {
            val grid = INPUT_SIZE / stride
            val cls = outputs["cls_$stride"] ?: continue
            val obj = outputs["obj_$stride"] ?: continue
            val bbox = outputs["bbox_$stride"] ?: continue
            val kps = outputs["kps_$stride"] ?: continue
            val n = grid * grid
            if (cls.size < n || bbox.size < n * 4 || kps.size < n * 10) continue
            for (i in 0 until n) {
                val score = sqrt(sigmoid(cls[i]) * sigmoid(obj[i]))
                if (score < scoreThreshold) continue
                val row = i / grid
                val col = i % grid
                val b = i * 4
                val cx = (col + bbox[b]) * stride
                val cy = (row + bbox[b + 1]) * stride
                val bw = exp(bbox[b + 2].toDouble()) * stride
                val bh = exp(bbox[b + 3].toDouble()) * stride
                val pts = ArrayList<Pt>(5)
                for (j in 0 until 5) {
                    val kx = (col + kps[i * 10 + 2 * j]) * stride / scale
                    val ky = (row + kps[i * 10 + 2 * j + 1]) * stride / scale
                    pts.add(Pt(kx, ky))
                }
                candidates.add(
                    YuNetFace(
                        x = (cx - bw / 2) / scale, y = (cy - bh / 2) / scale,
                        width = bw / scale, height = bh / scale,
                        points = pts, score = score,
                    ),
                )
            }
        }
        return nms(candidates, nmsThreshold).take(topK)
    }

    /** NMS voraz por score descendente con IoU > umbral (como cv2.dnn.NMSBoxes). */
    fun nms(faces: List<YuNetFace>, threshold: Double): List<YuNetFace> {
        val sorted = faces.sortedByDescending { it.score }
        val kept = ArrayList<YuNetFace>()
        for (f in sorted) {
            if (kept.any { iou(it, f) > threshold }) continue
            kept.add(f)
        }
        return kept
    }

    fun iou(a: YuNetFace, b: YuNetFace): Double {
        val x0 = max(a.x, b.x)
        val y0 = max(a.y, b.y)
        val x1 = min(a.x + a.width, b.x + b.width)
        val y1 = min(a.y + a.height, b.y + b.height)
        val inter = max(0.0, x1 - x0) * max(0.0, y1 - y0)
        val union = a.width * a.height + b.width * b.height - inter
        return if (union > 0) inter / union else 0.0
    }
}

/** Detector de caras YuNet sobre el raster (intérprete TFLite perezoso, un uso por hilo). */
class YuNetFaceDetector(private val context: Context) {
    private var interpreter: Interpreter? = null

    @Synchronized
    private fun interpreter(): Interpreter {
        interpreter?.let { return it }
        val fd = context.assets.openFd(MODEL_ASSET)
        val model = FileInputStream(fd.fileDescriptor).channel.map(
            FileChannel.MapMode.READ_ONLY, fd.startOffset, fd.declaredLength,
        )
        // 4 hilos + XNNPACK. Medido en el A14 (W6): ~450 ms por foto
        // (ORT tardaba ~170 ms; es el precio de quitar sus 17,6 MB).
        // 8 hilos no mejora nada y el delegado NNAPI baja a ~240 ms
        // pero compila 9,6 s en el primer uso de cada proceso: no vale.
        @Suppress("DEPRECATION")
        val options = Interpreter.Options().setNumThreads(4).setUseXNNPACK(true)
        return Interpreter(model, options).also { interpreter = it }
    }

    /** Caras en el Bitmap del raster (mismo tamaño que ve el motor). */
    fun detect(raster: Bitmap, scoreThreshold: Double = 0.6): List<YuNetFace> {
        val scale = YuNetDecode.INPUT_SIZE.toDouble() / max(raster.width, raster.height)
        val rw = max(1, Math.round(raster.width * scale).toInt())
        val rh = max(1, Math.round(raster.height * scale).toInt())
        val canvas = Bitmap.createBitmap(YuNetDecode.INPUT_SIZE, YuNetDecode.INPUT_SIZE, Bitmap.Config.ARGB_8888)
        val c = Canvas(canvas)
        c.drawColor(Color.BLACK)
        val scaled = SubjectRaster.scaleTo(raster, rw, rh)
        c.drawBitmap(scaled, 0f, 0f, null)
        if (scaled !== raster) scaled.recycle()
        val px = IntArray(YuNetDecode.INPUT_SIZE * YuNetDecode.INPUT_SIZE)
        canvas.getPixels(px, 0, YuNetDecode.INPUT_SIZE, 0, 0, YuNetDecode.INPUT_SIZE, YuNetDecode.INPUT_SIZE)
        canvas.recycle()
        // Tensor NHWC en orden BGR entrelazado, valores 0..255 (el TFLite
        // convertido espera [1,640,640,3]; los canales son los del ONNX).
        val input = ByteBuffer.allocateDirect(px.size * 3 * 4).order(ByteOrder.nativeOrder())
        val floats = input.asFloatBuffer()
        for (color in px) {
            floats.put(Color.blue(color).toFloat())
            floats.put(Color.green(color).toFloat())
            floats.put(Color.red(color).toFloat())
        }
        input.rewind()
        val interp = interpreter()
        // Salidas en ByteBuffer por índice (un FloatArray plano no casa
        // con la forma [1,N,C] del tensor y copyTo lo rechaza); los
        // nombres del .tflite coinciden con los del ONNX (cls_8, …).
        val outputBuffers = HashMap<Int, Any>()
        val outputMeta = HashMap<Int, Pair<String, Int>>()
        for (i in 0 until interp.outputTensorCount) {
            val tensor = interp.getOutputTensor(i)
            val n = tensor.numElements()
            outputBuffers[i] = ByteBuffer.allocateDirect(n * 4).order(ByteOrder.nativeOrder())
            outputMeta[i] = tensor.name() to n
        }
        interp.runForMultipleInputsOutputs(arrayOf(input), outputBuffers)
        val outputs = HashMap<String, FloatArray>()
        for ((i, buf) in outputBuffers) {
            val (name, n) = outputMeta[i] ?: continue
            val bb = (buf as ByteBuffer).order(ByteOrder.nativeOrder())
            bb.rewind()
            val arr = FloatArray(n)
            bb.asFloatBuffer().get(arr)
            outputs[name] = arr
        }
        return YuNetDecode.decode(outputs, scale, scoreThreshold)
    }

    @Synchronized
    fun close() {
        runCatching { interpreter?.close() }
        interpreter = null
    }

    companion object {
        const val MODEL_ASSET = "models/face_detection_yunet_2023mar_float32.tflite"
    }
}
