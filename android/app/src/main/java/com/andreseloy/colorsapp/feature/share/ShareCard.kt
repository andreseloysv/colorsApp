// Tarjeta compartible: espejo de Views/Tarjeta/ShareCardView.swift +
// ShareCardSheet.swift. Marco pergamino siempre en claro, foto, paleta y
// combinacion en pocillos neutros y nombre en Literata. Dos formatos:
// publicacion 4:5 (1080x1350 px) e historia 9:16 (1080x1920 px), dibujados
// en el telefono a escala 3 (360x450 / 360x640 dp con densidad 3). Nada sale
// sin la accion del usuario: la hoja ensena la vista previa y el boton
// abre el ACTION_SEND del sistema con el PNG (FileProvider, sin red).
package com.andreseloy.colorsapp.feature.share

import android.app.Activity
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.Canvas
import android.view.View
import android.view.ViewGroup
import android.widget.FrameLayout
import androidx.activity.ComponentActivity
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.ComposeView
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.Density
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import androidx.core.content.FileProvider
import androidx.lifecycle.setViewTreeLifecycleOwner
import androidx.lifecycle.setViewTreeViewModelStoreOwner
import androidx.savedstate.setViewTreeSavedStateRegistryOwner
import com.andreseloy.colorsapp.R
import com.andreseloy.colorsapp.data.ScanRecord
import com.andreseloy.colorsapp.data.WadaDictionary
import com.andreseloy.colorsapp.design.ChromaSolTheme
import com.andreseloy.colorsapp.design.JakartaFamily
import com.andreseloy.colorsapp.design.LiterataFamily
import com.andreseloy.colorsapp.design.SolarHeader
import com.andreseloy.colorsapp.design.SolarHeaderButton
import com.andreseloy.colorsapp.design.SolarIconLeaf
import com.andreseloy.colorsapp.design.SolarPrimaryButton
import com.andreseloy.colorsapp.design.SolarRadius
import com.andreseloy.colorsapp.design.SolarSpacing
import com.andreseloy.colorsapp.design.SolarTheme
import com.andreseloy.colorsapp.design.SwatchStrip
import com.andreseloy.colorsapp.design.WellContainer
import com.andreseloy.colorsapp.design.solarPress
import com.andreseloy.colorsapp.feature.extract.PaletteColor
import com.andreseloy.colorsapp.feature.extract.ScanJson
import com.andreseloy.colorsapp.feature.extract.comboSubtitle
import com.andreseloy.colorsapp.feature.extract.garmentShortLabel
import com.andreseloy.colorsapp.feature.extract.numberLabel
import com.andreseloy.colorsapp.feature.extract.percentText
import com.andreseloy.colorsapp.feature.feed.FeedComboName
import com.andreseloy.colorsapp.design.SolarIconClose
import com.andreseloy.colorsapp.design.SolarIconShare
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import kotlin.coroutines.resume
import java.io.File

/** Formato de la tarjeta (ShareCardFormat de iOS). */
enum class ShareFormat(val widthDp: Int, val heightDp: Int) {
    POST(360, 450),
    STORY(360, 640),
    ;

    val pixelLabel: String get() = "${widthDp * RENDER_SCALE} × ${heightDp * RENDER_SCALE}"

    companion object {
        const val RENDER_SCALE = 3
    }
}

/** Datos ya resueltos que pinta la tarjeta (ShareCardView de iOS). */
class ShareCardData(
    val photo: Bitmap?,
    val palette: List<PaletteColor>,
    val comboColors: List<PaletteColor>,
    val title: String,
    val number: String,
    val subtitle: String,
    val displayName: String?,
)

