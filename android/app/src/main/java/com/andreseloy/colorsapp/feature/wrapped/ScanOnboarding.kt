// Escaneo del carrete (dia 0) como flujo presentable: espejo de
// Views/Wrapped/ScanOnboardingView.swift. Explicacion -> progreso -> resumen
// «Tu carrete en color». El escaneo completo lo hace el runner de W2
// (ScanRunning.runInitialScan, MediaStore); con acceso limitado se ofrecen
// hasta 200 fotos del Photo Picker del sistema y se procesan por la misma
// regla del runner de iOS (scan source=library, desbloqueo solo si no es
// ambiguo y score <= unlock_max_score, conteos por combo y por color).
// Con acceso denegado: mensaje y boton a los Ajustes del sistema.
package com.andreseloy.colorsapp.feature.wrapped

import android.content.Intent
import android.net.Uri
import android.provider.Settings
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.PickVisualMediaRequest
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Icon
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.unit.dp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import com.andreseloy.colorsapp.R
import com.andreseloy.colorsapp.app.AppContainer
import com.andreseloy.colorsapp.data.ScanSource
import com.andreseloy.colorsapp.data.SettingsRepository
import com.andreseloy.colorsapp.data.WadaDictionary
import com.andreseloy.colorsapp.design.SolarCard
import com.andreseloy.colorsapp.design.SolarHeader
import com.andreseloy.colorsapp.design.SolarHeaderButton
import com.andreseloy.colorsapp.design.SolarIconSparkles
import com.andreseloy.colorsapp.design.SolarPrimaryButton
import com.andreseloy.colorsapp.design.SolarSecondaryButton
import com.andreseloy.colorsapp.design.SolarSpacing
import com.andreseloy.colorsapp.design.SolarTheme
import com.andreseloy.colorsapp.design.SolarTone
import com.andreseloy.colorsapp.design.ToneBadgeIcon
import com.andreseloy.colorsapp.feature.extract.AnalysisPolicy
import com.andreseloy.colorsapp.feature.extract.GhostPillButton
import com.andreseloy.colorsapp.feature.extract.PhotoLoading
import com.andreseloy.colorsapp.feature.extract.ScanAnalyzer
import com.andreseloy.colorsapp.feature.extract.ScanJson
import com.andreseloy.colorsapp.feature.extract.ScanSubjectInfo
import com.andreseloy.colorsapp.feature.feed.W3IconClose
import com.andreseloy.colorsapp.feature.feed.W3IconGear
import com.andreseloy.colorsapp.feature.feed.W3IconPhoto
import com.andreseloy.colorsapp.feature.feed.W3IconPhotoStack
import com.andreseloy.colorsapp.feature.feed.W3IconRefresh
import com.andreseloy.colorsapp.feature.feed.W3IconSeal
import com.andreseloy.colorsapp.feature.feed.W3IconWarning
import com.andreseloy.colorsapp.scan.ColorCount
import com.andreseloy.colorsapp.scan.ComboCount
import com.andreseloy.colorsapp.scan.ScanException
import com.andreseloy.colorsapp.scan.ScanProgress
import com.andreseloy.colorsapp.scan.ScanSummary
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.time.Instant

/** Conteos ordenados como en iOS: recuento descendente, desempate por clave ascendente. */
fun sortedCounts(counts: Map<Int, Int>): List<Pair<Int, Int>> =
    counts.entries.sortedWith(
        compareByDescending<Map.Entry<Int, Int>> { it.value }.thenBy { it.key },
    ).map { it.key to it.value }

/** Cuenta cada color del diccionario en los top-1, ponderado por fotos. */
fun colorCounts(
    comboCounts: Map<Int, Int>, dictionary: WadaDictionary,
): List<Pair<Int, Int>> {
    val counts = mutableMapOf<Int, Int>()
    for ((comboId, n) in comboCounts) {
        val combo = dictionary.combo(comboId) ?: continue
        for (index in combo.colors) counts[index] = (counts[index] ?: 0) + n
    }
    return sortedCounts(counts)
}

