// Puente Bitmap -> motor C: espejo de ios/ColorsApp/Engine/EngineBridge.swift.
// Reduce a maxSide (1024 por defecto) conservando el aspecto y copia los
// píxeles a un buffer RGBX8 sRGB empaquetado. Nada de lógica de color: solo
// copiar bytes. La conversión a sRGB la hace BitmapFactory/Bitmap al decodificar
// (ColorSpace sRGB); el escalado usa el filtro bilineal de Android, que NO es
// bit a bit el de CoreGraphics: la paridad garantizada es "mismos píxeles de
// entrada -> mismo resultado" (ver tests de paridad y docs/ANDROID.md).
package com.andreseloy.colorsapp.engine

import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Paint
import kotlin.math.max
import kotlin.math.roundToInt

object EngineRaster {
    /** Lado mayor tras la reducción (PLAN §7: <= 1024 px antes del motor). */
    const val DEFAULT_MAX_SIDE = 1024

    /** Dimensiones tras reducir a [maxSide] conservando aspecto; nunca amplía. */
    fun targetSize(width: Int, height: Int, maxSide: Int): IntArray {
        val longest = max(width, height)
        if (maxSide < 1 || longest <= maxSide) {
            return intArrayOf(max(1, width), max(1, height))
        }
        val scale = maxSide.toDouble() / longest.toDouble()
        return intArrayOf(
            max(1, (width * scale).roundToInt()),
            max(1, (height * scale).roundToInt()),
        )
    }

    /**
     * Rasteriza [bitmap] a un EngineImage RGBX8 (formato RGBX8, stride = w*4).
     * Si hay que escalar, dibuja sobre fondo blanco (como EngineBridge: las
     * zonas transparentes de un PNG quedan blancas, no negras). A escala 1:1
     * copia los píxeles tal cual.
     */
    fun rasterize(bitmap: Bitmap, maxSide: Int = DEFAULT_MAX_SIDE): EngineImage {
        require(bitmap.width >= 1 && bitmap.height >= 1) { "Bitmap vacío" }
        val (tw, th) = targetSize(bitmap.width, bitmap.height, maxSide).let { it[0] to it[1] }
        val source: Bitmap = if (tw == bitmap.width && th == bitmap.height) {
            bitmap
        } else {
            val out = Bitmap.createBitmap(tw, th, Bitmap.Config.ARGB_8888)
            val canvas = Canvas(out)
            canvas.drawColor(0xFFFFFFFF.toInt())
            val paint = Paint(Paint.FILTER_BITMAP_FLAG)
            canvas.drawBitmap(
                bitmap, null,
                android.graphics.Rect(0, 0, tw, th), paint,
            )
            out
        }
        val pixels = IntArray(tw * th)
        source.getPixels(pixels, 0, tw, 0, 0, tw, th)
        if (source !== bitmap) source.recycle()
        val bytes = ByteArray(tw * th * 4)
        for (i in pixels.indices) {
            val p = pixels[i]
            bytes[i * 4] = ((p shr 16) and 0xFF).toByte()
            bytes[i * 4 + 1] = ((p shr 8) and 0xFF).toByte()
            bytes[i * 4 + 2] = (p and 0xFF).toByte()
            bytes[i * 4 + 3] = ((p ushr 24) and 0xFF).toByte()
        }
        return EngineImage(bytes, tw, th, tw * 4, PixelFormat.RGBX8)
    }

    /**
     * Rasteriza una máscara (Bitmap en grises o alpha) a width*height bytes
     * 0..255 sin stride, el formato de ce_image.mask. Se toma el canal rojo
     * del bitmap escalado (las máscaras son grises: r = g = b).
     */
    fun rasterizeMask(bitmap: Bitmap, width: Int, height: Int): ByteArray {
        require(width >= 1 && height >= 1) { "Dimensiones de máscara inválidas" }
        val scaled = if (bitmap.width == width && bitmap.height == height) {
            bitmap
        } else {
            Bitmap.createScaledBitmap(bitmap, width, height, true)
        }
        val pixels = IntArray(width * height)
        scaled.getPixels(pixels, 0, width, 0, 0, width, height)
        if (scaled !== bitmap) scaled.recycle()
        return ByteArray(width * height) { ((pixels[it] shr 16) and 0xFF).toByte() }
    }

    /** Opciones de match que usa la app: alias de MatchOptions.DEFAULT (ADR-009). */
    val appMatchOptions: MatchOptions get() = MatchOptions.DEFAULT
}
