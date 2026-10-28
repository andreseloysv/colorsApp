// Pantalla del Feed: espejo de ios/ColorsApp/Views/Feed/FeedView.swift.
// Cabecera de marca, chips de filtro (Todo / 2 / 3 / 4 colores / Guardadas /
// Por votar), banner del escaneo del carrete, combinacion del dia con
// «Otra combinacion» (regla exacta de DayPick, composicion del libro) y una
// publicacion por scan. Acciones reales: votar, guardar en el Jardin
// (garden.json), copiar hex, compartir tarjeta, abrir en Extraer (re-analiza
// sin crear otro scan; si el scan es antiguo lo actualiza), borrar. La
// primera vez presenta el onboarding del escaneo si hay runner real.
package com.andreseloy.colorsapp.feature.feed

import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.graphics.Bitmap
import android.net.Uri
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBars
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.produceState
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import com.andreseloy.colorsapp.R
import com.andreseloy.colorsapp.app.AppContainer
import com.andreseloy.colorsapp.data.FeedbackVerdict
import com.andreseloy.colorsapp.data.ScanRecord
import com.andreseloy.colorsapp.design.SolarCard
import com.andreseloy.colorsapp.design.SolarChip
import com.andreseloy.colorsapp.design.SolarHeader
import com.andreseloy.colorsapp.design.SolarHeaderButton
import com.andreseloy.colorsapp.design.SolarHeaderCreatureButton
import com.andreseloy.colorsapp.design.SolarIconLeaf
import com.andreseloy.colorsapp.design.SolarIconSparkles
import com.andreseloy.colorsapp.design.SolarIconSun
import com.andreseloy.colorsapp.design.SolarPrimaryButton
import com.andreseloy.colorsapp.design.SolarSecondaryButton
import com.andreseloy.colorsapp.design.SolarSizes
import com.andreseloy.colorsapp.design.SolarSpacing
import com.andreseloy.colorsapp.design.SolarTheme
import com.andreseloy.colorsapp.design.WellContainer
import com.andreseloy.colorsapp.feature.extract.ErrorText
import com.andreseloy.colorsapp.feature.extract.PaletteColor
import com.andreseloy.colorsapp.feature.extract.PhotoLoading
import com.andreseloy.colorsapp.feature.extract.ResultModel
import com.andreseloy.colorsapp.feature.extract.ScanAnalyzer
import com.andreseloy.colorsapp.feature.extract.ScanOutcome
import com.andreseloy.colorsapp.feature.extract.ScanPhotoStore
import com.andreseloy.colorsapp.feature.extract.W3Format
import com.andreseloy.colorsapp.feature.extract.colorAccessibilityLabel
import com.andreseloy.colorsapp.feature.extract.garmentShortLabel
import com.andreseloy.colorsapp.feature.extract.numberLabel
import com.andreseloy.colorsapp.feature.share.ShareCardSheet
import com.andreseloy.colorsapp.feature.share.ShareFormat
import com.andreseloy.colorsapp.feature.wrapped.ScanOnboardingSheet
import com.andreseloy.colorsapp.scan.NoopScanRunner
import com.andreseloy.colorsapp.scan.ScanProgress
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.time.LocalDate
import java.time.ZoneId

private const val PAGE_SIZE = 50
private const val PREFS_W3 = "w3_feed"
private const val KEY_GARDEN_SEEN = "gardenSeenUnlocks"

/** Foto de una publicacion: copia guardada o la Uri del carrete (assetId). */
suspend fun loadScanPhoto(context: Context, scan: ScanRecord, maxSide: Int = 1024): Bitmap? =
    withContext(Dispatchers.IO) {
        ScanPhotoStore.image(context, scan.id, maxSide)?.let { return@withContext it }
        val asset = scan.assetId ?: return@withContext null
        runCatching { PhotoLoading.loadUpright(context, Uri.parse(asset), maxSide) }.getOrNull()
    }

