// Ajustes, Acerca de y licencias (Views/Ajustes de iOS): recorte de sujeto,
// umbral de desbloqueo, rehacer el escaneo del carrete, diagnóstico en zip
// compartido con Intent + FileProvider, versiones y atribuciones completas.
// Todo en el teléfono, sin red.
package com.andreseloy.colorsapp.feature.settings

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import com.andreseloy.colorsapp.R
import com.andreseloy.colorsapp.app.AppContainer
import com.andreseloy.colorsapp.data.Diagnostics
import com.andreseloy.colorsapp.data.DiagnosticsSnapshot
import com.andreseloy.colorsapp.data.ScanSource
import com.andreseloy.colorsapp.data.SettingsRepository
import com.andreseloy.colorsapp.data.shortSummary
import com.andreseloy.colorsapp.design.*
import com.andreseloy.colorsapp.feature.grid.shareFile
import com.andreseloy.colorsapp.feature.grid.writeShareFile
import com.andreseloy.colorsapp.subject.RegionMode
import com.andreseloy.colorsapp.subject.SubjectMode
import com.andreseloy.colorsapp.subject.SubjectSettings
import kotlinx.coroutines.launch

@Composable
internal fun W4TopBar(title: String, onBack: () -> Unit) {
    val type = SolarTheme.type; val colors = SolarTheme.colors
    Row(Modifier.fillMaxWidth().padding(horizontal = SolarSpacing.xs, vertical = SolarSpacing.sm), verticalAlignment = Alignment.CenterVertically) {
        IconButton(onClick = onBack) { Icon(SolarIconBack, stringResource(R.string.back), tint = colors.primary) }
        Text(title, style = type.brand, color = colors.primary)
    }
}

@Composable
private fun SectionCard(kicker: String, title: String, footer: String? = null, content: @Composable ColumnScope.() -> Unit) {
    val type = SolarTheme.type; val colors = SolarTheme.colors
    SolarCard(Modifier.fillMaxWidth()) {
        Column(verticalArrangement = Arrangement.spacedBy(SolarSpacing.sm)) {
            Text(kicker.uppercase(), style = type.overline, color = colors.secondary)
            Text(title, style = type.cardTitle, color = colors.onSurface)
            content()
            footer?.let { Text(it, style = type.bodySm, color = colors.onSurfaceVariant) }
        }
    }
}

