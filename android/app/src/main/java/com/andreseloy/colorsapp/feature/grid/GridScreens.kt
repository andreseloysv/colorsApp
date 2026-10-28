// Rejilla (Views/Rejilla + Explorar de iOS): las 348 combinaciones con
// buscador (nombre, número o #hex resuelto por el motor), filtros por
// tamaño y estado, tarjeta al azar, ficha con colores, fotos que la
// encontraron, tarjeta para compartir y búsqueda por color.
package com.andreseloy.colorsapp.feature.grid

import android.content.Context
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.GridItemSpan
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalClipboardManager
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.unit.dp
import com.andreseloy.colorsapp.R
import com.andreseloy.colorsapp.app.AppContainer
import com.andreseloy.colorsapp.data.ScanRecord
import com.andreseloy.colorsapp.data.ScanSource
import com.andreseloy.colorsapp.data.WadaCombo
import com.andreseloy.colorsapp.design.*
import com.andreseloy.colorsapp.engine.ColorMath
import com.andreseloy.colorsapp.engine.WadaEngineDictionary
import kotlinx.coroutines.launch
import java.text.DateFormat
import java.util.Date

// Nombres propuestos por el usuario (ComboNaming de iOS): preferencia local
// hasta que W1 decida su tabla; nunca toca los nombres curados protegidos.
private fun proposedName(ctx: Context, id: Int): String? =
    ctx.getSharedPreferences("w4_combo_names", Context.MODE_PRIVATE).getString("combo_$id", null)?.trim()?.takeIf { it.isNotEmpty() }
private fun setProposedName(ctx: Context, id: Int, name: String) {
    ctx.getSharedPreferences("w4_combo_names", Context.MODE_PRIVATE).edit().putString("combo_$id", name.trim()).apply()
}

@Composable
fun W4GridScreen(container: AppContainer, onOpenLayers: () -> Unit = {}, modifier: Modifier = Modifier) {
    var selectedId by remember { mutableStateOf<Int?>(null) }
    if (selectedId != null) {
        ComboDetailScreen(container, selectedId!!, onBack = { selectedId = null }, onOpenLayers = onOpenLayers,
            onOpenCombo = { selectedId = it }, modifier = modifier)
    } else {
        GridList(container, onOpenCombo = { selectedId = it }, modifier = modifier)
    }
}

