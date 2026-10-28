// Resultado de Extraer: espejo de ExtractResultContent.swift +
// ExtractViewfinder.swift + la tarjeta de prenda de ExtractLights.swift.
// Visor con la foto sin recortar y un alfiler por color (centroide del
// labelMap del motor), aviso de la cadena desplegable con sus pasos, «Ver
// mascara», fila de personas, tarjetas de prenda en pocillo neutro, cinta de
// pesos, top-3 con voto/desbloqueo y la explicacion del score del motor,
// guardar/copiar/capas/compartir y pie tecnico. La usan la pestana Extraer y
// la pantalla empujada desde el Feed (ResultPushedScreen, ResultView de iOS).
package com.andreseloy.colorsapp.feature.extract

import android.graphics.Bitmap
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.semantics.role
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBars
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.blur
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import com.andreseloy.colorsapp.R
import com.andreseloy.colorsapp.data.FeedbackVerdict
import com.andreseloy.colorsapp.data.WadaDictionary
import com.andreseloy.colorsapp.design.SolarCard
import com.andreseloy.colorsapp.design.SolarHeader
import com.andreseloy.colorsapp.design.SolarHeaderButton
import com.andreseloy.colorsapp.design.SolarIconBack
import com.andreseloy.colorsapp.design.SolarIconLeaf
import com.andreseloy.colorsapp.design.SolarIconSparkles
import com.andreseloy.colorsapp.design.SolarPrimaryButton
import com.andreseloy.colorsapp.design.SolarRadius
import com.andreseloy.colorsapp.design.SolarSizes
import com.andreseloy.colorsapp.design.SolarSpacing
import com.andreseloy.colorsapp.design.SolarTheme
import com.andreseloy.colorsapp.design.SwatchStrip
import com.andreseloy.colorsapp.design.WellContainer
import com.andreseloy.colorsapp.design.solarPress
import com.andreseloy.colorsapp.engine.MatchExplanation
import com.andreseloy.colorsapp.feature.feed.ComboMatchSummary
import com.andreseloy.colorsapp.feature.feed.ComboSheet
import com.andreseloy.colorsapp.design.SolarIconCheck
import com.andreseloy.colorsapp.design.SolarIconChevronRight
import com.andreseloy.colorsapp.design.SolarIconPerson
import com.andreseloy.colorsapp.design.SolarIconCopy
import com.andreseloy.colorsapp.design.SolarIconEye
import com.andreseloy.colorsapp.design.SolarIconEyeSlash
import com.andreseloy.colorsapp.design.SolarIconHeart
import com.andreseloy.colorsapp.design.SolarIconHeartFilled
import com.andreseloy.colorsapp.design.SolarIconLayers
import com.andreseloy.colorsapp.design.SolarIconLock
import com.andreseloy.colorsapp.design.SolarIconLockOpen
import com.andreseloy.colorsapp.design.SolarIconPalette
import com.andreseloy.colorsapp.design.SolarIconSeal
import com.andreseloy.colorsapp.design.SolarIconShare
import com.andreseloy.colorsapp.design.SolarIconThumbDown
import com.andreseloy.colorsapp.design.SolarIconWarning
import com.andreseloy.colorsapp.feature.share.ShareCardSheet
import com.andreseloy.colorsapp.feature.share.ShareFormat
import kotlin.math.roundToInt
import java.util.Locale

/* ---------------- Pantalla empujada (Feed -> Abrir en Extraer) ---------------- */

@Composable
fun ResultPushedScreen(
    model: ResultModel,
    dictionary: WadaDictionary,
    onBack: () -> Unit,
    onOpenLayers: (() -> Unit)?,
    modifier: Modifier = Modifier,
) {
    val colors = SolarTheme.colors
    var toast by remember { mutableStateOf<String?>(null) }
    Box(modifier.fillMaxSize().background(colors.surface)) {
        Column(Modifier.fillMaxSize().windowInsetsPadding(WindowInsets.statusBars)) {
            SolarHeader(section = stringResource(R.string.w3_result)) {
                SolarHeaderButton(
                    icon = SolarIconBack,
                    contentDescription = stringResource(R.string.back),
                    onClick = onBack,
                )
            }
            Column(
                Modifier
                    .fillMaxSize()
                    .verticalScroll(rememberScrollState())
                    .padding(horizontal = SolarSpacing.margin)
                    .padding(top = SolarSpacing.sm, bottom = SolarSpacing.xl),
            ) {
                ResultContent(
                    model = model, dictionary = dictionary,
                    onOpenLayers = onOpenLayers, onToast = { toast = it },
                )
            }
        }
        Box(Modifier.align(Alignment.TopCenter).windowInsetsPadding(WindowInsets.statusBars)) {
            com.andreseloy.colorsapp.feature.feed.W3ToastHost(
                toast, Modifier.padding(top = SolarSizes.header + SolarSpacing.margin),
            )
        }
        androidx.compose.runtime.LaunchedEffect(toast) {
            if (toast != null) {
                kotlinx.coroutines.delay(2200)
                toast = null
            }
        }
    }
}

/* ---------------- Contenido ---------------- */