@Composable
fun W4SettingsScreen(
    container: AppContainer, onBack: () -> Unit, onOpenLicenses: () -> Unit,
    onOpenAbout: () -> Unit = {}, onOpenLayers: () -> Unit = {}, modifier: Modifier = Modifier,
) {
    val type = SolarTheme.type; val colors = SolarTheme.colors; val context = LocalContext.current
    val scope = rememberCoroutineScope()
    var subject by remember { mutableStateOf(SubjectSettings()) }
    var confirmRedo by remember { mutableStateOf(false) }
    var diagState by remember { mutableStateOf<String?>(null) }
    val scanProgress by container.scanProgress.collectAsState()
    LaunchedEffect(Unit) { subject = container.settings.subjectSettings() }

    fun save(next: SubjectSettings) {
        subject = next
        scope.launch {
            container.settings.set(SettingsRepository.Key.SUBJECT_MODE, next.mode.raw)
            container.settings.set(SettingsRepository.Key.REGION_MODE, next.region.raw)
            container.settings.setBool(SettingsRepository.Key.ADAPTIVE_SKIN, next.adaptiveSkin)
            container.settings.setDouble(SettingsRepository.Key.UNLOCK_MAX_SCORE, next.unlockMaxScore)
        }
    }

    if (confirmRedo) {
        AlertDialog(
            onDismissRequest = { confirmRedo = false },
            title = { Text(stringResource(R.string.w4_redo_scan)) },
            text = { Text(stringResource(R.string.w4_redo_scan_footer)) },
            confirmButton = {
                TextButton(onClick = {
                    confirmRedo = false
                    scope.launch {
                        runCatching {
                            container.scans.deleteAll(ScanSource.LIBRARY)
                            container.unlocks.deleteAll(ScanSource.LIBRARY)
                            container.scanRunner.runInitialScan(limit = 200)
                        }
                    }
                }) { Text(stringResource(R.string.w4_redo_scan_confirm), color = colors.error) }
            },
            dismissButton = { TextButton(onClick = { confirmRedo = false }) { Text(stringResource(R.string.w4_cancel)) } },
        )
    }

    Column(modifier.fillMaxSize().windowInsetsPadding(WindowInsets.statusBars).verticalScroll(rememberScrollState())) {
        W4TopBar(stringResource(R.string.settings_title), onBack)
        Column(Modifier.padding(horizontal = SolarSpacing.margin), verticalArrangement = Arrangement.spacedBy(SolarSpacing.md)) {
            SectionCard(stringResource(R.string.w4_crop), stringResource(R.string.w4_people), stringResource(R.string.w4_crop_footer)) {
                Text(stringResource(R.string.w4_people), style = type.labelMd, color = colors.onSurfaceVariant)
                SubjectMode.entries.forEach { mode ->
                    Row(Modifier.fillMaxWidth().clickable { save(subject.copy(mode = mode)) }.semantics { contentDescription = "settings.mode.${mode.raw}" },
                        verticalAlignment = Alignment.CenterVertically) {
                        RadioButton(selected = subject.mode == mode, onClick = { save(subject.copy(mode = mode)) })
                        Text(stringResource(when (mode) {
                            SubjectMode.OFF -> R.string.w4_mode_off; SubjectMode.ALL_PEOPLE -> R.string.w4_mode_all
                            SubjectMode.LARGEST_PERSON -> R.string.w4_mode_largest; SubjectMode.SELECTED_PERSON -> R.string.w4_mode_selected
                        }), style = type.bodyMd, color = colors.onSurface)
                    }
                }
                RegionMode.entries.forEach { region ->
                    Row(Modifier.fillMaxWidth().clickable { save(subject.copy(region = region)) }, verticalAlignment = Alignment.CenterVertically) {
                        RadioButton(selected = subject.region == region, onClick = { save(subject.copy(region = region)) })
                        Text(stringResource(if (region == RegionMode.WHOLE_PERSON) R.string.w4_region_whole else R.string.w4_region_clothing),
                            style = type.bodyMd, color = colors.onSurface)
                    }
                }
                Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween, verticalAlignment = Alignment.CenterVertically) {
                    Text(stringResource(R.string.w4_exclude_skin), style = type.bodyMd, color = colors.onSurface)
                    Switch(checked = subject.adaptiveSkin, onCheckedChange = { save(subject.copy(adaptiveSkin = it)) })
                }
            }
            SectionCard(stringResource(R.string.w4_unlock_section), "%.1f".format(subject.unlockMaxScore), stringResource(R.string.w4_unlock_footer)) {
                Slider(value = subject.unlockMaxScore.toFloat(), onValueChange = { subject = subject.copy(unlockMaxScore = it.toDouble()) },
                    onValueChangeFinished = { save(subject) }, valueRange = 0f..30f, steps = 59)
            }
            SectionCard(stringResource(R.string.w4_library_section), stringResource(R.string.w4_library_section), stringResource(R.string.w4_redo_scan_footer)) {
                SolarSecondaryButton(stringResource(R.string.w4_redo_scan), onClick = { confirmRedo = true })
                if (scanProgress.phase.name != "IDLE") {
                    Text("${scanProgress.phase} ${scanProgress.processed}/${scanProgress.total}", style = type.labelMd, color = colors.primary)
                    LinearProgressIndicator(progress = { scanProgress.fraction.toFloat() }, modifier = Modifier.fillMaxWidth())
                }
            }
            SectionCard(stringResource(R.string.w4_diagnostics), stringResource(R.string.w4_diagnostics), stringResource(R.string.w4_diagnostics_footer)) {
                SolarSecondaryButton(stringResource(R.string.w4_export_diagnostics), onClick = {
                    diagState = "…"
                    scope.launch {
                        runCatching {
                            val scans = container.scans.recent(2000)
                            val feedback = container.feedback.all()
                            val counts = container.feedback.counts()
                            val snapshot = DiagnosticsSnapshot(
                                appVersion = appVersionName(context), appBuild = appVersionCode(context).toString(),
                                engineVersion = container.engineVersion, dictVersion = container.engineDictVersion,
                                launches = container.launches, comboCount = container.comboCount,
                                colorCount = container.dictionary.colors.size, unlockedCount = container.unlocks.count(),
                                scanCount = container.scans.count(), feedbackYes = counts.first, feedbackNo = counts.second,
                                scans = scans, feedback = feedback, subjectMode = subject.mode.raw,
                                regionMode = subject.region.raw, adaptiveSkin = subject.adaptiveSkin,
                                unlockMaxScore = subject.unlockMaxScore,
                            )
                            val uri = writeShareFile(context, Diagnostics.fileName(System.currentTimeMillis()), Diagnostics.buildZip(snapshot))
                            diagState = snapshot.shortSummary()
                            shareFile(context, uri, "application/zip", "ChromaSol")
                        }.onFailure { diagState = it.message }
                    }
                })
                diagState?.let { Text(if (it == "…") stringResource(R.string.w4_preparing) else "${stringResource(R.string.w4_ready)}: $it", style = type.labelMd, color = colors.primary) }
                SolarSecondaryButton(stringResource(R.string.w4_open_layers), onClick = onOpenLayers)
            }
            SectionCard(stringResource(R.string.w4_versions), stringResource(R.string.w4_versions)) {
                ValueRow(stringResource(R.string.w4_app_version), "${appVersionName(context)} (${appVersionCode(LocalContext.current)})")
                ValueRow(stringResource(R.string.w4_engine_version), container.engineVersion)
                ValueRow(stringResource(R.string.w4_dict_version), container.engineDictVersion)
                ValueRow(stringResource(R.string.w4_launches), container.launches.toString())
            }
            SectionCard(stringResource(R.string.w4_about), stringResource(R.string.w4_about)) {
                LinkRow(stringResource(R.string.w4_about_app), stringResource(R.string.w4_about_detail), onOpenAbout)
                LinkRow(stringResource(R.string.w4_font_licenses), stringResource(R.string.w4_font_licenses_detail), onOpenLicenses)
            }
            Box(Modifier.height(SolarSpacing.xl))
        }
    }
}

