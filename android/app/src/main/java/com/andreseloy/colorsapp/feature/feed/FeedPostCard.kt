// Publicacion del Feed: espejo de FeedLuminousPost.swift + FeedPostRow
// (FeedComponents.swift). Cabecera de origen, foto a sangre con pildora de
// lente y boton de abrir en Extraer, banda de pergamino con las gotas de la
// paleta en pocillo neutro, pie «Se parece a» y barra de acciones reales
// (Si/No/Guardar/Copiar/Compartir). Sin animaciones luminosas (W5).
package com.andreseloy.colorsapp.feature.feed

import android.graphics.Bitmap
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
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.produceState
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import com.andreseloy.colorsapp.R
import com.andreseloy.colorsapp.data.FeedbackVerdict
import com.andreseloy.colorsapp.design.SolarIconCamera
import com.andreseloy.colorsapp.design.SolarIconCheck
import com.andreseloy.colorsapp.design.SolarIconChevronRight
import com.andreseloy.colorsapp.design.SolarIconCopy
import com.andreseloy.colorsapp.design.SolarIconExpand
import com.andreseloy.colorsapp.design.SolarIconHeart
import com.andreseloy.colorsapp.design.SolarIconHeartFilled
import com.andreseloy.colorsapp.design.SolarIconPalette
import com.andreseloy.colorsapp.design.SolarIconPhoto
import com.andreseloy.colorsapp.design.SolarIconPhotoStack
import com.andreseloy.colorsapp.design.SolarIconShare
import com.andreseloy.colorsapp.design.SolarIconThumbDown
import com.andreseloy.colorsapp.design.SolarIconWarning
import com.andreseloy.colorsapp.design.SolarIconGrid
import com.andreseloy.colorsapp.design.SolarIconLeaf
import com.andreseloy.colorsapp.design.SolarSizes
import com.andreseloy.colorsapp.design.SolarSpacing
import com.andreseloy.colorsapp.design.SolarTheme
import com.andreseloy.colorsapp.design.SolarTone
import com.andreseloy.colorsapp.design.SwatchStrip
import com.andreseloy.colorsapp.design.ToneBadgeIcon
import com.andreseloy.colorsapp.design.WellContainer
import com.andreseloy.colorsapp.design.solarPress
import com.andreseloy.colorsapp.feature.extract.PaletteColor
import com.andreseloy.colorsapp.feature.extract.colorAccessibilityLabel
import com.andreseloy.colorsapp.feature.extract.comboSubtitle
import com.andreseloy.colorsapp.feature.extract.cropNoticeText
import com.andreseloy.colorsapp.feature.extract.numberLabel
import com.andreseloy.colorsapp.feature.extract.paletteTitleText
import com.andreseloy.colorsapp.feature.extract.personLabelText
import com.andreseloy.colorsapp.feature.extract.w3Locale
import java.time.ZoneId

/** Acciones de una publicacion (FeedPostHandlers de iOS). */
class FeedPostHandlers(
    val vote: (FeedbackVerdict) -> Unit,
    val toggleSave: () -> Unit,
    val copyCombo: () -> Unit,
    val copyPalette: () -> Unit,
    val copyColor: (PaletteColor) -> Unit,
    val openInExtract: (Bitmap?) -> Unit,
    val openCombo: (Int) -> Unit,
    val share: (Bitmap?) -> Unit,
    val delete: () -> Unit,
)

