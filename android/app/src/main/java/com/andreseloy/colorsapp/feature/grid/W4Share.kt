// Compartir de W4 (tarjeta de combinación, capas y diagnósticos): escribe
// en cacheDir/share y lanza ACTION_SEND con FileProvider. Sin red, como
// UIActivityViewController en iOS. Solo empaqueta ARGB ya calculados por
// el motor: nada de lógica de color aquí.
package com.andreseloy.colorsapp.feature.grid

import android.content.ClipData
import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Paint
import androidx.core.content.FileProvider
import java.io.File

/** Guarda bytes compartibles y devuelve su Uri de contenido. */
fun writeShareFile(context: Context, name: String, bytes: ByteArray): android.net.Uri {
    val dir = File(context.cacheDir, "share").apply { mkdirs() }
    val file = File(dir, name)
    file.writeBytes(bytes)
    return FileProvider.getUriForFile(context, "${context.packageName}.fileprovider", file)
}

fun bitmapToPng(bitmap: Bitmap): ByteArray {
    val out = java.io.ByteArrayOutputStream()
    bitmap.compress(Bitmap.CompressFormat.PNG, 100, out)
    return out.toByteArray()
}

fun shareFile(context: Context, uri: android.net.Uri, mime: String, chooserTitle: String, text: String? = null) {
    val intent = Intent(Intent.ACTION_SEND).apply {
        type = mime
        putExtra(Intent.EXTRA_STREAM, uri)
        if (text != null) putExtra(Intent.EXTRA_TEXT, text)
        clipData = ClipData.newRawUri(null, uri)
        addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
    }
    context.startActivity(Intent.createChooser(intent, chooserTitle).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
}

fun shareBitmap(context: Context, bitmap: Bitmap, fileName: String, chooserTitle: String, text: String? = null) {
    shareFile(context, writeShareFile(context, fileName, bitmapToPng(bitmap)), "image/png", chooserTitle, text)
}

/** Tarjeta de la combinación (Views/Tarjeta en iOS): tira de color + título. */
fun renderComboCard(title: String, subtitle: String, argbColors: List<Int>, hexes: List<String>): Bitmap {
    val w = 1080; val h = 1350
    val bmp = Bitmap.createBitmap(w, h, Bitmap.Config.ARGB_8888)
    val canvas = Canvas(bmp)
    val paint = Paint(Paint.ANTI_ALIAS_FLAG)
    paint.color = 0xFFF7EEDD.toInt(); canvas.drawRect(0f, 0f, w.toFloat(), h.toFloat(), paint)
    paint.color = 0xFFECEAE6.toInt(); canvas.drawRoundRect(60f, 60f, w - 60f, 900f, 32f, 32f, paint)
    val stripX = 92f; val stripW = w - 184f; val seg = if (argbColors.isEmpty()) stripW else stripW / argbColors.size
    argbColors.forEachIndexed { i, argb ->
        paint.color = argb
        canvas.drawRect(stripX + i * seg + 2f, 92f, stripX + (i + 1) * seg - 2f, 868f, paint)
    }
    paint.color = 0xFF2D5A3C.toInt(); paint.textSize = 64f; paint.isFakeBoldText = true
    canvas.drawText(title.take(28), 60f, 1010f, paint)
    paint.isFakeBoldText = false; paint.color = 0xFF6B6257.toInt(); paint.textSize = 40f
    canvas.drawText(subtitle.take(40), 60f, 1075f, paint)
    paint.textSize = 34f
    canvas.drawText(hexes.joinToString("  ").take(52), 60f, 1145f, paint)
    paint.color = 0xFF2D5A3C.toInt(); paint.textSize = 44f
    canvas.drawText("ChromaSol", 60f, 1270f, paint)
    return bmp
}
