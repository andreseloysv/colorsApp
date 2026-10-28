// Tests instrumentados del carril W3 en el emulador: Feed (tarjeta del dia
// con la regla exacta, filtros, publicacion con voto), captura de Extraer,
// Resultado real sobre una foto sintetica (motor C en el dispositivo),
// Wrapped y el dibujo de la tarjeta 1080x1350 / 1080x1920. De paso guardan
// capturas PNG en getExternalFilesDir("w3shots") para inspeccion visual
// (se bajan a harness/out/android/w3 con adb pull).
package com.andreseloy.colorsapp

import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.ui.graphics.asAndroidBitmap
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.captureToImage
import androidx.activity.ComponentActivity
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.hasScrollAction
import androidx.compose.ui.test.hasTestTag
import androidx.compose.ui.test.onAllNodesWithTag
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.performScrollToNode
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.onRoot
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performScrollTo
import androidx.compose.ui.test.performTouchInput
import androidx.compose.ui.test.swipeUp
import androidx.test.platform.app.InstrumentationRegistry
import com.andreseloy.colorsapp.app.AppContainer
import com.andreseloy.colorsapp.data.EngineWadaDictionary
import com.andreseloy.colorsapp.data.EmptyPhotoLibrarySource
import com.andreseloy.colorsapp.data.InMemoryFeedbackRepository
import com.andreseloy.colorsapp.data.InMemoryScanRepository
import com.andreseloy.colorsapp.data.InMemorySettingsRepository
import com.andreseloy.colorsapp.data.InMemoryUnlockRepository
import com.andreseloy.colorsapp.data.ScanRecord
import com.andreseloy.colorsapp.data.ScanSource
import com.andreseloy.colorsapp.design.ChromaSolTheme
import com.andreseloy.colorsapp.engine.Lab
import com.andreseloy.colorsapp.engine.Swatch
import com.andreseloy.colorsapp.feature.extract.ExtractScreen
import com.andreseloy.colorsapp.feature.extract.ResultContent
import com.andreseloy.colorsapp.feature.extract.ResultModel
import com.andreseloy.colorsapp.feature.extract.ScanAnalyzer
import com.andreseloy.colorsapp.feature.extract.ScanJson
import com.andreseloy.colorsapp.feature.extract.ScanPhotoStore
import com.andreseloy.colorsapp.feature.feed.FeedScreen
import com.andreseloy.colorsapp.feature.feed.GardenSavedStore
import com.andreseloy.colorsapp.feature.share.ShareCardFactory
import com.andreseloy.colorsapp.feature.share.ShareFormat
import com.andreseloy.colorsapp.feature.share.renderShareCard
import com.andreseloy.colorsapp.feature.wrapped.WrappedSummary
import com.andreseloy.colorsapp.scan.ColorCount
import com.andreseloy.colorsapp.scan.ComboCount
import com.andreseloy.colorsapp.scan.NoopScanRunner
import com.andreseloy.colorsapp.scan.ScanSummary
import com.andreseloy.colorsapp.subject.WholePhotoSubjectSegmenter
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Rule
import org.junit.Test
import java.io.File

class W3ScreensTest {

    @get:Rule
    val composeRule = createAndroidComposeRule<ComponentActivity>()

    private val context get() = InstrumentationRegistry.getInstrumentation().targetContext

    @Before
    fun fijarEspanol() {
        InstrumentationRegistry.getInstrumentation().uiAutomation.executeShellCommand(
            "cmd locale set-app-locales com.andreseloy.colorsapp --locales es-ES",
        ).close()
        composeRule.waitForIdle()
    }

    private fun capture(name: String) {
        val bitmap = composeRule.onRoot().captureToImage().asAndroidBitmap()
        saveCapture(name, bitmap)
    }

    /** A MediaStore (Pictures/w3shots): sobrevive a la desinstalacion tras los tests. */
    private fun saveCapture(name: String, bitmap: Bitmap) {
        val values = android.content.ContentValues().apply {
            put(android.provider.MediaStore.Images.Media.DISPLAY_NAME, name)
            put(android.provider.MediaStore.Images.Media.MIME_TYPE, "image/png")
            put(android.provider.MediaStore.Images.Media.RELATIVE_PATH, "Pictures/w3shots")
            put(android.provider.MediaStore.Images.Media.IS_PENDING, 1)
        }
        val uri = context.contentResolver.insert(
            android.provider.MediaStore.Images.Media.EXTERNAL_CONTENT_URI, values,
        ) ?: return
        context.contentResolver.openOutputStream(uri)?.use {
            bitmap.compress(Bitmap.CompressFormat.PNG, 100, it)
        }
        values.clear()
        values.put(android.provider.MediaStore.Images.Media.IS_PENDING, 0)
        context.contentResolver.update(uri, values, null, null)
    }