object ShareCardFactory {
    /** Tarjeta de un scan guardado con su foto si esta disponible. */
    fun dataFor(
        scan: ScanRecord,
        photo: Bitmap?,
        dictionary: WadaDictionary,
        resources: android.content.res.Resources,
    ): ShareCardData {
        val garments = ScanJson.decodeGarments(scan.garmentsJson)
        val palette: List<PaletteColor> = if (garments.isNotEmpty()) {
            garments.mapIndexedNotNull { i, e ->
                PaletteColor.fromHex(
                    i, e.hex, name = garmentShortLabel(resources, e.region), weight = e.weight,
                )
            }
        } else {
            ScanJson.decodePalette(scan.paletteJson).mapIndexedNotNull { i, e ->
                PaletteColor.fromHex(i, e.hex, weight = e.weight)
                    ?.namedByNearestWada(dictionary)
            }
        }
        val comboId = scan.top1
        val combo = comboId?.let { dictionary.combo(it) }
        return ShareCardData(
            photo = photo,
            palette = palette,
            comboColors = comboId?.let { PaletteColor.combo(it, dictionary) } ?: emptyList(),
            title = comboId?.let { dictionary.curatedName(it) ?: numberLabel(resources, it) }
                ?: resources.getString(R.string.w3_no_result),
            number = comboId?.let { numberLabel(resources, it) } ?: "—",
            subtitle = combo?.let {
                val count = if (it.size == 1) {
                    resources.getString(R.string.w3_color_count_one_fmt, it.size)
                } else {
                    resources.getString(R.string.w3_colors_count, it.size)
                }
                "${numberLabel(resources, it.id)} · $count"
            } ?: "",
            displayName = comboId?.let { FeedComboName.name(it, dictionary) },
        )
    }
}

