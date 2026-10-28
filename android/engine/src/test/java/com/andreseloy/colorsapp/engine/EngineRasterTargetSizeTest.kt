// Tests de host (sin librería nativa): solo helpers puros de Kotlin.
// La paridad numérica se comprueba en el emulador (EngineParityTest).
package com.andreseloy.colorsapp.engine

import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Test

class EngineRasterTargetSizeTest {

    @Test
    fun sinAmpliarNunca() {
        assertArrayEquals(intArrayOf(100, 50), EngineRaster.targetSize(100, 50, 1024))
        assertArrayEquals(intArrayOf(1024, 512), EngineRaster.targetSize(1024, 512, 1024))
    }

    @Test
    fun reduceConservandoAspecto() {
        // Igual que EngineBridge.targetSize del Swift: escala = maxSide / lado mayor.
        assertArrayEquals(intArrayOf(1024, 768), EngineRaster.targetSize(4032, 3024, 1024))
        assertArrayEquals(intArrayOf(768, 1024), EngineRaster.targetSize(3024, 4032, 1024))
        assertArrayEquals(intArrayOf(256, 256), EngineRaster.targetSize(512, 512, 256))
    }

    @Test
    fun minimoUnPixel() {
        assertArrayEquals(intArrayOf(1024, 1), EngineRaster.targetSize(10000, 3, 1024))
    }

    @Test
    fun swatchHexYArgbSoloFormato() {
        val s = Swatch(Lab(50.0, 0.0, 0.0), 0xBB, 0x71, 0x25, 0.5)
        assertEquals("#bb7125", s.hex)
        assertEquals(0xFFBB7125.toInt(), s.argb)
    }

    @Test
    fun posePlanaEnOrdenCeJoint() {
        val pose = Pose().with(Joint.NOSE, Keypoint(1.0, 2.0, 0.9))
        val flat = pose.toNative()
        assertEquals(45, flat.size)
        assertEquals(1.0, flat[0], 0.0)
        assertEquals(2.0, flat[1], 0.0)
        assertEquals(0.9, flat[2], 0.0)
        assertEquals(15, Joint.entries.size)
    }
}
