// Pantallas de la fundación: el Feed con su tarjeta del día real (datos del
// motor) y los esqueletos de Extraer, Rejilla y Jardín. Cada pantalla es de
// un carril de la ola 2; aquí solo demuestran el sistema de diseño y la
// navegación. El gesto «foto primero» (publicaciones del Feed) llega con el
// carril del Feed.
package com.andreseloy.colorsapp.feature

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.statusBars
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import com.andreseloy.colorsapp.R
import com.andreseloy.colorsapp.app.AppContainer
import com.andreseloy.colorsapp.design.SolarCard
import com.andreseloy.colorsapp.design.SolarChip
import com.andreseloy.colorsapp.design.SolarHeader
import com.andreseloy.colorsapp.design.SolarHeaderButton
import com.andreseloy.colorsapp.design.SolarIconCamera
import com.andreseloy.colorsapp.design.SolarIconDrop
import com.andreseloy.colorsapp.design.SolarIconGrid
import com.andreseloy.colorsapp.design.SolarIconLeaf
import com.andreseloy.colorsapp.design.SolarIconSparkles
import com.andreseloy.colorsapp.design.SolarPrimaryButton
import com.andreseloy.colorsapp.design.SolarSecondaryButton
import com.andreseloy.colorsapp.design.SolarSizes
import com.andreseloy.colorsapp.design.SolarSpacing
import com.andreseloy.colorsapp.design.SolarTheme
import com.andreseloy.colorsapp.design.SolarTone
import com.andreseloy.colorsapp.design.SwatchStrip
import com.andreseloy.colorsapp.design.ToneBadgeIcon
import com.andreseloy.colorsapp.design.WellContainer
import java.time.LocalDate

/** Combinación del día determinista (marcador: el carril Feed porta la regla
 *  exacta de FeedDayCard; aquí basta un reparto estable por fecha). */
private fun comboIdOfToday(comboCount: Int): Int {
    val day = LocalDate.now().toEpochDay()
    return ((day % comboCount) + 1).toInt()
}