@Composable
fun ResultContent(
    model: ResultModel,
    dictionary: WadaDictionary,
    onOpenLayers: (() -> Unit)?,
    onToast: (String) -> Unit,
    onOpenCombo: (Int) -> Unit = {},
    modifier: Modifier = Modifier,
) {
    val colors = SolarTheme.colors
    val type = SolarTheme.type
    var comboSheetId by remember { mutableStateOf<Int?>(null) }
    var copiedSwatch by remember { mutableStateOf<Int?>(null) }
    var copiedPalette by remember { mutableStateOf(false) }
    var showShare by remember { mutableStateOf(false) }

    fun flash(text: String) {
        onToast(text)
    }
    androidx.compose.runtime.LaunchedEffect(copiedSwatch, copiedPalette) {
        if (copiedSwatch != null || copiedPalette) {
            kotlinx.coroutines.delay(2200)
            copiedSwatch = null
            copiedPalette = false
        }
    }

    Column(modifier.fillMaxWidth()) {
        model.banner?.let { banner ->
            Box(
                Modifier
                    .padding(bottom = SolarSpacing.md)
                    .clip(RoundedCornerShape(50))
                    .background(colors.secondaryContainer)
                    .padding(horizontal = SolarSpacing.md, vertical = SolarSpacing.sm)
                    .testTag("result.banner"),
            ) {
                Text(banner, style = type.labelMd, color = colors.onSecondaryContainer)
            }
        }
        ResultViewfinder(model = model, onOpenLayers = onOpenLayers)
        if (model.showsPeopleRow && model.verdict != null) {
            Text(
                stringResource(R.string.w3_voted_person_note),
                style = type.bodySm, color = colors.onSurfaceVariant,
                modifier = Modifier.padding(top = SolarSpacing.sm),
            )
        }

        // Colores de la ropa / por prenda / de la foto
        Column(Modifier.padding(top = SolarSpacing.xs + SolarSpacing.md)) {
            Row(
                Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Text(
                    text = stringResource(
                        when (model.paletteTitle) {
                            ResultModel.PaletteTitle.BY_GARMENT -> R.string.w3_colors_by_garment
                            ResultModel.PaletteTitle.CLOTHING -> R.string.w3_colors_clothing
                            ResultModel.PaletteTitle.PHOTO -> R.string.w3_colors_photo
                        },
                    ),
                    style = type.headlineSm, color = colors.primary,
                )
                Icon(
                    SolarIconPalette, contentDescription = null, tint = colors.secondary,
                    modifier = Modifier.size(20.dp),
                )
            }
            PaletteSummaryPill(model.paletteSummary)
            // Tarjetas de prenda: 2 columnas.
            Column(
                Modifier.padding(top = SolarSpacing.md),
                verticalArrangement = Arrangement.spacedBy(SolarSpacing.gutter),
            ) {
                model.palette.chunked(2).forEach { rowColors ->
                    Row(
                        Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.spacedBy(SolarSpacing.gutter),
                    ) {
                        rowColors.forEach { color ->
                            GarmentCard(
                                index = color.id + 1,
                                color = color,
                                region = model.garmentRegionOf(color)?.let {
                                    garmentRegionLabel(
                                        androidx.compose.ui.platform.LocalContext.current.resources, it,
                                    )
                                },
                                isSelected = model.selectedSwatch == color.id,
                                isCopied = copiedSwatch == color.id,
                                onTap = {
                                    flash(model.copy(color))
                                    copiedSwatch = color.id
                                },
                                modifier = Modifier.weight(1f).testTag("result.garment.${color.id}"),
                            )
                        }
                        if (rowColors.size == 1) Box(Modifier.weight(1f))
                    }
                }
            }
            if (model.palette.isNotEmpty()) {
                WellContainer(
                    Modifier.fillMaxWidth().padding(top = SolarSpacing.lg).testTag("result.ribbon"),
                ) {
                    SwatchStrip(
                        argbColors = model.palette.map { it.argb },
                        height = SolarSizes.extractRibbon,
                        weights = model.palette.map { (it.weight ?: 0.0).toFloat().coerceAtLeast(0.01f) },
                    )
                }
            }
        }

        // Acciones: guardar, copiar hex, ver capas
        Column(
            Modifier.padding(top = SolarSpacing.lg),
            verticalArrangement = Arrangement.spacedBy(SolarSpacing.sm),
        ) {
            // Verde luminoso de iOS (ExtractLuminousButton): el SolarSecondaryButton
            // del sistema de diseno es el relleno musgo.
            com.andreseloy.colorsapp.design.SolarSecondaryButton(
                text = stringResource(
                    if (model.isSaved) R.string.w3_saved_in_garden_btn
                    else R.string.w3_save_in_garden_btn,
                ),
                onClick = { flash(model.toggleSave()) },
                modifier = Modifier.fillMaxWidth().height(52.dp).testTag("result.save"),
            )
            Row(
                Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(SolarSpacing.gutter),
            ) {
                PillButton(
                    text = stringResource(
                        if (copiedPalette) R.string.w3_copied_btn else R.string.w3_copy_hex,
                    ),
                    icon = SolarIconCopy,
                    onClick = {
                        flash(model.copyPalette())
                        copiedPalette = true
                    },
                    enabled = model.palette.isNotEmpty(),
                    isDone = copiedPalette,
                    modifier = Modifier.weight(1f).testTag("result.copyHex"),
                )
                PillButton(
                    text = stringResource(R.string.w3_view_layers),
                    icon = SolarIconLayers,
                    onClick = { onOpenLayers?.invoke() },
                    enabled = onOpenLayers != null && !model.reanalyzing,
                    modifier = Modifier.weight(1f).testTag("result.layersButton"),
                )
            }
        }

        // Combinaciones
        Column(Modifier.padding(top = SolarSpacing.xl)) {
            val matches = model.matches
            val top = matches.firstOrNull()
            val hit = model.topHit
            if (top != null && hit != null) {
                TopMatchCard(
                    model = model, match = top, score = hit.score,
                    explanation = model.topExplanation,
                    dictionary = dictionary,
                    onOpen = { comboSheetId = top.comboId },
                )
                if (matches.size > 1) {
                    SolarCard(Modifier.fillMaxWidth().padding(top = SolarSpacing.md)) {
                        Column(verticalArrangement = Arrangement.spacedBy(SolarSpacing.sm)) {
                            Text(
                                stringResource(R.string.w3_also_looks_like).uppercase(),
                                style = type.overline, color = colors.onSurfaceVariant,
                            )
                            matches.drop(1).forEachIndexed { i, match ->
                                MatchRow(
                                    rank = i + 2, match = match,
                                    score = model.hits[i + 1].score,
                                    onOpen = { comboSheetId = match.comboId },
                                )
                            }
                        }
                    }
                }
            } else {
                SolarCard(Modifier.fillMaxWidth()) {
                    Column(verticalArrangement = Arrangement.spacedBy(SolarSpacing.xs)) {
                        Text(
                            stringResource(R.string.w3_looks_like).uppercase(),
                            style = type.overline, color = colors.onSurfaceVariant,
                        )
                        Text(
                            stringResource(R.string.w3_no_combo_engine),
                            style = type.bodyMd, color = colors.onSurfaceVariant,
                        )
                    }
                }
            }
        }

        // Compartir tarjeta
        val shareInteraction = remember { MutableInteractionSource() }
        Row(
            Modifier
                .fillMaxWidth()
                .padding(top = SolarSpacing.md)
                .heightInMinTouch()
                .solarPress(shareInteraction)
                .clip(RoundedCornerShape(50))
                .background(colors.surface)
                .border(1.dp, colors.brassHairline, RoundedCornerShape(50))
                .clickable(
                    interactionSource = shareInteraction, indication = null, role = Role.Button,
                ) { showShare = true }
                .padding(horizontal = SolarSpacing.lg, vertical = SolarSpacing.md)
                .testTag("result.share"),
            horizontalArrangement = Arrangement.Center,
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Icon(
                SolarIconShare, contentDescription = null, tint = colors.primary,
                modifier = Modifier.size(16.dp),
            )
            Box(Modifier.size(SolarSpacing.sm))
            Text(stringResource(R.string.w3_share_card), style = type.labelLg, color = colors.primary)
        }

        model.errorMessage?.let { error ->
            Row(
                Modifier.padding(top = SolarSpacing.md).testTag("result.error"),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(SolarSpacing.sm),
            ) {
                Icon(
                    SolarIconWarning, contentDescription = null, tint = colors.error,
                    modifier = Modifier.size(18.dp),
                )
                Text(error, style = type.bodyMd, color = colors.error)
            }
        }
        Text(
            text = stringResource(
                R.string.w3_technical_footer,
                model.outcome.scan.engineVersion,
                model.outcome.scan.dictVersion,
                model.outcome.timings.totalMs.roundToInt(),
                model.outcome.timings.visionMs.roundToInt(),
                model.outcome.timings.maskMs.roundToInt(),
                model.outcome.timings.engineMs.roundToInt(),
            ),
            style = type.bodySm, color = colors.onSurfaceVariant,
            modifier = Modifier.padding(top = SolarSpacing.md).testTag("result.footer"),
        )
    }

    comboSheetId?.let { id ->
        onOpenCombo(id)
        ComboSheet(id, dictionary) { comboSheetId = null }
    }
    if (showShare) {
        ShareCardSheet(
            scan = model.outcome.scan, photo = model.outcome.bitmap,
            dictionary = dictionary, initialFormat = ShareFormat.POST,
            onDismiss = { showShare = false },
        )
    }
}

