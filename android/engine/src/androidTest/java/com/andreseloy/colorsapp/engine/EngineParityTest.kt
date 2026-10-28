// Paridad del motor en Android contra los goldens del repo y las fixtures de
// paridad WASM, con el mismo contrato que `make golden-check`: Lab, pesos y
// scores a 1e-9, mismo top-3 y mismo hash FNV-1a.
//
// Los assets llegan por la tarea syncParityAssets (copia de harness/golden y
// harness/wasm/fixtures a build/; nada duplicado en git). El esperado de las
// fixtures WASM lo genera android/tools/gen_wasm_expected.py con el CLI
// nativo `ce`, el mismo binario que `make parity` compara contra WASM.
package com.andreseloy.colorsapp.engine

import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Test
import org.junit.runner.RunWith
import kotlin.math.abs

@RunWith(AndroidJUnit4::class)
class EngineParityTest {

    private val tol = 1e-9

    private fun assetText(path: String): String =
        InstrumentationRegistry.getInstrumentation().context.assets
            .open(path).bufferedReader().readText()

    private fun assetBytes(path: String): ByteArray =
        InstrumentationRegistry.getInstrumentation().context.assets.open(path).readBytes()

    /** PPM P6 binario (cabecera ASCII, maxval 255) -> EngineImage RGB8. */
    private fun readPpm(path: String): EngineImage {
        val data = assetBytes(path)
        var pos = 0
        fun token(): String {
            while (pos < data.size && (data[pos].toInt().toChar().isWhitespace())) pos++
            val start = pos
            while (pos < data.size && !data[pos].toInt().toChar().isWhitespace()) pos++
            return String(data, start, pos - start, Charsets.US_ASCII)
        }
        check(token() == "P6") { "$path no es P6" }
        val w = token().toInt()
        val h = token().toInt()
        check(token().toInt() == 255) { "$path: maxval != 255" }
        pos++ // un único separador tras maxval
        val rgb = data.copyOfRange(pos, pos + w * h * 3)
        return EngineImage(rgb, w, h, w * 3, PixelFormat.RGB8)
    }

    private fun paletteOptions(json: JSONObject?): PaletteOptions {
        if (json == null) return PaletteOptions.DEFAULT
        val d = PaletteOptions.DEFAULT
        return PaletteOptions(
            kInit = json.optInt("k_init", d.kInit),
            maxIters = json.optInt("max_iters", d.maxIters),
            maxColors = json.optInt("max_colors", d.maxColors),
            maxSide = json.optInt("max_side", d.maxSide),
            centerSigma = json.optDouble("center_sigma", d.centerSigma),
            mergeDeltaE = json.optDouble("merge_de", d.mergeDeltaE),
            minWeight = json.optDouble("min_weight", d.minWeight),
            skinRule = json.optInt("skin_rule", if (d.skinRule) 1 else 0) != 0,
            mergeLightDeltaE = json.optDouble("merge_light_de", d.mergeLightDeltaE),
        )
    }

    private fun matchOptions(json: JSONObject?): MatchOptions {
        if (json == null) return MatchOptions.DEFAULT
        val d = MatchOptions.DEFAULT
        return MatchOptions(
            kL = json.optDouble("kL", d.kL),
            kC = json.optDouble("kC", d.kC),
            kH = json.optDouble("kH", d.kH),
            coverageLambda = json.optDouble("coverage_lambda", d.coverageLambda),
            ambiguousGap = json.optDouble("ambiguous_gap", d.ambiguousGap),
            exposureEvMax = json.optDouble("exposure_ev_max", d.exposureEvMax),
            exposurePenalty = json.optDouble("exposure_penalty", d.exposurePenalty),
            illuminantSearch = json.optInt("illuminant_search", if (d.illuminantSearch) 1 else 0) != 0,
            illuminantPenalty = json.optDouble("illuminant_penalty", d.illuminantPenalty),
        )
    }

    private fun hexHash(hash: Long): String =
        java.lang.Long.toUnsignedString(hash, 16).padStart(16, '0')

    private fun assertSwatches(file: String, expected: org.json.JSONArray, actual: List<Swatch>) {
        assertEquals("$file: número de swatches", expected.length(), actual.size)
        for (i in 0 until expected.length()) {
            val e = expected.getJSONObject(i)
            val lab = e.getJSONArray("lab")
            val rgb = e.getJSONArray("rgb")
            val a = actual[i]
            assertTrue("$file swatch$i L ${a.lab.l} vs ${lab.getDouble(0)}",
                abs(a.lab.l - lab.getDouble(0)) <= tol)
            assertTrue("$file swatch$i a ${a.lab.a} vs ${lab.getDouble(1)}",
                abs(a.lab.a - lab.getDouble(1)) <= tol)
            assertTrue("$file swatch$i b ${a.lab.b} vs ${lab.getDouble(2)}",
                abs(a.lab.b - lab.getDouble(2)) <= tol)
            assertTrue("$file swatch$i weight ${a.weight} vs ${e.getDouble("weight")}",
                abs(a.weight - e.getDouble("weight")) <= tol)
            assertEquals("$file swatch$i r", rgb.getInt(0), a.r)
            assertEquals("$file swatch$i g", rgb.getInt(1), a.g)
            assertEquals("$file swatch$i b8", rgb.getInt(2), a.b)
        }
    }

