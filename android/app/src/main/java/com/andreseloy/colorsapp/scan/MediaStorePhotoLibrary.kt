// Fuente de fotos del carrete con MediaStore: la versión Android de
// PhotoKit para PhotoLibrarySource (contrato de la fundación, data/).
// Permisos, los mínimos y pedidos en contexto por la UI (nunca al arrancar):
// READ_MEDIA_IMAGES (API 33+), READ_MEDIA_VISUAL_USER_SELECTED para el
// acceso limitado (API 34+) y READ_EXTERNAL_STORAGE solo hasta API 32.
// El selector de fotos del sistema no necesita permiso (lo usa la UI).
// Decodificación sRGB con la orientación EXIF aplicada por ImageDecoder y
// un solo escalado a <= maxSide (el raster que ve el motor).
package com.andreseloy.colorsapp.scan

import android.Manifest
import android.content.ContentResolver
import android.content.ContentUris
import android.content.Context
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.ImageDecoder
import android.os.Build
import android.os.Bundle
import android.provider.MediaStore
import android.util.Size
import androidx.core.content.ContextCompat
import com.andreseloy.colorsapp.data.LibraryAccess
import com.andreseloy.colorsapp.data.LibraryPhoto
import com.andreseloy.colorsapp.data.PhotoLibrarySource
import com.andreseloy.colorsapp.subject.SubjectRaster
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

/** Permisos de fotos según la API (la UI los pide en su momento). */
object PhotoPermissions {
    const val READ_MEDIA_IMAGES = Manifest.permission.READ_MEDIA_IMAGES
    const val READ_MEDIA_VISUAL_USER_SELECTED = "android.permission.READ_MEDIA_VISUAL_USER_SELECTED"
    const val READ_EXTERNAL_STORAGE = Manifest.permission.READ_EXTERNAL_STORAGE
    const val CAMERA = Manifest.permission.CAMERA

    /** Permisos a pedir para escanear el carrete en este dispositivo. */
    fun libraryPermissions(): Array<String> = when {
        Build.VERSION.SDK_INT >= 34 -> arrayOf(READ_MEDIA_IMAGES, READ_MEDIA_VISUAL_USER_SELECTED)
        Build.VERSION.SDK_INT >= 33 -> arrayOf(READ_MEDIA_IMAGES)
        else -> arrayOf(READ_EXTERNAL_STORAGE)
    }

    fun isGranted(context: Context, permission: String): Boolean =
        ContextCompat.checkSelfPermission(context, permission) == PackageManager.PERMISSION_GRANTED
}

