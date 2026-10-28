// Pestana Extraer: espejo de Views/Extract/ExtractView.swift +
// ExtractCaptureContent.swift. Captura (visor con «Elegir foto», «Camara» y
// «Escanear carrete (200 fotos)») y resultado en la misma pantalla. La foto
// se elige con el Photo Picker del sistema (SIN permiso) y la camara con el
// intent del sistema (TakePicture: SIN permiso CAMERA; el JPEG va a un
// fichero de cache propio servido por FileProvider). El analisis es
// ScanAnalyzer.run (cadena de sujeto + motor, scan guardado).
package com.andreseloy.colorsapp.feature.extract

import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.net.Uri
import android.provider.MediaStore
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.PickVisualMediaRequest
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBars
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.produceState
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.blur
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import androidx.core.content.FileProvider
import com.andreseloy.colorsapp.R
import com.andreseloy.colorsapp.app.AppContainer
import com.andreseloy.colorsapp.data.ScanSource
import com.andreseloy.colorsapp.design.SolarCard
import com.andreseloy.colorsapp.design.SolarHeader
import com.andreseloy.colorsapp.design.SolarHeaderButton
import com.andreseloy.colorsapp.design.SolarIconCamera
import com.andreseloy.colorsapp.design.SolarIconDrop
import com.andreseloy.colorsapp.design.SolarIconGrid
import com.andreseloy.colorsapp.design.SolarIconLeaf
import com.andreseloy.colorsapp.design.SolarIconSun
import com.andreseloy.colorsapp.design.SolarSecondaryButton
import com.andreseloy.colorsapp.design.SolarSizes
import com.andreseloy.colorsapp.design.SolarSpacing
import com.andreseloy.colorsapp.design.SolarTheme
import com.andreseloy.colorsapp.design.SolarTone
import com.andreseloy.colorsapp.design.ToneBadgeIcon
import com.andreseloy.colorsapp.design.solarPress
import com.andreseloy.colorsapp.feature.feed.GardenSavedStore
import com.andreseloy.colorsapp.design.SolarIconCheck
import com.andreseloy.colorsapp.design.SolarIconPerson
import com.andreseloy.colorsapp.design.SolarIconPhoto
import com.andreseloy.colorsapp.design.SolarIconPhotoStack
import com.andreseloy.colorsapp.design.SolarIconWarning
import com.andreseloy.colorsapp.feature.feed.W3ToastHost
import com.andreseloy.colorsapp.feature.wrapped.ScanOnboardingSheet
import com.andreseloy.colorsapp.scan.NoopScanRunner
import com.andreseloy.colorsapp.scan.ScanProgress
import com.andreseloy.colorsapp.subject.RegionMode
import com.andreseloy.colorsapp.subject.SubjectMode
import com.andreseloy.colorsapp.subject.SubjectSettings
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.io.File

/** Estado del visor de captura (ExtractCaptureState de iOS). */
sealed interface ExtractCaptureState {
    data object Idle : ExtractCaptureState
    data class Working(val text: String) : ExtractCaptureState
    data class Failed(val message: String) : ExtractCaptureState
}