@Composable
fun FeedPostRow(
    item: FeedItemData,
    verdict: FeedbackVerdict?,
    isSaved: Boolean,
    isCopied: Boolean,
    isReopening: Boolean,
    loadPhoto: suspend () -> Bitmap?,
    handlers: FeedPostHandlers,
    modifier: Modifier = Modifier,
) {
    val photo by produceState<Bitmap?>(null, item.id, item.scan.rev) {
        value = loadPhoto()
    }
    var copiedColorIndex by remember(item.id) { mutableStateOf<Int?>(null) }
    Box(modifier.testTag("feed.post.${item.id}")) {
        FeedPostCard(
            item = item,
            photo = photo,
            verdict = verdict,
            isSaved = isSaved,
            isCopied = isCopied,
            copiedColorIndex = copiedColorIndex,
            handlers = handlers,
            onCopyColorMarked = { index ->
                copiedColorIndex = index
            },
            photoForActions = photo,
        )
        if (isReopening) {
            Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                Row(
                    Modifier.clip(RoundedCornerShape(12.dp))
                        .background(SolarTheme.colors.frostTint)
                        .padding(SolarSpacing.md),
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(SolarSpacing.sm),
                ) {
                    CircularProgressIndicator(
                        color = SolarTheme.colors.primary, modifier = Modifier.size(18.dp),
                    )
                    Text(
                        stringResource(R.string.w3_reanalyzing),
                        style = SolarTheme.type.labelMd, color = SolarTheme.colors.onSurface,
                    )
                }
            }
        }
    }
    // La marca de copiado de una gota dura 1,2 s (como en iOS).
    androidx.compose.runtime.LaunchedEffect(copiedColorIndex) {
        if (copiedColorIndex != null) {
            kotlinx.coroutines.delay(1200)
            copiedColorIndex = null
        }
    }
}