/** La tarjeta en claro, en sus puntos exactos (360 x 450/640). */
@Composable
fun ShareCardContent(data: ShareCardData, format: ShareFormat, modifier: Modifier = Modifier) {
    val colors = SolarTheme.colors
    val photoHeight = if (format == ShareFormat.POST) 176.dp else 250.dp
    val gap = if (format == ShareFormat.POST) 10.dp else 12.dp
    val stripHeight = if (format == ShareFormat.POST) 34.dp else 44.dp
    val nameSize = if (format == ShareFormat.POST) 22.sp else 26.sp
    Box(
        modifier
            .width(format.widthDp.dp)
            .height(format.heightDp.dp)
            .background(colors.surface),
    ) {
        // Lavados de esquina, lejos de los pocillos.
        Box(
            Modifier.size(200.dp).align(Alignment.TopEnd)
                .clip(CircleShape).background(colors.washWarm),
        )
        Box(
            Modifier.size(180.dp).align(Alignment.BottomStart)
                .clip(CircleShape).background(colors.washGreen),
        )
        Column(
            Modifier.fillMaxSize().padding(horizontal = 18.dp).padding(top = 18.dp, bottom = 14.dp),
        ) {
            // Marca
            Row(
                Modifier.fillMaxWidth(),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                Image(
                    painter = painterResource(R.drawable.brand_mark), contentDescription = null,
                    modifier = Modifier.size(26.dp).clip(RoundedCornerShape(6.dp)),
                )
                Text(
                    stringResource(R.string.app_name),
                    style = TextStyle(
                        fontFamily = LiterataFamily, fontWeight = FontWeight.Medium,
                        fontSize = 19.sp,
                    ),
                    color = colors.primary,
                )
                Box(Modifier.weight(1f))
                Text(
                    stringResource(R.string.w3_wada_number, data.number).uppercase(),
                    style = TextStyle(
                        fontFamily = JakartaFamily, fontWeight = FontWeight.Bold, fontSize = 11.sp,
                        letterSpacing = 1.1.sp,
                    ),
                    color = colors.secondary,
                )
            }
            Box(Modifier.height(10.dp))
            // Foto (o la paleta a franjas en su sitio)
            if (data.photo != null) {
                Image(
                    bitmap = data.photo.asImageBitmap(), contentDescription = null,
                    contentScale = ContentScale.Crop,
                    modifier = Modifier.fillMaxWidth().height(photoHeight)
                        .clip(SolarRadius.cardShape),
                )
            } else {
                WellContainer(Modifier.fillMaxWidth().height(photoHeight)) {
                    SwatchStrip(
                        argbColors = data.palette.map { it.argb },
                        height = photoHeight - 20.dp,
                    )
                }
            }
            Box(Modifier.height(gap))
            if (format == ShareFormat.STORY) {
                WellContainer(Modifier.fillMaxWidth()) {
                    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                        SwatchStrip(
                            argbColors = data.palette.map { it.argb }, height = 12.dp,
                            weights = data.palette.map {
                                (it.weight ?: 0.0).toFloat().coerceAtLeast(0.01f)
                            },
                        )
                        Row(
                            Modifier.fillMaxWidth(),
                            horizontalArrangement = Arrangement.spacedBy(6.dp),
                        ) {
                            data.palette.take(5).forEach { color ->
                                Column(
                                    Modifier.weight(1f),
                                    horizontalAlignment = Alignment.CenterHorizontally,
                                    verticalArrangement = Arrangement.spacedBy(4.dp),
                                ) {
                                    Box(
                                        Modifier.size(40.dp).clip(CircleShape)
                                            .background(Color(color.argb))
                                            .border(
                                                0.5.dp, colors.swatchHairline, CircleShape,
                                            ),
                                    )
                                    color.name?.let {
                                        Text(
                                            it, style = SolarTheme.type.labelSm,
                                            color = colors.wellText, maxLines = 1,
                                        )
                                    }
                                    Text(
                                        color.hex, style = SolarTheme.type.hex,
                                        color = colors.wellTextSecondary, maxLines = 1,
                                    )
                                    color.weight?.let {
                                        Text(
                                            percentText(it), style = SolarTheme.type.labelSm,
                                            color = colors.wellTextSecondary,
                                        )
                                    }
                                }
                            }
                        }
                    }
                }
            } else {
                WellContainer(Modifier.fillMaxWidth(), compact = true) {
                    SwatchStrip(
                        argbColors = data.palette.map { it.argb }, height = 12.dp,
                        weights = data.palette.map {
                            (it.weight ?: 0.0).toFloat().coerceAtLeast(0.01f)
                        },
                    )
                }
            }
            Box(Modifier.height(gap))
            // Combinación
            Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
                Text(
                    stringResource(R.string.w3_looks_like).uppercase(),
                    style = TextStyle(
                        fontFamily = JakartaFamily, fontWeight = FontWeight.Bold, fontSize = 11.sp,
                        letterSpacing = 1.1.sp,
                    ),
                    color = colors.onSurfaceVariant,
                )
                if (data.comboColors.isEmpty()) {
                    Text(
                        stringResource(R.string.w3_no_combo),
                        style = TextStyle(
                            fontFamily = LiterataFamily, fontWeight = FontWeight.SemiBold,
                            fontSize = nameSize,
                        ),
                        color = colors.onSurface,
                    )
                } else {
                    WellContainer(Modifier.fillMaxWidth(), compact = true) {
                        SwatchStrip(
                            argbColors = data.comboColors.map { it.argb }, height = stripHeight,
                        )
                    }
                    Column {
                        // Una linea con escala minima 0,62, como en iOS.
                        var currentSize by remember(data.displayName, nameSize) {
                            mutableStateOf(nameSize)
                        }
                        Text(
                            data.displayName ?: data.title,
                            style = TextStyle(
                                fontFamily = LiterataFamily, fontWeight = FontWeight.SemiBold,
                                fontSize = currentSize,
                            ),
                            color = colors.onSurface, maxLines = 1, softWrap = false,
                            onTextLayout = { layout ->
                                if (layout.didOverflowWidth &&
                                    currentSize > nameSize * 0.62f
                                ) {
                                    currentSize *= 0.9f
                                }
                            },
                        )
                        Text(
                            data.subtitle,
                            style = TextStyle(
                                fontFamily = JakartaFamily, fontWeight = FontWeight.Medium,
                                fontSize = 12.5.sp,
                            ),
                            color = colors.onSurfaceVariant, maxLines = 1,
                        )
                    }
                }
            }
            Box(Modifier.weight(1f))
            Row(
                Modifier.fillMaxWidth(),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(6.dp),
            ) {
                Icon(
                    SolarIconLeaf, contentDescription = null, tint = colors.primary,
                    modifier = Modifier.size(10.dp),
                )
                Text(
                    stringResource(
                        R.string.w3_brand_wada,
                        stringResource(R.string.app_name), data.number,
                    ),
                    style = TextStyle(
                        fontFamily = JakartaFamily, fontWeight = FontWeight.SemiBold,
                        fontSize = 11.sp,
                    ),
                    color = colors.onSurfaceVariant,
                )
                Box(Modifier.weight(1f))
                Text(
                    stringResource(R.string.w3_analyzed_on_phone),
                    style = TextStyle(
                        fontFamily = JakartaFamily, fontWeight = FontWeight.Medium,
                        fontSize = 10.5.sp,
                    ),
                    color = colors.onSurfaceVariant,
                )
            }
        }
    }
}