@Composable
private fun GridList(container: AppContainer, onOpenCombo: (Int) -> Unit, modifier: Modifier = Modifier) {
    val dict = container.dictionary
    val unlocked by container.unlocks.observeUnlockedIds().collectAsState(initial = emptySet())
    var query by remember { mutableStateOf("") }
    var size by remember { mutableStateOf<Int?>(null) }
    var status by remember { mutableStateOf<StatusFilter?>(null) }
    var showColorSearch by remember { mutableStateOf(false) }
    var randomId by remember { mutableStateOf(GridFilters.nextRandom(null, dict.combinations.size)) }
    val context = LocalContext.current
    val type = SolarTheme.type; val colors = SolarTheme.colors

    val parsed = remember(query, dict.combinations.size) { GridSearch.interpret(query, dict.combinations.size) }
    // El hex lo resuelve el motor C (srgbToLab + nearest), como ColorSearch.
    val nearest = remember(parsed) {
        if (parsed is GridQuery.Hex) runCatching {
            val rgb = GridSearch.parseHexRgb(parsed.normalized)!!
            WadaEngineDictionary.nearestColor(ColorMath.srgbToLab(rgb[0], rgb[1], rgb[2]))
        }.getOrNull() else null
    }
    val haystacks = remember(dict) {
        dict.combinations.associate { c ->
            c.id to GridSearch.haystack(c, dict.curatedName(c.id) ?: proposedName(context, c.id) ?: "", dict.colorsOf(c.id).map { it.name })
        }
    }
    val filtered = remember(size, status, unlocked, parsed, nearest) {
        GridSearch.filter(GridFilters.apply(dict.combinations, size, status, unlocked), parsed, nearest?.first, haystacks)
    }
    val scopeTotal = GridFilters.sizeScope(dict, size).size
    val scopeUnlocked = GridFilters.unlockedInScope(dict, size, unlocked)

    if (showColorSearch) {
        ColorSearchSheet(container, onClose = { showColorSearch = false }, onShowInGrid = { hex ->
            query = hex; showColorSearch = false
        })
    }

    Column(modifier.fillMaxSize().windowInsetsPadding(WindowInsets.statusBars)) {
        SolarHeader(section = stringResource(R.string.section_grid)) {
            SolarHeaderButton(SolarIconSparkles, stringResource(R.string.w4_search_by_color), onClick = { showColorSearch = true })
        }
        OutlinedTextField(
            value = query, onValueChange = { query = it },
            placeholder = { Text(stringResource(R.string.w4_search_hint), style = type.bodyMd) },
            singleLine = true,
            modifier = Modifier.fillMaxWidth().padding(horizontal = SolarSpacing.margin, vertical = SolarSpacing.sm)
                .semantics { contentDescription = "rejilla.search" },
        )
        LazyRow(Modifier.padding(horizontal = SolarSpacing.margin), horizontalArrangement = Arrangement.spacedBy(SolarSpacing.sm)) {
            item { SolarChip(stringResource(R.string.w4_all), size == null, { size = null }) }
            item { SolarChip(stringResource(R.string.w4_size_2), size == 2, { size = if (size == 2) null else 2 }) }
            item { SolarChip(stringResource(R.string.w4_size_3), size == 3, { size = if (size == 3) null else 3 }) }
            item { SolarChip(stringResource(R.string.w4_size_4), size == 4, { size = if (size == 4) null else 4 }) }
            item { SolarChip(stringResource(R.string.w4_unlocked), status == StatusFilter.UNLOCKED, { status = if (status == StatusFilter.UNLOCKED) null else StatusFilter.UNLOCKED }) }
            item { SolarChip(stringResource(R.string.w4_locked), status == StatusFilter.LOCKED, { status = if (status == StatusFilter.LOCKED) null else StatusFilter.LOCKED }) }
        }
        Row(Modifier.fillMaxWidth().padding(SolarSpacing.margin, SolarSpacing.sm), horizontalArrangement = Arrangement.SpaceBetween) {
            Text(stringResource(R.string.w4_progress, scopeUnlocked, scopeTotal), style = type.labelMd, color = colors.primary)
            Text(stringResource(R.string.w4_results, filtered.size), style = type.labelSm, color = colors.onSurfaceVariant)
        }
        LinearProgressIndicator(
            progress = { if (scopeTotal == 0) 0f else scopeUnlocked.toFloat() / scopeTotal },
            modifier = Modifier.fillMaxWidth().padding(horizontal = SolarSpacing.margin).height(6.dp).clip(RoundedCornerShape(50)),
            color = colors.primary, trackColor = colors.containerLow,
        )
        if (parsed is GridQuery.NumberOutOfRange) {
            Text(stringResource(R.string.w4_no_such_combo, parsed.n), style = type.bodySm, color = colors.error,
                modifier = Modifier.padding(horizontal = SolarSpacing.margin, vertical = SolarSpacing.xs))
        }
        if (parsed is GridQuery.Hex && nearest != null) {
            val c = dict.color(nearest.first)
            Text(stringResource(R.string.w4_nearest_color, c?.name ?: "", "ΔE %.2f".format(nearest.second), dict.combosContaining(nearest.first).size),
                style = type.bodySm, color = colors.onSurfaceVariant,
                modifier = Modifier.padding(horizontal = SolarSpacing.margin, vertical = SolarSpacing.xs))
        }
        LazyVerticalGrid(
            columns = GridCells.Fixed(2), modifier = Modifier.fillMaxSize(),
            contentPadding = PaddingValues(SolarSpacing.margin),
            horizontalArrangement = Arrangement.spacedBy(SolarSpacing.gutter),
            verticalArrangement = Arrangement.spacedBy(SolarSpacing.gutter),
        ) {
            item(span = { GridItemSpan(maxLineSpan) }) {
                RandomCard(container, randomId, unlocked.contains(randomId),
                    onAnother = { randomId = GridFilters.nextRandom(randomId, dict.combinations.size) },
                    onOpen = { onOpenCombo(randomId) })
            }
            if (filtered.isEmpty()) {
                item(span = { GridItemSpan(maxLineSpan) }) {
                    SolarCard(Modifier.fillMaxWidth()) {
                        Column(verticalArrangement = Arrangement.spacedBy(SolarSpacing.md)) {
                            Text(stringResource(R.string.w4_no_combos), style = type.cardTitle, color = colors.onSurface)
                            SolarSecondaryButton(stringResource(R.string.w4_clear_filters), onClick = { query = ""; size = null; status = null })
                        }
                    }
                }
            }
            items(filtered, key = { it.id }) { combo ->
                ComboGridCard(container, combo, combo.id in unlocked) { onOpenCombo(combo.id) }
            }
        }
    }
}