@Composable
private fun FeedPostCard(
    item: FeedItemData,
    photo: Bitmap?,
    verdict: FeedbackVerdict?,
    isSaved: Boolean,
    isCopied: Boolean,
    copiedColorIndex: Int?,
    handlers: FeedPostHandlers,
    onCopyColorMarked: (Int) -> Unit,
    photoForActions: Bitmap?,
) {
    val colors = SolarTheme.colors
    val type = SolarTheme.type
    val source = PostSource.of(item.scan.source)
    val isCamera = source == PostSource.CAMERA
    var menuOpen by remember { mutableStateOf(false) }
    var paletteCopies by remember { mutableIntStateOf(0) }

    Box(
        Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(12.dp))
            .background(colors.card)
            .border(1.dp, colors.brassHairline, RoundedCornerShape(12.dp)),
    ) {
        Column {
            // Cabecera de origen
            Row(
                Modifier.fillMaxWidth().padding(
                    start = SolarSpacing.margin, end = SolarSpacing.xs,
                    top = SolarSpacing.md, bottom = SolarSpacing.md,
                ),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(SolarSpacing.sm),
            ) {
                ToneBadgeIcon(
                    icon = when (source) {
                        PostSource.LIBRARY -> SolarIconPhotoStack
                        PostSource.CAMERA -> SolarIconCamera
                        PostSource.PICKED -> SolarIconPhoto
                    },
                    tone = if (isCamera) SolarTone.CELADON else SolarTone.AMBER,
                    contentDescription = null,
                )
                Column(Modifier.weight(1f)) {
                    Text(
                        text = stringResource(
                            when (source) {
                                PostSource.LIBRARY -> R.string.w3_source_library
                                PostSource.CAMERA -> R.string.w3_source_camera
                                PostSource.PICKED -> R.string.w3_source_picked
                            },
                        ),
                        style = type.labelLg, color = colors.onSurface, maxLines = 1,
                    )
                    val locale = w3Locale()
                    val metadata = buildList {
                        add(
                            FeedPostText.dateText(
                                item.scan.scannedAtMs, locale, ZoneId.systemDefault(),
                                System.currentTimeMillis(),
                            ),
                        )
                        item.person?.let { add(personLabelText(it)) }
                    }.joinToString(" · ")
                    Text(metadata, style = type.bodySm, color = colors.onSurfaceVariant, maxLines = 2)
                    if (item.isOutdated) {
                        Box(
                            Modifier.padding(top = 2.dp).clip(RoundedCornerShape(50))
                                .background(colors.container)
                                .padding(horizontal = SolarSpacing.sm, vertical = 2.dp),
                        ) {
                            Text(
                                stringResource(R.string.w3_outdated),
                                style = type.labelSm, color = colors.onSurfaceVariant,
                            )
                        }
                    }
                }
                Box {
                    val interaction = remember { MutableInteractionSource() }
                    Box(
                        Modifier
                            .size(SolarSizes.minTouch)
                            .solarPress(interaction, 0.95f)
                            .clickable(
                                interactionSource = interaction, indication = null,
                                role = Role.Button,
                            ) { menuOpen = true }
                            .semantics {
                                contentDescription = ""
                            },
                        contentAlignment = Alignment.Center,
                    ) {
                        Text("…", style = type.headlineSm, color = colors.onSurfaceVariant)
                    }
                    DropdownMenu(expanded = menuOpen, onDismissRequest = { menuOpen = false }) {
                        DropdownMenuItem(
                            text = { Text(stringResource(R.string.w3_open_in_extract)) },
                            onClick = {
                                menuOpen = false
                                handlers.openInExtract(photoForActions)
                            },
                        )
                        item.match?.let { match ->
                            DropdownMenuItem(
                                text = { Text(stringResource(R.string.w3_view_combo)) },
                                onClick = {
                                    menuOpen = false
                                    handlers.openCombo(match.comboId)
                                },
                            )
                        }
                        DropdownMenuItem(
                            text = {
                                Text(
                                    stringResource(R.string.w3_delete_from_feed),
                                    color = colors.error,
                                )
                            },
                            onClick = {
                                menuOpen = false
                                handlers.delete()
                            },
                        )
                    }
                }
            }
            Box(Modifier.fillMaxWidth().height(1.dp).background(colors.container))
            // Foto a sangre
            val aspect = (
                photo?.let { it.width.toFloat() / maxOf(it.height, 1) } ?: (4f / 5f)
                ).coerceIn(SolarSizes.postAspectRange)
            Box(
                Modifier
                    .fillMaxWidth()
                    .aspectRatio(aspect)
                    .background(colors.containerLow)
                    .clip(RoundedCornerShape(0.dp)),
            ) {
                if (photo != null) {
                    Image(
                        bitmap = photo.asImageBitmap(), contentDescription = null,
                        contentScale = ContentScale.Crop, modifier = Modifier.fillMaxSize(),
                    )
                } else {
                    Column(
                        Modifier.fillMaxSize(),
                        horizontalAlignment = Alignment.CenterHorizontally,
                        verticalArrangement = Arrangement.Center,
                    ) {
                        Icon(
                            SolarIconPhoto, contentDescription = null,
                            tint = colors.onSurfaceVariant, modifier = Modifier.size(32.dp),
                        )
                        Text(
                            stringResource(R.string.w3_photo_unavailable),
                            style = type.bodySm, color = colors.onSurfaceVariant,
                        )
                    }
                }
                item.notice?.let { notice ->
                    Row(
                        Modifier
                            .align(Alignment.BottomStart)
                            .padding(SolarSpacing.md)
                            .clip(RoundedCornerShape(50))
                            .background(colors.frostTint)
                            .padding(horizontal = 10.dp, vertical = 4.dp),
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(6.dp),
                    ) {
                        Icon(
                            if (notice.isFallback) SolarIconWarning else SolarIconCamera,
                            contentDescription = null, tint = colors.secondary,
                            modifier = Modifier.size(13.dp),
                        )
                        Text(
                            cropNoticeText(notice), style = type.labelSm,
                            color = if (notice.isFallback) colors.secondary else colors.onSurface,
                            maxLines = 1,
                        )
                    }
                }
                if (photo != null) {
                    val interaction = remember { MutableInteractionSource() }
                    val openLabel = stringResource(R.string.w3_open_in_extract)
                    Box(
                        Modifier
                            .align(Alignment.TopEnd)
                            .padding(6.dp)
                            .size(SolarSizes.minTouch)
                            .solarPress(interaction, 0.95f)
                            .clip(CircleShape)
                            .background(colors.frostTint)
                            .clickable(
                                interactionSource = interaction, indication = null,
                                role = Role.Button,
                            ) { handlers.openInExtract(photoForActions) }
                            .semantics { contentDescription = openLabel },
                        contentAlignment = Alignment.Center,
                    ) {
                        Icon(
                            SolarIconExpand, contentDescription = null, tint = colors.primary,
                            modifier = Modifier.size(18.dp),
                        )
                    }
                }
            }
            // Banda de paleta
            Column(
                Modifier.fillMaxWidth().background(colors.containerLow).padding(SolarSpacing.md),
                verticalArrangement = Arrangement.spacedBy(SolarSpacing.sm),
            ) {
                Row(
                    Modifier.fillMaxWidth(),
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(6.dp),
                ) {
                    Icon(
                        SolarIconPalette, contentDescription = null, tint = colors.primary,
                        modifier = Modifier.size(14.dp),
                    )
                    Text(
                        paletteTitleText(item.paletteTitle).uppercase(),
                        style = type.overline, color = colors.primary, maxLines = 1,
                        modifier = Modifier.weight(1f),
                    )
                    if (item.palette.isNotEmpty()) {
                        val interaction = remember { MutableInteractionSource() }
                        Row(
                            Modifier
                                .solarPress(interaction, 0.95f)
                                .clickable(
                                    interactionSource = interaction, indication = null,
                                    role = Role.Button,
                                ) {
                                    paletteCopies++
                                    handlers.copyPalette()
                                }
                                .semantics {
                                    contentDescription = ""
                                }
                                .padding(vertical = SolarSpacing.sm),
                            verticalAlignment = Alignment.CenterVertically,
                            horizontalArrangement = Arrangement.spacedBy(3.dp),
                        ) {
                            Icon(
                                SolarIconCopy, contentDescription = null, tint = colors.secondary,
                                modifier = Modifier.size(12.dp),
                            )
                            Text(
                                stringResource(R.string.w3_copy_hex),
                                style = type.labelSm, color = colors.secondary,
                            )
                        }
                    }
                }
                DropletWell(
                    colorsList = item.palette,
                    selectedIndex = copiedColorIndex,
                    onTap = { color, index ->
                        handlers.copyColor(color)
                        onCopyColorMarked(index)
                    },
                )
                MatchFooter(item) { id -> handlers.openCombo(id) }
            }
            // Barra de acciones
            ActionBar(
                verdict = verdict,
                isSaved = isSaved,
                isCopied = isCopied,
                hasMatch = item.match != null,
                onYes = { handlers.vote(FeedbackVerdict.YES) },
                onNo = { handlers.vote(FeedbackVerdict.NO) },
                onSave = handlers.toggleSave,
                onCopy = handlers.copyCombo,
                onShare = { handlers.share(photoForActions) },
            )
        }
    }
}

