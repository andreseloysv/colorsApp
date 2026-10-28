// Resumen «Tu carrete en color»: espejo de
// ios/ColorsApp/Views/Wrapped/WrappedSummaryView.swift. Vista pura sobre
// ScanSummary + WadaDictionary: portada con la cifra de fotos, color firma,
// 5 colores mas frecuentes, combinaciones desbloqueadas, las que mas se
// repiten, contador n/348 y «Ver rejilla». Todo color de datos en pocillo.
package com.andreseloy.colorsapp.feature.wrapped

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Icon
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import com.andreseloy.colorsapp.R
import com.andreseloy.colorsapp.data.WadaDictionary
import com.andreseloy.colorsapp.design.SolarCard
import com.andreseloy.colorsapp.design.SolarPrimaryButton
import com.andreseloy.colorsapp.design.SolarRadius
import com.andreseloy.colorsapp.design.SolarSpacing
import com.andreseloy.colorsapp.design.SolarTheme
import com.andreseloy.colorsapp.design.SwatchStrip
import com.andreseloy.colorsapp.design.WellContainer
import com.andreseloy.colorsapp.feature.extract.PaletteColor
import com.andreseloy.colorsapp.feature.extract.W3Format
import com.andreseloy.colorsapp.feature.extract.numberLabel
import com.andreseloy.colorsapp.feature.extract.w3Locale
import com.andreseloy.colorsapp.feature.feed.FeedComboName
import com.andreseloy.colorsapp.feature.feed.W3IconPalette
import com.andreseloy.colorsapp.feature.feed.W3IconPhoto
import com.andreseloy.colorsapp.feature.feed.W3IconRefresh
import com.andreseloy.colorsapp.feature.feed.W3IconSeal
import com.andreseloy.colorsapp.scan.ScanSummary

private const val MAX_UNLOCK_TILES = 12

/** «41/348» (WrappedSummaryView.counterText). */
fun wrappedCounterText(unlocked: Int, total: Int): String = "$unlocked/$total"

/** Duracion «3,2 s» / «1 min 12 s» ya localizada se compone en la UI. */
fun wrappedDurationParts(durationMs: Long): Pair<Boolean, Double> {
    val seconds = durationMs / 1000.0
    return (seconds < 60) to seconds
}