@Composable
fun FeedScreen(
    container: AppContainer,
    onAnalyzePhoto: () -> Unit,
    onOpenGarden: () -> Unit,
    onShowGridFromScan: () -> Unit,
    onOpenLayers: (() -> Unit)? = null,
    modifier: Modifier = Modifier,
) {
    val context = LocalContext.current
    val resources = context.resources
    val scope = rememberCoroutineScope()
    val garden = remember { GardenSavedStore.getInstance(context) }
    val dictionary = container.dictionary
    val colors = SolarTheme.colors
    val type = SolarTheme.type

    var filter by remember { mutableStateOf(FeedFilter.ALL) }
    var limit by remember { mutableIntStateOf(PAGE_SIZE) }
    var loaded by remember { mutableStateOf(false) }
    var items by remember { mutableStateOf<List<FeedItemData>>(emptyList()) }
    var itemCache by remember { mutableStateOf<Map<String, FeedItemData>>(emptyMap()) }
    var verdicts by remember { mutableStateOf<Map<String, FeedbackVerdict>>(emptyMap()) }
    val unlockedIds by container.unlocks.observeUnlockedIds().collectAsState(emptySet())
    val savedItems by garden.items.collectAsState()
    val savedIds = remember(savedItems) { garden.savedScanIds }
    val scanProgress by container.scanProgress.collectAsState()

    var shuffleDay by remember { mutableStateOf<Long?>(null) }
    var shuffleCombo by remember { mutableIntStateOf(0) }
    var comboSheetId by remember { mutableStateOf<Int?>(null) }
    var shareScan by remember { mutableStateOf<ScanRecord?>(null) }
    var sharePhoto by remember { mutableStateOf<Bitmap?>(null) }
    var toast by remember { mutableStateOf<String?>(null) }
    var copiedPostId by remember { mutableStateOf<String?>(null) }
    var deleteCandidate by remember { mutableStateOf<ScanRecord?>(null) }
    var reopeningId by remember { mutableStateOf<String?>(null) }
    var reopenedModel by remember { mutableStateOf<ResultModel?>(null) }
    var showScan by remember { mutableStateOf(false) }
    var onboardingChecked by remember { mutableStateOf(false) }

    fun flash(text: String) {
        toast = text
    }

    LaunchedEffect(toast) {
        if (toast != null) {
            delay(2200)
            toast = null
            copiedPostId = null
        }
    }

    // Observación de scans (paginada por límite, con caché por id#rev).
    LaunchedEffect(limit) {
        container.scans.observeRecent(limit).collect { scans ->
            val built = withContext(Dispatchers.Default) {
                val cache = itemCache.toMutableMap()
                val list = scans.map { scan ->
                    val key = "${scan.id}#${scan.rev}"
                    cache[key] ?: FeedItemBuilder.build(
                        scan, dictionary, { garmentShortLabel(resources, it) },
                        container.engineVersion, container.engineDictVersion,
                    ).also { cache[key] = it }
                }
                itemCache = cache
                list
            }
            items = built
            garden.prune(scans.map { it.id }.toSet())
            val latest = runCatching { container.feedback.all() }.getOrDefault(emptyList())
            val byScan = latest.groupBy { it.scanId }
                .mapValues { (_, rows) -> rows.maxBy { it.createdAtMs }.verdict }
            verdicts = byScan + verdicts.filterKeys { it !in byScan }
            loaded = true
        }
    }

    // Onboarding del escaneo la primera vez (solo con runner real).
    LaunchedEffect(Unit) {
        if (onboardingChecked) return@LaunchedEffect
        onboardingChecked = true
        if (container.scanRunner is NoopScanRunner) return@LaunchedEffect
        val done = runCatching {
            container.settings.bool(
                com.andreseloy.colorsapp.data.SettingsRepository.Key.INITIAL_SCAN_DONE,
            )
        }.getOrDefault(false)
        val skipped = runCatching {
            container.settings.bool(
                com.andreseloy.colorsapp.data.SettingsRepository.Key.SCAN_ONBOARDING_SKIPPED,
            )
        }.getOrDefault(false)
        if (FeedOnboarding.shouldPresent(done, skipped)) showScan = true
    }

    fun copyColors(list: List<PaletteColor>, postId: String?) {
        if (list.isEmpty()) return
        val clipboard = context.getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
        clipboard.setPrimaryClip(ClipData.newPlainText("hex", W3Format.hexList(list)))
        flash(
            if (list.size == 1) {
                resources.getString(R.string.w3_copied_one, list.first().hex)
            } else {
                resources.getString(R.string.w3_copied_many, list.size)
            },
        )
        copiedPostId = postId
    }

    fun vote(verdict: FeedbackVerdict, item: FeedItemData) {
        if (verdicts[item.id] != null) return
        verdicts = verdicts + (item.id to verdict)
        scope.launch {
            runCatching {
                container.feedback.record(item.id, verdict)
            }.onSuccess {
                flash(
                    resources.getString(
                        if (verdict == FeedbackVerdict.YES) {
                            R.string.w3_thanks_hit
                        } else {
                            R.string.w3_thanks_consider
                        },
                    ),
                )
            }.onFailure {
                verdicts = verdicts - item.id
                flash(ErrorText.describe(resources, it))
            }
        }
    }

    fun reopen(item: FeedItemData, photo: Bitmap?) {
        if (reopeningId != null) return
        if (photo == null) {
            flash(resources.getString(R.string.w3_photo_unavailable_analysis))
            return
        }
        reopeningId = item.id
        scope.launch {
            try {
                val fallback = container.settings.subjectSettings().subjectOptions()
                val options = ScanAnalyzer.subjectOptionsFor(item.scan, fallback)
                val analysis = ScanAnalyzer.analyze(container, photo, options)
                var record = item.scan
                var updated = false
                if (com.andreseloy.colorsapp.feature.extract.AnalysisPolicy.needsReanalysis(
                        item.scan, container.engineVersion, container.engineDictVersion,
                    )
                ) {
                    record = com.andreseloy.colorsapp.feature.extract.ScanJson.updatedRecord(
                        old = item.scan, result = analysis.result,
                        subject = com.andreseloy.colorsapp.feature.extract.ScanSubjectInfo(
                            options, analysis.subject,
                        ),
                        garments = analysis.garmentInfo,
                        policyVersion = com.andreseloy.colorsapp.feature.extract.AnalysisPolicy.CURRENT,
                        engineVersion = container.engineVersion,
                        dictVersion = container.engineDictVersion,
                        nowMs = System.currentTimeMillis(),
                    )
                    container.scans.update(record)
                    updated = true
                }
                val recalculated = analysis.result.hits.firstOrNull()?.comboId != item.scan.top1 ||
                    item.scan.engineVersion != container.engineVersion
                val outcome = ScanOutcome(
                    bitmap = photo, raster = analysis.raster, result = analysis.result,
                    scan = record, subjectOptions = options, subject = analysis.subject,
                    debug = analysis.debug, garments = analysis.garments,
                    garmentRegionCount = analysis.garmentRegionCount,
                    garmentLayers = analysis.garmentLayers, timings = analysis.timings,
                )
                val model = ResultModel(outcome, container, garden, context, scope)
                model.banner = when {
                    updated -> resources.getString(R.string.w3_banner_updated)
                    recalculated -> resources.getString(R.string.w3_banner_recalculated)
                    else -> null
                }
                model.load()
                reopenedModel = model
                model.banner?.let { flash(it) }
            } catch (e: Exception) {
                flash(ErrorText.describe(resources, e))
            } finally {
                reopeningId = null
            }
        }
    }

    fun deleteScan(scan: ScanRecord) {
        deleteCandidate = null
        scope.launch {
            runCatching {
                container.scans.softDelete(scan.id)
                withContext(Dispatchers.IO) { ScanPhotoStore.remove(context, scan.id) }
                garden.remove(scan.id)
            }.onSuccess {
                flash(resources.getString(R.string.w3_deleted_from_feed))
            }.onFailure {
                flash(ErrorText.describe(resources, it))
            }
        }
    }

    // Resultado reabierto: pantalla completa empujada sobre el Feed (ResultView de iOS).
    reopenedModel?.let { model ->
        com.andreseloy.colorsapp.feature.extract.ResultPushedScreen(
            model = model,
            dictionary = dictionary,
            onBack = { reopenedModel = null },
            // Como en iOS: desde el resultado reabierto se entra en Capas
            // (ScanAnalyzer.analyze ya dejó la entrada en LayerInputHolder).
            onOpenLayers = onOpenLayers,
            modifier = modifier,
        )
        W3ToastHost(toast)
        return
    }

    Box(modifier.fillMaxSize().background(colors.surface)) {
        Column(Modifier.fillMaxSize().windowInsetsPadding(WindowInsets.statusBars)) {
            val prefs = remember { context.getSharedPreferences(PREFS_W3, Context.MODE_PRIVATE) }
            var gardenSeen by remember {
                mutableIntStateOf(prefs.getInt(KEY_GARDEN_SEEN, 0))
            }
            val newUnlocks = maxOf(0, unlockedIds.size - maxOf(0, gardenSeen))
            SolarHeader(section = stringResource(R.string.section_feed)) {
                // Sol-espíritu y avatar del Jardín de iOS (FIDELITY §2.2).
                SolarHeaderCreatureButton(
                    creature = com.andreseloy.colorsapp.design.BrandCreature.SEED,
                    contentDescription = stringResource(R.string.w3_analyze_photo),
                    onClick = onAnalyzePhoto,
                )
                Box {
                    SolarHeaderCreatureButton(
                        creature = com.andreseloy.colorsapp.design.BrandCreature.SPROUT,
                        contentDescription = stringResource(R.string.tab_garden),
                        onClick = {
                            gardenSeen = unlockedIds.size
                            prefs.edit().putInt(KEY_GARDEN_SEEN, gardenSeen).apply()
                            onOpenGarden()
                        },
                    )
                    if (newUnlocks > 0) {
                        Box(
                            Modifier
                                .align(Alignment.TopEnd)
                                .size(18.dp)
                                .clip(CircleShape)
                                .background(colors.secondary),
                            contentAlignment = Alignment.Center,
                        ) {
                            Text(
                                "$newUnlocks", style = type.labelSm, color = colors.onSecondary,
                            )
                        }
                    }
                }
            }
            LazyColumn(
                modifier = Modifier.fillMaxSize().testTag("feed.root"),
                contentPadding = PaddingValues(bottom = SolarSpacing.lg),
            ) {
                item { FeedFilterChips(filter) { filter = it } }
                if (isScanBannerVisible(scanProgress)) {
                    item {
                        FeedScanBanner(
                            scanProgress,
                            Modifier.padding(horizontal = SolarSpacing.margin, vertical = SolarSpacing.sm),
                        )
                    }
                }
                item {
                    val today = LocalDate.now()
                    val days = DayPick.localDaysSince1970(today)
                    val dayId = if (shuffleDay == days && shuffleCombo in 1..dictionary.combinations.size) {
                        shuffleCombo
                    } else {
                        DayPick.comboId(days, dictionary.combinations.size)
                    }
                    FeedDayCard(
                        comboId = dayId,
                        isToday = shuffleDay != days,
                        dictionary = dictionary,
                        unlocked = dayId in unlockedIds,
                        onShuffle = {
                            shuffleDay = days
                            shuffleCombo = DayPick.another(dayId, dictionary.combinations.size)
                        },
                        onOpen = { comboSheetId = dayId },
                        onCopyColor = { copyColors(listOf(it), null) },
                        modifier = Modifier.padding(
                            horizontal = SolarSpacing.margin, vertical = SolarSpacing.sm,
                        ),
                    )
                }
                when {
                    !loaded -> item {
                        Box(
                            Modifier.fillMaxWidth().padding(SolarSpacing.xl),
                            contentAlignment = Alignment.Center,
                        ) { CircularProgressIndicator(color = colors.primary) }
                    }
                    items.isEmpty() -> item {
                        FeedEmptyState(
                            onAnalyze = onAnalyzePhoto,
                            onScanLibrary = if (container.scanRunner is NoopScanRunner) {
                                null
                            } else {
                                { showScan = true }
                            },
                            modifier = Modifier.padding(
                                horizontal = SolarSpacing.margin, vertical = SolarSpacing.sm,
                            ),
                        )
                    }
                    else -> {
                        val visible = items.filter {
                            filter.includes(it.top1Size, verdicts[it.id], it.id in savedIds)
                        }
                        if (visible.isEmpty()) {
                            item {
                                Text(
                                    text = filterEmptyText(filter),
                                    style = type.bodyMd, color = colors.onSurfaceVariant,
                                    modifier = Modifier.fillMaxWidth().padding(SolarSpacing.xl),
                                )
                            }
                        }
                        items(visible, key = { it.id }) { item ->
                            FeedPostRow(
                                item = item,
                                verdict = verdicts[item.id],
                                isSaved = item.id in savedIds,
                                isCopied = copiedPostId == item.id,
                                isReopening = reopeningId == item.id,
                                loadPhoto = { loadScanPhoto(context, item.scan) },
                                handlers = FeedPostHandlers(
                                    vote = { vote(it, item) },
                                    toggleSave = {
                                        val saved = garden.toggle(item.id)
                                        flash(
                                            resources.getString(
                                                if (saved) {
                                                    R.string.w3_saved_in_garden_toast
                                                } else {
                                                    R.string.w3_removed_from_garden
                                                },
                                            ),
                                        )
                                    },
                                    copyCombo = {
                                        item.match?.let { copyColors(it.colors, item.id) }
                                    },
                                    copyPalette = { copyColors(item.palette, null) },
                                    copyColor = { copyColors(listOf(it), null) },
                                    openInExtract = { photo -> reopen(item, photo) },
                                    openCombo = { comboSheetId = it },
                                    share = { photo ->
                                        sharePhoto = photo
                                        shareScan = item.scan
                                    },
                                    delete = { deleteCandidate = item.scan },
                                ),
                                modifier = Modifier.padding(
                                    horizontal = SolarSpacing.margin, vertical = SolarSpacing.sm,
                                ),
                            )
                            LaunchedEffect(item.id) {
                                if (item.id == items.lastOrNull()?.id && items.size >= limit) {
                                    limit += PAGE_SIZE
                                }
                            }
                        }
                    }
                }
                item { Box(Modifier.height(SolarSpacing.xl)) }
            }
        }
        // Toast arriba, bajo la cabecera, 2,2 s.
        Box(Modifier.align(Alignment.TopCenter).windowInsetsPadding(WindowInsets.statusBars)) {
            W3ToastHost(toast, Modifier.padding(top = SolarSizes.header + SolarSpacing.margin))
        }
    }

    comboSheetId?.let { id -> ComboSheet(id, dictionary) { comboSheetId = null } }
    shareScan?.let { scan ->
        ShareCardSheet(
            scan = scan, photo = sharePhoto, dictionary = dictionary,
            initialFormat = ShareFormat.POST,
            onDismiss = { shareScan = null },
        )
    }
    if (showScan) {
        ScanOnboardingSheet(
            container = container,
            onShowGrid = {
                showScan = false
                onShowGridFromScan()
            },
            onDismiss = {
                showScan = false
                scope.launch {
                    val done = runCatching {
                        container.settings.bool(
                            com.andreseloy.colorsapp.data.SettingsRepository.Key.INITIAL_SCAN_DONE,
                        )
                    }.getOrDefault(false)
                    if (!done) {
                        runCatching {
                            container.settings.setBool(
                                com.andreseloy.colorsapp.data.SettingsRepository.Key.SCAN_ONBOARDING_SKIPPED,
                                true,
                            )
                        }
                    }
                }
            },
            showSkip = true,
        )
    }
    deleteCandidate?.let { scan ->
        AlertDialog(
            onDismissRequest = { deleteCandidate = null },
            title = { Text(stringResource(R.string.w3_delete_dialog_title), style = type.cardTitle) },
            text = { Text(stringResource(R.string.w3_delete_dialog_body), style = type.bodyMd) },
            confirmButton = {
                TextButton(onClick = { deleteScan(scan) }) {
                    Text(stringResource(R.string.w3_delete), color = colors.error)
                }
            },
            dismissButton = {
                TextButton(onClick = { deleteCandidate = null }) {
                    Text(stringResource(R.string.w3_cancel))
                }
            },
        )
    }
}