private fun Modifier.heightInMinTouch(): Modifier =
    this.then(Modifier.height(SolarSizes.minTouch + SolarSpacing.md))

@Composable
private fun PaletteSummaryPill(summary: PaletteSummaryData) {
    val colors = SolarTheme.colors
    val type = SolarTheme.type
    val parts = mutableListOf<String>()
    parts += if (summary.colorCount == 1) {
        stringResource(R.string.w3_one_color)
    } else {
        stringResource(R.string.w3_colors_count, summary.colorCount)
    }
    val coverage = summary.coverage
    if (coverage == null) {
        parts += stringResource(R.string.w3_whole_photo_lower)
    } else {
        summary.garmentRegions?.let { regions ->
            parts += if (regions == 1) {
                stringResource(R.string.w3_one_garment)
            } else {
                stringResource(R.string.w3_garments_count, regions)
            }
        }
        parts += stringResource(
            R.string.w3_of_the_photo, percentFractionText(coverage),
        )
    }
    Row(
        Modifier
            .padding(top = SolarSpacing.xs)
            .clip(RoundedCornerShape(50))
            .background(colors.container)
            .padding(horizontal = SolarSpacing.md, vertical = SolarSpacing.chipVertical)
            .testTag("result.paletteSummary"),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(SolarSpacing.xs),
    ) {
        Box(Modifier.size(8.dp).clip(CircleShape).background(colors.secondaryContainer))
        Text(
            parts.first(), style = type.labelMd, color = colors.onSurface,
        )
        if (parts.size > 1) {
            Text(
                " · " + parts.drop(1).joinToString(" · "),
                style = type.labelMd, color = colors.onSurfaceVariant,
            )
        }
    }
}

/** Tarjeta de prenda en pocillo neutro (ExtractGarmentCard de iOS). */
@Composable
fun GarmentCard(
    index: Int,
    color: PaletteColor,
    region: String?,
    isSelected: Boolean,
    isCopied: Boolean,
    onTap: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val colors = SolarTheme.colors
    val type = SolarTheme.type
    val locale = w3Locale()
    val eyebrow = String.format(Locale.ROOT, "%02d", index) + (color.weight?.let { " · ${percentText(it)}" } ?: "")
    val description = buildList {
        add(stringResource(R.string.w3_color_n, index))
        region?.let { add(it) }
        color.weight?.let {
            add(stringResource(R.string.w3_percent_words, W3Format.percentInt(it)))
        }
        color.name?.let { add(it) }
        add(color.hex)
        color.deltaE?.let {
            add(stringResource(R.string.w3_delta_e, W3Format.deltaEValue(it, locale)))
        }
    }.joinToString(", ")
    Column(
        modifier
            .clip(SolarRadius.cardShape)
            .background(colors.wellFill)
            .border(
                if (isSelected) 2.dp else 1.dp,
                if (isSelected) colors.wellText else colors.wellEdge,
                SolarRadius.cardShape,
            )
            .clickable(role = Role.Button) { onTap() }
            .semantics { contentDescription = description }
            .padding(SolarSpacing.sm),
        verticalArrangement = Arrangement.spacedBy(SolarSpacing.sm),
    ) {
        Box(
            Modifier
                .fillMaxWidth()
                .height(SolarSizes.garmentBlock)
                .clip(SolarRadius.blockShape)
                .background(Color(color.argb))
                .border(0.5.dp, colors.swatchHairline, SolarRadius.blockShape),
        )
        Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                Text(
                    eyebrow.uppercase(), style = type.overline,
                    color = colors.wellTextSecondary, maxLines = 1,
                )
                Text("✦", style = type.labelSm, color = colors.wellTextSecondary)
            }
            if (region != null) {
                Box(
                    Modifier
                        .padding(top = 1.dp)
                        .clip(SolarRadius.tagShape)
                        .background(colors.wellFillAlt)
                        .border(1.dp, colors.wellEdge, SolarRadius.tagShape)
                        .padding(horizontal = 6.dp, vertical = 2.dp),
                ) {
                    Text(region, style = type.labelSm, color = colors.wellText, maxLines = 1)
                }
            }
            Text(
                color.name ?: color.hex, style = type.headlineSm,
                color = colors.wellText, maxLines = 1,
            )
            Row(
                Modifier.fillMaxWidth().padding(top = 2.dp),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(SolarSpacing.xs),
            ) {
                Text(color.hex, style = type.hex, color = colors.wellTextSecondary, maxLines = 1)
                Icon(
                    if (isCopied) SolarIconCheck else SolarIconCopy,
                    contentDescription = null, tint = colors.wellTextSecondary,
                    modifier = Modifier.size(10.dp),
                )
                Box(Modifier.weight(1f))
                color.deltaE?.let { de ->
                    Box(
                        Modifier
                            .clip(SolarRadius.tagShape)
                            .background(colors.wellFillAlt)
                            .border(1.dp, colors.wellEdge, SolarRadius.tagShape)
                            .padding(horizontal = 6.dp, vertical = 2.dp),
                    ) {
                        Text(
                            stringResource(
                                R.string.w3_delta_e, W3Format.deltaEValue(de, locale),
                            ),
                            style = type.labelSm, color = colors.wellText, maxLines = 1,
                        )
                    }
                }
            }
        }
    }
}