@Composable
private fun RandomCard(container: AppContainer, comboId: Int, unlocked: Boolean, onAnother: () -> Unit, onOpen: () -> Unit) {
    val dict = container.dictionary; val type = SolarTheme.type; val colors = SolarTheme.colors
    val comboColors = remember(comboId) { dict.colorsOf(comboId) }
    SolarCard(Modifier.fillMaxWidth().clickable { onOpen() }) {
        Column(verticalArrangement = Arrangement.spacedBy(SolarSpacing.md)) {
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                Text(stringResource(R.string.w4_random).uppercase(), style = type.overline, color = colors.secondary)
                Text(stringResource(R.string.w4_combo_number, comboId), style = type.hex, color = colors.wellTextSecondary)
            }
            WellContainer(Modifier.fillMaxWidth()) { SwatchStrip(comboColors.map { it.argb }, height = SolarSizes.gridStripes) }
            Text(dict.curatedName(comboId) ?: comboColors.joinToString(" + ") { it.name }, style = type.headlineSm, color = colors.onSurface)
            if (!unlocked) Text(stringResource(R.string.w4_status_locked), style = type.labelSm, color = colors.onSurfaceVariant)
            SolarPrimaryButton(stringResource(R.string.w4_another), onClick = onAnother, icon = SolarIconSparkles)
        }
    }
}

@Composable
private fun ComboGridCard(container: AppContainer, combo: WadaCombo, unlocked: Boolean, onOpen: () -> Unit) {
    val dict = container.dictionary; val type = SolarTheme.type; val colors = SolarTheme.colors
    val comboColors = remember(combo.id) { dict.colorsOf(combo.id) }
    SolarCard(Modifier.fillMaxWidth().clickable { onOpen() }.semantics { contentDescription = "rejilla.combo.${combo.id}" }) {
        Column(verticalArrangement = Arrangement.spacedBy(SolarSpacing.sm)) {
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                Text(dict.curatedName(combo.id) ?: stringResource(R.string.w4_combo_number, combo.id),
                    style = type.labelMd, color = colors.onSurface, modifier = Modifier.weight(1f), maxLines = 2)
                if (unlocked) Text("●", color = colors.primary, style = type.labelMd)
            }
            WellContainer(Modifier.fillMaxWidth(), compact = true) { SwatchStrip(comboColors.map { it.argb }, height = 64.dp) }
            Text(comboColors.joinToString(" · ") { it.hex }, style = type.hex, color = colors.wellTextSecondary, maxLines = 2)
        }
    }
}