@Composable
fun ExtractScreen(
    container: AppContainer,
    onOpenGarden: () -> Unit,
    onShowGridFromScan: () -> Unit,
    onOpenLayers: (() -> Unit)? = null,
    modifier: Modifier = Modifier,
) {
    val context = LocalContext.current
    val resources = context.resources
    val scope = rememberCoroutineScope()
    val garden = remember { GardenSavedStore.getInstance(context) }
    val colors = SolarTheme.colors

    var resultModel by remember { mutableStateOf<ResultModel?>(null) }
    var capture by remember { mutableStateOf<ExtractCaptureState>(ExtractCaptureState.Idle) }
    var pendingBitmap by remember { mutableStateOf<Bitmap?>(null) }
    var showScan by remember { mutableStateOf(false) }
    var toast by remember { mutableStateOf<String?>(null) }
    var cameraFile by remember { mutableStateOf<File?>(null) }
    var cameraUri by remember { mutableStateOf<Uri?>(null) }

    val cameraAvailable = remember {
        val intent = Intent(MediaStore.ACTION_IMAGE_CAPTURE)
        context.packageManager.queryIntentActivities(
            intent, PackageManager.MATCH_DEFAULT_ONLY,
        ).isNotEmpty()
    }

    fun analyze(bitmap: Bitmap, source: ScanSource, assetId: String?) {
        pendingBitmap = bitmap
        capture = ExtractCaptureState.Working(resources.getString(R.string.w3_analyzing_clothing))
        scope.launch {
            runCatching {
                ScanAnalyzer.run(context, container, bitmap, source, assetId)
            }.onSuccess { outcome ->
                val model = ResultModel(outcome, container, garden, context, scope)
                model.load()
                capture = ExtractCaptureState.Idle
                pendingBitmap = null
                resultModel = model
            }.onFailure {
                // Sin este registro un fallo sin mensaje solo se ve como «imagen ilegible».
                android.util.Log.w("ChromaSolExtract", "análisis fallido", it)
                capture = ExtractCaptureState.Failed(ErrorText.describe(resources, it))
            }
        }
    }

    val picker = rememberLauncherForActivityResult(
        ActivityResultContracts.PickVisualMedia(),
    ) { uri: Uri? ->
        if (uri == null) return@rememberLauncherForActivityResult
        capture = ExtractCaptureState.Working(resources.getString(R.string.w3_loading_photo))
        scope.launch {
            val bitmap = withContext(Dispatchers.IO) {
                runCatching { PhotoLoading.loadUpright(context, uri) }
                    .onFailure { android.util.Log.w("ChromaSolExtract", "carga de la foto fallida", it) }
                    .getOrNull()
            }
            if (bitmap == null) {
                capture = ExtractCaptureState.Failed(
                    ErrorText.describe(resources, UnreadableImageException()),
                )
            } else {
                analyze(bitmap, ScanSource.PICKER, uri.toString())
            }
        }
    }

    val camera = rememberLauncherForActivityResult(
        ActivityResultContracts.TakePicture(),
    ) { success: Boolean ->
        val file = cameraFile
        val uri = cameraUri
        if (!success || file == null || uri == null) {
            file?.delete()
            return@rememberLauncherForActivityResult
        }
        capture = ExtractCaptureState.Working(resources.getString(R.string.w3_preparing_photo))
        scope.launch {
            val bitmap = withContext(Dispatchers.IO) {
                runCatching { PhotoLoading.loadUpright(context, uri) }.getOrNull()
            }
            file.delete()
            if (bitmap == null) {
                capture = ExtractCaptureState.Failed(
                    ErrorText.describe(resources, UnreadableImageException()),
                )
            } else {
                analyze(bitmap, ScanSource.CAMERA, null)
            }
        }
    }

    fun launchCamera() {
        val dir = File(context.cacheDir, "captures").apply { mkdirs() }
        val file = File.createTempFile("capture_", ".jpg", dir)
        cameraFile = file
        val uri = FileProvider.getUriForFile(
            context, "${context.packageName}.fileprovider", file,
        )
        cameraUri = uri
        runCatching { camera.launch(uri) }.onFailure {
            capture = ExtractCaptureState.Failed(
                ErrorText.describe(resources, UnreadableImageException()),
            )
        }
    }

    Box(modifier.fillMaxSize().background(colors.surface)) {
        Column(Modifier.fillMaxSize().windowInsetsPadding(WindowInsets.statusBars)) {
            SolarHeader(section = stringResource(R.string.section_extract)) {
                SolarHeaderButton(
                    icon = SolarIconSun,
                    contentDescription = stringResource(
                        if (resultModel == null) R.string.w3_scan_library_200
                        else R.string.w3_pick_photo,
                    ),
                    onClick = {
                        if (resultModel == null) {
                            showScan = true
                        } else {
                            resultModel = null
                            capture = ExtractCaptureState.Idle
                            pendingBitmap = null
                        }
                    },
                )
                SolarHeaderButton(
                    icon = SolarIconLeaf,
                    contentDescription = stringResource(R.string.tab_garden),
                    onClick = onOpenGarden,
                )
            }
            Column(
                Modifier
                    .fillMaxSize()
                    .verticalScroll(rememberScrollState())
                    .padding(horizontal = SolarSpacing.margin)
                    .padding(top = SolarSpacing.sm, bottom = SolarSpacing.xl)
                    .testTag("extraer.root"),
                verticalArrangement = Arrangement.spacedBy(SolarSpacing.lg),
            ) {
                val model = resultModel
                if (model != null) {
                    ResultContent(
                        model = model,
                        dictionary = container.dictionary,
                        onOpenLayers = onOpenLayers?.let { { it() } },
                        onToast = { toast = it },
                        onOpenCombo = { /* la hoja la abre ResultContent */ },
                    )
                } else {
                    CaptureContent(
                        container = container,
                        state = capture,
                        preview = pendingBitmap,
                        cameraAvailable = cameraAvailable,
                        scanEnabled = container.scanRunner !is NoopScanRunner,
                        onPick = {
                            picker.launch(
                                PickVisualMediaRequest(
                                    ActivityResultContracts.PickVisualMedia.ImageOnly,
                                ),
                            )
                        },
                        onCamera = { launchCamera() },
                        onScan = { showScan = true },
                    )
                }
            }
        }
        Box(Modifier.align(Alignment.TopCenter).windowInsetsPadding(WindowInsets.statusBars)) {
            W3ToastHost(toast, Modifier.padding(top = SolarSizes.header + SolarSpacing.margin))
        }
        androidx.compose.runtime.LaunchedEffect(toast) {
            if (toast != null) {
                kotlinx.coroutines.delay(2200)
                toast = null
            }
        }
    }

    if (showScan) {
        ScanOnboardingSheet(
            container = container,
            onShowGrid = {
                showScan = false
                onShowGridFromScan()
            },
            onDismiss = { showScan = false },
            showSkip = false,
        )
    }
}