    private fun assertHits(file: String, expected: org.json.JSONArray, actual: List<Hit>) {
        assertEquals("$file: número de hits", expected.length(), actual.size)
        for (i in 0 until expected.length()) {
            val e = expected.getJSONObject(i)
            assertEquals("$file hit$i id", e.getInt("id"), actual[i].comboId)
            assertTrue("$file hit$i score ${actual[i].score} vs ${e.getDouble("score")}",
                abs(actual[i].score - e.getDouble("score")) <= tol)
        }
    }

    @Test
    fun versionYdiccionarioCoincidenConElMotor() {
        assertEquals("0.1.0", colorEngineVersion)
        assertEquals(159, WadaEngineDictionary.colorCount)
        assertEquals(348, WadaEngineDictionary.comboCount)
        assertTrue(dictionaryVersion.isNotEmpty())
        assertTrue(colorEngineContextSize in 1..(2L * 1024 * 1024))
    }

    @Test
    fun goldensDePaleta20() {
        val doc = JSONObject(assetText("palettes_20.json"))
        assertEquals(dictionaryVersion, doc.getString("dict_version"))
        val entries = doc.getJSONArray("entries")
        assertEquals(20, entries.length())
        ColorEngine().use { engine ->
            for (i in 0 until entries.length()) {
                val e = entries.getJSONObject(i)
                val file = e.getString("file")
                val image = readPpm("golden/$file")
                val swatches = engine.extractPalette(image, paletteOptions(e.optJSONObject("opts")))
                assertSwatches(file, e.getJSONArray("swatches"), swatches)
                assertEquals("$file: hash", e.getString("hash"), hexHash(ColorMath.swatchHash(swatches)))
            }
        }
    }

    @Test
    fun goldensDeMatch50() {
        val doc = JSONObject(assetText("match_50.json"))
        assertEquals(dictionaryVersion, doc.getString("dict_version"))
        val entries = doc.getJSONArray("entries")
        assertEquals(50, entries.length())
        ColorEngine().use { engine ->
            for (i in 0 until entries.length()) {
                val e = entries.getJSONObject(i)
                val file = e.getString("file")
                val opts = e.getJSONObject("opts")
                val image = readPpm("golden/$file")
                val result = engine.analyze(
                    image, paletteOptions(opts.getJSONObject("palette")),
                    matchOptions(opts.getJSONObject("match")), topK = 3,
                )
                assertSwatches(file, e.getJSONArray("swatches"), result.swatches)
                assertHits(file, e.getJSONArray("hits"), result.hits)
                assertEquals("$file: ambiguous", e.getInt("ambiguous") != 0, result.ambiguous)
                assertEquals("$file: hash", e.getString("hash"), hexHash(result.hash))
            }
        }
    }

    @Test
    fun fixturesDeParidadWasm20() {
        val doc = JSONObject(assetText("wasm_expected.json"))
        assertEquals(dictionaryVersion, doc.getString("dict_version"))
        val entries = doc.getJSONArray("entries")
        assertEquals(20, entries.length())
        ColorEngine().use { engine ->
            for (i in 0 until entries.length()) {
                val e = entries.getJSONObject(i)
                val file = e.getString("file")
                val (po, mo) = opcionesDesdeArgs(e)
                val image = readPpm("wasm/$file")
                assertEquals("$file: ancho", e.getInt("width"), image.width)
                assertEquals("$file: alto", e.getInt("height"), image.height)
                val result = engine.analyze(image, po, mo, topK = 3)
                assertSwatches(file, e.getJSONArray("swatches"), result.swatches)
                assertHits(file, e.getJSONArray("hits"), result.hits)
                assertEquals("$file: ambiguous", e.getInt("ambiguous") != 0, result.ambiguous)
                assertEquals("$file: hash", e.getString("hash"), hexHash(result.hash))
            }
        }
    }

    /** Traduce los args del manifest WASM (flags del CLI ce) a opciones Kotlin. */
    private fun opcionesDesdeArgs(entry: JSONObject): Pair<PaletteOptions, MatchOptions> {
        var po = PaletteOptions.DEFAULT
        var mo = MatchOptions.DEFAULT
        val args = entry.optJSONArray("args") ?: return po to mo
        var i = 0
        while (i < args.length()) {
            val flag = args.getString(i)
            val value = if (i + 1 < args.length()) args.getString(i + 1).toDouble() else 0.0
            when (flag) {
                "--coverage-lambda" -> mo = mo.copy(coverageLambda = value)
                "--ambiguous-gap" -> mo = mo.copy(ambiguousGap = value)
                "--center-sigma" -> po = po.copy(centerSigma = value)
                "--kL" -> mo = mo.copy(kL = value)
                "--kC" -> mo = mo.copy(kC = value)
                "--kH" -> mo = mo.copy(kH = value)
                else -> fail("arg no soportado en el test: $flag (${entry.getString("file")})")
            }
            i += 2
        }
        return po to mo
    }
}
