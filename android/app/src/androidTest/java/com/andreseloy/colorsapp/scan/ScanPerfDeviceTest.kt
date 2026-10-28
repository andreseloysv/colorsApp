// Medición del escaneo día 0 (carril W6): 200 fotos variadas en un álbum
// de MediaStore PROPIO del test (Pictures/ChromaSolW6Test), escaneadas por
// el camino real de miniaturas de 256 px (loadThumbnail + scanBitmaps con
// 3 en paralelo) y borradas al terminar, también si el test falla. No se
// toca ninguna foto del dueño: no se enumera el carrete (runInitialScan
// quedaría fuera), solo se leen las URIs insertadas por este test.
// Composición tipo carrete: 30 con personas (las 9 de harness/people
// repetidas con recorte) y 170 escenas sintéticas sin personas.
// Informe JSON (Locale.US) en filesDir externo: w6/scan200.json.
package com.andreseloy.colorsapp.scan

import android.content.ContentValues
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.net.Uri
import android.os.Build
import android.provider.MediaStore
import android.util.Log
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.andreseloy.colorsapp.data.EngineWadaDictionary
import com.andreseloy.colorsapp.data.InMemoryScanRepository
import com.andreseloy.colorsapp.data.InMemorySettingsRepository
import com.andreseloy.colorsapp.data.InMemoryUnlockRepository
import com.andreseloy.colorsapp.data.LibraryPhoto
import com.andreseloy.colorsapp.subject.MediaPipePersonDetector
import com.andreseloy.colorsapp.subject.SubjectChainSegmenter
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import java.io.File
import java.util.Locale
import kotlin.random.Random

@RunWith(AndroidJUnit4::class)
class ScanPerfDeviceTest {

    private val peopleNames = listOf(
        "01_single_black_outfit.png", "02_single_dress_umbrella.png",
        "03_couple_denim_street.png", "04_two_women_backlit.png",
        "05_three_friends_closeup.png", "06_group_courier_street.png",
        "07_group_mural_white_outfits.png", "08_artist_colorful_mural.png",
        "synthetic_tight_selfie.png",
    )