/* ---------------- Visor con alfileres ---------------- */

/** Geometria del visor (ExtractViewfinder.layout): marco 300..400 y franjas HUD. */
object ViewfinderGeometry {
    const val HUD_TOP_DP = 48f
    const val HUD_BOTTOM_DP = 68f

    /** Devuelve (alto, margenSuperior, margenInferior) en dp. */
    fun layout(aspect: Float, widthDp: Float): Triple<Float, Float, Float> {
        val a = maxOf(aspect, 0.01f)
        val height = minOf(400f, maxOf(300f, widthDp / a + HUD_TOP_DP + HUD_BOTTOM_DP))
        val inset = minOf(widthDp, (height - HUD_TOP_DP - HUD_BOTTOM_DP) * a)
        return if (inset >= 0.75f * widthDp) {
            Triple(height, HUD_TOP_DP, HUD_BOTTOM_DP)
        } else {
            Triple(height, 0f, 0f)
        }
    }
}

@Composable
fun ResultViewfinder(
    model: ResultModel,
    onOpenLayers: (() -> Unit)?,
    modifier: Modifier = Modifier,
) {
    val colors = SolarTheme.colors
    val type = SolarTheme.type
    val bitmap = model.outcome.bitmap
    val aspect = bitmap.width.toFloat() / maxOf(bitmap.height, 1)
    var noticeExpanded by remember { mutableStateOf(false) }
    val maskOn = model.showMask && model.maskOverlay != null

    BoxWithConstraints(
        modifier
            .fillMaxWidth()
            .testTag("result.photo"),
    ) {
        val widthDp = maxWidth.value
        val (heightF, topF, bottomF) = ViewfinderGeometry.layout(aspect, widthDp)
        val frameHeight = heightF.dp
        val topInset = topF.dp
        val bottomInset = bottomF.dp
        Box(
            Modifier
                .fillMaxWidth()
                .height(frameHeight)
                .clip(SolarRadius.cardShape)
                .background(colors.containerLow),
        ) {
            // Fondo: la misma foto desenfocada llenando el marco.
            Image(
                bitmap = bitmap.asImageBitmap(), contentDescription = null,
                contentScale = ContentScale.Crop,
                modifier = Modifier.fillMaxSize().blur(32.dp),
            )
            Box(Modifier.fillMaxSize().background(colors.containerLow.copy(alpha = 0.3f)))
            // Rectangulo real de la foto ajustada (sin recorte) entre las franjas.
            val innerW = widthDp
            val innerH = heightF - topF - bottomF
            val dispW: Float
            val dispH: Float
            if (innerW / innerH > aspect) {
                dispH = innerH
                dispW = innerH * aspect
            } else {
                dispW = innerW
                dispH = innerW / aspect
            }
            val dispX = (innerW - dispW) / 2f
            val dispY = topF + (innerH - dispH) / 2f
            Box(
                Modifier
                    .offset(x = dispX.dp, y = dispY.dp)
                    .width(dispW.dp)
                    .height(dispH.dp),
            ) {
                Image(
                    bitmap = bitmap.asImageBitmap(), contentDescription = null,
                    contentScale = ContentScale.FillBounds, modifier = Modifier.fillMaxSize(),
                )
                if (maskOn) {
                    model.maskOverlay?.let { overlay ->
                        Image(
                            bitmap = overlay.asImageBitmap(), contentDescription = null,
                            contentScale = ContentScale.FillBounds,
                            modifier = Modifier.fillMaxSize().testTag("result.maskOverlay"),
                        )
                    }
                }
                model.isolationOverlay?.let { overlay ->
                    Image(
                        bitmap = overlay.asImageBitmap(), contentDescription = null,
                        contentScale = ContentScale.FillBounds,
                        modifier = Modifier.fillMaxSize().testTag("result.isolation"),
                    )
                }
                if (model.reanalyzing) {
                    Box(
                        Modifier.fillMaxSize().background(Color(0x40000000)),
                        contentAlignment = Alignment.Center,
                    ) { CircularProgressIndicator(color = Color.White) }
                }
                // Alfileres: cuenta en el punto y etiqueta arriba o abajo.
                model.pins.forEach { pin ->
                    val px = (dispW * pin.x).toFloat()
                    val py = (dispH * pin.y).toFloat()
                    val selected = model.selectedSwatch == pin.swatchIndex
                    val labelAbove = pin.y > 0.35
                    val bead = 24f
                    val labelText = buildList {
                        add(pin.color.name ?: pin.color.hex)
                        pin.color.weight?.let { add(percentText(it)) }
                    }.joinToString(" ")
                    Box(
                        Modifier
                            .offset(
                                x = (px - bead / 2).dp, y = (py - bead / 2).dp,
                            )
                            .size(bead.dp)
                            .pointerInput(pin.swatchIndex) {
                                detectTapGestures(
                                    onTap = {
                                        model.selectedSwatch =
                                            if (selected) null else pin.swatchIndex
                                    },
                                    onLongPress = {
                                        // Mantener en iOS aisla mientras dura; aqui la
                                        // pulsacion larga conmuta el aislamiento.
                                        val active =
                                            model.isolatedSwatch != pin.swatchIndex
                                        model.setIsolation(pin.swatchIndex, active)
                                    },
                                )
                            }
                            .semantics {
                                role = Role.Button
                                contentDescription = labelText
                            },
                    ) {
                        Box(
                            Modifier
                                .fillMaxSize()
                                .clip(CircleShape)
                                .background(Color(pin.color.argb))
                                .border(
                                    if (selected) 2.5.dp else 1.5.dp, Color.White, CircleShape,
                                ),
                        )
                    }
                    Row(
                        Modifier
                            .offset(
                                x = (px - 40f).coerceIn(0f, maxOf(0f, dispW - 80f)).dp,
                                y = if (labelAbove) {
                                    (py - bead / 2 - 30f).coerceAtLeast(0f).dp
                                } else {
                                    (py + bead / 2 + 6f).dp
                                },
                            )
                            .width(120.dp),
                        horizontalArrangement = Arrangement.Center,
                    ) {
                        Row(
                            Modifier
                                .clip(RoundedCornerShape(50))
                                .background(Color(0xE6FFFFFF))
                                .border(0.5.dp, Color(0x33000000), RoundedCornerShape(50))
                                .padding(horizontal = 8.dp, vertical = 3.dp),
                            verticalAlignment = Alignment.CenterVertically,
                            horizontalArrangement = Arrangement.spacedBy(4.dp),
                        ) {
                            Box(
                                Modifier.size(8.dp).clip(CircleShape)
                                    .background(Color(pin.color.argb)),
                            )
                            Text(
                                labelText, style = type.labelSm, color = Color(0xFF1C1C17),
                                maxLines = 1,
                            )
                            Text("✦", style = type.labelSm, color = Color(0xFFB25F00))
                        }
                    }
                }
            }
            // HUD superior: aviso del recorte + ver mascara.
            Column(
                Modifier.align(Alignment.TopStart).fillMaxWidth().padding(SolarSpacing.md),
                verticalArrangement = Arrangement.spacedBy(SolarSpacing.sm),
            ) {
                Row(
                    Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.SpaceBetween,
                    verticalAlignment = Alignment.Top,
                ) {
                    val notice = model.maskNotice
                    val interaction = remember { MutableInteractionSource() }
                    Row(
                        Modifier
                            .solarPress(interaction, 0.95f)
                            .clip(RoundedCornerShape(50))
                            .background(colors.frostTint)
                            .clickable(
                                interactionSource = interaction, indication = null,
                                role = Role.Button,
                            ) { noticeExpanded = !noticeExpanded }
                            .padding(horizontal = 10.dp, vertical = 5.dp)
                            .testTag("result.subjectNotice"),
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(6.dp),
                    ) {
                        Icon(
                            if (notice.isFallback) SolarIconWarning
                            else SolarIconPerson,
                            contentDescription = null,
                            tint = if (notice.isFallback) colors.secondary else colors.onSurface,
                            modifier = Modifier.size(13.dp),
                        )
                        Text(
                            maskNoticeText(notice), style = type.labelSm,
                            color = if (notice.isFallback) colors.secondary else colors.onSurface,
                            maxLines = 1,
                        )
                    }
                    // Ver / ocultar mascara
                    val maskInteraction = remember { MutableInteractionSource() }
                    val available = model.maskOverlay != null
                    Row(
                        Modifier
                            .solarPress(maskInteraction, 0.95f)
                            .clip(RoundedCornerShape(50))
                            .background(colors.frostTint.copy(alpha = if (available) 1f else 0.7f))
                            .clickable(
                                interactionSource = maskInteraction, indication = null,
                                role = Role.Button, enabled = available,
                            ) { model.showMask = !model.showMask }
                            .padding(horizontal = 10.dp, vertical = 5.dp)
                            .testTag("result.showMask"),
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(4.dp),
                    ) {
                        Icon(
                            if (maskOn) SolarIconEyeSlash else SolarIconEye,
                            contentDescription = stringResource(
                                if (maskOn) R.string.w3_hide_mask else R.string.w3_view_mask,
                            ),
                            tint = if (available) colors.primary else colors.onSurfaceVariant,
                            modifier = Modifier.size(13.dp),
                        )
                        if (available) {
                            Text(
                                stringResource(
                                    if (maskOn) R.string.w3_hide_mask else R.string.w3_view_mask,
                                ),
                                style = type.labelSm, color = colors.primary, maxLines = 1,
                            )
                        }
                    }
                }
                if (noticeExpanded) {
                    Column(
                        Modifier
                            .fillMaxWidth()
                            .clip(SolarRadius.cardShape)
                            .background(colors.frostTint)
                            .clickable(role = Role.Button) { noticeExpanded = false }
                            .padding(SolarSpacing.md)
                            .testTag("result.subjectNotice.detail"),
                        verticalArrangement = Arrangement.spacedBy(SolarSpacing.xs),
                    ) {
                        val notice = model.maskNotice
                        Text(
                            maskNoticeText(notice), style = type.labelMd,
                            color = if (notice.isFallback) colors.secondary else colors.onSurface,
                        )
                        Text(
                            model.stepKinds.map { stepTitleText(it) }.joinToString(" → "),
                            style = type.bodySm, color = colors.onSurfaceVariant,
                        )
                        Text(
                            stringResource(R.string.w3_notice_detail_layers),
                            style = type.bodySm, color = colors.onSurfaceVariant,
                        )
                    }
                }
                if (model.isExample) {
                    Box(
                        Modifier.clip(RoundedCornerShape(50)).background(colors.tertiaryFixed)
                            .padding(horizontal = SolarSpacing.sm, vertical = 2.dp),
                    ) {
                        Text(
                            stringResource(R.string.w3_example), style = type.labelSm,
                            color = colors.onTertiaryFixed,
                        )
                    }
                }
            }
            // Barra inferior: personas + capas.
            Row(
                Modifier
                    .align(Alignment.BottomCenter)
                    .fillMaxWidth()
                    .padding(SolarSpacing.md)
                    .clip(SolarRadius.cardShape)
                    .background(colors.surface.copy(alpha = 0.9f))
                    .padding(horizontal = SolarSpacing.sm, vertical = 2.dp),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(SolarSpacing.sm),
            ) {
                Icon(
                    com.andreseloy.colorsapp.design.SolarIconSun, contentDescription = null,
                    tint = colors.secondary, modifier = Modifier.size(20.dp),
                )
                if (model.showsPeopleRow) {
                    Row(
                        Modifier.weight(1f).testTag("result.people"),
                        horizontalArrangement = Arrangement.spacedBy(SolarSpacing.sm),
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        model.personThumbnails.forEachIndexed { index, thumb ->
                            val selected = model.currentChoice == PersonChoice.Person(index)
                            val label = if (index == 0) {
                                stringResource(R.string.w3_person_1_main)
                            } else {
                                stringResource(R.string.w3_person_n, index + 1)
                            }
                            Box(
                                Modifier
                                    .size(width = 30.dp, height = 36.dp)
                                    .clip(SolarRadius.blockShape)
                                    .border(
                                        if (selected) 2.dp else 1.dp,
                                        if (selected) colors.primary else colors.outlineVariant,
                                        SolarRadius.blockShape,
                                    )
                                    .clickable(
                                        role = Role.Button,
                                        enabled = model.canChangePerson || selected,
                                    ) { model.choose(PersonChoice.Person(index)) }
                                    .semantics { contentDescription = label }
                                    .testTag("result.person.$index"),
                            ) {
                                Image(
                                    bitmap = thumb.asImageBitmap(), contentDescription = null,
                                    contentScale = ContentScale.Crop,
                                    modifier = Modifier.fillMaxSize(),
                                )
                            }
                        }
                        val allSelected = model.currentChoice == PersonChoice.All
                        Box(
                            Modifier
                                .height(36.dp)
                                .clip(SolarRadius.blockShape)
                                .background(colors.container)
                                .border(
                                    if (allSelected) 2.dp else 1.dp,
                                    if (allSelected) colors.primary else colors.outlineVariant,
                                    SolarRadius.blockShape,
                                )
                                .clickable(
                                    role = Role.Button,
                                    enabled = model.canChangePerson || allSelected,
                                ) { model.choose(PersonChoice.All) }
                                .padding(horizontal = SolarSpacing.sm)
                                .testTag("result.person.all"),
                            contentAlignment = Alignment.Center,
                        ) {
                            Text(
                                stringResource(R.string.w3_all_fem),
                                style = type.labelSm, color = colors.primary,
                            )
                        }
                    }
                } else {
                    Text(
                        text = when {
                            model.peopleCount == 0 &&
                                model.outcome.subjectOptions.mode ==
                                com.andreseloy.colorsapp.subject.SubjectMode.OFF ->
                                stringResource(R.string.w3_crop_off_short)
                            model.peopleCount == 0 ->
                                stringResource(R.string.w3_no_people_full)
                            else -> stringResource(R.string.w3_one_person)
                        },
                        style = type.labelSm, color = colors.onSurfaceVariant,
                        modifier = Modifier.weight(1f).testTag("result.peopleSummary"),
                        maxLines = 1,
                    )
                }
                val layersInteraction = remember { MutableInteractionSource() }
                Box(
                    Modifier
                        .size(SolarSizes.minTouch)
                        .solarPress(layersInteraction, 0.95f)
                        .clickable(
                            interactionSource = layersInteraction, indication = null,
                            role = Role.Button,
                            enabled = onOpenLayers != null && !model.reanalyzing,
                        ) { onOpenLayers?.invoke() }
                        .semantics {
                            contentDescription = ""
                        }
                        .testTag("result.layers"),
                    contentAlignment = Alignment.Center,
                ) {
                    Box(
                        Modifier.size(32.dp).clip(CircleShape).background(colors.container),
                        contentAlignment = Alignment.Center,
                    ) {
                        Icon(
                            SolarIconLayers, contentDescription = null, tint = colors.primary,
                            modifier = Modifier.size(16.dp),
                        )
                    }
                }
            }
        }
    }
}

