// Inspector de capas (Views/Capas de iOS): cada capa que exponen el motor
// (analyzeWithLayers/analyzeGarmentsWithLayers) y la cadena de sujeto,
// compartible una a una o todas en un zip. Es la herramienta con la que
// el dueño diagnostica problemas de color: sin análisis previo muestra
// las capas de una imagen de ejemplo generada en el teléfono.
package com.andreseloy.colorsapp.feature.layers

import android.graphics.Bitmap
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.Text
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import com.andreseloy.colorsapp.R
import com.andreseloy.colorsapp.app.AppContainer
import com.andreseloy.colorsapp.design.*
import com.andreseloy.colorsapp.engine.ColorEngine
import com.andreseloy.colorsapp.engine.GarmentDebugLayers
import com.andreseloy.colorsapp.feature.grid.bitmapToPng
import com.andreseloy.colorsapp.feature.grid.shareBitmap
import com.andreseloy.colorsapp.feature.grid.shareFile
import com.andreseloy.colorsapp.feature.grid.writeShareFile
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.io.ByteArrayOutputStream
import java.util.Locale
import java.util.zip.ZipEntry
import java.util.zip.ZipOutputStream

private data class LayerEntry(val id: String, val title: String, val desc: String?, val bitmap: Bitmap?, val fileName: String)

private fun bitmapOf(argb: IntArray, w: Int, h: Int): Bitmap {
    val bmp = Bitmap.createBitmap(w, h, Bitmap.Config.ARGB_8888)
    bmp.setPixels(argb, 0, w, 0, 0, w, h)
    return bmp
}