@Composable
private fun filterEmptyText(filter: FeedFilter): String = when (filter) {
    FeedFilter.ALL -> stringResource(R.string.w3_feed_empty_all)
    FeedFilter.TWO, FeedFilter.THREE, FeedFilter.FOUR ->
        stringResource(R.string.w3_feed_empty_size, filter.comboSize ?: 0)
    FeedFilter.SAVED -> stringResource(R.string.w3_feed_empty_saved)
    FeedFilter.UNVOTED -> stringResource(R.string.w3_feed_empty_unvoted)
}

fun isScanBannerVisible(progress: ScanProgress): Boolean = when (progress.phase) {
    ScanProgress.Phase.REQUESTING_ACCESS,
    ScanProgress.Phase.FETCHING,
    ScanProgress.Phase.ANALYZING,
    -> true
    else -> false
}

/** Fila de chips con los puntos de tono de marca del ejemplo (salvia, anil…). */
@Composable
fun FeedFilterChips(selection: FeedFilter, onSelect: (FeedFilter) -> Unit) {
    val dark = SolarTheme.colors.dark
    val filters = FeedFilter.entries
    LazyRow(
        contentPadding = PaddingValues(horizontal = SolarSpacing.margin, vertical = SolarSpacing.sm),
        horizontalArrangement = Arrangement.spacedBy(SolarSpacing.sm),
        modifier = Modifier.testTag("feed.filters"),
    ) {
        items(filters) { item ->
            val dot = when (item) {
                FeedFilter.ALL, FeedFilter.TWO -> Color(0xFF81B29A)
                FeedFilter.THREE -> if (dark) Color(0xFFA9AED6) else Color(0xFF3D405B)
                FeedFilter.FOUR -> if (dark) Color(0xFF8FBF8D) else Color(0xFF588157)
                FeedFilter.SAVED -> Color(0xFFE07A5F)
                FeedFilter.UNVOTED -> Color(0xFFE9B44C)
            }
            SolarChip(
                text = when (item) {
                    FeedFilter.ALL -> stringResource(R.string.w3_filter_all)
                    FeedFilter.TWO, FeedFilter.THREE, FeedFilter.FOUR ->
                        stringResource(R.string.w3_colors_count, item.comboSize ?: 0)
                    FeedFilter.SAVED -> stringResource(R.string.w3_filter_saved)
                    FeedFilter.UNVOTED -> stringResource(R.string.w3_filter_unvoted)
                },
                selected = item == selection,
                onClick = { onSelect(item) },
                dot = if (item == selection) null else dot,
                modifier = Modifier.testTag("feed.filter.${item.name.lowercase()}"),
            )
        }
    }
}