@Composable
private fun CaptureContent(
    container: AppContainer,
    state: ExtractCaptureState,
    preview: Bitmap?,
    cameraAvailable: Boolean,
    scanEnabled: Boolean,
    onPick: () -> Unit,
    onCamera: () -> Unit,
    onScan: () -> Unit,
) {
    val colors = SolarTheme.colors
    val type = SolarTheme.type
    val settings by produceState<SubjectSettings?>(null) {
        value = runCatching { container.settings.subjectSettings() }.getOrNull()
    }
    val scanProgress by container.scanProgress.collectAsState()
    val working = state is ExtractCaptureState.Working

    Column(verticalArrangement = Arrangement.spacedBy(SolarSpacing.lg)) {
        Box(
            Modifier
                .fillMaxWidth()
                .heightIn(min = SolarSizes.viewfinderMaxHeight)
                .clip(RoundedCornerShape(12.dp))
                .background(colors.containerLow),
        ) {
            if (preview != null && working) {
                Image(
                    bitmap = preview.asImageBitmap(), contentDescription = null,
                    contentScale = ContentScale.Crop,
                    modifier = Modifier.fillMaxSize().blur(28.dp),
                )
                Image(
                    bitmap = preview.asImageBitmap(), contentDescription = null,
                    contentScale = ContentScale.Fit,
                    modifier = Modifier.fillMaxSize(),
                )
                Box(Modifier.fillMaxSize().background(ColorBlack30))
                Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                    Column(
                        Modifier
                            .clip(RoundedCornerShape(12.dp))
                            .background(colors.frostTint)
                            .padding(horizontal = SolarSpacing.lg, vertical = SolarSpacing.md),
                        horizontalAlignment = Alignment.CenterHorizontally,
                        verticalArrangement = Arrangement.spacedBy(SolarSpacing.sm),
                    ) {
                        CircularProgressIndicator(color = colors.primary)
                        Text(
                            (state as ExtractCaptureState.Working).text,
                            style = type.labelLg, color = colors.onSurface,
                        )
                    }
                }
            } else {
                Column(Modifier.fillMaxWidth()) {
                    Row(Modifier.fillMaxWidth().padding(SolarSpacing.md)) {
                        CropSettingsChip(settings)
                    }
                    Column(
                        Modifier.fillMaxWidth().padding(horizontal = SolarSpacing.lg),
                        horizontalAlignment = Alignment.CenterHorizontally,
                        verticalArrangement = Arrangement.spacedBy(SolarSpacing.md),
                    ) {
                        Box(
                            Modifier.size(64.dp).clip(CircleShape)
                                .background(colors.amberBadge),
                            contentAlignment = Alignment.Center,
                        ) {
                            Icon(
                                SolarIconSun, contentDescription = null,
                                tint = colors.onAmberBadge, modifier = Modifier.size(38.dp),
                            )
                        }
                        Column(
                            horizontalAlignment = Alignment.CenterHorizontally,
                            verticalArrangement = Arrangement.spacedBy(SolarSpacing.xs),
                        ) {
                            Text(
                                stringResource(R.string.w3_extract_title),
                                style = type.headlineSm, color = colors.onSurface,
                            )
                            Text(
                                stringResource(R.string.w3_extract_subtitle),
                                style = type.bodySm, color = colors.onSurfaceVariant,
                            )
                        }
                        Column(
                            Modifier.fillMaxWidth().padding(top = SolarSpacing.xs),
                            verticalArrangement = Arrangement.spacedBy(SolarSpacing.sm),
                            horizontalAlignment = Alignment.CenterHorizontally,
                        ) {
                            SolarSecondaryButton(
                                text = stringResource(R.string.w3_pick_photo),
                                onClick = onPick,
                                modifier = Modifier.fillMaxWidth().testTag("extraer.pick"),
                            )
                            PillButton(
                                text = stringResource(R.string.w3_source_camera),
                                icon = SolarIconCamera,
                                onClick = onCamera,
                                enabled = cameraAvailable && !working,
                                modifier = Modifier.fillMaxWidth().testTag("extraer.camera"),
                            )
                            if (!cameraAvailable) {
                                Text(
                                    stringResource(R.string.w3_no_camera),
                                    style = type.bodySm, color = colors.onSurfaceVariant,
                                )
                            }
                            GhostPillButton(
                                text = stringResource(R.string.w3_scan_library_200),
                                icon = SolarIconPhotoStack,
                                onClick = onScan,
                                enabled = scanEnabled && !isScanRunning(scanProgress),
                                modifier = Modifier.fillMaxWidth().testTag("extraer.scanLibrary"),
                            )
                        }
                    }
                }
            }
        }
        if (state is ExtractCaptureState.Failed) {
            Row(
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(SolarSpacing.sm),
                modifier = Modifier.testTag("extraer.error"),
            ) {
                Icon(
                    SolarIconWarning, contentDescription = null, tint = colors.error,
                    modifier = Modifier.size(18.dp),
                )
                Text(state.message, style = type.bodyMd, color = colors.error)
            }
        }
        if (isScanRunning(scanProgress)) {
            SolarCard(Modifier.fillMaxWidth(), fill = colors.container) {
                Column(verticalArrangement = Arrangement.spacedBy(SolarSpacing.sm)) {
                    Row(
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(SolarSpacing.sm),
                    ) {
                        Icon(
                            SolarIconPhotoStack, contentDescription = null, tint = colors.secondary,
                            modifier = Modifier.size(18.dp),
                        )
                        Text(
                            text = when (scanProgress.phase) {
                                ScanProgress.Phase.ANALYZING -> stringResource(
                                    R.string.w3_scan_analyzing_library,
                                    scanProgress.processed, scanProgress.total,
                                )
                                ScanProgress.Phase.FETCHING ->
                                    stringResource(R.string.w3_scan_fetching)
                                else -> stringResource(R.string.w3_scan_requesting)
                            },
                            style = type.labelLg, color = colors.onSurface,
                        )
                    }
                    if (scanProgress.phase == ScanProgress.Phase.ANALYZING) {
                        LinearProgressIndicator(
                            progress = { scanProgress.fraction.toFloat() },
                            color = colors.primary, modifier = Modifier.fillMaxWidth(),
                        )
                    } else {
                        LinearProgressIndicator(
                            color = colors.primary, modifier = Modifier.fillMaxWidth(),
                        )
                    }
                }
            }
        }
        // Qué hace el análisis (tres pasos reales)
        SolarCard(Modifier.fillMaxWidth()) {
            Column(verticalArrangement = Arrangement.spacedBy(SolarSpacing.md)) {
                Text(
                    stringResource(R.string.w3_what_analysis_does).uppercase(),
                    style = type.overline, color = colors.secondary,
                )
                AnalysisStep(
                    SolarIconPerson,
                    stringResource(R.string.w3_step1_title),
                    stringResource(R.string.w3_step1_body),
                )
                AnalysisStep(
                    SolarIconDrop,
                    stringResource(R.string.w3_step2_title),
                    stringResource(R.string.w3_step2_body),
                )
                AnalysisStep(
                    SolarIconGrid,
                    stringResource(R.string.w3_step3_title),
                    stringResource(R.string.w3_step3_body),
                )
            }
        }
    }
}