@Composable
fun WrappedSummary(
    summary: ScanSummary,
    dictionary: WadaDictionary,
    totalCombos: Int,
    onShowGrid: (() -> Unit)?,
    modifier: Modifier = Modifier,
) {
    val colors = SolarTheme.colors
    val type = SolarTheme.type
    val locale = w3Locale()
    Column(
        modifier
            .verticalScroll(rememberScrollState())
            .padding(horizontal = SolarSpacing.margin)
            .padding(top = SolarSpacing.md, bottom = SolarSpacing.xl)
            .testTag("wrapped.summary"),
        verticalArrangement = Arrangement.spacedBy(SolarSpacing.lg),
    ) {
        // Portada
        SolarCard(Modifier.fillMaxWidth()) {
            Column(verticalArrangement = Arrangement.spacedBy(SolarSpacing.sm)) {
                Text(
                    stringResource(R.string.w3_wrapped_section).uppercase(),
                    style = type.overline, color = colors.secondary,
                )
                Text(
                    stringResource(R.string.w3_wrapped_title),
                    style = type.headlineXlMobile, color = colors.primary,
                )
                Row(
                    verticalAlignment = Alignment.Bottom,
                    horizontalArrangement = Arrangement.spacedBy(SolarSpacing.sm),
                ) {
                    Text(
                        "${summary.scanned}", style = type.headlineXl, color = colors.onSurface,
                    )
                    Text(
                        stringResource(
                            if (summary.scanned == 1) {
                                R.string.w3_photo_analyzed_one
                            } else {
                                R.string.w3_photos_analyzed_many
                            },
                        ),
                        style = type.labelLg, color = colors.onSurfaceVariant,
                    )
                }
                val (isSeconds, seconds) = wrappedDurationParts(summary.durationMs)
                val duration = if (isSeconds) {
                    stringResource(
                        R.string.w3_duration_seconds, W3Format.number(seconds, 1, locale),
                    )
                } else {
                    stringResource(
                        R.string.w3_duration_minutes,
                        (seconds.toLong() / 60).toInt(), (seconds.toLong() % 60).toInt(),
                    )
                }
                val stats = buildList {
                    add(stringResource(R.string.w3_stats_analyzed, summary.scanned))
                    if (summary.skipped > 0) {
                        add(stringResource(R.string.w3_stats_skipped, summary.skipped))
                    }
                    if (summary.failed > 0) {
                        add(stringResource(R.string.w3_stats_failed, summary.failed))
                    }
                    add(duration)
                }.joinToString(" · ")
                Text(
                    stats, style = type.bodySm, color = colors.onSurfaceVariant,
                    modifier = Modifier.testTag("wrapped.stats"),
                )
            }
        }

        if (summary.scanned == 0) {
            SolarCard(Modifier.fillMaxWidth(), fill = colors.container) {
                Column(verticalArrangement = Arrangement.spacedBy(SolarSpacing.sm)) {
                    Row(
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(SolarSpacing.sm),
                    ) {
                        Icon(
                            W3IconPhoto, contentDescription = null, tint = colors.primary,
                            modifier = Modifier.size(20.dp),
                        )
                        Text(
                            stringResource(R.string.w3_wrapped_empty_title),
                            style = type.headlineSm, color = colors.primary,
                        )
                    }
                    Text(
                        stringResource(R.string.w3_wrapped_empty_body),
                        style = type.bodyMd, color = colors.onSurfaceVariant,
                    )
                }
            }
        } else {
            // Color firma
            summary.signatureColorIndex?.let { index ->
                dictionary.color(index)?.let { wada ->
                    val count = summary.topColors.firstOrNull { it.colorIndex == index }?.count ?: 0
                    Column(
                        Modifier.testTag("wrapped.signature"),
                        verticalArrangement = Arrangement.spacedBy(SolarSpacing.sm),
                    ) {
                        SectionHeader(stringResource(R.string.w3_signature_color), W3IconSeal)
                        WellContainer(Modifier.fillMaxWidth()) {
                            Row(
                                horizontalArrangement = Arrangement.spacedBy(SolarSpacing.margin),
                                verticalAlignment = Alignment.CenterVertically,
                            ) {
                                Box(
                                    Modifier
                                        .size(96.dp)
                                        .clip(SolarRadius.blockShape)
                                        .background(Color(wada.argb))
                                        .border(
                                            0.5.dp, colors.swatchHairline, SolarRadius.blockShape,
                                        ),
                                )
                                Column(verticalArrangement = Arrangement.spacedBy(SolarSpacing.xs)) {
                                    Text(wada.name, style = type.headlineMd, color = colors.wellText)
                                    Text(
                                        wada.hex.uppercase(), style = type.hex,
                                        color = colors.wellTextSecondary,
                                    )
                                    Text(
                                        if (count == 1) {
                                            stringResource(R.string.w3_in_one_photo)
                                        } else {
                                            stringResource(R.string.w3_in_n_photos, count)
                                        },
                                        style = type.labelMd, color = colors.wellTextSecondary,
                                    )
                                }
                            }
                        }
                    }
                }
            }
            // Tus 5 colores
            val topColors = summary.topColors.take(5).mapNotNull { entry ->
                dictionary.color(entry.colorIndex)?.let { entry to it }
            }
            if (topColors.isNotEmpty()) {
                Column(
                    Modifier.testTag("wrapped.topColors"),
                    verticalArrangement = Arrangement.spacedBy(SolarSpacing.sm),
                ) {
                    SectionHeader(stringResource(R.string.w3_your_5_colors), W3IconPalette)
                    WellContainer(Modifier.fillMaxWidth(), compact = true) {
                        Row(
                            Modifier.fillMaxWidth(),
                            horizontalArrangement = Arrangement.spacedBy(SolarSpacing.xs),
                        ) {
                            topColors.forEach { (entry, wada) ->
                                Column(
                                    Modifier.weight(1f),
                                    horizontalAlignment = Alignment.CenterHorizontally,
                                    verticalArrangement = Arrangement.spacedBy(SolarSpacing.xs),
                                ) {
                                    Box(
                                        Modifier
                                            .padding(top = 2.dp)
                                            .size(48.dp)
                                            .clip(CircleShape)
                                            .background(Color(wada.argb))
                                            .border(0.5.dp, colors.swatchHairline, CircleShape),
                                    )
                                    Text(
                                        wada.name, style = type.labelSm, color = colors.wellText,
                                        maxLines = 2,
                                    )
                                    Text(
                                        "×${entry.count}", style = type.labelSm,
                                        color = colors.wellTextSecondary,
                                    )
                                }
                            }
                        }
                    }
                }
            }
            // Desbloqueadas
            Column(
                Modifier.testTag("wrapped.unlocks"),
                verticalArrangement = Arrangement.spacedBy(SolarSpacing.sm),
            ) {
                SectionHeader(
                    if (summary.newUnlocks.size == 1) {
                        stringResource(R.string.w3_unlocked_one_combo)
                    } else {
                        stringResource(
                            R.string.w3_unlocked_many_combos, summary.newUnlocks.size,
                        )
                    },
                    W3IconSeal,
                )
                if (summary.newUnlocks.isEmpty()) {
                    Text(
                        stringResource(R.string.w3_no_unlock_reason),
                        style = type.bodySm, color = colors.onSurfaceVariant,
                    )
                } else {
                    WellContainer(Modifier.fillMaxWidth(), compact = true) {
                        Column(verticalArrangement = Arrangement.spacedBy(SolarSpacing.sm)) {
                            summary.newUnlocks.take(MAX_UNLOCK_TILES).chunked(4)
                                .forEach { rowIds ->
                                    Row(
                                        Modifier.fillMaxWidth(),
                                        horizontalArrangement = Arrangement.spacedBy(SolarSpacing.sm),
                                    ) {
                                        rowIds.forEach { id ->
                                            Column(
                                                Modifier.weight(1f),
                                                horizontalAlignment = Alignment.CenterHorizontally,
                                                verticalArrangement = Arrangement.spacedBy(SolarSpacing.xs),
                                            ) {
                                                SwatchStrip(
                                                    argbColors = PaletteColor
                                                        .combo(id, dictionary).map { it.argb },
                                                    height = 56.dp,
                                                )
                                                Text(
                                                    numberLabel(id), style = type.labelSm,
                                                    color = colors.wellTextSecondary, maxLines = 1,
                                                )
                                            }
                                        }
                                        repeat(4 - rowIds.size) { Box(Modifier.weight(1f)) }
                                    }
                                }
                        }
                    }
                    if (summary.newUnlocks.size > MAX_UNLOCK_TILES) {
                        Text(
                            stringResource(
                                R.string.w3_and_more_in_grid,
                                summary.newUnlocks.size - MAX_UNLOCK_TILES,
                            ),
                            style = type.bodySm, color = colors.onSurfaceVariant,
                        )
                    }
                }
            }
            // Las que mas se repiten
            val topCombos = summary.topCombos.take(5)
                .filter { dictionary.combo(it.comboId) != null }
            if (topCombos.isNotEmpty()) {
                Column(
                    Modifier.testTag("wrapped.topCombos"),
                    verticalArrangement = Arrangement.spacedBy(SolarSpacing.sm),
                ) {
                    SectionHeader(stringResource(R.string.w3_most_repeated), W3IconRefresh)
                    SolarCard(Modifier.fillMaxWidth()) {
                        Column {
                            topCombos.forEachIndexed { i, entry ->
                                if (i > 0) {
                                    Box(
                                        Modifier.fillMaxWidth().height(1.dp)
                                            .background(colors.outlineVariant),
                                    )
                                }
                                Row(
                                    Modifier.fillMaxWidth().padding(vertical = SolarSpacing.sm),
                                    verticalAlignment = Alignment.CenterVertically,
                                    horizontalArrangement = Arrangement.spacedBy(SolarSpacing.md),
                                ) {
                                    WellContainer(Modifier.width(104.dp), compact = true) {
                                        SwatchStrip(
                                            argbColors = PaletteColor
                                                .combo(entry.comboId, dictionary).map { it.argb },
                                            height = 28.dp,
                                        )
                                    }
                                    Column(Modifier.weight(1f)) {
                                        Text(
                                            FeedComboName.name(entry.comboId, dictionary)
                                                ?: numberLabel(entry.comboId),
                                            style = type.labelLg, color = colors.onSurface,
                                            maxLines = 2,
                                        )
                                        Text(
                                            numberLabel(entry.comboId),
                                            style = type.bodySm, color = colors.onSurfaceVariant,
                                        )
                                    }
                                    Text(
                                        if (entry.count == 1) {
                                            stringResource(R.string.w3_one_photo)
                                        } else {
                                            stringResource(R.string.w3_n_photos, entry.count)
                                        },
                                        style = type.labelMd, color = colors.secondary,
                                    )
                                }
                            }
                        }
                    }
                }
            }
        }

        // Contador n/348
        SolarCard(Modifier.fillMaxWidth(), fill = colors.container) {
            Column(verticalArrangement = Arrangement.spacedBy(SolarSpacing.sm)) {
                Row(
                    verticalAlignment = Alignment.Bottom,
                    horizontalArrangement = Arrangement.spacedBy(SolarSpacing.sm),
                ) {
                    Text(
                        wrappedCounterText(summary.totalUnlocked, totalCombos),
                        style = type.headlineXl, color = colors.primary,
                        modifier = Modifier.testTag("wrapped.counter"),
                    )
                    Text(
                        stringResource(R.string.w3_counter_label),
                        style = type.labelMd, color = colors.onSurfaceVariant,
                        modifier = Modifier.weight(1f),
                    )
                }
                LinearProgressIndicator(
                    progress = {
                        summary.totalUnlocked.toFloat() / maxOf(1, totalCombos)
                    },
                    color = colors.primary, trackColor = colors.surfaceVariant,
                    modifier = Modifier.fillMaxWidth().height(8.dp)
                        .clip(RoundedCornerShape(50)),
                )
            }
        }
        if (onShowGrid != null) {
            SolarPrimaryButton(
                text = stringResource(R.string.w3_view_grid),
                icon = com.andreseloy.colorsapp.design.SolarIconGrid,
                onClick = onShowGrid,
                modifier = Modifier.testTag("wrapped.showGrid"),
            )
        }
    }
}

@Composable
private fun SectionHeader(
    title: String,
    icon: androidx.compose.ui.graphics.vector.ImageVector,
) {
    val colors = SolarTheme.colors
    Row(
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(SolarSpacing.sm),
    ) {
        Icon(icon, contentDescription = null, tint = colors.secondary, modifier = Modifier.size(16.dp))
        Text(title, style = SolarTheme.type.headlineSm, color = colors.onSurface)
    }
}