/** Gotas de la paleta en pocillo neutro: hasta 5 por fila (FeedDropletWell). */
@Composable
fun DropletWell(
    colorsList: List<PaletteColor>,
    selectedIndex: Int? = null,
    onTap: ((PaletteColor, Int) -> Unit)? = null,
    modifier: Modifier = Modifier,
) {
    val colors = SolarTheme.colors
    val type = SolarTheme.type
    WellContainer(modifier.fillMaxWidth()) {
        if (colorsList.isEmpty()) {
            Text(
                stringResource(R.string.w3_no_colors),
                style = type.bodySm, color = colors.wellTextSecondary,
                modifier = Modifier.fillMaxWidth().padding(vertical = SolarSpacing.md),
            )
        } else {
            Column(verticalArrangement = Arrangement.spacedBy(SolarSpacing.sm)) {
                colorsList.chunked(5).forEach { rowColors ->
                    Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                        rowColors.forEach { color ->
                            val index = colorsList.indexOf(color)
                            val selected = selectedIndex == index
                            val description = colorAccessibilityLabel(color, index, colorsList.size)
                            Column(
                                Modifier
                                    .weight(1f)
                                    .then(
                                        if (onTap != null) {
                                            Modifier.clickable(role = Role.Button) {
                                                onTap(color, index)
                                            }
                                        } else {
                                            Modifier
                                        },
                                    )
                                    .semantics { contentDescription = description },
                                horizontalAlignment = Alignment.CenterHorizontally,
                                verticalArrangement = Arrangement.spacedBy(SolarSpacing.xs),
                            ) {
                                Box(
                                    Modifier
                                        .padding(top = 4.dp)
                                        .size(SolarSizes.droplet)
                                        .clip(CircleShape)
                                        .background(Color(color.argb))
                                        .border(
                                            if (selected) 2.dp else 0.5.dp,
                                            if (selected) colors.wellText else colors.swatchHairline,
                                            CircleShape,
                                        ),
                                )
                                color.name?.let {
                                    Text(
                                        it, style = type.labelSm, color = colors.wellText,
                                        maxLines = 1,
                                    )
                                }
                                Text(
                                    color.hex, style = type.hex,
                                    color = colors.wellTextSecondary, maxLines = 1,
                                )
                            }
                        }
                        repeat(5 - rowColors.size) { Box(Modifier.weight(1f)) }
                    }
                }
            }
        }
    }
}