@Composable
fun LayersScreen(container: AppContainer, onBack: () -> Unit, modifier: Modifier = Modifier) {
    val type = SolarTheme.type; val colors = SolarTheme.colors; val context = LocalContext.current
    var result by remember { mutableStateOf<GarmentDebugLayers?>(null) }
    var errorText by remember { mutableStateOf<String?>(null) }
    var isolate by remember { mutableStateOf<Int?>(null) }
    var expanded by remember { mutableStateOf("reduced") }
    val isDemo = LayerInputHolder.image == null
    val titles = LayerTitles(
        original = stringResource(R.string.w4_layer_original), raster = stringResource(R.string.w4_layer_raster),
        people = stringResource(R.string.w4_layer_people), mask = stringResource(R.string.w4_layer_mask),
        clothing = stringResource(R.string.w4_layer_clothing), skin = stringResource(R.string.w4_layer_skin),
        garments = stringResource(R.string.w4_layer_garments), reduced = stringResource(R.string.w4_layer_reduced),
        weight = stringResource(R.string.w4_layer_weight), assign = stringResource(R.string.w4_layer_assign),
        palette = stringResource(R.string.w4_layer_palette), why = stringResource(R.string.w4_layer_why),
    )
    val descs = mapOf(
        "raster" to stringResource(R.string.w4_layer_raster_desc), "mask" to stringResource(R.string.w4_layer_mask_desc),
        "reduced" to stringResource(R.string.w4_layer_reduced_desc), "weight" to stringResource(R.string.w4_layer_weight_desc),
        "assign" to stringResource(R.string.w4_layer_assign_desc), "palette" to stringResource(R.string.w4_layer_palette_desc),
        "why" to stringResource(R.string.w4_layer_why_desc),
    )
    LaunchedEffect(isolate) { /* el aislamiento solo repinta la capa de asignación */ }
    LaunchedEffect(Unit) {
        withContext(Dispatchers.Default) {
            runCatching {
                val image = LayerInputHolder.image ?: LayerPixels.syntheticDemoImage(160, 200,
                    container.dictionary.colorsOf(1).map { it.rgb } + container.dictionary.colorsOf(2).map { it.rgb })
                ColorEngine().use { it.analyzeGarmentsWithLayers(image) }
            }.onSuccess { result = it }.onFailure { errorText = it.message }
        }
    }
    val layersResult = result
    val entries = remember(layersResult, isolate) {
        if (layersResult == null) emptyList() else buildEntries(container, layersResult, titles, descs, isolate)
    }
    Column(modifier.fillMaxSize().windowInsetsPadding(WindowInsets.statusBars)) {
        Row(Modifier.fillMaxWidth().padding(SolarSpacing.xs), verticalAlignment = Alignment.CenterVertically) {
            IconButton(onClick = onBack) { Icon(SolarIconBack, stringResource(R.string.back), tint = colors.primary) }
            Text(stringResource(R.string.w4_layers_title), style = type.brand, color = colors.primary)
            if (isDemo) Text(" · " + stringResource(R.string.w4_layers_demo), style = type.labelMd, color = colors.secondary)
        }
        if (layersResult == null && errorText == null) {
            Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) { CircularProgressIndicator(color = colors.primary) }
            return@Column
        }
        if (errorText != null) {
            Text(errorText!!, style = type.bodyMd, color = colors.error, modifier = Modifier.padding(SolarSpacing.margin)); return@Column
        }
        val analysis = layersResult!!.layers.analysis
        LazyColumn(
            Modifier.fillMaxSize(), contentPadding = PaddingValues(horizontal = SolarSpacing.margin, vertical = SolarSpacing.md),
            verticalArrangement = Arrangement.spacedBy(SolarSpacing.md),
        ) {
            if (isDemo) item {
                SolarCard(Modifier.fillMaxWidth()) { Text(stringResource(R.string.w4_layers_demo_body), style = type.bodySm, color = colors.onSurfaceVariant) }
            }
            item {
                SolarCard(Modifier.fillMaxWidth()) {
                    Column(verticalArrangement = Arrangement.spacedBy(SolarSpacing.sm)) {
                        analysis.hits.forEachIndexed { i, hit ->
                            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                                Text("${i + 1}. " + (container.dictionary.curatedName(hit.comboId) ?: stringResource(R.string.w4_combo_number, hit.comboId)),
                                    style = type.labelMd, color = colors.onSurface)
                                Text(stringResource(R.string.w4_score, String.format(Locale.ROOT, "%.2f", hit.score)), style = type.hex, color = colors.wellTextSecondary)
                            }
                        }
                        if (analysis.ambiguous) Text(stringResource(R.string.w4_ambiguous), style = type.labelSm, color = colors.error)
                        LayerInputHolder.subject?.let { s ->
                            Text(stringResource(R.string.w4_coverage, String.format(Locale.ROOT, "%.1f %%", s.maskCoverage * 100)), style = type.bodySm, color = colors.onSurfaceVariant)
                            Text(s.steps.joinToString(", ") { it.raw }, style = type.hex, color = colors.wellTextSecondary)
                        }
                        SolarPrimaryButton(stringResource(R.string.w4_share_all_layers), onClick = {
                            val zip = layersZip(entries, container, layersResult)
                            val uri = writeShareFile(context, "chromasol-capas.zip", zip)
                            shareFile(context, uri, "application/zip", titles.palette)
                        })
                    }
                }
            }
            itemsIndexed(entries, key = { _, e -> e.id }) { _, entry ->
                LayerCard(entry, expanded == entry.id, onToggle = { expanded = if (expanded == entry.id) "" else entry.id },
                    onShare = { entry.bitmap?.let { shareBitmap(context, it, entry.fileName, entry.title) } })
            }
            // Paleta final: tocar un color aísla sus píxeles en la asignación.
            item {
                SolarCard(Modifier.fillMaxWidth()) {
                    Column(verticalArrangement = Arrangement.spacedBy(SolarSpacing.sm)) {
                        Text(titles.palette.uppercase(), style = type.overline, color = colors.secondary)
                        Text(descs["palette"] ?: "", style = type.bodySm, color = colors.onSurfaceVariant)
                        analysis.swatches.forEachIndexed { i, sw ->
                            Row(Modifier.fillMaxWidth().clickable { isolate = if (isolate == i) null else i; expanded = "assign" },
                                horizontalArrangement = Arrangement.spacedBy(SolarSpacing.md), verticalAlignment = Alignment.CenterVertically) {
                                Box(Modifier.size(36.dp).clip(SolarRadius.blockShape).background(Color(sw.argb)))
                                Text(sw.hex, style = type.hex, color = colors.wellTextSecondary)
                                Text(String.format(Locale.ROOT, "%.1f %%", sw.weight * 100), style = type.labelMd, color = colors.onSurface)
                                if (isolate == i) Text("●", color = colors.primary)
                            }
                        }
                        val debug = layersResult.layers.debug
                        Text(String.format(Locale.ROOT, "reduced ${debug.reducedWidth}×${debug.reducedHeight} · clusters ${debug.clusters.size} · lloyd ${debug.lloydIterations} · σ %.1f px", debug.centerSigmaPx),
                            style = type.hex, color = colors.wellTextSecondary)
                        debug.clusters.forEachIndexed { i, cl ->
                            Text(String.format(Locale.ROOT, "cluster $i ${cl.fate} final=${cl.finalIndex ?: "-"} head=${cl.groupHead} ${cl.hex} w=%.3f", cl.weight),
                                style = type.hex, color = colors.wellTextSecondary)
                        }
                    }
                }
            }
            // Por qué ganó: explicación del motor por hit.
            item {
                SolarCard(Modifier.fillMaxWidth()) {
                    Column(verticalArrangement = Arrangement.spacedBy(SolarSpacing.sm)) {
                        Text(titles.why.uppercase(), style = type.overline, color = colors.secondary)
                        Text(descs["why"] ?: "", style = type.bodySm, color = colors.onSurfaceVariant)
                        layersResult.layers.explanations.forEachIndexed { i, ex ->
                            Text(String.format(Locale.ROOT, "${i + 1}. Nº ${ex.comboId} score %.2f fit %.2f coverage %.2f EV %.2f", ex.score, ex.fitTerm, ex.coverageTerm, ex.exposureEv),
                                style = type.labelMd, color = colors.onSurface)
                            ex.perSwatch.forEachIndexed { j, s ->
                                val name = container.dictionary.color(s.nearestColorIndex)?.name ?: "#${s.nearestColorIndex}"
                                Text(String.format(Locale.ROOT, "  swatch $j → $name ΔE %.2f", s.deltaE), style = type.hex, color = colors.wellTextSecondary)
                            }
                        }
                    }
                }
            }
            item { Box(Modifier.height(SolarSpacing.xl)) }
        }
    }
}