/* ---------------- Top-1 y filas del top-3 ---------------- */

@Composable
fun TopMatchCard(
    model: ResultModel,
    match: ComboMatchSummary,
    score: Double,
    explanation: MatchExplanation?,
    dictionary: WadaDictionary,
    onOpen: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val colors = SolarTheme.colors
    val type = SolarTheme.type
    val locale = w3Locale()
    SolarCard(modifier.fillMaxWidth().testTag("result.topCard")) {
        Column(verticalArrangement = Arrangement.spacedBy(SolarSpacing.md)) {
            Row(
                Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Row(
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(6.dp),
                ) {
                    Icon(
                        SolarIconSparkles, contentDescription = null, tint = colors.secondary,
                        modifier = Modifier.size(13.dp),
                    )
                    Text(
                        stringResource(R.string.w3_looks_like).uppercase(),
                        style = type.overline, color = colors.secondary,
                    )
                }
                Box(
                    Modifier.clip(RoundedCornerShape(50)).background(colors.containerHighest)
                        .padding(horizontal = SolarSpacing.sm, vertical = 2.dp),
                ) {
                    Text(
                        numberLabel(match.comboId), style = type.labelSm,
                        color = colors.onSurfaceVariant,
                    )
                }
            }
            val interaction = remember { MutableInteractionSource() }
            Column(
                Modifier
                    .fillMaxWidth()
                    .solarPress(interaction)
                    .clickable(
                        interactionSource = interaction, indication = null, role = Role.Button,
                    ) { onOpen() }
                    .testTag("result.openCombo"),
                verticalArrangement = Arrangement.spacedBy(SolarSpacing.sm),
            ) {
                WellContainer(Modifier.fillMaxWidth()) {
                    SwatchStrip(argbColors = match.colors.map { it.argb }, height = 56.dp)
                }
                Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
                    Text(
                        match.name ?: numberLabel(match.comboId),
                        style = type.headlineLgMobile, color = colors.onSurface,
                        modifier = Modifier.testTag("result.top1"),
                    )
                    Row(
                        Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.SpaceBetween,
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        Text(
                            comboSubtitle(match.comboId, match.size),
                            style = type.bodySm, color = colors.onSurfaceVariant,
                        )
                        Icon(
                            SolarIconChevronRight, contentDescription = null,
                            tint = colors.onSurfaceVariant, modifier = Modifier.size(13.dp),
                        )
                    }
                    Text(
                        stringResource(
                            R.string.w3_score_better, W3Format.score(score, locale),
                        ),
                        style = type.bodySm, color = colors.onSurfaceVariant,
                    )
                }
            }
            explanation?.let { e ->
                Column(verticalArrangement = Arrangement.spacedBy(SolarSpacing.xs)) {
                    Text(
                        stringResource(
                            R.string.w3_explain_terms,
                            W3Format.score(e.fitTerm, locale),
                            W3Format.score(e.coverageTerm, locale),
                            W3Format.score(e.hypothesisPenalty, locale),
                        ),
                        style = type.bodySm, color = colors.onSurfaceVariant,
                    )
                    Text(
                        explainSummary(
                            e, coverageLambda = com.andreseloy.colorsapp.engine
                                .MatchOptions.DEFAULT.coverageLambda,
                            locale = locale,
                            resources = androidx.compose.ui.platform.LocalContext.current.resources,
                        ),
                        style = type.bodySm, color = colors.onSurfaceVariant,
                    )
                    // Cada color de la combinación contra su swatch más cercano (ΔE00).
                    e.perColor.forEach { line ->
                        val wada = dictionary.color(line.colorIndex)
                        Row(
                            Modifier.fillMaxWidth(),
                            verticalAlignment = Alignment.CenterVertically,
                            horizontalArrangement = Arrangement.spacedBy(SolarSpacing.sm),
                        ) {
                            if (wada != null) {
                                Box(
                                    Modifier.size(14.dp).clip(CircleShape)
                                        .background(Color(wada.argb))
                                        .border(0.5.dp, colors.swatchHairline, CircleShape),
                                )
                            }
                            Text(
                                wada?.name ?: stringResource(R.string.w3_color_n, line.colorIndex),
                                style = type.bodySm, color = colors.onSurface,
                                modifier = Modifier.weight(1f), maxLines = 1,
                            )
                            Text(
                                stringResource(
                                    R.string.w3_delta_e, W3Format.deltaEValue(line.deltaE, locale),
                                ),
                                style = type.bodySm, color = colors.onSurfaceVariant,
                            )
                        }
                    }
                }
            }
            if (match.ambiguousWithTop2 && model.hits.size >= 2) {
                Box(
                    Modifier.clip(RoundedCornerShape(50)).background(colors.secondaryFixed)
                        .padding(horizontal = SolarSpacing.sm, vertical = SolarSpacing.xs)
                        .testTag("result.ambiguous"),
                ) {
                    Text(
                        stringResource(
                            R.string.w3_between,
                            numberLabel(match.comboId), numberLabel(model.hits[1].comboId),
                        ),
                        style = type.labelMd, color = colors.onSecondaryFixedVariant,
                    )
                }
            }
            Box(Modifier.fillMaxWidth().height(1.dp).background(colors.outlineVariant))
            // Voto: un solo veredicto.
            Column(verticalArrangement = Arrangement.spacedBy(SolarSpacing.sm)) {
                Text(
                    stringResource(R.string.w3_is_this_combo),
                    style = type.labelLg, color = colors.onSurface,
                )
                Row(
                    Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.spacedBy(SolarSpacing.sm),
                ) {
                    VoteButton(
                        title = stringResource(
                            if (model.verdict == FeedbackVerdict.YES) {
                                R.string.w3_it_is
                            } else {
                                R.string.w3_yes_it_is
                            },
                        ),
                        icon = if (model.verdict == FeedbackVerdict.YES) {
                            SolarIconHeartFilled
                        } else {
                            SolarIconHeart
                        },
                        chosen = model.verdict == FeedbackVerdict.YES,
                        chosenFill = colors.primaryFixed,
                        enabled = model.verdict == null && !model.busy && !model.reanalyzing,
                        testTag = "result.yes",
                        modifier = Modifier.weight(1f),
                    ) { model.vote(FeedbackVerdict.YES) }
                    VoteButton(
                        title = stringResource(R.string.w3_no_short),
                        icon = SolarIconThumbDown,
                        chosen = model.verdict == FeedbackVerdict.NO,
                        chosenFill = colors.secondaryFixed,
                        enabled = model.verdict == null && !model.busy && !model.reanalyzing,
                        testTag = "result.no",
                        modifier = Modifier.weight(1f),
                    ) { model.vote(FeedbackVerdict.NO) }
                }
                model.verdict?.let { verdict ->
                    Row(
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(SolarSpacing.xs),
                        modifier = Modifier.testTag("result.thanks"),
                    ) {
                        Icon(
                            SolarIconSeal, contentDescription = null, tint = colors.primary,
                            modifier = Modifier.size(14.dp),
                        )
                        Text(
                            stringResource(
                                if (verdict == FeedbackVerdict.YES) {
                                    R.string.w3_thanks_hit_period
                                } else {
                                    R.string.w3_thanks_miss
                                },
                            ),
                            style = type.bodySm, color = colors.primary,
                        )
                    }
                }
            }
            // Desbloqueo
            when (model.unlockState) {
                UnlockState.UNKNOWN, UnlockState.LOCKED -> Row(
                    Modifier.fillMaxWidth(),
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(SolarSpacing.sm),
                ) {
                    Icon(
                        SolarIconLock, contentDescription = null, tint = colors.onSurfaceVariant,
                        modifier = Modifier.size(14.dp),
                    )
                    Text(
                        stringResource(R.string.w3_not_in_grid_yet),
                        style = type.bodySm, color = colors.onSurfaceVariant,
                        modifier = Modifier.weight(1f),
                    )
                    PillButton(
                        text = stringResource(R.string.w3_unlock),
                        icon = SolarIconLockOpen,
                        onClick = { model.unlock() },
                        enabled = model.topHit != null && !model.busy &&
                            model.unlockState != UnlockState.UNKNOWN,
                        filled = true,
                        modifier = Modifier.testTag("result.unlock"),
                    )
                }
                UnlockState.UNLOCKED_NOW -> UnlockLine(
                    stringResource(R.string.w3_unlocked_now), "result.unlocked",
                )
                UnlockState.ALREADY_UNLOCKED -> UnlockLine(
                    stringResource(R.string.w3_already_in_grid), "result.already",
                )
            }
        }
    }
}