/** Espera al siguiente frame del Choreographer (hilo principal). */
private suspend fun awaitFrame() {
    kotlinx.coroutines.suspendCancellableCoroutine { cont ->
        val choreographer = android.view.Choreographer.getInstance()
        val callback = android.view.Choreographer.FrameCallback {
            if (cont.isActive) cont.resume(Unit)
        }
        choreographer.postFrameCallback(callback)
        cont.invokeOnCancellation { choreographer.removeFrameCallback(callback) }
    }
}

/** La ComponentActivity que envuelve este contexto, si la hay. */
tailrec fun android.content.Context.findComponentActivity(): ComponentActivity? = when (this) {
    is ComponentActivity -> this
    is android.content.ContextWrapper -> baseContext.findComponentActivity()
    else -> null
}

/**
 * Dibuja la tarjeta a un Bitmap de 1080 x (1350|1920): ComposeView fuera de
 * pantalla con densidad 3 (360 dp = 1080 px), tema claro forzado.
 */
suspend fun renderShareCard(
    activity: ComponentActivity,
    data: ShareCardData,
    format: ShareFormat,
): Bitmap = withContext(Dispatchers.Main.immediate) {
    val widthPx = format.widthDp * ShareFormat.RENDER_SCALE
    val heightPx = format.heightDp * ShareFormat.RENDER_SCALE
    val composeView = ComposeView(activity)
    composeView.setViewTreeLifecycleOwner(activity)
    composeView.setViewTreeSavedStateRegistryOwner(activity)
    composeView.setViewTreeViewModelStoreOwner(activity)
    composeView.setContent {
        ChromaSolTheme(darkTheme = false) {
            CompositionLocalProvider(
                LocalDensity provides Density(ShareFormat.RENDER_SCALE.toFloat(), 1f),
            ) {
                ShareCardContent(data, format)
            }
        }
    }
    val parent = activity.window.decorView as ViewGroup
    val holder = FrameLayout(activity)
    holder.alpha = 0f
    holder.addView(composeView, widthPx, heightPx)
    parent.addView(holder, widthPx, heightPx)
    try {
        // Dos frames: componer y medirse antes de dibujar. Choreographer y
        // no withFrameNanos: el llamante puede no traer MonotonicFrameClock
        // en su contexto (p. ej. un runBlocking de test).
        awaitFrame()
        awaitFrame()
        composeView.measure(
            View.MeasureSpec.makeMeasureSpec(widthPx, View.MeasureSpec.EXACTLY),
            View.MeasureSpec.makeMeasureSpec(heightPx, View.MeasureSpec.EXACTLY),
        )
        composeView.layout(0, 0, widthPx, heightPx)
        val bitmap = Bitmap.createBitmap(widthPx, heightPx, Bitmap.Config.ARGB_8888)
        composeView.draw(Canvas(bitmap))
        bitmap
    } finally {
        parent.removeView(holder)
        composeView.disposeComposition()
    }
}

