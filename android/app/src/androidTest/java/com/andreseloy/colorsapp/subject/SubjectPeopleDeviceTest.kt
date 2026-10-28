// Test instrumentado del carril W2 en el AVD propio (chromasol-w2): corre
// el detector completo (MediaPipe + YuNet) y la cadena sobre las 8 fotos
// CC0 de harness/people + la selfie sintética, y compara con la referencia
// iOS que el carril B regeneró con visionmask (conteos y top-1 de la tabla
// §3.6 de docs/research/android-subject.md; IoU contra instances_split
// si los PGM se sincronizaron en compilación). Escribe el informe por foto
// (personas, IoU, top-1/3, pasos, tiempos) y overlays PNG en el filesDir
// externo de la app para recogerlos por adb a harness/out/android/w2/.
package com.andreseloy.colorsapp.subject

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.andreseloy.colorsapp.scan.PhotoAnalysis
import com.andreseloy.colorsapp.scan.PhotoAnalyzer
import kotlinx.coroutines.runBlocking
import android.util.Log
import org.junit.Assert.assertEquals
import org.junit.Assert.fail
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import java.io.File
import java.io.FileOutputStream

@RunWith(AndroidJUnit4::class)
class SubjectPeopleDeviceTest {

    private data class Ref(val file: String, val peopleIos: Int, val top1Ios: Int?)

    // Referencia iOS del carril B (visionmask, macOS): personas tras separar
    // y top-1 del camino por prenda (05 va al clásico en iOS: sin top fijo).
    private val refs = listOf(
        Ref("01_single_black_outfit.png", 1, 117),
        Ref("02_single_dress_umbrella.png", 1, 69),
        Ref("03_couple_denim_street.png", 2, 218),
        Ref("04_two_women_backlit.png", 2, 117),
        Ref("05_three_friends_closeup.png", 3, null),
        Ref("06_group_courier_street.png", 4, 143),
        Ref("07_group_mural_white_outfits.png", 7, 139),
        Ref("08_artist_colorful_mural.png", 1, 49),
        Ref("synthetic_tight_selfie.png", 3, null),
    )

    private fun loadPgm(bytes: ByteArray): Triple<Int, Int, ByteArray>? {
        // P5\n<w> <h>\n255\n<datos>
        var i = 0
        fun token(): String {
            while (i < bytes.size && bytes[i].toInt().toChar().isWhitespace()) i++
            val sb = StringBuilder()
            while (i < bytes.size && !bytes[i].toInt().toChar().isWhitespace()) {
                sb.append(bytes[i].toInt().toChar())
                i++
            }
            return sb.toString()
        }
        if (token() != "P5") return null
        val w = token().toIntOrNull() ?: return null
        val h = token().toIntOrNull() ?: return null
        token() // maxval
        i++ // un whitespace tras el maxval
        if (bytes.size - i < w * h) return null
        return Triple(w, h, bytes.copyOfRange(i, i + w * h))
    }