    /** Escena sin personas: degradado + formas, variedad determinista. */
    private fun syntheticScene(seed: Int): Bitmap {
        val rnd = Random(seed)
        val w = 1600
        val h = 1200
        val bmp = Bitmap.createBitmap(w, h, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(bmp)
        val paint = Paint()
        fun rndColor() = Color.rgb(rnd.nextInt(256), rnd.nextInt(256), rnd.nextInt(256))
        paint.color = rndColor()
        canvas.drawRect(0f, 0f, w.toFloat(), h.toFloat(), paint)
        // Bandas horizontales (paisaje abstracto).
        var y = 0f
        while (y < h) {
            val bandH = 60f + rnd.nextInt(240)
            paint.color = rndColor()
            canvas.drawRect(0f, y, w.toFloat(), y + bandH, paint)
            y += bandH
        }
        repeat(12) {
            paint.color = rndColor()
            if (rnd.nextBoolean()) {
                canvas.drawCircle(
                    rnd.nextInt(w).toFloat(), rnd.nextInt(h).toFloat(),
                    40f + rnd.nextInt(260), paint,
                )
            } else {
                val x = rnd.nextInt(w).toFloat()
                val yy = rnd.nextInt(h).toFloat()
                canvas.drawRect(x, yy, x + 80 + rnd.nextInt(500), yy + 60 + rnd.nextInt(400), paint)
            }
        }
        return bmp
    }

    private fun insertJpeg(
        resolver: android.content.ContentResolver, name: String, bitmap: Bitmap,
    ): Uri? {
        val values = ContentValues().apply {
            put(MediaStore.Images.Media.DISPLAY_NAME, name)
            put(MediaStore.Images.Media.MIME_TYPE, "image/jpeg")
            if (Build.VERSION.SDK_INT >= 29) {
                put(MediaStore.Images.Media.RELATIVE_PATH, "Pictures/ChromaSolW6Test")
                put(MediaStore.Images.Media.IS_PENDING, 1)
            }
        }
        val uri = resolver.insert(MediaStore.Images.Media.EXTERNAL_CONTENT_URI, values)
            ?: return null
        resolver.openOutputStream(uri)?.use { out ->
            bitmap.compress(Bitmap.CompressFormat.JPEG, 85, out)
        }
        if (Build.VERSION.SDK_INT >= 29) {
            values.clear()
            values.put(MediaStore.Images.Media.IS_PENDING, 0)
            resolver.update(uri, values, null, null)
        }
        return uri
    }

    @Test
    fun day0Scan200Photos() = runBlocking {
        val instrumentation = InstrumentationRegistry.getInstrumentation()
        val testAssets = instrumentation.context.assets
        val appContext = instrumentation.targetContext
        val resolver = appContext.contentResolver
        val outDir = File(appContext.getExternalFilesDir(null), "w6").apply { mkdirs() }
        val inserted = ArrayList<Pair<String, Uri>>()
        try {
            // 30 con personas (ciclo de las 9) + 170 sintéticas.
            val tInsert0 = System.nanoTime()
            val peopleBitmaps = peopleNames.map { name ->
                testAssets.open("people/$name").use { BitmapFactory.decodeStream(it) }
            }
            for (i in 0 until 30) {
                val src = peopleBitmaps[i % peopleBitmaps.size]
                val name = "w6_people_%02d.jpg".format(Locale.US, i)
                insertJpeg(resolver, name, src)?.let { inserted.add("people" to it) }
            }
            for (i in 0 until 170) {
                val name = "w6_scene_%03d.jpg".format(Locale.US, i)
                val scene = syntheticScene(1000 + i)
                insertJpeg(resolver, name, scene)?.let { inserted.add("scene" to it) }
                scene.recycle()
            }
            assertEquals(200, inserted.size)
            val insertMs = (System.nanoTime() - tInsert0) / 1_000_000.0

            val segmenter = SubjectChainSegmenter(MediaPipePersonDetector(appContext))
            val scans = InMemoryScanRepository()
            val runner = MediaStoreScanRunner(
                scans = scans,
                unlocks = InMemoryUnlockRepository(),
                settings = InMemorySettingsRepository(),
                dictionary = EngineWadaDictionary(),
                photoLibrary = MediaStorePhotoLibrarySource(appContext),
                segmenter = segmenter,
            )
            val source = MediaStorePhotoLibrarySource(appContext)
            val options = com.andreseloy.colorsapp.subject.SubjectSettings().subjectOptions()

            // Calentamiento (modelos) medido aparte, como la 1ª foto real.
            val warmThumb = source.loadThumbnail(
                LibraryPhoto(inserted.first().second.toString(), inserted.first().second, 0, 0, 0), 256,
            )
            assertTrue("miniatura de calentamiento", warmThumb != null)
            val tWarm0 = System.nanoTime()
            PhotoAnalyzer.analyze(warmThumb!!, segmenter, options)
            val warmMs = (System.nanoTime() - tWarm0) / 1_000_000.0

            suspend fun scanGroup(kind: String): Triple<Double, Double, ScanSummary> {
                val uris = inserted.filter { it.first == kind }.map { it.second }
                val tThumb0 = System.nanoTime()
                val thumbs = uris.map { uri ->
                    uri.toString() to source.loadThumbnail(LibraryPhoto(uri.toString(), uri, 0, 0, 0), 256)!!
                }
                val thumbMs = (System.nanoTime() - tThumb0) / 1_000_000.0
                val tScan0 = System.nanoTime()
                val summary = runner.scanBitmaps(thumbs)
                val scanMs = (System.nanoTime() - tScan0) / 1_000_000.0
                return Triple(thumbMs, scanMs, summary)
            }

            val (thumbPeople, scanPeople, sumPeople) = scanGroup("people")
            val (thumbScenes, scanScenes, sumScenes) = scanGroup("scene")
            val totalScanMs = thumbPeople + scanPeople + thumbScenes + scanScenes
            val perPhoto = totalScanMs / 200.0
            fun f(v: Double) = String.format(Locale.US, "%.1f", v)
            val json = "{\n" +
                " \"photos\": 200,\n" +
                " \"insertMs\": ${f(insertMs)}, \"warmupMs\": ${f(warmMs)},\n" +
                " \"people\": {\"n\": 30, \"thumbMs\": ${f(thumbPeople)}, \"scanMs\": ${f(scanPeople)}, " +
                "\"perPhotoMs\": ${f((thumbPeople + scanPeople) / 30)}, \"failed\": ${sumPeople.failed}},\n" +
                " \"scenes\": {\"n\": 170, \"thumbMs\": ${f(thumbScenes)}, \"scanMs\": ${f(scanScenes)}, " +
                "\"perPhotoMs\": ${f((thumbScenes + scanScenes) / 170)}, \"failed\": ${sumScenes.failed}},\n" +
                " \"totalScanMs\": ${f(totalScanMs)}, \"perPhotoMs\": ${f(perPhoto)},\n" +
                " \"stepCounts\": {${runner.lastStepCounts.entries.joinToString(",") { "\"${it.key}\":${it.value}" }}}\n" +
                "}\n"
            File(outDir, "scan200.json").writeText(json)
            Log.i("W6Scan", json)
            assertEquals(0, sumPeople.failed + sumScenes.failed)
            assertEquals(200, scans.count())
        } finally {
            // Retirada completa del álbum del test (también si hay fallo).
            for ((_, uri) in inserted) runCatching { resolver.delete(uri, null, null) }
        }
    }
}