/** Pie «Se parece a» con tira de Wada (ComboMatchFooter). */
@Composable
private fun MatchFooter(item: FeedItemData, onOpenCombo: (Int) -> Unit) {
    val colors = SolarTheme.colors
    val type = SolarTheme.type
    Column(
        Modifier.fillMaxWidth().padding(top = SolarSpacing.xs),
        verticalArrangement = Arrangement.spacedBy(SolarSpacing.sm),
    ) {
        Text(
            stringResource(R.string.w3_looks_like).uppercase(),
            style = type.overline, color = colors.onSurfaceVariant,
        )
        val match = item.match
        if (match == null) {
            Text(
                stringResource(R.string.w3_no_combo_found),
                style = type.bodyMd, color = colors.onSurfaceVariant,
            )
        } else {
            val interaction = remember { MutableInteractionSource() }
            Row(
                Modifier
                    .fillMaxWidth()
                    .solarPress(interaction)
                    .clickable(
                        interactionSource = interaction, indication = null, role = Role.Button,
                    ) { onOpenCombo(match.comboId) },
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(SolarSpacing.md),
            ) {
                WellContainer(Modifier.width(104.dp), compact = true) {
                    SwatchStrip(argbColors = match.colors.map { it.argb }, height = 28.dp)
                }
                Column(Modifier.weight(1f)) {
                    Text(
                        match.name ?: numberLabel(match.comboId),
                        style = type.headlineSm, color = colors.onSurface, maxLines = 2,
                    )
                    Text(
                        comboSubtitle(match.comboId, match.size),
                        style = type.bodySm, color = colors.onSurfaceVariant,
                    )
                }
                Icon(
                    SolarIconChevronRight, contentDescription = null,
                    tint = colors.onSurfaceVariant, modifier = Modifier.size(14.dp),
                )
            }
            if (match.ambiguousWithTop2 && item.scan.top2 != null) {
                Box(
                    Modifier.clip(RoundedCornerShape(50)).background(colors.secondaryFixed)
                        .padding(horizontal = SolarSpacing.sm, vertical = SolarSpacing.xs),
                ) {
                    Text(
                        text = stringResource(
                            R.string.w3_between,
                            numberLabel(match.comboId), numberLabel(item.scan.top2!!),
                        ),
                        style = type.labelMd, color = colors.onSecondaryFixedVariant,
                    )
                }
            }
        }
    }
}