    private fun overlayPng(photo: Bitmap, analysis: PhotoAnalysis, out: File) {
        val w = photo.width
        val h = photo.height
        val outBmp = Bitmap.createBitmap(w, h, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(outBmp)
        canvas.drawBitmap(photo, 0f, 0f, null)
        val mask = analysis.subject.mask
        val garments = analysis.subject.garmentRegions
        if (mask != null) {
            val px = IntArray(w * h)
            outBmp.getPixels(px, 0, w, 0, 0, w, h)
            for (i in px.indices) {
                val g = garments?.bytes?.getOrNull(i)?.toInt() ?: 0
                val tint = when {
                    g == 1 -> Color.argb(110, 255, 90, 40)
                    g == 2 -> Color.argb(110, 40, 120, 255)
                    mask.bytes[i] != 0.toByte() -> Color.argb(90, 60, 255, 120)
                    else -> 0
                }
                if (tint != 0) px[i] = blend(px[i], tint)
            }
            outBmp.setPixels(px, 0, w, 0, 0, w, h)
        }
        val paint = Paint().apply {
            color = Color.YELLOW
            strokeWidth = 2f
            style = Paint.Style.FILL
        }
        for (p in analysis.subject.people) {
            val pose = p.pose ?: continue
            for (k in pose.joints) {
                if (k.confidence >= 0.3) canvas.drawCircle(k.x.toFloat(), k.y.toFloat(), 3f, paint)
            }
        }
        FileOutputStream(out).use { outBmp.compress(Bitmap.CompressFormat.PNG, 92, it) }
    }

    private fun blend(base: Int, tint: Int): Int {
        val a = Color.alpha(tint) / 255.0
        fun ch(b: Int, t: Int) = (b * (1 - a) + t * a).toInt().coerceIn(0, 255)
        return Color.rgb(
            ch(Color.red(base), Color.red(tint)),
            ch(Color.green(base), Color.green(tint)),
            ch(Color.blue(base), Color.blue(tint)),
        )
    }

    private fun ByteArray.getOrNull(i: Int): Byte? = if (i in indices) this[i] else null

    @Test
    fun peoplePhotosVsIosReference() = runBlocking {
        val instrumentation = InstrumentationRegistry.getInstrumentation()
        val testAssets = instrumentation.context.assets
        val appContext = instrumentation.targetContext
        val outDir = File(appContext.getExternalFilesDir(null), "w2").apply { mkdirs() }
        val segmenter = SubjectChainSegmenter(MediaPipePersonDetector(appContext))
        val options = com.andreseloy.colorsapp.subject.SubjectSettings().subjectOptions()
        val report = StringBuilder()
        val problems = ArrayList<String>()
        report.append("{\n \"photos\": [\n")
        var first = true
        for (ref in refs) {
            val bitmap = testAssets.open("people/${ref.file}").use { BitmapFactory.decodeStream(it) }
            assertTrue("sin bitmap ${ref.file}", bitmap != null)
            val t0 = System.nanoTime()
            val analysis = PhotoAnalyzer.analyze(bitmap, segmenter, options)
            val totalMs = (System.nanoTime() - t0) / 1_000_000.0
            val subject = analysis.subject
            val top = analysis.result.hits.map { it.comboId }
            // IoU contra las instancias separadas de iOS, si están.
            var ious = ""
            val pgmName = "ios-ref/" + ref.file.removeSuffix(".png") + ".instances_split.pgm"
            val pgmBytes = runCatching { testAssets.open(pgmName).readBytes() }.getOrNull()
            if (pgmBytes != null) {
                val (pw, ph, labels) = loadPgm(pgmBytes)!!
                val labelIds = labels.map { MaskOps.u(it) }.filter { it > 0 }.toSortedSet()
                val best = labelIds.map { label ->
                    var b = 0.0
                    for (p in subject.people) {
                        val inst = p.instanceMask ?: continue
                        var inter = 0
                        var union = 0
                        val n = minOf(labels.size, inst.bytes.size)
                        for (i in 0 until n) {
                            val a = MaskOps.u(labels[i]) == label
                            val c = MaskOps.u(inst.bytes[i]) >= 128
                            if (a && c) inter++
                            if (a || c) union++
                        }
                        if (union > 0) b = maxOf(b, inter.toDouble() / union)
                    }
                    b
                }
                ious = best.joinToString(",", "[", "]") { String.format("%.3f", it) }
                if (ref.file.substring(0, 2) in setOf("01", "02", "03", "04") && pw == bitmap.width) {
                    if (best.isNotEmpty() && best.average() < 0.5) {
                        problems.add("${ref.file}: IoU medio ${best.average()} < 0.5 (IoU=$best)")
                    }
                }
            }
            overlayPng(bitmap, analysis, File(outDir, ref.file.removeSuffix(".png") + ".overlay.png"))
            val chosenInst = subject.chosenIndex?.let { subject.people.getOrNull(it)?.instanceMask }
            val instStats = chosenInst?.let { MaskOps.stats(it.bytes, bitmap.width, bitmap.height) }
            Log.i(
                "W2Report",
                "${ref.file} people=${subject.people.size}/${ref.peopleIos} top=$top steps=${subject.steps} " +
                    "maskCov=${String.format("%.3f", subject.maskCoverage)} instBBox=${instStats?.bbox} iou=$ious " +
                    "garments=${analysis.garments.map { it.swatch.hex to it.region }} totalMs=${String.format("%.0f", totalMs)}",
            )
            report.append(if (first) "  " else "  ,")
            first = false
            report.append(
                "{\"file\":\"${ref.file}\",\"people\":${subject.people.size},\"peopleIos\":${ref.peopleIos}," +
                    "\"chosen\":${subject.chosenIndex},\"steps\":[${subject.steps.joinToString(",") { "\"${it.raw}\"" }}]," +
                    "\"top\":${top},\"top1Ios\":${ref.top1Ios},\"garments\":[" +
                    analysis.garments.joinToString(",") { "{\"hex\":\"${it.swatch.hex}\",\"region\":${it.region.code}}" } +
                    "],\"iou\":${ious.ifEmpty { "null" }}," +
                    "\"timings\":{${subject.timingsMs.entries.joinToString(",") { "\"${it.key}\":${String.format("%.1f", it.value)}" }}}," +
                    "\"totalMs\":${String.format("%.1f", totalMs)}}\n",
            )
            // Afirmaciones por foto (la vara del carril B sin la cadena era
            // top-1 en 01-04; con la cadena entera debe mantenerse).
            fun check(cond: Boolean, msg: String) { if (!cond) problems.add(msg) }
            when (ref.file.substring(0, 2)) {
                "01", "02", "04", "08" -> {
                    check(subject.people.size == ref.peopleIos, "${ref.file} personas ${subject.people.size} != ${ref.peopleIos}")
                    if (ref.top1Ios != null && ref.file.substring(0, 2) != "08") {
                        check(top.firstOrNull() == ref.top1Ios, "${ref.file} top1 ${top.firstOrNull()} != ${ref.top1Ios} (top=$top)")
                    }
                }
                // 03: la figura desenfocada del fondo (anotada en
                // expected.json) da pose en Android; Vision no la instancia.
                "03" -> {
                    check(subject.people.size in 2..3, "03 personas ${subject.people.size}")
                    check(top.firstOrNull() == ref.top1Ios, "03 top1 ${top.firstOrNull()} != ${ref.top1Ios} (top=$top)")
                }
                "05" -> check(subject.people.size in 2..4, "05 personas ${subject.people.size}")
                "06" -> {
                    check(subject.people.size >= 2, "06 personas ${subject.people.size} (iOS 4)")
                    check(143 in top, "06 top3 sin el top1 iOS: $top")
                }
                "07" -> check(subject.people.size in 4..9, "07 personas ${subject.people.size}")
                else -> check(subject.people.size in 1..4, "selfie personas ${subject.people.size}")
            }
            File(outDir, "w2-report.json").writeText(report.toString() + " ]\n}\n")
        }
        report.append(" ]\n}\n")
        File(outDir, "w2-report.json").writeText(report.toString())
        if (problems.isNotEmpty()) fail(problems.joinToString("\n"))
    }

    @Test
    fun blankPhotoHasNoPeople() = runBlocking {
        val appContext = InstrumentationRegistry.getInstrumentation().targetContext
        val segmenter = SubjectChainSegmenter(MediaPipePersonDetector(appContext))
        val options = com.andreseloy.colorsapp.subject.SubjectSettings().subjectOptions()
        val blank = Bitmap.createBitmap(320, 240, Bitmap.Config.ARGB_8888).apply { eraseColor(Color.rgb(120, 140, 90)) }
        val analysis = PhotoAnalyzer.analyze(blank, segmenter, options)
        assertEquals(0, analysis.subject.people.size)
        assertTrue(analysis.subject.mask == null)
    }
}