/** Regla de desbloqueo del escaneo (UnlockPolicy de iOS). */
fun unlockCandidate(
    topComboId: Int?, topScore: Double?, ambiguous: Boolean, unlockMaxScore: Double,
): Int? {
    if (topComboId == null || topScore == null) return null
    if (ambiguous) return null
    if (topScore > unlockMaxScore) return null
    return topComboId
}

private sealed interface Stage {
    data object Intro : Stage
    data object Running : Stage
    data object Limited : Stage
    data object Denied : Stage
    data class Done(val summary: ScanSummary) : Stage
    data class Failed(val message: String) : Stage
}

@Composable
fun ScanOnboardingSheet(
    container: AppContainer,
    onShowGrid: () -> Unit,
    onDismiss: () -> Unit,
    showSkip: Boolean,
    autoStart: Boolean = false,
    limit: Int = 200,
) {
    val context = LocalContext.current
    val resources = context.resources
    val scope = rememberCoroutineScope()
    var stage by remember { mutableStateOf<Stage>(Stage.Intro) }
    var scanJob by remember { mutableStateOf<Job?>(null) }
    var pickerProcessed by remember { mutableIntStateOf(0) }
    var pickerTotal by remember { mutableIntStateOf(0) }
    var pickerUnlocked by remember { mutableIntStateOf(0) }
    val progress by container.scanProgress.collectAsState()

    fun startPickerScan(uris: List<Uri>) {
        stage = Stage.Running
        pickerTotal = uris.size
        pickerProcessed = 0
        pickerUnlocked = 0
        scanJob?.cancel()
        scanJob = scope.launch {
            try {
                val startedAt = System.currentTimeMillis()
                val subjectSettings = container.settings.subjectSettings()
                val options = subjectSettings.subjectOptions()
                var scanned = 0
                var skipped = 0
                var failed = 0
                val comboCounts = mutableMapOf<Int, Int>()
                val newUnlocks = mutableListOf<Int>()
                for (uri in uris) {
                    val bitmap = withContext(Dispatchers.IO) {
                        runCatching { PhotoLoading.loadUpright(context, uri) }.getOrNull()
                    }
                    if (bitmap == null) {
                        skipped++
                    } else {
                        try {
                            val analysis = ScanAnalyzer.analyze(
                                container, bitmap, options, layers = false,
                            )
                            val record = ScanJson.makeRecord(
                                id = ScanAnalyzer.newScanId(),
                                result = analysis.result, source = ScanSource.LIBRARY,
                                assetId = uri.toString(),
                                subject = ScanSubjectInfo(options, analysis.subject),
                                garments = analysis.garmentInfo,
                                policyVersion = AnalysisPolicy.CURRENT,
                                engineVersion = container.engineVersion,
                                dictVersion = container.engineDictVersion,
                                nowMs = System.currentTimeMillis(),
                            )
                            container.scans.insert(record)
                            scanned++
                            analysis.result.hits.firstOrNull()?.let { top ->
                                comboCounts[top.comboId] =
                                    (comboCounts[top.comboId] ?: 0) + 1
                            }
                            unlockCandidate(
                                analysis.result.hits.firstOrNull()?.comboId,
                                analysis.result.hits.firstOrNull()?.score,
                                analysis.result.ambiguous,
                                subjectSettings.unlockMaxScore,
                            )?.let { candidate ->
                                if (container.unlocks.unlock(
                                        candidate, ScanSource.LIBRARY,
                                        assetId = uri.toString(), scanId = record.id,
                                    )
                                ) {
                                    newUnlocks += candidate
                                    pickerUnlocked = newUnlocks.size
                                }
                            }
                        } catch (e: CancellationException) {
                            throw e
                        } catch (e: Exception) {
                            failed++
                        }
                    }
                    pickerProcessed++
                }
                val finishedAt = System.currentTimeMillis()
                container.settings.setBool(SettingsRepository.Key.INITIAL_SCAN_DONE, true)
                container.settings.set(
                    SettingsRepository.Key.INITIAL_SCAN_AT, Instant.ofEpochMilli(finishedAt).toString(),
                )
                container.settings.setInt(SettingsRepository.Key.INITIAL_SCAN_COUNT, scanned)
                val colorsCounted = colorCounts(comboCounts, container.dictionary)
                stage = Stage.Done(
                    ScanSummary(
                        scanned = scanned, skipped = skipped, failed = failed,
                        newUnlocks = newUnlocks,
                        totalUnlocked = container.unlocks.count(),
                        topCombos = sortedCounts(comboCounts).map {
                            ComboCount(it.first, it.second)
                        },
                        startedAtMs = startedAt, finishedAtMs = finishedAt,
                        topColors = colorsCounted.map { ColorCount(it.first, it.second) },
                        signatureColorIndex = colorsCounted.firstOrNull()?.first,
                    ),
                )
            } catch (e: CancellationException) {
                stage = Stage.Limited
            } catch (e: Exception) {
                stage = Stage.Failed(e.toString())
            }
        }
    }

    val multiplePicker = rememberLauncherForActivityResult(
        ActivityResultContracts.PickMultipleVisualMedia(limit),
    ) { uris: List<Uri> ->
        if (uris.isNotEmpty()) startPickerScan(uris)
    }

    fun start() {
        stage = Stage.Running
        pickerTotal = 0
        scanJob?.cancel()
        scanJob = scope.launch {
            try {
                val summary = container.scanRunner.runInitialScan(limit)
                stage = if (summary.needsPicker) Stage.Limited else Stage.Done(summary)
            } catch (e: ScanException.AccessDenied) {
                stage = Stage.Denied
            } catch (e: ScanException.LimitedAccess) {
                stage = Stage.Limited
            } catch (e: ScanException.Cancelled) {
                stage = Stage.Intro
            } catch (e: CancellationException) {
                stage = Stage.Intro
            } catch (e: Exception) {
                stage = Stage.Failed(e.toString())
            }
        }
    }

    LaunchedEffect(Unit) {
        if (autoStart && stage == Stage.Intro) start()
    }

    Dialog(
        onDismissRequest = {
            scanJob?.cancel()
            onDismiss()
        },
        properties = DialogProperties(usePlatformDefaultWidth = false),
    ) {
        val colors = SolarTheme.colors
        val type = SolarTheme.type
        Column(
            Modifier.fillMaxSize().background(colors.surface).testTag("scan.sheet"),
        ) {
            SolarHeader(
                section = stringResource(
                    if (stage == Stage.Running) R.string.w3_scanning
                    else R.string.w3_library_section,
                ),
            ) {
                SolarHeaderButton(
                    icon = W3IconClose,
                    contentDescription = stringResource(R.string.w3_close),
                    onClick = {
                        scanJob?.cancel()
                        onDismiss()
                    },
                )
            }
            when (val current = stage) {
                Stage.Intro -> IntroContent(
                    limit = limit,
                    showSkip = showSkip,
                    onStart = { start() },
                    onSkip = onDismiss,
                )
                Stage.Running -> RunningContent(
                    progress = if (pickerTotal > 0) {
                        ScanProgress(
                            phase = ScanProgress.Phase.ANALYZING,
                            processed = pickerProcessed, total = pickerTotal,
                            unlocked = pickerUnlocked,
                        )
                    } else {
                        progress
                    },
                )
                Stage.Limited -> StageCard(
                    icon = W3IconPhoto,
                    title = stringResource(R.string.w3_limited_title),
                    message = stringResource(R.string.w3_limited_body, limit),
                ) {
                    SolarSecondaryButton(
                        text = stringResource(R.string.w3_pick_photos),
                        onClick = {
                            multiplePicker.launch(
                                PickVisualMediaRequest(
                                    ActivityResultContracts.PickVisualMedia.ImageOnly,
                                ),
                            )
                        },
                        modifier = Modifier.fillMaxWidth().testTag("scan.picker"),
                    )
                }
                Stage.Denied -> StageCard(
                    icon = W3IconWarning,
                    title = stringResource(R.string.w3_denied_title),
                    message = stringResource(
                        R.string.w3_denied_body, stringResource(R.string.app_name),
                    ),
                ) {
                    SolarPrimaryButton(
                        text = stringResource(R.string.w3_open_settings),
                        icon = W3IconGear,
                        onClick = {
                            val intent = Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS)
                                .setData(Uri.fromParts("package", context.packageName, null))
                            runCatching { context.startActivity(intent) }
                        },
                        modifier = Modifier.fillMaxWidth().testTag("scan.openSettings"),
                    )
                    GhostPillButton(
                        text = stringResource(R.string.w3_retry),
                        icon = W3IconRefresh,
                        onClick = { start() },
                        modifier = Modifier.fillMaxWidth(),
                    )
                }
                is Stage.Failed -> StageCard(
                    icon = W3IconWarning,
                    title = stringResource(R.string.w3_scan_failed_title),
                    message = current.message,
                    monospacedMessage = true,
                ) {
                    SolarPrimaryButton(
                        text = stringResource(R.string.w3_retry),
                        icon = W3IconRefresh,
                        onClick = { start() },
                        modifier = Modifier.fillMaxWidth(),
                    )
                }
                is Stage.Done -> WrappedSummary(
                    summary = current.summary,
                    dictionary = container.dictionary,
                    totalCombos = container.comboCount,
                    onShowGrid = onShowGrid,
                    modifier = Modifier.fillMaxSize(),
                )
            }
        }
    }
}