@Composable
private fun ValueRow(title: String, value: String) {
    val type = SolarTheme.type; val colors = SolarTheme.colors
    Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
        Text(title, style = type.bodyMd, color = colors.onSurface)
        Text(value, style = type.hex, color = colors.wellTextSecondary)
    }
}

@Composable
private fun LinkRow(title: String, detail: String, onClick: () -> Unit) {
    val type = SolarTheme.type; val colors = SolarTheme.colors
    Row(Modifier.fillMaxWidth().clickable { onClick() }, horizontalArrangement = Arrangement.SpaceBetween, verticalAlignment = Alignment.CenterVertically) {
        Column(Modifier.weight(1f)) {
            Text(title, style = type.cardTitle, color = colors.onSurface)
            Text(detail, style = type.bodySm, color = colors.onSurfaceVariant)
        }
        Text("›", style = type.headlineSm, color = colors.onSurfaceVariant)
    }
}

@Composable
fun AboutScreen(container: AppContainer, onBack: () -> Unit, onOpenLicenses: () -> Unit, modifier: Modifier = Modifier) {
    val context = LocalContext.current; val type = SolarTheme.type; val colors = SolarTheme.colors
    val credits = listOf(
        stringResource(R.string.w4_credit_wada), stringResource(R.string.w4_credit_seigensha),
        stringResource(R.string.w4_credit_dblodorn), stringResource(R.string.w4_credit_mattdesl),
        stringResource(R.string.w4_credit_room), stringResource(R.string.w4_credit_unity),
        stringResource(R.string.w4_credit_musl), stringResource(R.string.w4_credit_ciede),
        stringResource(R.string.w4_credit_model),
    )
    Column(modifier.fillMaxSize().windowInsetsPadding(WindowInsets.statusBars).verticalScroll(rememberScrollState())) {
        W4TopBar(stringResource(R.string.w4_about), onBack)
        Column(Modifier.padding(horizontal = SolarSpacing.margin), verticalArrangement = Arrangement.spacedBy(SolarSpacing.md)) {
            SolarCard(Modifier.fillMaxWidth()) {
                Column(verticalArrangement = Arrangement.spacedBy(SolarSpacing.md)) {
                    Text(stringResource(R.string.app_name), style = type.headlineMd, color = colors.primary)
                    Text(stringResource(R.string.w4_about_intro), style = type.bodyMd, color = colors.onSurface)
                    Text(stringResource(R.string.settings_no_network), style = type.bodySm, color = colors.onSurfaceVariant)
                }
            }
            SectionCard(stringResource(R.string.w4_attributions), stringResource(R.string.w4_attributions)) {
                credits.forEach { credit ->
                    Text(credit, style = type.bodySm, color = colors.onSurface, modifier = Modifier.padding(vertical = SolarSpacing.xs))
                    HorizontalDivider(color = colors.outlineVariant)
                }
                LinkRow(stringResource(R.string.w4_font_licenses), stringResource(R.string.w4_font_licenses_detail), onOpenLicenses)
            }
            SectionCard(stringResource(R.string.w4_this_build), stringResource(R.string.w4_this_build)) {
                ValueRow(stringResource(R.string.w4_app_version), "${appVersionName(context)} (${appVersionCode(LocalContext.current)})")
                ValueRow(stringResource(R.string.w4_engine_version), container.engineVersion)
                ValueRow(stringResource(R.string.w4_dict_version), "${container.engineDictVersion} · ${container.comboCount} · ${container.dictionary.colors.size}")
                ValueRow(stringResource(R.string.w4_dict_source), "mattdesl/dictionary-of-colour-combinations 1.0.2")
            }
            Box(Modifier.height(SolarSpacing.xl))
        }
    }
}

