// Ajustes y licencias de la fundación: versiones reales del motor y el texto
// OFL de las fuentes desde assets (ios/ColorsApp/Views/Ajustes en la ola 2
// trae el resto: recorte de sujeto, diagnósticos, acerca de completo).
package com.andreseloy.colorsapp.feature

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.statusBars
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import com.andreseloy.colorsapp.R
import com.andreseloy.colorsapp.app.AppContainer
import com.andreseloy.colorsapp.design.SolarCard
import com.andreseloy.colorsapp.design.SolarIconBack
import com.andreseloy.colorsapp.design.SolarSpacing
import com.andreseloy.colorsapp.design.SolarTheme

@Composable
private fun SecondaryTopBar(title: String, onBack: () -> Unit) {
    val type = SolarTheme.type
    val colors = SolarTheme.colors
    Row(
        Modifier
            .fillMaxWidth()
            .padding(horizontal = SolarSpacing.xs, vertical = SolarSpacing.sm),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        IconButton(onClick = onBack) {
            Icon(
                SolarIconBack,
                contentDescription = stringResource(R.string.back),
                tint = colors.primary,
            )
        }
        Text(title, style = type.brand, color = colors.primary)
    }
}

@Composable
fun SettingsScreen(
    container: AppContainer,
    onBack: () -> Unit,
    onOpenLicenses: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val type = SolarTheme.type
    val colors = SolarTheme.colors
    Column(
        modifier
            .fillMaxSize()
            .windowInsetsPadding(WindowInsets.statusBars)
            .verticalScroll(rememberScrollState()),
    ) {
        SecondaryTopBar(stringResource(R.string.settings_title), onBack)
        Column(
            Modifier.padding(horizontal = SolarSpacing.margin),
            verticalArrangement = Arrangement.spacedBy(SolarSpacing.md),
        ) {
            Text(
                stringResource(R.string.settings_about),
                style = type.overline, color = colors.secondary,
            )
            SolarCard(Modifier.fillMaxWidth()) {
                Column(verticalArrangement = Arrangement.spacedBy(SolarSpacing.sm)) {
                    Text(
                        stringResource(R.string.app_name),
                        style = type.headlineSm, color = colors.onSurface,
                    )
                    Text(
                        stringResource(R.string.feed_empty_body),
                        style = type.bodyMd, color = colors.onSurfaceVariant,
                    )
                    Text(
                        stringResource(R.string.settings_no_network),
                        style = type.bodySm, color = colors.onSurfaceVariant,
                    )
                    Text(
                        stringResource(R.string.settings_engine_version, container.engineVersion),
                        style = type.hex, color = colors.wellTextSecondary,
                    )
                    Text(
                        stringResource(
                            R.string.settings_dict_version,
                            container.engineDictVersion, container.comboCount,
                            container.dictionary.colors.size,
                        ),
                        style = type.hex, color = colors.wellTextSecondary,
                    )
                }
            }
            SolarCard(
                Modifier
                    .fillMaxWidth()
                    .clickable { onOpenLicenses() },
            ) {
                Row(
                    Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.SpaceBetween,
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Text(
                        stringResource(R.string.settings_licenses),
                        style = type.cardTitle, color = colors.onSurface,
                    )
                    Text("›", style = type.headlineSm, color = colors.onSurfaceVariant)
                }
            }
        }
    }
}

@Composable
fun LicensesScreen(onBack: () -> Unit, modifier: Modifier = Modifier) {
    val context = LocalContext.current
    val type = SolarTheme.type
    val colors = SolarTheme.colors
    val literataOfl = remember(context) {
        runCatching {
            context.assets.open("licenses/literata_ofl.txt").bufferedReader().readText()
        }.getOrDefault("")
    }
    val jakartaOfl = remember(context) {
        runCatching {
            context.assets.open("licenses/plus_jakarta_sans_ofl.txt").bufferedReader().readText()
        }.getOrDefault("")
    }
    Column(
        modifier
            .fillMaxSize()
            .windowInsetsPadding(WindowInsets.statusBars)
            .verticalScroll(rememberScrollState()),
    ) {
        SecondaryTopBar(stringResource(R.string.settings_licenses), onBack)
        Column(
            Modifier.padding(horizontal = SolarSpacing.margin),
            verticalArrangement = Arrangement.spacedBy(SolarSpacing.md),
        ) {
            Text(
                stringResource(R.string.settings_font_licenses_title),
                style = type.cardTitle, color = colors.onSurface,
            )
            Text("Literata", style = type.headlineSm, color = colors.primary)
            Text(literataOfl, style = type.hex, color = colors.onSurfaceVariant)
            Text("Plus Jakarta Sans", style = type.headlineSm, color = colors.primary)
            Text(jakartaOfl, style = type.hex, color = colors.onSurfaceVariant)
        }
    }
}