/** Banner del progreso del escaneo del carrete bajo los chips. */
@Composable
fun FeedScanBanner(progress: ScanProgress, modifier: Modifier = Modifier) {
    val colors = SolarTheme.colors
    val type = SolarTheme.type
    SolarCard(modifier.fillMaxWidth(), fill = colors.container) {
        Column(verticalArrangement = Arrangement.spacedBy(SolarSpacing.sm)) {
            Text(
                text = when (progress.phase) {
                    ScanProgress.Phase.REQUESTING_ACCESS -> stringResource(R.string.w3_scan_requesting)
                    ScanProgress.Phase.FETCHING -> stringResource(R.string.w3_scan_fetching)
                    ScanProgress.Phase.ANALYZING -> stringResource(
                        R.string.w3_scan_analyzing_library, progress.processed, progress.total,
                    )
                    ScanProgress.Phase.FINISHED -> stringResource(R.string.w3_scan_finished_banner)
                    ScanProgress.Phase.FAILED -> stringResource(R.string.w3_scan_failed_banner)
                    ScanProgress.Phase.IDLE -> ""
                },
                style = type.labelLg, color = colors.onSurface,
            )
            if (progress.phase == ScanProgress.Phase.ANALYZING) {
                LinearProgressIndicator(
                    progress = { progress.fraction.toFloat() },
                    color = colors.primary, trackColor = colors.surfaceVariant,
                    modifier = Modifier.fillMaxWidth(),
                )
            } else {
                LinearProgressIndicator(
                    color = colors.primary, trackColor = colors.surfaceVariant,
                    modifier = Modifier.fillMaxWidth(),
                )
            }
        }
    }
}