@Composable
fun FontLicensesScreen(onBack: () -> Unit, modifier: Modifier = Modifier) {
    val context = LocalContext.current; val type = SolarTheme.type; val colors = SolarTheme.colors
    val literata = remember { runCatching { context.assets.open("licenses/literata_ofl.txt").bufferedReader().readText() }.getOrDefault("") }
    val jakarta = remember { runCatching { context.assets.open("licenses/plus_jakarta_sans_ofl.txt").bufferedReader().readText() }.getOrDefault("") }
    Column(modifier.fillMaxSize().windowInsetsPadding(WindowInsets.statusBars).verticalScroll(rememberScrollState())) {
        W4TopBar(stringResource(R.string.w4_font_licenses), onBack)
        Column(Modifier.padding(horizontal = SolarSpacing.margin), verticalArrangement = Arrangement.spacedBy(SolarSpacing.md)) {
            Text(stringResource(R.string.settings_font_licenses_title), style = type.cardTitle, color = colors.onSurface)
            Text("Literata", style = type.headlineSm, color = colors.primary)
            Text(literata, style = type.hex, color = colors.onSurfaceVariant)
            Text("Plus Jakarta Sans", style = type.headlineSm, color = colors.primary)
            Text(jakarta, style = type.hex, color = colors.onSurfaceVariant)
            // Licencias de las librerías de Android que usa la app (sin red).
            Text("AndroidX / Jetpack Compose / Room", style = type.headlineSm, color = colors.primary)
            Text("Copyright The Android Open Source Project. Licensed under the Apache License, Version 2.0. " +
                "Kotlin: Copyright JetBrains s.r.o., Apache License 2.0. " +
                "Motor de color en C y diccionario: ver Atribuciones en Acerca de.", style = type.hex, color = colors.onSurfaceVariant)
            Box(Modifier.height(SolarSpacing.xl))
        }
    }
}

/** Versión instalada leída del paquete (sin BuildConfig: AGP no lo genera aquí). */
internal fun appVersionName(context: android.content.Context): String =
    runCatching { context.packageManager.getPackageInfo(context.packageName, 0).versionName ?: "?" }.getOrDefault("?")
internal fun appVersionCode(context: android.content.Context): Long =
    runCatching { androidx.core.content.pm.PackageInfoCompat.getLongVersionCode(context.packageManager.getPackageInfo(context.packageName, 0)) }.getOrDefault(0L)