private data class LayerTitles(val original: String, val raster: String, val people: String, val mask: String, val clothing: String, val skin: String, val garments: String, val reduced: String, val weight: String, val assign: String, val palette: String, val why: String)

private fun buildEntries(container: AppContainer, r: GarmentDebugLayers, t: LayerTitles, descs: Map<String, String>, isolate: Int?): List<LayerEntry> {
    val layers = r.layers; val debug = layers.debug; val w = debug.reducedWidth; val h = debug.reducedHeight
    val swArgb = layers.analysis.swatches.map { it.argb }
    val input = LayerInputHolder.image
    val subject = LayerInputHolder.subject
    val entries = mutableListOf<LayerEntry>()
    if (input != null) {
        entries += LayerEntry("raster", t.raster, descs["raster"], bitmapOf(LayerPixels.fromEngineImage(input), input.width, input.height), "01-raster.png")
        subject?.people?.forEachIndexed { i, person ->
            person.finalMask?.let { m ->
                entries += LayerEntry("person$i", "${t.people} ${i + 1}", null,
                    bitmapOf(LayerPixels.fromWeight(m.bytes, m.width, m.height), m.width, m.height), "02-persona-${i + 1}.png")
            }
            person.garmentRegions?.let { g ->
                entries += LayerEntry("cloth$i", t.clothing, null, bitmapOf(LayerPixels.fromRegions(g.bytes, g.width, g.height), g.width, g.height), "03-ropa-${i + 1}.png")
            }
        }
        subject?.mask?.let { m ->
            entries += LayerEntry("mask", t.mask, descs["mask"], bitmapOf(LayerPixels.fromWeight(m.bytes, m.width, m.height), m.width, m.height), "04-mascara.png")
        }
        subject?.garmentRegions?.let { g ->
            entries += LayerEntry("garments-subject", t.garments, null, bitmapOf(LayerPixels.fromRegions(g.bytes, g.width, g.height), g.width, g.height), "05-prendas.png")
        }
    }
    entries += LayerEntry("reduced", t.reduced, descs["reduced"], bitmapOf(LayerPixels.fromRgb8(layers.reducedRgb, w, h), w, h), "06-reducida.png")
    entries += LayerEntry("weight", t.weight, descs["weight"], bitmapOf(LayerPixels.fromWeight(layers.weightMap, w, h), w, h), "07-peso.png")
    entries += LayerEntry("assign", t.assign, descs["assign"], bitmapOf(LayerPixels.fromLabels(layers.labelMap, w, h, swArgb, isolate), w, h), "08-asignacion.png")
    entries += LayerEntry("cluster", "Clusters", null, bitmapOf(LayerPixels.fromLabels(layers.clusterMap, w, h, swArgb), w, h), "09-clusters.png")
    if (r.garmentMap.isNotEmpty()) entries += LayerEntry("garmentmap", t.garments, null, bitmapOf(LayerPixels.fromLabels(r.garmentMap, w, h, swArgb), w, h), "10-prendas-motor.png")
    if (r.regionMap.isNotEmpty()) entries += LayerEntry("regionmap", t.clothing, null, bitmapOf(LayerPixels.fromRegions(r.regionMap, w, h), w, h), "11-regiones.png")
    return entries
}