@Composable
private fun UnlockLine(text: String, testTag: String) {
    val colors = SolarTheme.colors
    Row(
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(SolarSpacing.xs),
        modifier = Modifier.testTag(testTag),
    ) {
        Icon(
            SolarIconSeal, contentDescription = null, tint = colors.primary,
            modifier = Modifier.size(14.dp),
        )
        Text(text, style = SolarTheme.type.labelMd, color = colors.primary)
    }
}

@Composable
private fun VoteButton(
    title: String,
    icon: androidx.compose.ui.graphics.vector.ImageVector,
    chosen: Boolean,
    chosenFill: Color,
    enabled: Boolean,
    testTag: String,
    modifier: Modifier = Modifier,
    onClick: () -> Unit,
) {
    val colors = SolarTheme.colors
    val interaction = remember { MutableInteractionSource() }
    Row(
        modifier
            .height(SolarSizes.minTouch)
            .solarPress(interaction, 0.95f)
            .clip(RoundedCornerShape(50))
            .background(if (chosen) chosenFill else colors.container)
            .clickable(
                interactionSource = interaction, indication = null,
                role = Role.Button, enabled = enabled,
            ) { onClick() }
            .padding(horizontal = SolarSpacing.md)
            .testTag(testTag),
        horizontalArrangement = Arrangement.Center,
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Icon(
            icon, contentDescription = null,
            tint = if (enabled || chosen) colors.primary else colors.onSurfaceVariant,
            modifier = Modifier.size(16.dp),
        )
        Box(Modifier.size(6.dp))
        Text(
            title, style = SolarTheme.type.labelMd,
            color = if (chosen) colors.onPrimaryFixed else colors.primary, maxLines = 1,
        )
    }
}