/** Barra de acciones reales: Sí / No / Guardar / Copiar / Compartir (un solo voto). */
@Composable
private fun ActionBar(
    verdict: FeedbackVerdict?,
    isSaved: Boolean,
    isCopied: Boolean,
    hasMatch: Boolean,
    onYes: () -> Unit,
    onNo: () -> Unit,
    onSave: () -> Unit,
    onCopy: () -> Unit,
    onShare: () -> Unit,
) {
    val colors = SolarTheme.colors
    val showLabels = LocalConfiguration.current.fontScale <= 1.3f
    Row(
        Modifier.fillMaxWidth().background(colors.card).padding(
            start = SolarSpacing.md, end = 2.dp, top = 2.dp, bottom = 2.dp,
        ),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(SolarSpacing.md),
    ) {
        ActionButton(
            title = stringResource(
                if (verdict == FeedbackVerdict.YES) R.string.w3_it_is else R.string.w3_yes_short,
            ),
            label = stringResource(R.string.w3_yes_it_is),
            icon = if (verdict == FeedbackVerdict.YES) SolarIconHeartFilled else SolarIconHeart,
            tint = if (verdict == FeedbackVerdict.YES) colors.secondary else colors.onSurfaceVariant,
            enabled = verdict == null || verdict == FeedbackVerdict.YES,
            showLabel = showLabels,
            testTag = "feed.yes",
            onClick = onYes,
        )
        ActionButton(
            title = stringResource(R.string.w3_no_short),
            label = stringResource(R.string.w3_no_it_isnt),
            icon = SolarIconThumbDown,
            tint = if (verdict == FeedbackVerdict.NO) colors.onSurface else colors.onSurfaceVariant,
            enabled = verdict == null || verdict == FeedbackVerdict.NO,
            showLabel = showLabels,
            testTag = "feed.no",
            onClick = onNo,
        )
        ActionButton(
            title = stringResource(if (isSaved) R.string.w3_saved_short else R.string.w3_save_short),
            label = stringResource(
                if (isSaved) R.string.w3_saved_in_garden_label else R.string.w3_save_in_garden_label,
            ),
            icon = SolarIconLeaf,
            tint = if (isSaved) colors.primary else colors.onSurfaceVariant,
            enabled = true,
            showLabel = showLabels,
            testTag = "feed.save",
            onClick = onSave,
        )
        if (hasMatch) {
            ActionButton(
                title = stringResource(
                    if (isCopied) R.string.w3_copied_short else R.string.w3_copy_short,
                ),
                label = stringResource(R.string.w3_copy_combo_hex),
                icon = if (isCopied) SolarIconCheck else SolarIconCopy,
                tint = if (isCopied) colors.primary else colors.onSurfaceVariant,
                enabled = true,
                showLabel = showLabels,
                testTag = "feed.copy",
                onClick = onCopy,
            )
        }
        Box(Modifier.weight(1f))
        val interaction = remember { MutableInteractionSource() }
        val shareLabel = stringResource(R.string.w3_share_card)
        Box(
            Modifier
                .size(SolarSizes.minTouch)
                .solarPress(interaction, 0.95f)
                .clickable(interactionSource = interaction, indication = null, role = Role.Button) {
                    onShare()
                }
                .testTag("feed.share")
                .semantics { contentDescription = shareLabel },
            contentAlignment = Alignment.Center,
        ) {
            Icon(
                SolarIconShare, contentDescription = null, tint = colors.onSurfaceVariant,
                modifier = Modifier.size(19.dp),
            )
        }
    }
}

@Composable
private fun ActionButton(
    title: String,
    label: String,
    icon: ImageVector,
    tint: Color,
    enabled: Boolean,
    showLabel: Boolean,
    testTag: String,
    onClick: () -> Unit,
) {
    val interaction = remember { MutableInteractionSource() }
    Row(
        Modifier
            .height(SolarSizes.minTouch)
            .solarPress(interaction, 0.95f)
            .clickable(
                interactionSource = interaction, indication = null,
                role = Role.Button, enabled = enabled,
            ) { onClick() }
            .testTag(testTag)
            .semantics { contentDescription = label },
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(SolarSpacing.xs),
    ) {
        Icon(
            icon, contentDescription = null,
            tint = if (enabled) tint else tint.copy(alpha = 0.45f),
            modifier = Modifier.size(19.dp),
        )
        if (showLabel) {
            Text(
                title, style = SolarTheme.type.labelMd,
                color = if (enabled) tint else tint.copy(alpha = 0.45f), maxLines = 1,
            )
        }
    }
}