/** Escaneo día 0 sobre bitmaps (el camino de MediaStore sin permiso). */
@RunWith(AndroidJUnit4::class)
class MediaStoreScanRunnerDeviceTest {

    @Test
    fun scanBitmapsPersistsAndUnlocks() = runBlocking {
        val instrumentation = InstrumentationRegistry.getInstrumentation()
        val testAssets = instrumentation.context.assets
        val appContext = instrumentation.targetContext
        val scans = com.andreseloy.colorsapp.data.InMemoryScanRepository()
        val unlocks = com.andreseloy.colorsapp.data.InMemoryUnlockRepository()
        val settings = com.andreseloy.colorsapp.data.InMemorySettingsRepository()
        val dictionary = com.andreseloy.colorsapp.data.EngineWadaDictionary()
        val segmenter = SubjectChainSegmenter(MediaPipePersonDetector(appContext))
        val runner = com.andreseloy.colorsapp.scan.MediaStoreScanRunner(
            scans = scans, unlocks = unlocks, settings = settings, dictionary = dictionary,
            photoLibrary = com.andreseloy.colorsapp.scan.MediaStorePhotoLibrarySource(appContext),
            segmenter = segmenter,
        )
        // El top-1 de la 01 puntúa ~24: con el umbral de la app (12) no se
        // desbloquea (igual que en iOS); el test sube el ajuste para probar
        // el mecanismo de desbloqueo.
        settings.setDouble(com.andreseloy.colorsapp.data.SettingsRepository.Key.UNLOCK_MAX_SCORE, 30.0)
        val seen = ArrayList<com.andreseloy.colorsapp.scan.ScanProgress>()
        runner.onProgress = { seen.add(it) }
        val images = listOf("01_single_black_outfit.png", "03_couple_denim_street.png").map { name ->
            name to testAssets.open("people/$name").use { BitmapFactory.decodeStream(it) }
        }
        val summary = runner.scanBitmaps(images)
        assertEquals(2, summary.scanned)
        assertEquals(0, summary.failed)
        assertEquals(2, scans.count())
        val first = scans.recent(2).firstOrNull { it.top1 == 117 }
        assertTrue("scan 01 con top1 117", first != null)
        assertTrue("steps guardados", (first!!.maskStepsJson ?: "").contains("poseRegions"))
        assertTrue("desbloqueo 117", unlocks.isUnlocked(117))
        assertTrue("progreso final", seen.last().phase == com.andreseloy.colorsapp.scan.ScanProgress.Phase.FINISHED)
        assertTrue("topCombos", summary.topCombos.isNotEmpty())
    }
}
