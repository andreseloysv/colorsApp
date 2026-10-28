// Raster que ve el motor y ve el detector: el mismo buffer sRGB de lado
// <=1024 que en iOS (EngineBridge/SubjectRaster.targetSize). Android
// decodifica con BitmapFactory/ImageDecoder a sRGB; aquí se convierte entre
// Bitmap ARGB_8888 y el EngineImage RGBA8 del motor sin lógica de color
// (solo empaquetado de bytes y un escalado bilineal de Canvas, el
// equivalente documentado en docs/ANDROID.md §6).
package com.andreseloy.colorsapp.subject

import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import com.andreseloy.colorsapp.engine.EngineImage
import com.andreseloy.colorsapp.engine.PixelFormat
import java.nio.ByteBuffer
import kotlin.math.max
import kotlin.math.roundToInt

object SubjectRaster {
    /** Lado mayor del raster del motor (SubjectRaster.defaultMaxSide). */
    const val DEFAULT_MAX_SIDE = 1024

    /** Dimensiones tras reducir a maxSide conservando el aspecto (nunca amplía). */
    fun targetSize(width: Int, height: Int, maxSide: Int): Pair<Int, Int> {
        val longest = max(width, height)
        if (maxSide < 1 || longest <= maxSide) return max(1, width) to max(1, height)
        val scale = maxSide.toDouble() / longest
        return max(1, (width * scale).roundToInt()) to max(1, (height * scale).roundToInt())
    }

    /** Bitmap -> EngineImage RGBA8 (stride = width*4), reduciendo a maxSide. */
    fun engineImage(bitmap: Bitmap, maxSide: Int = DEFAULT_MAX_SIDE): EngineImage {
        val (w, h) = targetSize(bitmap.width, bitmap.height, maxSide)
        val scaled = scaleTo(bitmap, w, h)
        val pixels = IntArray(w * h)
        scaled.getPixels(pixels, 0, w, 0, 0, w, h)
        val bytes = ByteArray(w * h * 4)
        for (i in pixels.indices) {
            val c = pixels[i]
            bytes[i * 4] = Color.red(c).toByte()
            bytes[i * 4 + 1] = Color.green(c).toByte()
            bytes[i * 4 + 2] = Color.blue(c).toByte()
            bytes[i * 4 + 3] = -1
        }
        if (scaled !== bitmap) scaled.recycle()
        return EngineImage(bytes, w, h, w * 4, PixelFormat.RGBA8)
    }

    /** EngineImage -> Bitmap ARGB_8888 (para MediaPipe y para pintar capas). */
    fun bitmapFrom(image: EngineImage): Bitmap {
        val bmp = Bitmap.createBitmap(image.width, image.height, Bitmap.Config.ARGB_8888)
        val buf = ByteBuffer.allocate(image.width * image.height * 4)
        val bpp = image.format.bytesPerPixel
        for (y in 0 until image.height) {
            val row = y * image.strideBytes
            for (x in 0 until image.width) {
                val s = row + x * bpp
                buf.put(image.pixels[s])
                buf.put(image.pixels[s + 1])
                buf.put(image.pixels[s + 2])
                buf.put(-1)
            }
        }
        buf.rewind()
        bmp.copyPixelsFromBuffer(buf)
        return bmp
    }

    /** Escala con Canvas bilineal sobre fondo blanco, como el dibujo de iOS. */
    fun scaleTo(bitmap: Bitmap, w: Int, h: Int): Bitmap {
        if (bitmap.width == w && bitmap.height == h) return bitmap
        val out = Bitmap.createBitmap(w, h, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(out)
        canvas.drawColor(Color.WHITE)
        val paint = Paint(Paint.FILTER_BITMAP_FLAG)
        canvas.drawBitmap(
            bitmap,
            android.graphics.Rect(0, 0, bitmap.width, bitmap.height),
            android.graphics.Rect(0, 0, w, h),
            paint,
        )
        return out
    }

    /** Bitmap gris desde una máscara 0..255 (para depurar/capturar capas). */
    fun maskBitmap(mask: MaskBuffer): Bitmap {
        val bmp = Bitmap.createBitmap(mask.width, mask.height, Bitmap.Config.ARGB_8888)
        val pixels = IntArray(mask.width * mask.height)
        for (i in pixels.indices) {
            val v = MaskOps.u(mask.bytes[i])
            pixels[i] = Color.rgb(v, v, v)
        }
        bmp.setPixels(pixels, 0, mask.width, 0, 0, mask.width, mask.height)
        return bmp
    }
}