private val ColorBlack30 = androidx.compose.ui.graphics.Color(0x4D000000)

private fun isScanRunning(progress: ScanProgress): Boolean = when (progress.phase) {
    ScanProgress.Phase.REQUESTING_ACCESS, ScanProgress.Phase.FETCHING, ScanProgress.Phase.ANALYZING -> true
    else -> false
}

@Composable
private fun CropSettingsChip(settings: SubjectSettings?) {
    val colors = SolarTheme.colors
    val type = SolarTheme.type
    val title = if (settings == null) {
        stringResource(R.string.w3_subject_crop)
    } else if (settings.mode == SubjectMode.OFF) {
        stringResource(R.string.w3_crop_off_full)
    } else {
        val parts = mutableListOf(
            stringResource(
                when (settings.mode) {
                    SubjectMode.OFF -> R.string.w3_mode_off
                    SubjectMode.ALL_PEOPLE -> R.string.w3_mode_all_people
                    SubjectMode.LARGEST_PERSON -> R.string.w3_mode_largest
                    SubjectMode.SELECTED_PERSON -> R.string.w3_mode_selected
                },
            ),
            stringResource(
                if (settings.region == RegionMode.CLOTHING) {
                    R.string.w3_region_clothing_lower
                } else {
                    R.string.w3_region_person_lower
                },
            ),
        )
        if (settings.adaptiveSkin) parts += stringResource(R.string.w3_no_skin)
        parts.joinToString(" · ")
    }
    Row(
        Modifier
            .clip(RoundedCornerShape(50))
            .background(colors.frostTint)
            .padding(horizontal = 10.dp, vertical = 4.dp)
            .testTag("extraer.cropSettings"),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(6.dp),
    ) {
        Icon(
            SolarIconPerson, contentDescription = null, tint = colors.secondary,
            modifier = Modifier.size(13.dp),
        )
        Text(title, style = type.labelSm, color = colors.onSurface, maxLines = 1)
    }
}