/** Hoja «Compartir tarjeta»: formato, vista previa y enviar (ShareCardSheet). */
@Composable
fun ShareCardSheet(
    scan: ScanRecord,
    photo: Bitmap?,
    dictionary: WadaDictionary,
    initialFormat: ShareFormat = ShareFormat.POST,
    onDismiss: () -> Unit,
) {
    val context = LocalContext.current
    val colors = SolarTheme.colors
    val type = SolarTheme.type
    val scope = rememberCoroutineScope()
    var format by remember { mutableStateOf(initialFormat) }
    var rendered by remember { mutableStateOf<Map<ShareFormat, Bitmap>>(emptyMap()) }
    val data = remember(scan.id, scan.rev, photo) {
        ShareCardFactory.dataFor(scan, photo, dictionary, context.resources)
    }
    val shareTitle = scan.top1?.let {
        stringResource(
            R.string.w3_brand_wada, stringResource(R.string.app_name), numberLabel(it),
        )
    } ?: stringResource(R.string.app_name)

    LaunchedEffect(format) {
        if (rendered[format] == null) {
            val activity = context.findComponentActivity() ?: return@LaunchedEffect
            val bitmap = runCatching { renderShareCard(activity, data, format) }.getOrNull()
            if (bitmap != null) rendered = rendered + (format to bitmap)
        }
    }

    Dialog(
        onDismissRequest = onDismiss,
        properties = DialogProperties(usePlatformDefaultWidth = false),
    ) {
        Column(
            Modifier.fillMaxSize().background(colors.surface).testTag("share.sheet"),
        ) {
            SolarHeader(section = stringResource(R.string.w3_share_card)) {
                SolarHeaderButton(
                    icon = SolarIconClose,
                    contentDescription = stringResource(R.string.w3_close),
                    onClick = onDismiss,
                )
            }
            Column(
                Modifier.fillMaxSize().padding(horizontal = SolarSpacing.margin)
                    .padding(top = SolarSpacing.sm, bottom = SolarSpacing.sm),
                verticalArrangement = Arrangement.spacedBy(SolarSpacing.md),
            ) {
                // Selector de formato segmentado.
                Row(
                    Modifier
                        .fillMaxWidth()
                        .clip(RoundedCornerShape(50))
                        .background(colors.container)
                        .padding(4.dp)
                        .testTag("share.format"),
                    horizontalArrangement = Arrangement.spacedBy(4.dp),
                ) {
                    ShareFormat.entries.forEach { candidate ->
                        val selected = candidate == format
                        val interaction = remember(candidate) { MutableInteractionSource() }
                        Box(
                            Modifier
                                .weight(1f)
                                .solarPress(interaction, 0.97f)
                                .clip(RoundedCornerShape(50))
                                .background(if (selected) colors.primary else Color.Transparent)
                                .clickable(
                                    interactionSource = interaction, indication = null,
                                    role = Role.Tab,
                                ) { format = candidate }
                                .padding(vertical = SolarSpacing.sm),
                            contentAlignment = Alignment.Center,
                        ) {
                            Text(
                                stringResource(
                                    if (candidate == ShareFormat.POST) {
                                        R.string.w3_share_post_format
                                    } else {
                                        R.string.w3_share_story_format
                                    },
                                ),
                                style = type.labelMd,
                                color = if (selected) colors.onPrimary else colors.onSurfaceVariant,
                            )
                        }
                    }
                }
                Box(
                    Modifier.fillMaxWidth().weight(1f),
                    contentAlignment = Alignment.Center,
                ) {
                    val image = rendered[format]
                    if (image != null) {
                        val previewLabel = stringResource(R.string.w3_share_card_preview)
                        Image(
                            bitmap = image.asImageBitmap(), contentDescription = null,
                            modifier = Modifier
                                .aspectRatio(format.widthDp.toFloat() / format.heightDp)
                                .fillMaxWidth()
                                .clip(SolarRadius.cardShape)
                                .border(1.dp, colors.outlineVariant, SolarRadius.cardShape)
                                .semantics { contentDescription = previewLabel },
                        )
                    } else {
                        CircularProgressIndicator(color = colors.primary)
                    }
                }
                Text(
                    stringResource(R.string.w3_share_pixels_light, format.pixelLabel),
                    style = type.bodySm, color = colors.onSurfaceVariant,
                    modifier = Modifier.align(Alignment.CenterHorizontally),
                )
                val image = rendered[format]
                if (image != null) {
                    SolarPrimaryButton(
                        text = stringResource(R.string.w3_share_send),
                        icon = SolarIconShare,
                        onClick = {
                            scope.launch(Dispatchers.IO) {
                                val dir = File(context.cacheDir, "share").apply { mkdirs() }
                                val file = File(
                                    dir, "card-${scan.id}-${format.name.lowercase()}.png",
                                )
                                file.outputStream().use { out ->
                                    image.compress(Bitmap.CompressFormat.PNG, 100, out)
                                }
                                val uri = FileProvider.getUriForFile(
                                    context, "${context.packageName}.fileprovider", file,
                                )
                                val intent = Intent(Intent.ACTION_SEND).apply {
                                    setType("image/png")
                                    putExtra(Intent.EXTRA_STREAM, uri)
                                    putExtra(Intent.EXTRA_TITLE, shareTitle)
                                    addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                                }
                                withContext(Dispatchers.Main) {
                                    context.startActivity(
                                        Intent.createChooser(intent, shareTitle),
                                    )
                                }
                            }
                        },
                        modifier = Modifier.testTag("share.send"),
                    )
                } else {
                    SolarPrimaryButton(
                        text = stringResource(R.string.w3_preparing_card),
                        onClick = {},
                        enabled = false,
                    )
                }
            }
        }
    }
}