/** Combinacion del dia con la composicion del libro y «Otra combinación». */
@Composable
fun FeedDayCard(
    comboId: Int,
    isToday: Boolean,
    dictionary: com.andreseloy.colorsapp.data.WadaDictionary,
    unlocked: Boolean,
    onShuffle: () -> Unit,
    onOpen: () -> Unit,
    onCopyColor: (PaletteColor) -> Unit,
    modifier: Modifier = Modifier,
) {
    val colors = SolarTheme.colors
    val type = SolarTheme.type
    val comboColors = remember(comboId) { PaletteColor.combo(comboId, dictionary) }
    val name = FeedComboName.name(comboId, dictionary) ?: numberLabel(comboId)
    val size = dictionary.combo(comboId)?.size ?: 0
    SolarCard(modifier.fillMaxWidth().testTag("feed.day"), fill = colors.container) {
        Column(verticalArrangement = Arrangement.spacedBy(SolarSpacing.sm)) {
            Row(
                Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Row(
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(SolarSpacing.xs),
                ) {
                    // Sol pequeño antes del rótulo, como en iOS.
                    Icon(
                        SolarIconSun, contentDescription = null,
                        tint = colors.secondary, modifier = Modifier.size(14.dp),
                    )
                    Text(
                        text = stringResource(
                            if (isToday) R.string.w3_day_combo else R.string.w3_random_combo,
                        ).uppercase(),
                        style = type.overline, color = colors.secondary,
                    )
                }
                Box(
                    Modifier
                        .clip(RoundedCornerShape(50))
                        .background(colors.containerHighest)
                        .padding(horizontal = SolarSpacing.sm, vertical = 2.dp),
                ) {
                    Text(numberLabel(comboId), style = type.labelSm, color = colors.onSurfaceVariant)
                }
            }
            WellContainer(Modifier.fillMaxWidth()) {
                BookComposition(
                    colors = comboColors,
                    maxHeight = SolarSizes.dayComposition,
                    descriptionFor = { color, i ->
                        colorAccessibilityLabel(color, i, comboColors.size)
                    },
                    onTap = onCopyColor,
                )
            }
            Row(
                Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically,
            ) {
                TextButton(onClick = onOpen, modifier = Modifier.weight(1f)) {
                    Text(
                        "✦ $name", style = type.headlineSm, color = colors.onSurface,
                        maxLines = 2,
                    )
                }
                val colorsText = if (size == 1) {
                    stringResource(R.string.w3_one_color)
                } else {
                    stringResource(R.string.w3_colors_count, size)
                }
                val state = stringResource(
                    if (unlocked) R.string.w3_in_grid else R.string.w3_locked_state,
                )
                Text(
                    "$colorsText · $state".uppercase(),
                    style = type.labelSm, color = colors.onSurfaceVariant, maxLines = 1,
                )
            }
            SolarPrimaryButton(
                text = stringResource(R.string.w3_another_combo),
                icon = SolarIconSparkles,
                onClick = onShuffle,
                modifier = Modifier.testTag("feed.day.shuffle"),
            )
        }
    }
}