@Composable
private fun AnalysisStep(
    icon: androidx.compose.ui.graphics.vector.ImageVector,
    title: String,
    detail: String,
) {
    val colors = SolarTheme.colors
    val type = SolarTheme.type
    Row(
        horizontalArrangement = Arrangement.spacedBy(SolarSpacing.md),
        verticalAlignment = Alignment.Top,
    ) {
        ToneBadgeIcon(icon, SolarTone.MOSS, contentDescription = null, size = 36.dp)
        Column(Modifier.weight(1f)) {
            Text(title, style = type.labelLg, color = colors.onSurface)
            Text(detail, style = type.bodySm, color = colors.onSurfaceVariant)
        }
    }
}

/** Boton pildora de superficie (ExtractPillButton de iOS); [filled] = ambar primario compacto. */
@Composable
fun PillButton(
    text: String,
    icon: androidx.compose.ui.graphics.vector.ImageVector?,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    enabled: Boolean = true,
    isDone: Boolean = false,
    filled: Boolean = false,
) {
    val colors = SolarTheme.colors
    val interaction = remember { MutableInteractionSource() }
    val content = if (filled && enabled) colors.onSecondary
    else if (enabled) colors.primary else colors.onSurfaceVariant
    Row(
        modifier
            .heightIn(min = 48.dp)
            .solarPress(interaction)
            .clip(RoundedCornerShape(50))
            .background(if (filled) colors.secondary else colors.card)
            .border(
                1.dp,
                if (filled) colors.secondary else colors.outlineVariant,
                RoundedCornerShape(50),
            )
            .clickable(
                interactionSource = interaction, indication = null,
                role = androidx.compose.ui.semantics.Role.Button, enabled = enabled,
                onClick = onClick,
            )
            .padding(horizontal = SolarSpacing.lg, vertical = SolarSpacing.md),
        horizontalArrangement = Arrangement.Center,
        verticalAlignment = Alignment.CenterVertically,
    ) {
        if (icon != null) {
            Icon(
                icon, contentDescription = null,
                tint = content,
                modifier = Modifier.size(18.dp).padding(end = 0.dp),
            )
            Box(Modifier.size(SolarSpacing.sm))
        }
        Text(
            text, style = SolarTheme.type.labelLg,
            color = content,
        )
        if (isDone) {
            Box(Modifier.size(SolarSpacing.sm))
            Icon(
                SolarIconCheck, contentDescription = null,
                tint = content, modifier = Modifier.size(16.dp),
            )
        }
    }
}