class MediaStorePhotoLibrarySource(
    private val context: Context,
) : PhotoLibrarySource {

    private val resolver: ContentResolver get() = context.contentResolver

    override fun access(): LibraryAccess {
        val full = when {
            Build.VERSION.SDK_INT >= 33 ->
                PhotoPermissions.isGranted(context, PhotoPermissions.READ_MEDIA_IMAGES)
            else ->
                PhotoPermissions.isGranted(context, PhotoPermissions.READ_EXTERNAL_STORAGE)
        }
        if (full) return LibraryAccess.FULL
        if (Build.VERSION.SDK_INT >= 34 &&
            PhotoPermissions.isGranted(context, PhotoPermissions.READ_MEDIA_VISUAL_USER_SELECTED)
        ) {
            return LibraryAccess.LIMITED
        }
        // Sin Activity no se distingue "nunca pedido" de "denegado": la UI
        // pide el permiso y su resultado decide (como el .notDetermined inicial).
        return LibraryAccess.NOT_DETERMINED
    }

    override suspend fun recentPhotos(limit: Int): List<LibraryPhoto> = withContext(Dispatchers.IO) {
        if (limit <= 0) return@withContext emptyList()
        val projection = arrayOf(
            MediaStore.Images.Media._ID,
            MediaStore.Images.Media.DATE_TAKEN,
            MediaStore.Images.Media.DATE_ADDED,
            MediaStore.Images.Media.WIDTH,
            MediaStore.Images.Media.HEIGHT,
        )
        val sort = "${MediaStore.Images.Media.DATE_TAKEN} DESC, ${MediaStore.Images.Media.DATE_ADDED} DESC"
        val cursor = if (Build.VERSION.SDK_INT >= 30) {
            val args = Bundle().apply {
                putStringArray(ContentResolver.QUERY_ARG_SORT_COLUMNS, arrayOf(MediaStore.Images.Media.DATE_TAKEN, MediaStore.Images.Media.DATE_ADDED))
                putInt(ContentResolver.QUERY_ARG_SORT_DIRECTION, ContentResolver.QUERY_SORT_DIRECTION_DESCENDING)
                putInt(ContentResolver.QUERY_ARG_LIMIT, limit)
            }
            runCatching {
                resolver.query(MediaStore.Images.Media.EXTERNAL_CONTENT_URI, projection, args, null)
            }.getOrNull() ?: resolver.query(
                MediaStore.Images.Media.EXTERNAL_CONTENT_URI, projection, null, null, sort,
            )
        } else {
            resolver.query(MediaStore.Images.Media.EXTERNAL_CONTENT_URI, projection, null, null, sort)
        }
        val out = ArrayList<LibraryPhoto>()
        cursor?.use { c ->
            val idCol = c.getColumnIndexOrThrow(MediaStore.Images.Media._ID)
            val takenCol = c.getColumnIndex(MediaStore.Images.Media.DATE_TAKEN)
            val addedCol = c.getColumnIndex(MediaStore.Images.Media.DATE_ADDED)
            val wCol = c.getColumnIndex(MediaStore.Images.Media.WIDTH)
            val hCol = c.getColumnIndex(MediaStore.Images.Media.HEIGHT)
            while (c.moveToNext() && out.size < limit) {
                val id = c.getLong(idCol)
                val uri = ContentUris.withAppendedId(MediaStore.Images.Media.EXTERNAL_CONTENT_URI, id)
                var taken = if (takenCol >= 0) c.getLong(takenCol) else 0L
                if (taken <= 0 && addedCol >= 0) taken = c.getLong(addedCol) * 1000
                out.add(
                    LibraryPhoto(
                        id = uri.toString(), uri = uri, dateTakenMs = taken,
                        width = if (wCol >= 0) c.getInt(wCol) else 0,
                        height = if (hCol >= 0) c.getInt(hCol) else 0,
                    ),
                )
            }
        }
        out
    }

    override suspend fun loadBitmap(photo: LibraryPhoto, maxSide: Int): Bitmap? =
        withContext(Dispatchers.IO) {
            runCatching {
                if (Build.VERSION.SDK_INT >= 28) decode28(photo, maxSide) else decodeLegacy(photo, maxSide)
            }.getOrNull()
        }

    @androidx.annotation.RequiresApi(28)
    private fun decode28(photo: LibraryPhoto, maxSide: Int): Bitmap {
        val source = ImageDecoder.createSource(resolver, photo.uri)
        return ImageDecoder.decodeBitmap(source) { decoder, info, _ ->
            decoder.allocator = ImageDecoder.ALLOCATOR_SOFTWARE
            val (w, h) = SubjectRaster.targetSize(info.size.width, info.size.height, maxSide)
            if (w != info.size.width || h != info.size.height) {
                decoder.setTargetSize(w, h)
            }
        }
    }

    /** API 26-27: BitmapFactory con muestreo + rotación EXIF a mano. */
    private fun decodeLegacy(photo: LibraryPhoto, maxSide: Int): Bitmap? {
        val bounds = android.graphics.BitmapFactory.Options().apply { inJustDecodeBounds = true }
        resolver.openInputStream(photo.uri)?.use {
            android.graphics.BitmapFactory.decodeStream(it, null, bounds)
        } ?: return null
        if (bounds.outWidth < 1 || bounds.outHeight < 1) return null
        var sample = 1
        while (maxOf(bounds.outWidth, bounds.outHeight) / (sample * 2) >= maxSide) sample *= 2
        val opts = android.graphics.BitmapFactory.Options().apply { inSampleSize = sample }
        var bmp = resolver.openInputStream(photo.uri)?.use {
            android.graphics.BitmapFactory.decodeStream(it, null, opts)
        } ?: return null
        val rotation = runCatching {
            resolver.openInputStream(photo.uri)?.use { stream ->
                when (
                    android.media.ExifInterface(stream)
                        .getAttributeInt(android.media.ExifInterface.TAG_ORIENTATION, 1)
                ) {
                    android.media.ExifInterface.ORIENTATION_ROTATE_90 -> 90f
                    android.media.ExifInterface.ORIENTATION_ROTATE_180 -> 180f
                    android.media.ExifInterface.ORIENTATION_ROTATE_270 -> 270f
                    else -> 0f
                }
            } ?: 0f
        }.getOrDefault(0f)
        if (rotation != 0f) {
            val matrix = android.graphics.Matrix().apply { postRotate(rotation) }
            bmp = Bitmap.createBitmap(bmp, 0, 0, bmp.width, bmp.height, matrix, true)
        }
        val (w, h) = SubjectRaster.targetSize(bmp.width, bmp.height, maxSide)
        return SubjectRaster.scaleTo(bmp, w, h)
    }

    override suspend fun loadThumbnail(photo: LibraryPhoto, maxSide: Int): Bitmap? =
        withContext(Dispatchers.IO) {
            if (Build.VERSION.SDK_INT >= 29) {
                runCatching {
                    resolver.loadThumbnail(photo.uri, Size(maxSide, maxSide), null)
                }.getOrNull()?.let { thumb ->
                    // loadThumbnail puede devolver <= el tamaño pedido ya
                    // orientada; se normaliza al mismo criterio targetSize.
                    val (w, h) = SubjectRaster.targetSize(thumb.width, thumb.height, maxSide)
                    return@withContext SubjectRaster.scaleTo(thumb, w, h)
                }
            }
            loadBitmap(photo, maxSide)
        }
}
