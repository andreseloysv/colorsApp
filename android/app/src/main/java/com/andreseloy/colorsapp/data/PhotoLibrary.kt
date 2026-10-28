// Fuente de fotos del carrete: la versión Android de PhotoKit. La ola 2 la
// implementa con el selector de fotos (Photo Picker, sin permiso) para
// "foto elegida" y con MediaStore + READ_MEDIA_IMAGES (o acceso limitado
// READ_MEDIA_VISUAL_USER_SELECTED en API 34+) para el escaneo del carrete.
// Ninguna foto sale del dispositivo: todo devuelve Bitmap locales.
package com.andreseloy.colorsapp.data

import android.graphics.Bitmap
import android.net.Uri

/** Una foto del carrete (PHAsset en iOS). */
data class LibraryPhoto(
    /** Identificador estable: Uri de MediaStore como texto (scans.asset_id). */
    val id: String,
    val uri: Uri,
    val dateTakenMs: Long,
    val width: Int,
    val height: Int,
)

/** Nivel de acceso al carrete (PHAuthorizationStatus en iOS). */
enum class LibraryAccess { FULL, LIMITED, DENIED, NOT_DETERMINED }

interface PhotoLibrarySource {
    /** Nivel de acceso actual sin pedir permiso. */
    fun access(): LibraryAccess

    /** Últimas [limit] fotos por fecha descendente (fetchLimit de PhotoKit). */
    suspend fun recentPhotos(limit: Int): List<LibraryPhoto>

    /**
     * Decodifica la foto a un Bitmap sRGB de lado <= [maxSide] (1024: el
     * raster del motor), con la orientación EXIF aplicada. Null si no se
     * puede leer sin red (en Android no hay iCloud: null = corrupta/borrada).
     */
    suspend fun loadBitmap(photo: LibraryPhoto, maxSide: Int = 1024): Bitmap?

    /** Miniatura para listas (lado <= [maxSide], 256 en el escaneo de iOS). */
    suspend fun loadThumbnail(photo: LibraryPhoto, maxSide: Int = 256): Bitmap?
}

/** Sustituto inerte de la fundación. */
class EmptyPhotoLibrarySource : PhotoLibrarySource {
    override fun access() = LibraryAccess.NOT_DETERMINED
    override suspend fun recentPhotos(limit: Int) = emptyList<LibraryPhoto>()
    override suspend fun loadBitmap(photo: LibraryPhoto, maxSide: Int): Bitmap? = null
    override suspend fun loadThumbnail(photo: LibraryPhoto, maxSide: Int): Bitmap? = null
}