/** Fila del top-2/top-3 (ExtractMatchRow). */
@Composable
fun MatchRow(
    rank: Int,
    match: ComboMatchSummary,
    score: Double,
    onOpen: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val colors = SolarTheme.colors
    val type = SolarTheme.type
    val locale = w3Locale()
    val interaction = remember { MutableInteractionSource() }
    Row(
        modifier
            .fillMaxWidth()
            .height(SolarSizes.minTouch + 8.dp)
            .solarPress(interaction)
            .clickable(
                interactionSource = interaction, indication = null, role = Role.Button,
            ) { onOpen() }
            .testTag("result.match.$rank"),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(SolarSpacing.md),
    ) {
        WellContainer(Modifier.width(104.dp), compact = true) {
            SwatchStrip(argbColors = match.colors.map { it.argb }, height = 28.dp)
        }
        Column(Modifier.weight(1f)) {
            Text(
                match.name ?: numberLabel(match.comboId),
                style = type.cardTitle, color = colors.onSurface, maxLines = 2,
            )
            Text(
                "${comboSubtitle(match.comboId, match.size)} · ${stringResource(R.string.w3_score_better, W3Format.score(score, locale))}",
                style = type.bodySm, color = colors.onSurfaceVariant, maxLines = 1,
            )
        }
        Icon(
            SolarIconChevronRight, contentDescription = null, tint = colors.onSurfaceVariant,
            modifier = Modifier.size(13.dp),
        )
    }
}