private fun layersZip(entries: List<LayerEntry>, container: AppContainer, r: GarmentDebugLayers): ByteArray {
    val out = ByteArrayOutputStream()
    ZipOutputStream(out).use { zip ->
        val analysis = r.layers.analysis
        val summary = buildString {
            appendLine("ChromaSol capas")
            appendLine("engine=${container.engineVersion} dict=${container.engineDictVersion}")
            analysis.hits.forEachIndexed { i, hit -> appendLine("hit${i + 1}=${hit.comboId} score=${hit.score}") }
            appendLine("ambiguous=${analysis.ambiguous}")
            analysis.swatches.forEachIndexed { i, s -> appendLine("swatch$i=${s.hex} weight=${s.weight}") }
        }
        zip.putNextEntry(ZipEntry("resumen.txt")); zip.write(summary.toByteArray()); zip.closeEntry()
        for (e in entries) e.bitmap?.let { zip.putNextEntry(ZipEntry(e.fileName)); zip.write(bitmapToPng(it)); zip.closeEntry() }
    }
    return out.toByteArray()
}

@Composable
private fun LayerCard(entry: LayerEntry, expanded: Boolean, onToggle: () -> Unit, onShare: () -> Unit) {
    val type = SolarTheme.type; val colors = SolarTheme.colors
    SolarCard(Modifier.fillMaxWidth().semantics { contentDescription = "layers.${entry.id}" }) {
        Column(verticalArrangement = Arrangement.spacedBy(SolarSpacing.sm)) {
            Row(Modifier.fillMaxWidth().clickable { onToggle() }, horizontalArrangement = Arrangement.SpaceBetween) {
                Text(entry.title, style = type.cardTitle, color = colors.onSurface)
                Text(if (expanded) "−" else "+", style = type.headlineSm, color = colors.primary)
            }
            if (expanded) {
                entry.desc?.let { Text(it, style = type.bodySm, color = colors.onSurfaceVariant) }
                entry.bitmap?.let { bmp ->
                    WellContainer(Modifier.fillMaxWidth()) {
                        Image(bmp.asImageBitmap(), contentDescription = entry.title, contentScale = ContentScale.FillWidth,
                            modifier = Modifier.fillMaxWidth().heightIn(max = 320.dp))
                    }
                    SolarSecondaryButton(stringResource(R.string.w4_share_layer), onClick = onShare)
                }
            }
        }
    }
}