@Composable
fun ComboDetailScreen(
    container: AppContainer, comboId: Int, onBack: () -> Unit,
    onOpenLayers: () -> Unit = {}, onOpenCombo: (Int) -> Unit = {}, modifier: Modifier = Modifier,
) {
    val dict = container.dictionary; val context = LocalContext.current
    val scope = rememberCoroutineScope(); val clipboard = LocalClipboardManager.current
    val type = SolarTheme.type; val colors = SolarTheme.colors
    val combo = dict.combo(comboId)
    var unlock by remember { mutableStateOf<com.andreseloy.colorsapp.data.UnlockRecord?>(null) }
    var scans by remember { mutableStateOf<List<ScanRecord>>(emptyList()) }
    var nameDraft by remember(comboId) { mutableStateOf(proposedName(context, comboId) ?: "") }
    var copied by remember { mutableStateOf(false) }
    LaunchedEffect(comboId) {
        unlock = container.unlocks.record(comboId)
        scans = runCatching { container.scans.scansWithTop1(comboId) }.getOrDefault(emptyList())
    }
    Column(modifier.fillMaxSize().windowInsetsPadding(WindowInsets.statusBars).verticalScroll(rememberScrollState())) {
        Row(Modifier.fillMaxWidth().padding(SolarSpacing.xs), verticalAlignment = Alignment.CenterVertically) {
            IconButton(onClick = onBack) { Icon(SolarIconBack, stringResource(R.string.back), tint = colors.primary) }
            Text(stringResource(R.string.w4_combo_number, comboId), style = type.brand, color = colors.primary)
            Spacer(Modifier.weight(1f))
            Text(stringResource(R.string.w4_counter, 0, dict.combinations.size), style = type.hex, color = colors.wellTextSecondary)
        }
        if (combo == null) { Text(stringResource(R.string.w4_no_such_combo, comboId), Modifier.padding(SolarSpacing.margin)); return@Column }
        val comboColors = dict.colorsOf(comboId)
        Column(Modifier.padding(horizontal = SolarSpacing.margin), verticalArrangement = Arrangement.spacedBy(SolarSpacing.md)) {
            Text(dict.curatedName(comboId) ?: nameDraft.ifBlank { comboColors.joinToString(" + ") { it.name } },
                style = type.headlineMd, color = colors.onSurface)
            WellContainer(Modifier.fillMaxWidth()) { SwatchStrip(comboColors.map { it.argb }, height = SolarSizes.gridStripes) }
            Text(stringResource(R.string.w4_colors).uppercase(), style = type.overline, color = colors.secondary)
            comboColors.forEach { c ->
                SolarCard(Modifier.fillMaxWidth().clickable { clipboard.setText(AnnotatedString(c.hex)); copied = true }) {
                    Row(horizontalArrangement = Arrangement.spacedBy(SolarSpacing.md), verticalAlignment = Alignment.CenterVertically) {
                        Box(Modifier.size(44.dp).clip(SolarRadius.blockShape).background(Color(c.argb)))
                        Column(Modifier.weight(1f)) {
                            Text(c.name, style = type.cardTitle, color = colors.onSurface)
                            val lab = remember(c.index) { runCatching { ColorMath.srgbToLab(c.rgb[0], c.rgb[1], c.rgb[2]) }.getOrNull() }
                            Text("${c.hex} · rgb ${c.rgb.joinToString(",")}" + (lab?.let { " · Lab %.1f %.1f %.1f".format(it.l, it.a, it.b) } ?: ""),
                                style = type.hex, color = colors.wellTextSecondary)
                            Text(stringResource(R.string.w4_color_in_combos, dict.combosContaining(c.index).size), style = type.labelSm, color = colors.onSurfaceVariant)
                        }
                    }
                }
            }
            if (copied) Text(stringResource(R.string.w4_hex_copied), style = type.labelMd, color = colors.primary)
            val u = unlock
            if (u != null) {
                val date = DateFormat.getDateInstance(DateFormat.MEDIUM).format(Date(u.firstSeenAtMs))
                Text(stringResource(R.string.w4_unlocked_since, date, sourceLabel(u.source)), style = type.bodySm, color = colors.onSurfaceVariant)
            } else {
                Text(stringResource(R.string.w4_locked_hint), style = type.bodySm, color = colors.onSurfaceVariant)
                SolarPrimaryButton(stringResource(R.string.w4_save_garden), onClick = {
                    scope.launch { container.unlocks.unlock(comboId, ScanSource.MANUAL); unlock = container.unlocks.record(comboId) }
                })
            }
            if (dict.curatedName(comboId) == null) {
                OutlinedTextField(nameDraft, { nameDraft = it }, label = { Text(stringResource(R.string.w4_proposed_name)) },
                    singleLine = true, modifier = Modifier.fillMaxWidth())
                SolarSecondaryButton(stringResource(R.string.w4_save), onClick = { setProposedName(context, comboId, nameDraft) })
            }
            Row(horizontalArrangement = Arrangement.spacedBy(SolarSpacing.sm)) {
                SolarSecondaryButton(stringResource(R.string.w4_copy_hex), onClick = {
                    clipboard.setText(AnnotatedString(comboColors.joinToString(" ") { it.hex })); copied = true
                }, modifier = Modifier.weight(1f))
                SolarSecondaryButton(stringResource(R.string.w4_share_card), onClick = {
                    val title = dict.curatedName(comboId) ?: "Nº $comboId"
                    shareBitmap(context, renderComboCard(title, comboColors.joinToString(" + ") { it.name },
                        comboColors.map { it.argb }, comboColors.map { it.hex }),
                        "chromasol-combo-$comboId.png", title)
                }, modifier = Modifier.weight(1f))
            }
            SolarSecondaryButton(stringResource(R.string.w4_open_layers), onClick = onOpenLayers)
            if (scans.isNotEmpty()) {
                Text(stringResource(R.string.w4_found_in_photos).uppercase(), style = type.overline, color = colors.secondary)
                scans.forEach { s -> ScanMiniRow(s) }
            }
            // Otras combinaciones con el primer color (navegación de Explorar).
            comboColors.firstOrNull()?.let { first ->
                val related = dict.combosContaining(first.index).filter { it.id != comboId }.take(6)
                if (related.isNotEmpty()) {
                    Text(first.name.uppercase(), style = type.overline, color = colors.secondary)
                    related.forEach { rel ->
                        SolarCard(Modifier.fillMaxWidth().clickable { onOpenCombo(rel.id) }) {
                            Column(verticalArrangement = Arrangement.spacedBy(SolarSpacing.sm)) {
                                Text(dict.curatedName(rel.id) ?: stringResource(R.string.w4_combo_number, rel.id), style = type.labelMd, color = colors.onSurface)
                                WellContainer(Modifier.fillMaxWidth(), compact = true) { SwatchStrip(dict.colorsOf(rel.id).map { it.argb }, height = 40.dp) }
                            }
                        }
                    }
                }
            }
            Box(Modifier.height(SolarSpacing.xl))
        }
    }
}