/** Estado vacio del Feed: invitacion a Extraer y al escaneo del carrete. */
@Composable
fun FeedEmptyState(
    onAnalyze: () -> Unit,
    onScanLibrary: (() -> Unit)?,
    modifier: Modifier = Modifier,
) {
    val colors = SolarTheme.colors
    val type = SolarTheme.type
    SolarCard(modifier.fillMaxWidth().testTag("feed.empty")) {
        Column(verticalArrangement = Arrangement.spacedBy(SolarSpacing.md)) {
            Box(
                Modifier.size(64.dp).clip(CircleShape).background(colors.amberBadge),
                contentAlignment = Alignment.Center,
            ) {
                androidx.compose.material3.Icon(
                    SolarIconSun, contentDescription = null, tint = colors.onAmberBadge,
                    modifier = Modifier.size(36.dp),
                )
            }
            Text(stringResource(R.string.w3_feed_empty_title), style = type.headlineMd, color = colors.onSurface)
            Text(stringResource(R.string.w3_feed_empty_body), style = type.bodyLg, color = colors.onSurfaceVariant)
            SolarPrimaryButton(
                text = stringResource(R.string.w3_analyze_photo), onClick = onAnalyze,
                modifier = Modifier.testTag("feed.empty.analyze"),
            )
            if (onScanLibrary != null) {
                SolarSecondaryButton(
                    text = stringResource(R.string.w3_scan_library), onClick = onScanLibrary,
                )
            }
        }
    }
}

