// Jardín (Views/Garden de iOS): perfil de la colección, colecciones por
// tamaño, cosechas (análisis recientes), guardadas y estudio de
// exportación (JSON/CSV y tarjeta) por Intent, sin red.
package com.andreseloy.colorsapp.feature.garden

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.Text
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import com.andreseloy.colorsapp.R
import com.andreseloy.colorsapp.app.AppContainer
import com.andreseloy.colorsapp.data.ScanRecord
import com.andreseloy.colorsapp.data.ScanSource
import com.andreseloy.colorsapp.design.*
import com.andreseloy.colorsapp.feature.grid.ComboDetailScreen
import com.andreseloy.colorsapp.feature.grid.ScanMiniRow
import com.andreseloy.colorsapp.feature.grid.renderComboCard
import com.andreseloy.colorsapp.feature.grid.shareBitmap
import com.andreseloy.colorsapp.feature.grid.shareFile
import com.andreseloy.colorsapp.feature.grid.writeShareFile

private enum class GardenSegment { HARVESTS, SAVED }

@Composable
fun W4GardenScreen(container: AppContainer, onOpenLayers: () -> Unit = {}, onOpenSettings: () -> Unit = {}, modifier: Modifier = Modifier) {
    var selectedId by remember { mutableStateOf<Int?>(null) }
    if (selectedId != null) {
        ComboDetailScreen(container, selectedId!!, onBack = { selectedId = null }, onOpenLayers = onOpenLayers,
            onOpenCombo = { selectedId = it }, modifier = modifier)
        return
    }
    val dict = container.dictionary
    val context = LocalContext.current
    val type = SolarTheme.type; val colors = SolarTheme.colors
    val unlocks by container.unlocks.observeAll().collectAsState(initial = emptyList())
    val scansFlow = remember { container.scans.observeRecent(50) }
    val scans by scansFlow.collectAsState(initial = emptyList())
    var segment by remember { mutableStateOf(GardenSegment.HARVESTS) }
    var collectionSize by remember { mutableStateOf<Int?>(null) }
    var feedbackCounts by remember { mutableStateOf(0 to 0) }
    LaunchedEffect(Unit) { feedbackCounts = runCatching { container.feedback.counts() }.getOrDefault(0 to 0) }

    val unlockedIds = remember(unlocks) { unlocks.map { it.comboId }.toSet() }
    val collections = remember(unlocks) { GardenLogic.sizeCollections(dict, unlocks) }
    val topColors = remember(unlocks) { GardenLogic.topColors(dict, unlockedIds) }
    val accuracy = GardenLogic.accuracyText(feedbackCounts.first, feedbackCounts.first + feedbackCounts.second)
    val shareTitle = stringResource(R.string.w4_share_title)

    Column(modifier.fillMaxSize().windowInsetsPadding(WindowInsets.statusBars)) {
        SolarHeader(section = stringResource(R.string.section_garden))
        LazyColumn(
            Modifier.fillMaxSize(),
            contentPadding = PaddingValues(horizontal = SolarSpacing.margin, vertical = SolarSpacing.md),
            verticalArrangement = Arrangement.spacedBy(SolarSpacing.md),
        ) {
            item {
                SolarCard(Modifier.fillMaxWidth()) {
                    Column(verticalArrangement = Arrangement.spacedBy(SolarSpacing.sm)) {
                        Row(horizontalArrangement = Arrangement.spacedBy(SolarSpacing.md)) {
                            ToneBadgeIcon(SolarIconLeaf, SolarTone.MOSS, null, size = SolarSizes.profileBadge)
                            Column(Modifier.weight(1f)) {
                                Text(stringResource(R.string.w4_progress, unlocks.size, dict.combinations.size), style = type.headlineSm, color = colors.onSurface)
                                Text("${stringResource(R.string.w4_photos_analyzed)}: ${scans.size}", style = type.bodySm, color = colors.onSurfaceVariant)
                                if (accuracy != null) Text(stringResource(R.string.w4_accuracy, accuracy, feedbackCounts.first, feedbackCounts.first + feedbackCounts.second),
                                    style = type.bodySm, color = colors.primary)
                            }
                            // Engranaje a Ajustes, como GardenProfileCard de iOS.
                            SolarHeaderButton(
                                icon = SolarIconGear,
                                contentDescription = stringResource(R.string.settings_title),
                                onClick = onOpenSettings,
                            )
                        }
                        if (topColors.isNotEmpty()) {
                            Text(stringResource(R.string.w4_top_colors).uppercase(), style = type.overline, color = colors.secondary)
                            LazyRow(horizontalArrangement = Arrangement.spacedBy(SolarSpacing.sm)) {
                                items(topColors) { (idx, n) ->
                                    val c = dict.color(idx)
                                    if (c != null) Column(Modifier.width(64.dp)) {
                                        Box(Modifier.size(48.dp).clip(SolarRadius.blockShape).background(Color(c.argb)))
                                        Text("${c.hex}\n×$n", style = type.hex, color = colors.wellTextSecondary)
                                    }
                                }
                            }
                        }
                    }
                }
            }
            item { Text(stringResource(R.string.w4_collections).uppercase(), style = type.overline, color = colors.secondary) }
            items(collections) { col ->
                SolarCard(Modifier.fillMaxWidth().clickable { collectionSize = if (collectionSize == col.size) null else col.size }) {
                    Column(verticalArrangement = Arrangement.spacedBy(SolarSpacing.sm)) {
                        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                            Text(stringResource(when (col.size) { 2 -> R.string.w4_size_2; 3 -> R.string.w4_size_3; else -> R.string.w4_size_4 }), style = type.cardTitle, color = colors.onSurface)
                            Text(stringResource(R.string.w4_counter, col.unlocked, col.total), style = type.hex, color = colors.wellTextSecondary)
                        }
                        LinearProgressIndicator(progress = { col.fraction.toFloat() },
                            modifier = Modifier.fillMaxWidth().height(6.dp).clip(RoundedCornerShape(50)), color = colors.primary, trackColor = colors.containerLow)
                        if (collectionSize == col.size) {
                            dict.combinations.filter { it.size == col.size && it.id in unlockedIds }.take(12).forEach { combo ->
                                Row(Modifier.fillMaxWidth().clickable { selectedId = combo.id }, horizontalArrangement = Arrangement.spacedBy(SolarSpacing.sm)) {
                                    Box(Modifier.weight(1f)) {
                                        WellContainer(Modifier.fillMaxWidth(), compact = true) { SwatchStrip(dict.colorsOf(combo.id).map { it.argb }, height = 32.dp) }
                                    }
                                    Text(stringResource(R.string.w4_combo_number, combo.id), style = type.hex, color = colors.wellTextSecondary)
                                }
                            }
                        }
                    }
                }
            }
            item {
                LazyRow(horizontalArrangement = Arrangement.spacedBy(SolarSpacing.sm)) {
                    item { SolarChip(stringResource(R.string.w4_harvests), segment == GardenSegment.HARVESTS, { segment = GardenSegment.HARVESTS }) }
                    item { SolarChip(stringResource(R.string.w4_saved), segment == GardenSegment.SAVED, { segment = GardenSegment.SAVED }) }
                }
            }
            when (segment) {
                GardenSegment.HARVESTS -> {
                    if (scans.isEmpty()) item {
                        SolarCard(Modifier.fillMaxWidth()) { Text(stringResource(R.string.w4_garden_empty), style = type.bodyMd, color = colors.onSurfaceVariant) }
                    } else items(scans, key = { it.id }) { scan ->
                        Box(Modifier.clickable { scan.top1?.let { selectedId = it } }.semantics { contentDescription = "garden.harvest.${scan.id}" }) {
                            HarvestCard(container, scan)
                        }
                    }
                }
                GardenSegment.SAVED -> {
                    val saved = unlocks.filter { it.source == ScanSource.MANUAL }
                    if (saved.isEmpty()) item {
                        SolarCard(Modifier.fillMaxWidth()) { Text(stringResource(R.string.w4_no_saved), style = type.bodyMd, color = colors.onSurfaceVariant) }
                    } else items(saved, key = { it.comboId }) { u ->
                        SolarCard(Modifier.fillMaxWidth().clickable { selectedId = u.comboId }) {
                            Column(verticalArrangement = Arrangement.spacedBy(SolarSpacing.sm)) {
                                Text(dict.curatedName(u.comboId) ?: stringResource(R.string.w4_combo_number, u.comboId), style = type.cardTitle, color = colors.onSurface)
                                WellContainer(Modifier.fillMaxWidth(), compact = true) { SwatchStrip(dict.colorsOf(u.comboId).map { it.argb }, height = 48.dp) }
                            }
                        }
                    }
                }
            }
            item {
                SolarCard(Modifier.fillMaxWidth()) {
                    Column(verticalArrangement = Arrangement.spacedBy(SolarSpacing.md)) {
                        Text(stringResource(R.string.w4_export_studio).uppercase(), style = type.overline, color = colors.secondary)
                        SolarSecondaryButton(stringResource(R.string.w4_export_json), onClick = {
                            val uri = writeShareFile(context, "chromasol-coleccion.json", GardenLogic.collectionJson(dict, unlocks).toByteArray())
                            shareFile(context, uri, "application/json", shareTitle)
                        })
                        SolarSecondaryButton(stringResource(R.string.w4_export_csv), onClick = {
                            val uri = writeShareFile(context, "chromasol-cosechas.csv", GardenLogic.harvestsCsv(scans).toByteArray())
                            shareFile(context, uri, "text/csv", shareTitle)
                        })
                        val latestCombo = scans.firstOrNull()?.top1
                        if (latestCombo != null) SolarSecondaryButton(stringResource(R.string.w4_share_card), onClick = {
                            val cs = dict.colorsOf(latestCombo)
                            shareBitmap(context, renderComboCard(dict.curatedName(latestCombo) ?: "Nº $latestCombo",
                                cs.joinToString(" + ") { it.name }, cs.map { it.argb }, cs.map { it.hex }),
                                "chromasol-cosecha.png", shareTitle)
                        })
                    }
                }
            }
            item { Box(Modifier.height(SolarSpacing.xl)) }
        }
    }
}

@Composable
private fun HarvestCard(container: AppContainer, scan: ScanRecord) {
    val dict = container.dictionary; val type = SolarTheme.type; val colors = SolarTheme.colors
    SolarCard(Modifier.fillMaxWidth()) {
        Column(verticalArrangement = Arrangement.spacedBy(SolarSpacing.sm)) {
            ScanMiniRow(scan)
            scan.top1?.let { top ->
                Text(dict.curatedName(top) ?: dict.colorsOf(top).joinToString(" + ") { it.name }, style = type.cardTitle, color = colors.onSurface)
                WellContainer(Modifier.fillMaxWidth(), compact = true) { SwatchStrip(dict.colorsOf(top).map { it.argb }, height = SolarSizes.harvestStrip) }
            }
        }
    }
}