@Composable
fun FeedScreen(
    container: AppContainer,
    onAnalyzePhoto: () -> Unit,
    onOpenSettings: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val dictionary = container.dictionary
    val unlockedCount by container.unlocks.observeCount().collectAsState(0)
    var comboId by remember { mutableIntStateOf(comboIdOfToday(dictionary.combinations.size)) }
    val combo = dictionary.combo(comboId)
    val comboColors = remember(comboId) { dictionary.colorsOf(comboId) }
    var filterIndex by remember { mutableIntStateOf(0) }
    val type = SolarTheme.type
    val colors = SolarTheme.colors

    Column(modifier.fillMaxSize().windowInsetsPadding(WindowInsets.statusBars)) {
        SolarHeader(section = stringResource(R.string.section_feed)) {
            SolarHeaderButton(
                icon = SolarIconCamera,
                contentDescription = stringResource(R.string.feed_analyze_photo),
                onClick = onAnalyzePhoto,
            )
            SolarHeaderButton(
                icon = SolarIconLeaf,
                contentDescription = stringResource(R.string.settings_open),
                onClick = onOpenSettings,
            )
        }
        LazyColumn(
            modifier = Modifier.fillMaxSize(),
            contentPadding = androidx.compose.foundation.layout.PaddingValues(
                horizontal = SolarSpacing.margin, vertical = SolarSpacing.md,
            ),
            verticalArrangement = Arrangement.spacedBy(SolarSpacing.md),
        ) {
            item {
                val filters = listOf(
                    stringResource(R.string.feed_filter_all),
                    stringResource(R.string.feed_filter_2),
                    stringResource(R.string.feed_filter_3),
                    stringResource(R.string.feed_filter_4),
                )
                LazyRow(horizontalArrangement = Arrangement.spacedBy(SolarSpacing.sm)) {
                    items(filters.indices.toList()) { i ->
                        SolarChip(
                            text = filters[i],
                            selected = i == filterIndex,
                            onClick = { filterIndex = i },
                            dot = when (i) {
                                0 -> colors.sunAmber
                                1 -> colors.tertiaryFixedDim
                                2 -> colors.primaryContainer
                                else -> colors.primary
                            },
                        )
                    }
                }
            }
            if (combo != null) {
                item {
                    SolarCard(Modifier.fillMaxWidth()) {
                        Column(verticalArrangement = Arrangement.spacedBy(SolarSpacing.md)) {
                            Row(
                                Modifier.fillMaxWidth(),
                                horizontalArrangement = Arrangement.SpaceBetween,
                                verticalAlignment = Alignment.CenterVertically,
                            ) {
                                Text(
                                    stringResource(R.string.feed_combo_of_the_day),
                                    style = type.overline, color = colors.secondary,
                                )
                                Text(
                                    stringResource(R.string.feed_combo_number, combo.id),
                                    style = type.hex, color = colors.wellTextSecondary,
                                )
                            }
                            WellContainer(Modifier.fillMaxWidth()) {
                                SwatchStrip(
                                    argbColors = comboColors.map { it.argb },
                                    height = SolarSizes.gridStripes,
                                )
                            }
                            Row(
                                Modifier.fillMaxWidth(),
                                horizontalArrangement = Arrangement.SpaceBetween,
                                verticalAlignment = Alignment.CenterVertically,
                            ) {
                                Text(
                                    dictionary.curatedName(combo.id)
                                        ?: comboColors.joinToString(" + ") { it.name },
                                    style = type.headlineSm, color = colors.onSurface,
                                    modifier = Modifier.weight(1f),
                                )
                                Text(
                                    stringResource(R.string.feed_combo_colors_in_grid, combo.size),
                                    style = type.labelSm, color = colors.onSurfaceVariant,
                                )
                            }
                            SolarPrimaryButton(
                                text = stringResource(R.string.feed_another_combo),
                                icon = SolarIconSparkles,
                                onClick = {
                                    comboId = comboId % dictionary.combinations.size + 1
                                },
                            )
                        }
                    }
                }
            }
            item {
                SolarCard(Modifier.fillMaxWidth()) {
                    Column(verticalArrangement = Arrangement.spacedBy(SolarSpacing.md)) {
                        Row(
                            verticalAlignment = Alignment.CenterVertically,
                            horizontalArrangement = Arrangement.spacedBy(SolarSpacing.md),
                        ) {
                            ToneBadgeIcon(
                                SolarIconCamera, SolarTone.AMBER,
                                contentDescription = null,
                            )
                            Text(
                                stringResource(R.string.feed_empty_title),
                                style = type.cardTitle, color = colors.onSurface,
                            )
                        }
                        Text(
                            stringResource(R.string.feed_empty_body),
                            style = type.bodyMd, color = colors.onSurfaceVariant,
                        )
                        Text(
                            stringResource(R.string.stub_unlocked_count, unlockedCount, container.comboCount),
                            style = type.labelMd, color = colors.primary,
                        )
                        SolarSecondaryButton(
                            text = stringResource(R.string.feed_analyze_photo),
                            onClick = onAnalyzePhoto,
                        )
                    }
                }
            }
            item { Box(Modifier.height(SolarSpacing.xl)) }
        }
    }
}

@Composable
fun ExtractScreen(container: AppContainer, modifier: Modifier = Modifier) {
    StubScreen(
        section = stringResource(R.string.section_extract),
        icon = SolarIconDrop,
        tone = SolarTone.CELADON,
        body = stringResource(R.string.stub_extract_body),
        container = container,
        modifier = modifier,
    )
}