/**
 * Resumen en prosa de la explicacion (LayerStack.explanationCards, rank 0):
 * score = ajuste + cobertura + penalizacion, que significa cada termino y
 * la hipotesis de luz supuesta.
 */
fun explainSummary(
    e: MatchExplanation,
    coverageLambda: Double,
    locale: java.util.Locale,
    resources: android.content.res.Resources,
): String {
    fun num(v: Double, digits: Int) = W3Format.number(v, digits, locale)
    val parts = mutableListOf<String>()
    parts += resources.getString(
        R.string.w3_explain_summary_score,
        num(e.score, 2), num(e.fitTerm, 2), num(e.coverageTerm, 2), num(e.hypothesisPenalty, 2),
    )
    parts += resources.getString(R.string.w3_explain_fit, num(e.fitTerm, 2))
    val meanCoverage = if (coverageLambda > 0) e.coverageTerm / coverageLambda else 0.0
    parts += resources.getString(R.string.w3_explain_coverage, num(meanCoverage, 2))
    if (e.hypothesisPenalty > 0) {
        val hypothesis = hypothesisText(e.exposureEv, e.illuminant, locale, resources)
        val isGerman = locale.language == "de"
        val inline = if (isGerman) hypothesis else hypothesis.lowercase(locale)
        parts += resources.getString(
            R.string.w3_explain_hypothesis, inline, num(e.hypothesisPenalty, 2),
        )
    } else {
        parts += resources.getString(R.string.w3_explain_no_correction)
    }
    parts += resources.getString(R.string.w3_explain_wins)
    return parts.joinToString(" ") { it.trim() }
}

/** Hipotesis de luz supuesta (LayerStack.hypothesisText). */
fun hypothesisText(
    exposureEv: Double,
    illuminant: Int,
    locale: java.util.Locale,
    resources: android.content.res.Resources,
): String {
    val parts = mutableListOf<String>()
    if (exposureEv != 0.0) {
        parts += resources.getString(
            R.string.w3_exposure_part,
            if (exposureEv > 0) "+" else "", W3Format.number(exposureEv, 1, locale),
        )
    }
    if (illuminant >= 0) {
        val light = resources.getString(
            when (illuminant) {
                0 -> R.string.w3_light_a
                1 -> R.string.w3_light_d50
                2 -> R.string.w3_light_d65
                3 -> R.string.w3_light_d75
                4 -> R.string.w3_light_f2
                else -> R.string.w3_light_n
            },
            illuminant,
        )
        parts += resources.getString(R.string.w3_illuminant_part, light)
    }
    if (parts.isEmpty()) return resources.getString(R.string.w3_no_correction_photo)
    return ResultNotice.capitalizedFirst(
        parts.joinToString(resources.getString(R.string.w3_join_and)),
    )
}