    /** Foto sintetica de bloques (arriba negro, abajo azul, fondo gris). */
    private fun blocksBitmap(): Bitmap {
        val bitmap = Bitmap.createBitmap(800, 1000, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(bitmap)
        val paint = Paint()
        paint.color = Color.rgb(160, 160, 160)
        canvas.drawRect(0f, 0f, 800f, 1000f, paint)
        paint.color = Color.rgb(20, 20, 25)
        canvas.drawRect(200f, 150f, 600f, 550f, paint)
        paint.color = Color.rgb(35, 60, 150)
        canvas.drawRect(200f, 550f, 600f, 950f, paint)
        return bitmap
    }

    private fun container(scans: InMemoryScanRepository): AppContainer = AppContainer(
        dictionary = EngineWadaDictionary(),
        scans = scans,
        unlocks = InMemoryUnlockRepository(),
        feedback = InMemoryFeedbackRepository(),
        settings = InMemorySettingsRepository(),
        photoLibrary = EmptyPhotoLibrarySource(),
        subjectSegmenter = WholePhotoSubjectSegmenter(),
        scanRunner = NoopScanRunner(),
        launches = 1,
    )

    private fun scanRecord(id: String, top1: Int, scannedAt: Long): ScanRecord {
        val palette = ScanJson.encodePalette(
            listOf(
                ScanJson.paletteEntry(Swatch(Lab(8.0, 0.0, -2.0), 20, 20, 25, 0.6)),
                ScanJson.paletteEntry(Swatch(Lab(30.0, 5.0, -40.0), 35, 60, 150, 0.4)),
            ),
        )
        return ScanRecord(
            id = id, assetId = null, source = ScanSource.PICKER,
            top1 = top1, top2 = null, top3 = null,
            scoresJson = "[3.5]", paletteJson = palette, ambiguous = false,
            engineVersion = "test", dictVersion = "test",
            scannedAtMs = scannedAt, updatedAtMs = scannedAt,
            subjectMode = "off", regionMode = "clothing", peopleCount = 0,
            personIndex = null, maskStepsJson = "[\"none\"]", maskCoverage = 0.0,
            enginePolicyVersion = 1,
        )
    }

    /** Regresion: la foto del picker (Uri de MediaStore) debe decodificarse. */
    @Test
    fun cargaFotoDesdeUriDeMediaStore() {
        val values = android.content.ContentValues().apply {
            put(android.provider.MediaStore.Images.Media.DISPLAY_NAME, "w3-regression.png")
            put(android.provider.MediaStore.Images.Media.MIME_TYPE, "image/png")
            put(android.provider.MediaStore.Images.Media.RELATIVE_PATH, "Pictures/w3shots")
            put(android.provider.MediaStore.Images.Media.IS_PENDING, 1)
        }
        val uri = context.contentResolver.insert(
            android.provider.MediaStore.Images.Media.EXTERNAL_CONTENT_URI, values,
        )!!
        context.contentResolver.openOutputStream(uri)?.use {
            blocksBitmap().compress(Bitmap.CompressFormat.PNG, 100, it)
        }
        values.clear()
        values.put(android.provider.MediaStore.Images.Media.IS_PENDING, 0)
        context.contentResolver.update(uri, values, null, null)
        val loaded = com.andreseloy.colorsapp.feature.extract.PhotoLoading
            .loadUpright(context, uri)
        org.junit.Assert.assertNotNull("la foto elegida debe decodificarse", loaded)
        assertEquals(800, loaded!!.width)
        assertEquals(1000, loaded.height)
    }

    @Test
    fun feedConPublicacionesYFiltros() {
        val dictionary = EngineWadaDictionary()
        val size2 = dictionary.combinations.first { it.size == 2 }.id
        val size4 = dictionary.combinations.first { it.size == 4 }.id
        val scans = InMemoryScanRepository()
        val now = System.currentTimeMillis()
        val first = scanRecord("w3-post-2", size2, now - 1000)
        val second = scanRecord("w3-post-4", size4, now - 2000)
        runBlocking {
            scans.insert(first)
            scans.insert(second)
        }
        ScanPhotoStore.save(context, blocksBitmap(), first.id)
        ScanPhotoStore.save(context, blocksBitmap(), second.id)
        val testContainer = container(scans)
        // Versiones del scan de prueba alineadas con el contenedor para no
        // marcarlo «Análisis antiguo» en la captura.
        runBlocking {
            scans.update(
                first.copy(
                    engineVersion = testContainer.engineVersion,
                    dictVersion = testContainer.engineDictVersion,
                ),
            )
            scans.update(
                second.copy(
                    engineVersion = testContainer.engineVersion,
                    dictVersion = testContainer.engineDictVersion,
                ),
            )
        }
        composeRule.setContent {
            ChromaSolTheme {
                FeedScreen(
                    container = testContainer,
                    onAnalyzePhoto = {}, onOpenGarden = {}, onShowGridFromScan = {},
                )
            }
        }
        composeRule.onNodeWithText("COMBINACIÓN DEL DÍA").assertIsDisplayed()
        composeRule.onNodeWithText("Otra combinación").assertIsDisplayed()
        composeRule.onNodeWithTag("feed.post.w3-post-2").assertExists()
        capture("feed-light.png")
        composeRule.onNodeWithTag("feed.root")
            .performScrollToNode(hasTestTag("feed.post.w3-post-4"))
        composeRule.onNodeWithTag("feed.post.w3-post-4").assertExists()
        capture("feed-post-light.png")
        composeRule.onNodeWithTag("feed.root")
            .performScrollToNode(hasTestTag("feed.filter.four"))

        // Barajar cambia el número de la combinación.
        composeRule.onNodeWithTag("feed.day.shuffle").performClick()
        composeRule.onNodeWithText("COMBINACIÓN AL AZAR").assertIsDisplayed()

        // Filtro de 4 colores: la de 2 desaparece.
        composeRule.onNodeWithTag("feed.filter.four").performClick()
        composeRule.onNodeWithTag("feed.root")
            .performScrollToNode(hasTestTag("feed.post.w3-post-4"))
        composeRule.onNodeWithTag("feed.post.w3-post-4").assertExists()
        composeRule.onNodeWithTag("feed.post.w3-post-2").assertDoesNotExist()
        capture("feed-filtro4-light.png")

        // Votar «Sí» en la publicación visible deja el veredicto puesto.
        composeRule.onNodeWithTag("feed.root")
            .performScrollToNode(hasTestTag("feed.yes"))
        composeRule.onNodeWithTag("feed.yes").performClick()
        composeRule.onNodeWithText("Es eso").assertExists()
    }

    @Test
    fun feedOscuro() {
        val scans = InMemoryScanRepository()
        composeRule.setContent {
            ChromaSolTheme(darkTheme = true) {
                FeedScreen(
                    container = container(scans),
                    onAnalyzePhoto = {}, onOpenGarden = {}, onShowGridFromScan = {},
                )
            }
        }
        composeRule.onNodeWithText("COMBINACIÓN DEL DÍA").assertIsDisplayed()
        composeRule.onNodeWithTag("feed.empty").assertExists()
        capture("feed-dark.png")
    }

    @Test
    fun capturaDeExtraer() {
        val scans = InMemoryScanRepository()
        val dark = androidx.compose.runtime.mutableStateOf(false)
        composeRule.setContent {
            ChromaSolTheme(darkTheme = dark.value) {
                ExtractScreen(
                    container = container(scans),
                    onOpenGarden = {}, onShowGridFromScan = {},
                )
            }
        }
        composeRule.onNodeWithText("Analiza la ropa de una foto").assertIsDisplayed()
        composeRule.onNodeWithText("Elegir foto").assertIsDisplayed()
        composeRule.onNodeWithText("Cámara").assertIsDisplayed()
        composeRule.onNodeWithText("Escanear carrete (200 fotos)").assertIsDisplayed()
        capture("extraer-light.png")
        composeRule.onRoot().performTouchInput { swipeUp() }
        composeRule.onNodeWithText("QUÉ HACE EL ANÁLISIS").assertExists()
        composeRule.onNodeWithText("Recorta a la persona").assertExists()

        composeRule.runOnUiThread { dark.value = true }
        composeRule.waitForIdle()
        composeRule.onNodeWithText("Analiza la ropa de una foto").assertIsDisplayed()
        capture("extraer-dark.png")
    }

    @Test
    fun resultadoRealConFotoSintetica() {
        val scans = InMemoryScanRepository()
        val testContainer = container(scans)
        val outcome = runBlocking {
            ScanAnalyzer.run(
                context, testContainer, blocksBitmap(), ScanSource.PICKER, assetId = null,
                subject = com.andreseloy.colorsapp.subject.SubjectOptions(
                    mode = com.andreseloy.colorsapp.subject.SubjectMode.OFF,
                ),
            )
        }
        assertTrue(outcome.result.swatches.isNotEmpty())
        assertTrue(outcome.result.hits.isNotEmpty())
        val garden = GardenSavedStore.getInstance(context)
        val model = ResultModel(
            outcome, testContainer, garden, context,
            CoroutineScope(Dispatchers.Main),
        )
        model.load()
        val dark = androidx.compose.runtime.mutableStateOf(false)
        composeRule.setContent {
            ChromaSolTheme(darkTheme = dark.value) {
                Column(androidx.compose.ui.Modifier.verticalScroll(rememberScrollState())) {
                    ResultContent(
                        model = model, dictionary = testContainer.dictionary,
                        onOpenLayers = null, onToast = {},
                    )
                }
            }
        }
        composeRule.onNodeWithTag("result.photo").assertExists()
        composeRule.onNodeWithText("Recorte desactivado: foto completa").assertExists()
        composeRule.onNodeWithTag("result.garment.0").assertExists()
        capture("resultado-light.png")
        composeRule.onNodeWithTag("result.top1", useUnmergedTree = true).assertExists()
        composeRule.onNodeWithTag("result.topCard").performScrollTo()
        composeRule.waitForIdle()
        capture("resultado-match-light.png")
        // Votar y desbloquear desde la tarjeta ganadora.
        composeRule.onNodeWithTag("result.yes").performScrollTo().performClick()
        composeRule.waitForIdle()
        composeRule.onNodeWithTag("result.thanks").assertExists()
        composeRule.onNodeWithTag("result.unlock").performScrollTo().performClick()
        composeRule.waitForIdle()
        composeRule.onNodeWithTag("result.unlocked").assertExists()

        composeRule.runOnUiThread { dark.value = true }
        composeRule.waitForIdle()
        composeRule.onNodeWithTag("result.photo").assertExists()
        capture("resultado-dark.png")
    }

    @Test
    fun wrappedYDibujoDeTarjeta() {
        val dictionary = EngineWadaDictionary()
        val combo = dictionary.combinations.first { it.size == 3 }
        val summary = ScanSummary(
            scanned = 42, skipped = 3, failed = 1,
            newUnlocks = listOf(combo.id), totalUnlocked = 41,
            topCombos = listOf(ComboCount(combo.id, 5)),
            startedAtMs = 1000, finishedAtMs = 4200,
            topColors = listOf(ColorCount(combo.colors[0], 9), ColorCount(combo.colors[1], 4)),
            signatureColorIndex = combo.colors[0],
        )
        val dark = androidx.compose.runtime.mutableStateOf(false)
        composeRule.setContent {
            ChromaSolTheme(darkTheme = dark.value) {
                WrappedSummary(summary, dictionary, totalCombos = 348, onShowGrid = {})
            }
        }
        composeRule.onNodeWithText("Tu carrete en color").assertIsDisplayed()
        composeRule.onNodeWithText("41/348").assertExists()
        capture("wrapped-light.png")
        composeRule.runOnUiThread { dark.value = true }
        composeRule.waitForIdle()
        capture("wrapped-dark.png")

        // La tarjeta se dibuja a 1080x1350 y 1080x1920 exactos.
        val scan = scanRecord("w3-card", combo.id, System.currentTimeMillis())
        val data = ShareCardFactory.dataFor(scan, blocksBitmap(), dictionary, context.resources)
        val post = runBlocking {
            renderShareCard(composeRule.activity, data, ShareFormat.POST)
        }
        assertEquals(1080, post.width)
        assertEquals(1350, post.height)
        val story = runBlocking {
            renderShareCard(composeRule.activity, data, ShareFormat.STORY)
        }
        assertEquals(1080, story.width)
        assertEquals(1920, story.height)
        saveCapture("tarjeta-4x5.png", post)
        saveCapture("tarjeta-9x16.png", story)
    }
}