@Composable
private fun IntroContent(
    limit: Int,
    showSkip: Boolean,
    onStart: () -> Unit,
    onSkip: () -> Unit,
) {
    val colors = SolarTheme.colors
    val type = SolarTheme.type
    Column(
        Modifier
            .fillMaxSize()
            .padding(horizontal = SolarSpacing.margin)
            .padding(top = SolarSpacing.md, bottom = SolarSpacing.xl),
        verticalArrangement = Arrangement.spacedBy(SolarSpacing.lg),
    ) {
        SolarCard(Modifier.fillMaxWidth()) {
            Column(verticalArrangement = Arrangement.spacedBy(SolarSpacing.md)) {
                Row(
                    Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.SpaceBetween,
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Text(
                        stringResource(R.string.app_name),
                        style = type.brand, color = colors.primary,
                    )
                    ToneBadgeIcon(
                        W3IconPhotoStack, SolarTone.AMBER, contentDescription = null, size = 44.dp,
                    )
                }
                Text(
                    stringResource(R.string.w3_scan_intro_title, limit),
                    style = type.headlineXlMobile, color = colors.primary,
                )
                Text(
                    stringResource(
                        R.string.w3_scan_intro_body,
                        stringResource(R.string.app_name), limit,
                    ),
                    style = type.bodyLg, color = colors.onSurfaceVariant,
                )
                Row(horizontalArrangement = Arrangement.spacedBy(SolarSpacing.sm)) {
                    Badge(stringResource(R.string.w3_badge_no_network), colors.primaryFixed, colors.onPrimaryFixed)
                    Badge(stringResource(R.string.w3_badge_no_account), colors.secondaryFixed, colors.onSecondaryFixed)
                    Badge(stringResource(R.string.w3_badge_on_phone), colors.tertiaryFixed, colors.onTertiaryFixed)
                }
            }
        }
        SolarPrimaryButton(
            text = stringResource(R.string.w3_scan_now),
            icon = SolarIconSparkles,
            onClick = onStart,
            modifier = Modifier.testTag("scan.start"),
        )
        if (showSkip) {
            GhostPillButton(
                text = stringResource(R.string.w3_not_now),
                icon = null,
                onClick = onSkip,
                modifier = Modifier.fillMaxWidth().testTag("scan.skip"),
            )
            Text(
                stringResource(R.string.w3_scan_later_note),
                style = type.bodySm, color = colors.onSurfaceVariant,
            )
        }
    }
}