/** Hoja breve de una combinacion (el detalle completo es de la Rejilla/W4). */
@Composable
fun ComboSheet(
    comboId: Int,
    dictionary: com.andreseloy.colorsapp.data.WadaDictionary,
    onDismiss: () -> Unit,
) {
    val colors = SolarTheme.colors
    val type = SolarTheme.type
    val comboColors = remember(comboId) { PaletteColor.combo(comboId, dictionary) }
    val name = FeedComboName.name(comboId, dictionary) ?: numberLabel(comboId)
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text(name, style = type.headlineSm) },
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(SolarSpacing.sm)) {
                Text(numberLabel(comboId), style = type.labelSm, color = colors.onSurfaceVariant)
                WellContainer(Modifier.fillMaxWidth()) {
                    BookComposition(comboColors, maxHeight = SolarSizes.dayComposition)
                }
                comboColors.forEach { color ->
                    Row(
                        Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.SpaceBetween,
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        Row(
                            verticalAlignment = Alignment.CenterVertically,
                            horizontalArrangement = Arrangement.spacedBy(SolarSpacing.sm),
                        ) {
                            Box(
                                Modifier.size(20.dp).clip(CircleShape)
                                    .background(Color(color.argb)),
                            )
                            Text(color.name ?: color.hex, style = type.labelLg, color = colors.onSurface)
                        }
                        Text(color.hex, style = type.hex, color = colors.onSurfaceVariant)
                    }
                }
            }
        },
        confirmButton = {
            TextButton(onClick = onDismiss) { Text(stringResource(R.string.w3_close)) }
        },
    )
}

/** Toast de W3 (el SolarToast luminoso de iOS llega con el pulido de W5). */
@Composable
fun W3ToastHost(toast: String?, modifier: Modifier = Modifier) {
    val colors = SolarTheme.colors
    val type = SolarTheme.type
    if (toast != null) {
        Box(
            modifier
                .padding(horizontal = SolarSpacing.margin)
                .clip(RoundedCornerShape(50))
                .background(colors.frostTint)
                .padding(horizontal = SolarSpacing.md, vertical = SolarSpacing.sm),
        ) {
            Row(
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(SolarSpacing.sm),
            ) {
                androidx.compose.material3.Icon(
                    SolarIconSparkles, contentDescription = null, tint = colors.secondary,
                    modifier = Modifier.size(16.dp),
                )
                Text(toast, style = type.labelMd, color = colors.onSurface)
            }
        }
    }
}