/** Boton fantasma con contorno de laton (GhostButton de iOS). */
@Composable
fun GhostPillButton(
    text: String,
    icon: androidx.compose.ui.graphics.vector.ImageVector?,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    enabled: Boolean = true,
) {
    val colors = SolarTheme.colors
    val interaction = remember { MutableInteractionSource() }
    Row(
        modifier
            .heightIn(min = 48.dp)
            .solarPress(interaction)
            .clip(RoundedCornerShape(50))
            .border(1.dp, colors.brassHairline, RoundedCornerShape(50))
            .clickable(
                interactionSource = interaction, indication = null,
                role = androidx.compose.ui.semantics.Role.Button, enabled = enabled,
                onClick = onClick,
            )
            .padding(horizontal = SolarSpacing.lg, vertical = SolarSpacing.md),
        horizontalArrangement = Arrangement.Center,
        verticalAlignment = Alignment.CenterVertically,
    ) {
        if (icon != null) {
            Icon(
                icon, contentDescription = null,
                tint = if (enabled) colors.primary else colors.onSurfaceVariant,
                modifier = Modifier.size(18.dp),
            )
            Box(Modifier.size(SolarSpacing.sm))
        }
        Text(
            text, style = SolarTheme.type.labelLg,
            color = if (enabled) colors.primary else colors.onSurfaceVariant,
        )
    }
}