@Composable
private fun Badge(
    title: String,
    fill: androidx.compose.ui.graphics.Color,
    foreground: androidx.compose.ui.graphics.Color,
) {
    Box(
        Modifier.clip(RoundedCornerShape(50)).background(fill)
            .padding(horizontal = SolarSpacing.sm, vertical = SolarSpacing.xs),
    ) {
        Text(title, style = SolarTheme.type.labelSm, color = foreground, maxLines = 1)
    }
}

@Composable
private fun RunningContent(progress: ScanProgress) {
    val colors = SolarTheme.colors
    val type = SolarTheme.type
    Column(
        Modifier.fillMaxSize().padding(horizontal = SolarSpacing.margin),
        verticalArrangement = Arrangement.Center,
    ) {
        SolarCard(Modifier.fillMaxWidth(), fill = colors.container) {
            Column(verticalArrangement = Arrangement.spacedBy(SolarSpacing.md)) {
                Row(
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(SolarSpacing.sm),
                ) {
                    ToneBadgeIcon(
                        W3IconPhotoStack, SolarTone.MOSS, contentDescription = null, size = 40.dp,
                    )
                    Column {
                        Text(
                            stringResource(R.string.w3_scanning_library).uppercase(),
                            style = type.overline, color = colors.secondary,
                        )
                        Text(
                            text = when (progress.phase) {
                                ScanProgress.Phase.IDLE ->
                                    stringResource(R.string.w3_phase_preparing)
                                ScanProgress.Phase.REQUESTING_ACCESS ->
                                    stringResource(R.string.w3_scan_requesting)
                                ScanProgress.Phase.FETCHING ->
                                    stringResource(R.string.w3_scan_fetching)
                                ScanProgress.Phase.ANALYZING -> stringResource(
                                    R.string.w3_phase_analyzing,
                                    progress.processed, progress.total,
                                )
                                ScanProgress.Phase.FINISHED ->
                                    stringResource(R.string.w3_phase_done)
                                ScanProgress.Phase.FAILED ->
                                    stringResource(R.string.w3_phase_error)
                            },
                            style = type.headlineSm, color = colors.onSurface,
                            modifier = Modifier.testTag("scan.progress"),
                        )
                    }
                }
                if (progress.total > 0) {
                    LinearProgressIndicator(
                        progress = { progress.fraction.toFloat() },
                        color = colors.primary, modifier = Modifier.fillMaxWidth(),
                    )
                } else {
                    LinearProgressIndicator(
                        color = colors.primary, modifier = Modifier.fillMaxWidth(),
                    )
                }
                if (progress.unlocked > 0) {
                    Row(
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(SolarSpacing.xs),
                    ) {
                        Icon(
                            W3IconSeal, contentDescription = null, tint = colors.primary,
                            modifier = Modifier.size(14.dp),
                        )
                        Text(
                            if (progress.unlocked == 1) {
                                stringResource(R.string.w3_unlocked_one_combo)
                            } else {
                                stringResource(
                                    R.string.w3_unlocked_many_combos, progress.unlocked,
                                )
                            },
                            style = type.labelMd, color = colors.primary,
                        )
                    }
                }
                if (progress.skipped > 0) {
                    Text(
                        stringResource(R.string.w3_skipped_icloud, progress.skipped),
                        style = type.bodySm, color = colors.onSurfaceVariant,
                    )
                }
                Text(
                    stringResource(R.string.w3_scan_on_phone_note),
                    style = type.bodySm, color = colors.onSurfaceVariant,
                )
            }
        }
        Box(Modifier.height(SolarSpacing.xl))
    }
}

@Composable
private fun StageCard(
    icon: androidx.compose.ui.graphics.vector.ImageVector,
    title: String,
    message: String,
    monospacedMessage: Boolean = false,
    actions: @Composable () -> Unit,
) {
    val colors = SolarTheme.colors
    val type = SolarTheme.type
    Column(
        Modifier
            .fillMaxSize()
            .padding(horizontal = SolarSpacing.margin)
            .padding(top = SolarSpacing.md, bottom = SolarSpacing.xl),
        verticalArrangement = Arrangement.spacedBy(SolarSpacing.lg),
    ) {
        SolarCard(Modifier.fillMaxWidth()) {
            Column(verticalArrangement = Arrangement.spacedBy(SolarSpacing.md)) {
                ToneBadgeIcon(
                    icon, SolarTone.AMBER, contentDescription = null, size = 52.dp,
                )
                Text(title, style = type.headlineMd, color = colors.primary)
                Text(
                    message,
                    style = if (monospacedMessage) type.hex else type.bodyLg,
                    color = colors.onSurfaceVariant,
                )
            }
        }
        actions()
    }
}
