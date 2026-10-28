// Pruebas de comportamiento de la API Kotlin sobre el motor real (emulador):
// conversiones puntuales, diccionario, caminos de error, máscaras, prendas y
// capas. La paridad numérica bit a bit vive en EngineParityTest.
package com.andreseloy.colorsapp.engine

import androidx.test.ext.junit.runners.AndroidJUnit4
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import kotlin.math.abs

@RunWith(AndroidJUnit4::class)
class ColorEngineTest {

    private fun solidImage(r: Int, g: Int, b: Int, w: Int = 16, h: Int = 16): EngineImage {
        val px = ByteArray(w * h * 3)
        for (i in 0 until w * h) {
            px[i * 3] = r.toByte()
            px[i * 3 + 1] = g.toByte()
            px[i * 3 + 2] = b.toByte()
        }
        return EngineImage(px, w, h, w * 3, PixelFormat.RGB8)
    }

    @Test
    fun blancoEsLab100() {
        val lab = ColorMath.srgbToLab(255, 255, 255)
        assertTrue(abs(lab.l - 100.0) < 1e-9)
        assertTrue(abs(lab.a) < 1e-9 && abs(lab.b) < 1e-9)
        val negro = ColorMath.srgbToLab(0, 0, 0)
        assertTrue(abs(negro.l) < 1e-12)
    }

    @Test
    fun deltaEIdentidadYSimetria() {
        val x = ColorMath.srgbToLab(187, 113, 37)
        val y = ColorMath.srgbToLab(20, 80, 200)
        assertEquals(0.0, ColorMath.deltaE2000(x, x), 1e-12)
        assertEquals(ColorMath.deltaE2000(x, y), ColorMath.deltaE2000(y, x), 1e-12)
        assertTrue(ColorMath.deltaE2000(x, y) > 20.0)
        assertTrue(ColorMath.deltaE76(x, y) > 0.0)
    }

    @Test
    fun diccionarioBasico() {
        assertEquals("Hermosa Pink", WadaEngineDictionary.colorName(0))
        assertNull(WadaEngineDictionary.colorName(159))
        assertNull(WadaEngineDictionary.colorRgb(-1))
        assertNull(WadaEngineDictionary.combo(0))
        assertNull(WadaEngineDictionary.combo(349))
        val combo4 = WadaEngineDictionary.combo(4)
        assertNotNull(combo4)
        assertArrayEquals(intArrayOf(50, 150), combo4)
        val rgb = WadaEngineDictionary.colorRgb(50)!!
        val lab = ColorMath.srgbToLab(rgb[0], rgb[1], rgb[2])
        val (nearest, de) = WadaEngineDictionary.nearestColor(lab)
        assertEquals(50, nearest)
        assertEquals(0.0, de, 1e-9)
    }

    @Test
    fun paletaDeUnColorSolido() {
        ColorEngine().use { engine ->
            val swatches = engine.extractPalette(solidImage(128, 128, 128))
            assertEquals(1, swatches.size)
            assertEquals("#808080", swatches[0].hex)
            assertEquals(1.0, swatches[0].weight, 1e-12)
        }
    }

    @Test
    fun analizarDevuelveTopKYPesosQueSumanUno() {
        ColorEngine().use { engine ->
            val result = engine.analyze(solidImage(240, 200, 60), topK = 3)
            assertEquals(3, result.hits.size)
            assertTrue(abs(result.swatches.sumOf { it.weight } - 1.0) < 1e-9)
            assertTrue(result.hits.zipWithNext().all { (a, b) -> a.score <= b.score })
            assertEquals(result.hash, ColorMath.resultHash(result))
        }
    }

    @Test
    fun erroresTipados() {
        ColorEngine().use { engine ->
            val corta = EngineImage(ByteArray(10), 16, 16, 48, PixelFormat.RGB8)
            assertThrowsKind<EngineException.BufferTooSmall> { engine.extractPalette(corta) }
            val conMascaraCorta = EngineImage(
                ByteArray(16 * 16 * 3), 16, 16, 48, PixelFormat.RGB8, ByteArray(3),
            )
            assertThrowsKind<EngineException.MaskTooSmall> { engine.extractPalette(conMascaraCorta) }
            assertThrowsKind<EngineException.Engine> {
                engine.analyze(solidImage(0, 0, 0), topK = 0)
            }
        }
        val cerrado = ColorEngine()
        cerrado.close()
        assertThrowsKind<EngineException.Engine> { cerrado.extractPalette(solidImage(0, 0, 0)) }
    }

    @Test
    fun mascaraTodaACeroDaColorMedio() {
        ColorEngine().use { engine ->
            val image = EngineImage(
                solidImage(200, 40, 40, 8, 8).pixels, 8, 8, 24, PixelFormat.RGB8,
                ByteArray(64),
            )
            val swatches = engine.extractPalette(image)
            assertEquals(1, swatches.size)
            assertEquals(200, swatches[0].r)
        }
    }

    @Test
    fun prendasSinMapaDaUnaRegion() {
        ColorEngine().use { engine ->
            val result = engine.analyzeGarments(solidImage(40, 90, 160, 24, 24))
            assertTrue(result.garments.isNotEmpty())
            assertTrue(result.garments.all { it.region == GarmentRegion.NONE })
            assertEquals(3, result.analysis.hits.size)
        }
    }

    @Test
    fun capasYExplicacion() {
        ColorEngine().use { engine ->
            val layers = engine.analyzeWithLayers(solidImage(180, 90, 30, 32, 32))
            assertEquals(32, layers.debug.reducedWidth)
            assertEquals(32 * 32 * 3, layers.reducedRgb.size)
            assertEquals(32 * 32, layers.labelMap.size)
            assertEquals(layers.analysis.hits.size, layers.explanations.size)
            assertEquals(
                layers.analysis.hits[0].score, layers.explanations[0].score, 1e-12,
            )
        }
    }

    @Test
    fun cutHeadYSplitInstance() {
        val mask = ByteArray(10 * 10) { (255).toByte() }
        val quedan = ColorEngine.cutHead(mask.copyOf(), 10, 10, 0.2)
        assertEquals(80, quedan)
        val (labels, count) = ColorEngine.splitInstance(
            mask, 10, 10,
            listOf(
                PersonSeed(2.5, 0.0, 2.5, 10.0, 3.0),
                PersonSeed(7.5, 0.0, 7.5, 10.0, 3.0),
            ),
        )
        assertEquals(2, count)
        assertEquals(1, labels[0].toInt())
        assertEquals(2, labels[9].toInt())
    }

    private inline fun <reified T : Throwable> assertThrowsKind(block: () -> Unit) {
        try {
            block()
        } catch (t: Throwable) {
            if (t is T) return
            throw AssertionError("se esperaba ${T::class.simpleName}, llegó $t")
        }
        throw AssertionError("se esperaba ${T::class.simpleName}, no se lanzó nada")
    }
}
