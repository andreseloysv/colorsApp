// Tests de host del carril W4: buscador de la Rejilla, colecciones del
// Jardín, zip de diagnósticos y conversión de capas (lógica pura).
package com.andreseloy.colorsapp

import com.andreseloy.colorsapp.data.Diagnostics
import com.andreseloy.colorsapp.data.DiagnosticsSnapshot
import com.andreseloy.colorsapp.data.FeedbackRecord
import com.andreseloy.colorsapp.data.FeedbackVerdict
import com.andreseloy.colorsapp.data.ScanRecord
import com.andreseloy.colorsapp.data.ScanSource
import com.andreseloy.colorsapp.data.UnlockRecord
import com.andreseloy.colorsapp.data.WadaColor
import com.andreseloy.colorsapp.data.WadaCombo
import com.andreseloy.colorsapp.data.WadaDictionary
import com.andreseloy.colorsapp.feature.garden.GardenLogic
import com.andreseloy.colorsapp.feature.grid.GridFilters
import com.andreseloy.colorsapp.feature.grid.GridQuery
import com.andreseloy.colorsapp.feature.grid.GridSearch
import com.andreseloy.colorsapp.feature.grid.StatusFilter
import com.andreseloy.colorsapp.feature.layers.LayerPixels
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import java.util.zip.ZipInputStream
import kotlin.random.Random

private class FakeDict : WadaDictionary {
    override val dictVersion = "test"
    override val colors = listOf(
        WadaColor(0, "Snow White", intArrayOf(255, 255, 255)),
        WadaColor(1, "Ébano Pink", intArrayOf(200, 100, 110)),
        WadaColor(2, "Pale Blue", intArrayOf(120, 160, 200)),
    )
    override val combinations = listOf(
        WadaCombo(1, intArrayOf(0, 1)), WadaCombo(2, intArrayOf(0, 2, 1)), WadaCombo(3, intArrayOf(2, 1, 0, 0)),
    )
    override fun curatedName(id: Int): String? = if (id == 1) "Amanecer" else null
}

class W4LogicTest {
    @Test fun buscadorInterpretaComoIos() {
        assertEquals(GridQuery.Empty, GridSearch.interpret("  ", 348))
        assertEquals(GridQuery.Number(12), GridSearch.interpret("Nº 12", 348))
        assertEquals(GridQuery.Number(12), GridSearch.interpret(" 012 ", 348))
        assertEquals(GridQuery.NumberOutOfRange(999), GridSearch.interpret("999", 348))
        assertEquals(GridQuery.Hex("#C5A56E"), GridSearch.interpret("c5a56e", 348))
        assertEquals(GridQuery.Hex("#123456"), GridSearch.interpret("123456", 348))
        assertEquals(GridQuery.Text("ebano"), GridSearch.interpret("Ébano", 348))
        assertEquals(intArrayOf(197, 165, 110).toList(), GridSearch.parseHexRgb("#C5A56E")!!.toList())
    }

    @Test fun filtrosYTamano() {
        val dict = FakeDict()
        val unlocked = setOf(1)
        assertEquals(listOf(1), GridFilters.apply(dict.combinations, 2, null, unlocked).map { it.id })
        assertEquals(listOf(2, 3), GridFilters.apply(dict.combinations, null, StatusFilter.LOCKED, unlocked).map { it.id })
        val hay = dict.combinations.associate { it.id to GridSearch.haystack(it, dict.curatedName(it.id) ?: "", dict.colorsOf(it.id).map { c -> c.name }) }
        assertEquals(listOf(1), GridSearch.filter(dict.combinations, GridQuery.Text("amanecer"), null, hay).map { it.id })
        assertEquals(listOf(1, 2, 3), GridSearch.filter(dict.combinations, GridQuery.Hex("#FFFFFF"), 1, hay).map { it.id })
        // La aleatoria nunca repite la actual (salvo total 1).
        repeat(50) { assertTrue(GridFilters.nextRandom(2, 3, Random(it)) != 2) }
        assertEquals(1, GridFilters.nextRandom(1, 1))
    }

    @Test fun jardinColeccionesYExport() {
        val dict = FakeDict()
        val unlocks = listOf(UnlockRecord(1, 100L, ScanSource.MANUAL, updatedAtMs = 100L))
        val cols = GardenLogic.sizeCollections(dict, unlocks)
        assertEquals(1, cols[0].unlocked); assertEquals(1, cols[0].total)
        assertEquals("50 %", GardenLogic.accuracyText(1, 2))
        assertTrue(GardenLogic.collectionJson(dict, unlocks).contains("\"id\":1"))
        val scan = ScanRecord("s1", null, ScanSource.PICKER, 1, 2, null, engineVersion = "e", dictVersion = "d", scannedAtMs = 5L, updatedAtMs = 5L)
        assertTrue(GardenLogic.harvestsCsv(listOf(scan)).contains("s1,5,picker,1,2,,false"))
        assertEquals(0 to 2, GardenLogic.topColors(dict, setOf(1, 2)).first())
    }

    @Test fun diagnosticosZip() {
        val scan = ScanRecord("s,1", null, ScanSource.LIBRARY, 7, null, null, engineVersion = "e", dictVersion = "d", scannedAtMs = 9L, updatedAtMs = 9L)
        val snap = DiagnosticsSnapshot("1.0", "1", "ce", "dict", 3, 348, 159, 2, 1, 1, 0,
            listOf(scan), listOf(FeedbackRecord("f1", "s,1", FeedbackVerdict.YES, 1L, 1L)), "largestPerson", "clothing", true, 12.0)
        val names = mutableListOf<String>()
        ZipInputStream(Diagnostics.buildZip(snap).inputStream()).use { zip ->
            var e = zip.nextEntry
            while (e != null) { names += e.name; e = zip.nextEntry }
        }
        assertEquals(listOf("resumen.txt", "scans.csv", "feedback.csv"), names)
        assertTrue(Diagnostics.scansCsv(listOf(scan)).contains("\"s,1\""))
        assertTrue(Diagnostics.summaryText(snap).contains("unlocked=2/348"))
    }

    @Test fun capasConversion() {
        assertEquals(listOf(LayerPixels.argb(1, 2, 3)), LayerPixels.fromRgb8(byteArrayOf(1, 2, 3), 1, 1).toList())
        assertEquals(LayerPixels.argb(255, 191, 31), LayerPixels.fromWeight(byteArrayOf(255.toByte()), 1, 1)[0])
        val red = LayerPixels.argb(255, 0, 0)
        assertEquals(red, LayerPixels.fromLabels(byteArrayOf(0), 1, 1, listOf(red))[0])
        assertEquals(LayerPixels.argb(24, 24, 24), LayerPixels.fromLabels(byteArrayOf(255.toByte()), 1, 1, listOf(red))[0])
        assertEquals(LayerPixels.argb(217, 164, 65), LayerPixels.fromRegions(byteArrayOf(1), 1, 1)[0])
        val img = LayerPixels.syntheticDemoImage(8, 6, listOf(intArrayOf(10, 20, 30)))
        assertEquals(8 * 6 * 4, img.pixels.size)
        assertEquals(48, LayerPixels.fromEngineImage(img).size)
    }
}