@Composable
fun GridScreen(container: AppContainer, modifier: Modifier = Modifier) {
    val dictionary = container.dictionary
    val type = SolarTheme.type
    val colors = SolarTheme.colors
    Column(modifier.fillMaxSize().windowInsetsPadding(WindowInsets.statusBars)) {
        SolarHeader(section = stringResource(R.string.section_grid))
        LazyColumn(
            modifier = Modifier.fillMaxSize(),
            contentPadding = androidx.compose.foundation.layout.PaddingValues(
                horizontal = SolarSpacing.margin, vertical = SolarSpacing.md,
            ),
            verticalArrangement = Arrangement.spacedBy(SolarSpacing.gutter),
        ) {
            item {
                Text(
                    stringResource(R.string.stub_grid_body),
                    style = type.bodyMd, color = colors.onSurfaceVariant,
                )
            }
            items(dictionary.combinations.take(12)) { combo ->
                SolarCard(Modifier.fillMaxWidth()) {
                    Column(verticalArrangement = Arrangement.spacedBy(SolarSpacing.sm)) {
                        Row(
                            Modifier.fillMaxWidth(),
                            horizontalArrangement = Arrangement.SpaceBetween,
                        ) {
                            Text(
                                dictionary.curatedName(combo.id)
                                    ?: stringResource(R.string.feed_combo_number, combo.id),
                                style = type.cardTitle, color = colors.onSurface,
                            )
                            Text(
                                stringResource(R.string.feed_combo_number, combo.id),
                                style = type.hex, color = colors.wellTextSecondary,
                            )
                        }
                        WellContainer(Modifier.fillMaxWidth(), compact = true) {
                            SwatchStrip(
                                argbColors = dictionary.colorsOf(combo.id).map { it.argb },
                                height = 56.dp,
                            )
                        }
                    }
                }
            }
            item { Box(Modifier.height(SolarSpacing.xl)) }
        }
    }
}

@Composable
fun GardenScreen(container: AppContainer, modifier: Modifier = Modifier) {
    val unlockedCount by container.unlocks.observeCount().collectAsState(0)
    StubScreen(
        section = stringResource(R.string.section_garden),
        icon = SolarIconLeaf,
        tone = SolarTone.MOSS,
        body = stringResource(R.string.stub_garden_body) + "\n\n" +
            stringResource(R.string.stub_unlocked_count, unlockedCount, container.comboCount),
        container = container,
        modifier = modifier,
    )
}

@Composable
private fun StubScreen(
    section: String,
    icon: androidx.compose.ui.graphics.vector.ImageVector,
    tone: SolarTone,
    body: String,
    container: AppContainer,
    modifier: Modifier = Modifier,
) {
    val type = SolarTheme.type
    val colors = SolarTheme.colors
    Column(modifier.fillMaxSize().windowInsetsPadding(WindowInsets.statusBars)) {
        SolarHeader(section = section)
        Column(
            Modifier
                .fillMaxSize()
                .padding(horizontal = SolarSpacing.margin, vertical = SolarSpacing.md),
            verticalArrangement = Arrangement.spacedBy(SolarSpacing.md),
        ) {
            SolarCard(Modifier.fillMaxWidth()) {
                Column(verticalArrangement = Arrangement.spacedBy(SolarSpacing.md)) {
                    ToneBadgeIcon(icon, tone, contentDescription = null, size = SolarSizes.profileBadge)
                    Text(body, style = type.bodyMd, color = colors.onSurfaceVariant)
                    Text(
                        text = stringResource(
                            R.string.settings_engine_version, container.engineVersion,
                        ) + " · " + stringResource(
                            R.string.settings_dict_version,
                            container.engineDictVersion, container.comboCount,
                            container.dictionary.colors.size,
                        ),
                        style = type.hex, color = colors.wellTextSecondary,
                    )
                }
            }
            // Muestra viva del motor: tira con los tres primeros colores del
            // diccionario dentro de su pocillo neutro.
            WellContainer(Modifier.fillMaxWidth()) {
                SwatchStrip(
                    argbColors = container.dictionary.colors.take(3).map { it.argb },
                    height = SolarSizes.harvestStrip,
                )
            }
            Box(Modifier.height(SolarSizes.gridStripes)) {
                // hueco para el contenido real de la ola 2
            }
            ToneBadgeIcon(SolarIconGrid, SolarTone.AMBER, contentDescription = null)
        }
    }
}
