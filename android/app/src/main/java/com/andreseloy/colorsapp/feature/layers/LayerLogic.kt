// Conversión de mapas del motor a píxeles ARGB para el inspector de capas:
// espejo de LayerBitmaps/LayerStack de iOS. Pura (sin Bitmap de Android ni
// lógica de color: solo reempaqueta bytes que ya dio el motor C).
package com.andreseloy.colorsapp.feature.layers

import com.andreseloy.colorsapp.engine.EngineImage
import com.andreseloy.colorsapp.engine.PixelFormat
import com.andreseloy.colorsapp.subject.SubjectMaskResult

/** Entrada del inspector: la pone Extraer (W3) tras analizar; si no hay, se usa el ejemplo. */
object LayerInputHolder {
    @Volatile var image: EngineImage? = null
    @Volatile var subject: SubjectMaskResult? = null
    @Volatile var title: String? = null
    fun set(image: EngineImage, subject: SubjectMaskResult? = null, title: String? = null) {
        this.image = image; this.subject = subject; this.title = title
    }
    fun clear() { image = null; subject = null; title = null }
}

object LayerPixels {
    fun argb(r: Int, g: Int, b: Int): Int = (0xFF shl 24) or (r shl 16) or (g shl 8) or b

    /** RGB8 empaquetado (reducedRgb del motor) a ARGB. */
    fun fromRgb8(bytes: ByteArray, width: Int, height: Int): IntArray {
        val n = width * height; val out = IntArray(n)
        for (i in 0 until n) {
            val o = i * 3
            out[i] = if (o + 2 < bytes.size) argb(bytes[o].toInt() and 0xFF, bytes[o + 1].toInt() and 0xFF, bytes[o + 2].toInt() and 0xFF) else argb(0, 0, 0)
        }
        return out
    }

    /** Mapa de pesos 0..255 a rampa negro→ámbar (falso color de presentación). */
    fun fromWeight(bytes: ByteArray, width: Int, height: Int): IntArray {
        val n = width * height; val out = IntArray(n)
        for (i in 0 until n) {
            val v = if (i < bytes.size) bytes[i].toInt() and 0xFF else 0
            out[i] = argb(v, (v * 3) / 4, v / 8)
        }
        return out
    }

    /** Etiquetas de cluster: cada etiqueta con el ARGB de su swatch; 255 = sin peso (oscuro). */
    fun fromLabels(bytes: ByteArray, width: Int, height: Int, swatchArgb: List<Int>, isolate: Int? = null): IntArray {
        val n = width * height; val out = IntArray(n)
        for (i in 0 until n) {
            val v = if (i < bytes.size) bytes[i].toInt() and 0xFF else 255
            out[i] = when {
                v == 255 || v >= swatchArgb.size && isolate == null -> argb(24, 24, 24)
                isolate != null && v != isolate -> argb(32, 32, 32)
                v < swatchArgb.size -> swatchArgb[v]
                else -> argb(90, 90, 90)
            }
        }
        return out
    }

    /** Máscara 0..255 sobre el fondo: dentro claro, fuera oscuro. */
    fun fromMaskOverRgb(rgb: ByteArray, mask: ByteArray?, width: Int, height: Int): IntArray {
        val base = fromRgb8(rgb, width, height)
        if (mask == null) return base
        for (i in base.indices) {
            val m = if (i < mask.size) mask[i].toInt() and 0xFF else 0
            if (m < 128) {
                val c = base[i]
                base[i] = argb(((c shr 16) and 0xFF) / 4, ((c shr 8) and 0xFF) / 4, (c and 0xFF) / 4)
            }
        }
        return base
    }

    /** Regiones de prenda: 1 arriba (ámbar), 2 abajo (musgo), resto oscuro. */
    fun fromRegions(bytes: ByteArray, width: Int, height: Int): IntArray {
        val n = width * height; val out = IntArray(n)
        for (i in 0 until n) {
            out[i] = when (if (i < bytes.size) bytes[i].toInt() and 0xFF else 0) {
                1 -> argb(217, 164, 65); 2 -> argb(45, 90, 60); else -> argb(20, 20, 20)
            }
        }
        return out
    }

    /** Raster RGBA8/RGB8 de entrada a ARGB (para «Lo que ve el motor»). */
    fun fromEngineImage(image: EngineImage): IntArray {
        val n = image.width * image.height; val out = IntArray(n); val bpp = image.format.bytesPerPixel
        for (y in 0 until image.height) for (x in 0 until image.width) {
            val o = y * image.strideBytes + x * bpp; val i = y * image.width + x
            out[i] = if (o + 2 < image.pixels.size) argb(image.pixels[o].toInt() and 0xFF, image.pixels[o + 1].toInt() and 0xFF, image.pixels[o + 2].toInt() and 0xFF) else argb(0, 0, 0)
        }
        return out
    }

    /** Escena de ejemplo determinista (sin RNG): bloques con los colores dados. */
    fun syntheticDemoImage(width: Int, height: Int, rgbs: List<IntArray>): EngineImage {
        val pixels = ByteArray(width * height * 4)
        val cols = rgbs.ifEmpty { listOf(intArrayOf(180, 60, 50), intArrayOf(50, 90, 160)) }
        for (y in 0 until height) for (x in 0 until width) {
            val band = ((x * cols.size) / width + if (y > height * 2 / 3) 1 else 0) % cols.size
            val c = cols[band]; val o = (y * width + x) * 4
            // Varia la luz por filas para que haya clusters que fusionar.
            val f = 0.85 + 0.15 * ((x + y) % 7) / 6.0
            pixels[o] = (c[0] * f).toInt().coerceIn(0, 255).toByte()
            pixels[o + 1] = (c[1] * f).toInt().coerceIn(0, 255).toByte()
            pixels[o + 2] = (c[2] * f).toInt().coerceIn(0, 255).toByte()
            pixels[o + 3] = 255.toByte()
        }
        return EngineImage(pixels, width, height, width * 4, PixelFormat.RGBA8, null)
    }
}