@Composable
internal fun ScanMiniRow(scan: ScanRecord) {
    val type = SolarTheme.type; val colors = SolarTheme.colors
    val hexes = remember(scan.paletteJson) { Regex("\"(#[0-9a-fA-F]{6})\"").findAll(scan.paletteJson).map { it.groupValues[1] }.toList() }
    val argbs = hexes.mapNotNull { h -> GridSearch.parseHexRgb(h)?.let { (0xFF shl 24) or (it[0] shl 16) or (it[1] shl 8) or it[2] } }
    SolarCard(Modifier.fillMaxWidth()) {
        Column(verticalArrangement = Arrangement.spacedBy(SolarSpacing.sm)) {
            if (argbs.isNotEmpty()) WellContainer(Modifier.fillMaxWidth(), compact = true) { SwatchStrip(argbs, height = SolarSizes.harvestStrip) }
            Text("${DateFormat.getDateInstance(DateFormat.MEDIUM).format(Date(scan.scannedAtMs))} · ${sourceLabel(scan.source)}" +
                (if (scan.ambiguous) " · ${stringResource(R.string.w4_ambiguous)}" else ""),
                style = type.labelSm, color = colors.onSurfaceVariant)
        }
    }
}

@Composable
internal fun sourceLabel(source: ScanSource): String = stringResource(when (source) {
    ScanSource.CAMERA -> R.string.w4_source_camera; ScanSource.PICKER -> R.string.w4_source_picker
    ScanSource.LIBRARY -> R.string.w4_source_library; ScanSource.MANUAL -> R.string.w4_source_manual
})

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun ColorSearchSheet(container: AppContainer, onClose: () -> Unit, onShowInGrid: (String) -> Unit) {
    val type = SolarTheme.type; val colors = SolarTheme.colors
    var hexText by remember { mutableStateOf("#C5A56E") }
    var error by remember { mutableStateOf(false) }
    var submitted by remember { mutableStateOf<String?>(null) }
    ModalBottomSheet(onDismissRequest = onClose) {
        Column(Modifier.padding(SolarSpacing.margin), verticalArrangement = Arrangement.spacedBy(SolarSpacing.md)) {
            Text(stringResource(R.string.w4_color_search_title), style = type.headlineSm, color = colors.onSurface)
            OutlinedTextField(hexText, { hexText = it; error = false }, label = { Text(stringResource(R.string.w4_hex_label)) },
                isError = error, singleLine = true, modifier = Modifier.fillMaxWidth())
            if (error) Text(stringResource(R.string.w4_hex_invalid), style = type.bodySm, color = colors.error)
            SolarPrimaryButton(stringResource(R.string.w4_search), onClick = {
                val n = GridSearch.normalizedHex(hexText)
                if (n == null) error = true else submitted = n
            })
            submitted?.let { n ->
                val rgb = GridSearch.parseHexRgb(n)
                val near = remember(n) { runCatching { WadaEngineDictionary.nearestColor(ColorMath.srgbToLab(rgb!![0], rgb[1], rgb[2])) }.getOrNull() }
                if (near != null) {
                    val c = container.dictionary.color(near.first)
                    if (c != null) {
                        WellContainer(Modifier.fillMaxWidth()) {
                            SwatchStrip(listOf((0xFF shl 24) or (rgb!![0] shl 16) or (rgb[1] shl 8) or rgb[2], c.argb), height = 72.dp)
                        }
                        Text(stringResource(R.string.w4_nearest_color, c.name, "ΔE %.2f".format(near.second),
                            container.dictionary.combosContaining(near.first).size), style = type.bodyMd, color = colors.onSurface)
                        SolarSecondaryButton(stringResource(R.string.w4_show_in_grid), onClick = { onShowInGrid(n) })
                    }
                }
            }
            SolarSecondaryButton(stringResource(R.string.w4_close), onClick = onClose)
            Box(Modifier.height(SolarSpacing.lg))
        }
    }
}
