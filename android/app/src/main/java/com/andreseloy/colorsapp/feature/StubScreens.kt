// Esqueletos que quedan de la fundacion: Rejilla y Jardin (carril W4 de la
// ola 2). El Feed y Extraer reales viven en feature/feed y feature/extract
// (carril W3); sus stubs se retiraron al llegar.
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
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import com.andreseloy.colorsapp.R
import com.andreseloy.colorsapp.app.AppContainer
import com.andreseloy.colorsapp.design.SolarCard
import com.andreseloy.colorsapp.design.SolarHeader
import com.andreseloy.colorsapp.design.SolarIconGrid
import com.andreseloy.colorsapp.design.SolarIconLeaf
import com.andreseloy.colorsapp.design.SolarSizes
import com.andreseloy.colorsapp.design.SolarSpacing
import com.andreseloy.colorsapp.design.SolarTheme
import com.andreseloy.colorsapp.design.SolarTone
import com.andreseloy.colorsapp.design.SwatchStrip
import com.andreseloy.colorsapp.design.ToneBadgeIcon
import com.andreseloy.colorsapp.design.WellContainer

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
            WellContainer(Modifier.fillMaxWidth()) {
                SwatchStrip(
                    argbColors = container.dictionary.colors.take(3).map { it.argb },
                    height = SolarSizes.harvestStrip,
                )
            }
            Box(Modifier.height(SolarSizes.gridStripes))
            ToneBadgeIcon(SolarIconGrid, SolarTone.AMBER, contentDescription = null)
        }
    }
}
