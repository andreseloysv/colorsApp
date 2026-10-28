// Paridad de YuNet-TFLite en dispositivo (carril W6): las caras sobre
// harness/people deben ser las mismas que daba ONNX Runtime (conteos
// validados en el Mac contra ORT y cv2.FaceDetectorYN). Si el runtime o
// el mapeo de salidas del .tflite cambia, este test lo caza antes que el
// de la cadena entera.
package com.andreseloy.colorsapp.subject

import android.graphics.BitmapFactory
import android.util.Log
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class YuNetParityDeviceTest {

    // Caras YuNet (score >= 0,6) con el ONNX en el Mac (informe W6).
    // Rangos: la tercera cara de la 03 sale a 0,60 clavados en el A14
    // (el letterbox de Canvas y el de PIL difieren en el último bit),
    // así que 2..3 es paridad válida; el resto va exacto.
    private val expectedFaces = linkedMapOf(
        "01_single_black_outfit.png" to (1..1),
        "02_single_dress_umbrella.png" to (1..1),
        "03_couple_denim_street.png" to (2..3),
        "04_two_women_backlit.png" to (1..1),
        "05_three_friends_closeup.png" to (3..3),
        "06_group_courier_street.png" to (5..5),
        "07_group_mural_white_outfits.png" to (7..7),
        "08_artist_colorful_mural.png" to (1..1),
        "synthetic_tight_selfie.png" to (3..3),
    )

    @Test
    fun yunetFacesMatchOnnxReference() {
        val instrumentation = InstrumentationRegistry.getInstrumentation()
        val testAssets = instrumentation.context.assets
        val detector = YuNetFaceDetector(instrumentation.targetContext)
        for ((file, expected) in expectedFaces) {
            val bitmap = testAssets.open("people/$file").use { BitmapFactory.decodeStream(it) }
            val t0 = System.nanoTime()
            val faces = detector.detect(bitmap)
            val ms = (System.nanoTime() - t0) / 1_000_000.0
            Log.i(
                "W6YuNet",
                "$file caras=${faces.size} (esperadas $expected) ${String.format(java.util.Locale.US, "%.0f", ms)}ms " +
                    faces.joinToString(" ") {
                        "[${it.x.toInt()},${it.y.toInt()},${it.width.toInt()}x${it.height.toInt()} " +
                            String.format(java.util.Locale.US, "%.2f", it.score) + "]"
                    },
            )
            assertTrue("$file: conteo de caras YuNet-TFLite ${faces.size} ∉ $expected", faces.size in expected)
            assertTrue("$file: scores sanos", faces.all { it.score in 0.6..1.0 && it.width > 2 && it.height > 2 })
        }
        detector.close()
    }
}
