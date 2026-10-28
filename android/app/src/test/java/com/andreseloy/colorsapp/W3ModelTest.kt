// Tests JVM del carril W3: regla exacta de la combinacion del dia, filtros,
// JSON de scans (claves ordenadas como JSONCoding de iOS), politica de
// re-analisis, geometria del libro y del visor, descriptores de texto del
// Feed y de la cadena, alfileres y conteos del Wrapped. Sin motor nativo:
// lo que llama a JNI se cubre en los instrumentados (W3ScreensTest).
package com.andreseloy.colorsapp

import com.andreseloy.colorsapp.data.FeedbackVerdict
import com.andreseloy.colorsapp.data.ScanRecord
import com.andreseloy.colorsapp.data.ScanSource
import com.andreseloy.colorsapp.data.WadaColor
import com.andreseloy.colorsapp.data.WadaCombo
import com.andreseloy.colorsapp.data.WadaDictionary
import com.andreseloy.colorsapp.engine.AnalysisResult
import com.andreseloy.colorsapp.engine.Hit
import com.andreseloy.colorsapp.engine.Lab
import com.andreseloy.colorsapp.engine.Swatch
import com.andreseloy.colorsapp.feature.extract.AnalysisPolicy
import com.andreseloy.colorsapp.feature.extract.MaskNotice
import com.andreseloy.colorsapp.feature.extract.NoticePart
import com.andreseloy.colorsapp.feature.extract.PaletteColor
import com.andreseloy.colorsapp.feature.extract.PinPositions
import com.andreseloy.colorsapp.feature.extract.ResultNotice
import com.andreseloy.colorsapp.feature.extract.ScanJson
import com.andreseloy.colorsapp.feature.extract.ScanSubjectInfo
import com.andreseloy.colorsapp.feature.extract.W3Format
import com.andreseloy.colorsapp.feature.feed.BookCompositionGeometry
import com.andreseloy.colorsapp.feature.feed.CropNotice
import com.andreseloy.colorsapp.feature.feed.DayPick
import com.andreseloy.colorsapp.feature.feed.FeedFilter
import com.andreseloy.colorsapp.feature.feed.FeedItemBuilder
import com.andreseloy.colorsapp.feature.feed.FeedPostText
import com.andreseloy.colorsapp.feature.feed.GardenSavedStore
import com.andreseloy.colorsapp.feature.feed.PaletteTitleKind
import com.andreseloy.colorsapp.feature.feed.PersonLabel
import com.andreseloy.colorsapp.feature.feed.RegionTextKind
import com.andreseloy.colorsapp.feature.extract.ViewfinderGeometry
import com.andreseloy.colorsapp.feature.wrapped.colorCounts
import com.andreseloy.colorsapp.feature.wrapped.sortedCounts
import com.andreseloy.colorsapp.feature.wrapped.unlockCandidate
import com.andreseloy.colorsapp.feature.wrapped.wrappedCounterText
import com.andreseloy.colorsapp.subject.MaskStep
import com.andreseloy.colorsapp.subject.PersonInstanceResult
import com.andreseloy.colorsapp.subject.RegionMode
import com.andreseloy.colorsapp.subject.SubjectMaskResult
import com.andreseloy.colorsapp.subject.SubjectMode
import com.andreseloy.colorsapp.subject.SubjectOptions
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.time.LocalDate
import java.time.ZoneId
import java.util.Locale
import kotlin.random.Random

private class FakeDictionary(
    private val curated: Map<Int, String> = emptyMap(),
) : WadaDictionary {
    override val dictVersion: String = "test"
    override val colors: List<WadaColor> = listOf(
        WadaColor(0, "Black", intArrayOf(10, 10, 10)),
        WadaColor(1, "Warm Gray", intArrayOf(120, 110, 100)),
        WadaColor(2, "Red", intArrayOf(200, 30, 30)),
        WadaColor(3, "Blue", intArrayOf(30, 30, 200)),
    )
    override val combinations: List<WadaCombo> = listOf(
        WadaCombo(1, intArrayOf(0, 1)),
        WadaCombo(2, intArrayOf(0, 2, 3)),
        WadaCombo(3, intArrayOf(0, 1, 2, 3)),
    )

    override fun curatedName(id: Int): String? = curated[id]
}

private fun scan(
    subjectMode: String? = null,
    regionMode: String? = null,
    peopleCount: Int? = null,
    personIndex: Int? = null,
    maskStepsJson: String? = null,
    maskCoverage: Double? = null,
    garmentsJson: String? = null,
    paletteJson: String = "[]",
    top1: Int? = 1,
    top2: Int? = 2,
    ambiguous: Boolean = false,
    source: ScanSource = ScanSource.PICKER,
    engineVersion: String = "e1",
    dictVersion: String = "d1",
    enginePolicyVersion: Int? = 1,
) = ScanRecord(
    id = "scan-1", assetId = null, source = source,
    top1 = top1, top2 = top2, top3 = null,
    scoresJson = "[1.5,2.5]", paletteJson = paletteJson, ambiguous = ambiguous,
    engineVersion = engineVersion, dictVersion = dictVersion,
    scannedAtMs = 1000, updatedAtMs = 1000,
    subjectMode = subjectMode, regionMode = regionMode, peopleCount = peopleCount,
    personIndex = personIndex, maskStepsJson = maskStepsJson, maskCoverage = maskCoverage,
    garmentsJson = garmentsJson, enginePolicyVersion = enginePolicyVersion,
)

class W3DayPickTest {
    // Valores calculados con la formula de DayPick (FeedModel.swift):
    // 2026-09-22 -> Nº 199, el de la captura de App Store (22 sept).
    @Test
    fun combinacionDelDiaExacta() {
        assertEquals(1, DayPick.comboId(LocalDate.of(1970, 1, 1), 348))
        assertEquals(264, DayPick.comboId(LocalDate.of(1970, 1, 2), 348))
        assertEquals(199, DayPick.comboId(LocalDate.of(2026, 9, 22), 348))
        assertEquals(271, DayPick.comboId(LocalDate.of(2026, 10, 28), 348))
        assertEquals(109, DayPick.comboId(LocalDate.of(2000, 2, 29), 348))
        assertEquals(86, DayPick.comboId(LocalDate.of(1969, 12, 31), 348))
        assertEquals(20718L, DayPick.localDaysSince1970(LocalDate.of(2026, 9, 22)))
    }

    @Test
    fun otraCombinacionNuncaRepite() {
        val random = Random(42)
        repeat(200) {
            val next = DayPick.another(199, 348, random)
            assertTrue(next in 1..348 && next != 199)
        }
        assertEquals(1, DayPick.another(1, 1, random))
        assertEquals(2, DayPick.another(1, 2, random))
        assertEquals(1, DayPick.another(2, 2, random))
    }
}

class W3FilterTest {
    @Test
    fun matrizDeFiltros() {
        assertTrue(FeedFilter.ALL.includes(null, FeedbackVerdict.YES, false))
        assertTrue(FeedFilter.TWO.includes(2, null, false))
        assertFalse(FeedFilter.TWO.includes(3, null, false))
        assertFalse(FeedFilter.THREE.includes(null, null, false))
        assertTrue(FeedFilter.FOUR.includes(4, FeedbackVerdict.NO, false))
        assertTrue(FeedFilter.SAVED.includes(3, null, true))
        assertFalse(FeedFilter.SAVED.includes(3, null, false))
        assertTrue(FeedFilter.UNVOTED.includes(2, null, false))
        assertFalse(FeedFilter.UNVOTED.includes(2, FeedbackVerdict.YES, false))
    }
}

class W3ScanJsonTest {
    private val swatch = Swatch(Lab(10.5, -2.25, 3.0), 27, 27, 33, 0.28)

    @Test
    fun paletaConClavesOrdenadas() {
        val json = ScanJson.encodePalette(listOf(ScanJson.paletteEntry(swatch)))
        assertEquals(
            "[{\"hex\":\"#1b1b21\",\"lab\":[10.5,-2.25,3.0],\"rgb\":[27,27,33],\"weight\":0.28}]",
            json,
        )
        val back = ScanJson.decodePalette(json).single()
        assertEquals("#1b1b21", back.hex)
        assertEquals(listOf(27, 27, 33), back.rgb)
        assertEquals(listOf(10.5, -2.25, 3.0), back.lab)
        assertEquals(0.28, back.weight, 0.0)
    }

    @Test
    fun prendasRoundTrip() {
        val garment = com.andreseloy.colorsapp.engine.GarmentSwatch(
            swatch, com.andreseloy.colorsapp.engine.GarmentRegion.UPPER, 0.62, 3,
        )
        val json = ScanJson.encodeGarments(listOf(ScanJson.garmentEntry(garment)))
        assertEquals(
            "[{\"hex\":\"#1b1b21\",\"lab\":[10.5,-2.25,3.0],\"mergedClusters\":3," +
                "\"region\":1,\"regionShare\":0.62,\"rgb\":[27,27,33],\"weight\":0.28}]",
            json,
        )
        val back = ScanJson.decodeGarments(json).single()
        assertEquals(1, back.region)
        assertEquals(0.62, back.regionShare, 0.0)
        assertEquals(3, back.mergedClusters)
        assertTrue(ScanJson.decodeGarments(null).isEmpty())
        assertTrue(ScanJson.decodeGarments("no-json").isEmpty())
        assertTrue(ScanJson.decodePalette("").isEmpty())
    }

    @Test
    fun scoresYPasos() {
        assertEquals("[1.5,2.5]", ScanJson.encodeScores(listOf(1.5, 2.5)))
        assertEquals(listOf(1.5, 2.5), ScanJson.decodeScores("[1.5, 2.5]"))
        val json = ScanJson.encodeSteps(listOf(MaskStep.POSE_REGIONS, MaskStep.SKIN_EXCLUDED))
        assertEquals("[\"poseRegions\",\"skinExcluded\"]", json)
        assertEquals(
            listOf(MaskStep.POSE_REGIONS, MaskStep.SKIN_EXCLUDED),
            ScanJson.decodeSteps(json),
        )
        assertEquals(
            listOf(MaskStep.NO_PEOPLE),
            ScanJson.decodeSteps("[\"noPeople\",\"pasoFuturo\"]"),
        )
    }

    @Test
    fun makeYUpdated() {
        val result = AnalysisResult(
            listOf(swatch), listOf(Hit(7, 3.25), Hit(9, 4.0)), true, 99L,
        )
        val subject = ScanSubjectInfo(
            "largestPerson", "clothing", true, 2, 0,
            listOf(MaskStep.POSE_REGIONS), 0.123,
        )
        val record = ScanJson.makeRecord(
            id = "id-1", result = result, source = ScanSource.CAMERA, assetId = null,
            subject = subject, policyVersion = 1,
            engineVersion = "e1", dictVersion = "d1", nowMs = 5000,
        )
        assertEquals(7, record.top1)
        assertEquals(9, record.top2)
        assertNull(record.top3)
        assertEquals("[3.25,4.0]", record.scoresJson)
        assertTrue(record.ambiguous)
        assertEquals("largestPerson", record.subjectMode)
        assertEquals(2, record.peopleCount)
        assertEquals("[\"poseRegions\"]", record.maskStepsJson)
        assertNull(record.garmentsJson)
        val updated = ScanJson.updatedRecord(
            record, result, subject, nowMs = 9000,
        )
        assertEquals("id-1", updated.id)
        assertEquals(5000, updated.scannedAtMs)
        assertEquals(9000, updated.updatedAtMs)
        assertEquals(record.rev + 1, updated.rev)
        assertTrue(updated.dirty)
    }
}

class W3PolicyTest {
    @Test
    fun necesitaReanalisis() {
        assertFalse(AnalysisPolicy.needsReanalysis(scan(), "e1", "d1"))
        assertTrue(AnalysisPolicy.needsReanalysis(scan(enginePolicyVersion = null), "e1", "d1"))
        assertTrue(AnalysisPolicy.needsReanalysis(scan(enginePolicyVersion = 0), "e1", "d1"))
        assertTrue(AnalysisPolicy.needsReanalysis(scan(engineVersion = "viejo"), "e1", "d1"))
        assertTrue(AnalysisPolicy.needsReanalysis(scan(dictVersion = "viejo"), "e1", "d1"))
        assertFalse(
            AnalysisPolicy.needsReanalysis(
                scan(source = ScanSource.MANUAL, enginePolicyVersion = null), "e1", "d1",
            ),
        )
    }
}

class W3FeedTextTest {
    @Test
    fun persona() {
        assertNull(FeedPostText.person(scan()))
        assertEquals(
            PersonLabel.WholePhoto,
            FeedPostText.person(scan(subjectMode = "off", peopleCount = 2)),
        )
        assertEquals(
            PersonLabel.WholePhoto,
            FeedPostText.person(scan(subjectMode = "largestPerson", peopleCount = 0)),
        )
        assertEquals(
            PersonLabel.AllPeople(3),
            FeedPostText.person(scan(subjectMode = "allPeople", peopleCount = 3)),
        )
        assertEquals(
            PersonLabel.OnePerson,
            FeedPostText.person(scan(subjectMode = "allPeople", peopleCount = 1)),
        )
        assertEquals(
            PersonLabel.MainOf(3),
            FeedPostText.person(
                scan(subjectMode = "largestPerson", peopleCount = 3, personIndex = 0),
            ),
        )
        assertEquals(
            PersonLabel.PersonOf(3, 3),
            FeedPostText.person(
                scan(subjectMode = "selectedPerson", peopleCount = 3, personIndex = 2),
            ),
        )
    }

    @Test
    fun avisoDelRecorte() {
        assertNull(FeedPostText.cropNotice(scan()))
        assertEquals(
            CropNotice.WholePhoto(false),
            FeedPostText.cropNotice(scan(subjectMode = "off")),
        )
        assertEquals(
            CropNotice.WholePhoto(true),
            FeedPostText.cropNotice(
                scan(
                    subjectMode = "largestPerson", maskStepsJson = "[\"noPeople\"]",
                    maskCoverage = 0.5,
                ),
            ),
        )
        assertEquals(
            CropNotice.WholePersonFallback,
            FeedPostText.cropNotice(
                scan(
                    subjectMode = "largestPerson", regionMode = "clothing",
                    maskStepsJson = "[\"wholePerson\"]", maskCoverage = 0.2,
                ),
            ),
        )
        assertEquals(
            CropNotice.Region(RegionTextKind.CLOTHING, 2, true, false),
            FeedPostText.cropNotice(
                scan(
                    subjectMode = "allPeople", regionMode = "clothing", peopleCount = 2,
                    maskStepsJson = "[\"poseRegions\",\"skinExcluded\"]", maskCoverage = 0.3,
                ),
            ),
        )
        val guard = FeedPostText.cropNotice(
            scan(
                subjectMode = "largestPerson", regionMode = "wholePerson", peopleCount = 1,
                maskStepsJson = "[\"skinGuard\"]", maskCoverage = 0.3,
            ),
        ) as CropNotice.Region
        assertTrue(guard.isFallback)
        assertEquals(RegionTextKind.WHOLE_PERSON, guard.kind)
    }

    @Test
    fun tituloDePaleta() {
        assertEquals(PaletteTitleKind.PHOTO, FeedPostText.paletteTitleKind(scan(), false))
        assertEquals(PaletteTitleKind.GARMENTS, FeedPostText.paletteTitleKind(scan(), true))
        assertEquals(
            PaletteTitleKind.CLOTHING,
            FeedPostText.paletteTitleKind(
                scan(subjectMode = "largestPerson", regionMode = "clothing", maskCoverage = 0.2),
                false,
            ),
        )
        assertEquals(
            PaletteTitleKind.PERSON,
            FeedPostText.paletteTitleKind(
                scan(subjectMode = "largestPerson", regionMode = "wholePerson", maskCoverage = 0.2),
                false,
            ),
        )
    }

    @Test
    fun fechaEsteAnoYOtro() {
        val zone = ZoneId.of("Europe/Madrid")
        val now = LocalDate.of(2026, 10, 1).atStartOfDay(zone).toInstant().toEpochMilli()
        val sept = LocalDate.of(2026, 9, 22).atTime(18, 59).atZone(zone).toInstant().toEpochMilli()
        val text = FeedPostText.dateText(sept, Locale.forLanguageTag("es-ES"), zone, now)
        assertTrue(text.contains("22") && text.contains("18:59") && !text.contains("2026"))
        val old = LocalDate.of(2024, 9, 22).atTime(18, 59).atZone(zone).toInstant().toEpochMilli()
        assertTrue(FeedPostText.dateText(old, Locale.forLanguageTag("es-ES"), zone, now).contains("2024"))
    }

    @Test
    fun itemDelFeedConPrendas() {
        val garments =
            "[{\"hex\":\"#0a0a0a\",\"lab\":[0,0,0],\"mergedClusters\":1,\"region\":1," +
                "\"regionShare\":0.6,\"rgb\":[10,10,10],\"weight\":0.7}]"
        val item = FeedItemBuilder.build(
            scan(
                garmentsJson = garments, top1 = 2, ambiguous = true,
                subjectMode = "largestPerson", regionMode = "clothing",
                peopleCount = 1, maskCoverage = 0.3,
            ),
            FakeDictionary(mapOf(2 to "Taller")),
            { code -> "region-$code" },
            "e1", "d1",
        )
        assertEquals(1, item.palette.size)
        assertEquals("region-1", item.palette.single().name)
        assertEquals(3, item.top1Size)
        assertEquals("Taller", item.match?.name)
        assertTrue(item.match!!.ambiguousWithTop2)
        assertEquals(PaletteTitleKind.GARMENTS, item.paletteTitle)
        assertFalse(item.isOutdated)
    }
}

class W3NoticeTest {
    private fun result(
        people: Int, steps: List<MaskStep>, chosen: Int? = 0, withMask: Boolean = true,
    ) = SubjectMaskResult(
        width = 4, height = 4,
        people = (0 until people).map { PersonInstanceResult(it, 0.1, null) },
        chosenIndex = chosen,
        mask = if (withMask) {
            com.andreseloy.colorsapp.subject.MaskBuffer(4, 4, ByteArray(16) { -1 })
        } else {
            null
        },
        steps = steps,
    )

    @Test
    fun casosDelAviso() {
        val off = SubjectOptions(mode = SubjectMode.OFF)
        assertEquals(
            MaskNotice.Whole(MaskNotice.Fixed.CROP_OFF, false),
            ResultNotice.notice(off, result(0, listOf(MaskStep.NONE), null, false)),
        )
        val def = SubjectOptions()
        assertEquals(
            MaskNotice.Whole(MaskNotice.Fixed.NO_PERSON, true),
            ResultNotice.notice(def, result(0, listOf(MaskStep.NO_PEOPLE), null, false)),
        )
        val parts = ResultNotice.notice(
            def,
            result(2, listOf(MaskStep.POSE_REGIONS, MaskStep.SKIN_EXCLUDED, MaskStep.GARMENT_REGIONS)),
        ) as MaskNotice.Parts
        assertEquals(
            listOf(
                NoticePart.MainOf(2), NoticePart.ClothingOnly,
                NoticePart.SkinExcluded, NoticePart.GarmentRegions,
            ),
            parts.parts,
        )
        assertFalse(parts.isFallback)
        val guard = ResultNotice.notice(
            def, result(1, listOf(MaskStep.POSE_REGIONS, MaskStep.SKIN_GUARD), 0),
        ) as MaskNotice.Parts
        assertTrue(guard.isFallback)
        assertEquals("Hola", ResultNotice.capitalizedFirst("hola"))
    }
}

class W3GeometryTest {
    @Test
    fun libro() {
        assertEquals(2.36, BookCompositionGeometry.aspectRatio(2), 0.0)
        assertEquals(2.85, BookCompositionGeometry.aspectRatio(3), 0.0)
        assertEquals(1.252, BookCompositionGeometry.aspectRatio(4), 0.0)
        val r4 = BookCompositionGeometry.rects(4)
        assertEquals(0.248, r4[0].x, 0.0)
        assertEquals(0.537, r4[2].x, 0.0)
        assertEquals(2.0 / 3.0, r4[3].y, 1e-9)
        val r3 = BookCompositionGeometry.rects(3)
        assertEquals(listOf(0.0, 1.0 / 3.0, 2.0 / 3.0), r3.map { it.x })
        // El tope de alto estrecha la caja, no la estira.
        assertEquals(260f * 2.36f, BookCompositionGeometry.boxWidthDp(4000f, 2, 260f), 0.01f)
        assertEquals(300f, BookCompositionGeometry.boxWidthDp(300f, 2, 260f), 0.01f)
    }

    @Test
    fun visor() {
        val (h1, top1, bottom1) = ViewfinderGeometry.layout(1.5f, 390f)
        assertEquals(376f, h1, 0.01f)
        assertEquals(48f, top1, 0f)
        assertEquals(68f, bottom1, 0f)
        val (h2, top2, bottom2) = ViewfinderGeometry.layout(0.5f, 390f)
        assertEquals(400f, h2, 0f)
        assertEquals(0f, top2, 0f)
        assertEquals(0f, bottom2, 0f)
    }

    @Test
    fun alfileresAlCentroide() {
        // 4x3: swatch 0 en (0,0),(1,0); swatch 1 en (3,2); 255 fuera, 254 descartado.
        val map = byteArrayOf(
            0, 0, -1, -2,
            -1, -1, -1, -1,
            -1, -1, -1, 1,
        )
        val pins = PinPositions.compute(map, 4, 3, 2)
        assertEquals(2, pins.size)
        // Centroide de 0: (0.5, 0) -> el pixel mas cercano es (0,0) o (1,0); gana el primero.
        assertEquals(0.125, pins[0]!!.first, 1e-9)
        assertEquals((3.5) / 4, pins[1]!!.first, 1e-9)
        assertEquals((2.5) / 3, pins[1]!!.second, 1e-9)
        assertTrue(PinPositions.compute(ByteArray(0), 0, 0, 1).isEmpty())
    }
}

class W3WrappedTest {
    @Test
    fun conteosYDesbloqueo() {
        assertEquals(
            listOf(2 to 5, 1 to 3, 3 to 3),
            sortedCounts(mapOf(1 to 3, 2 to 5, 3 to 3)),
        )
        val dict = FakeDictionary()
        // Combo 1 (colores 0,1) x2 + combo 2 (0,2,3) x1 -> 0:3, 1:2, 2:1, 3:1.
        assertEquals(
            listOf(0 to 3, 1 to 2, 2 to 1, 3 to 1),
            colorCounts(mapOf(1 to 2, 2 to 1), dict),
        )
        assertEquals("41/348", wrappedCounterText(41, 348))
        assertEquals(7, unlockCandidate(7, 12.0, false, 12.0))
        assertNull(unlockCandidate(7, 12.01, false, 12.0))
        assertNull(unlockCandidate(7, 3.0, true, 12.0))
        assertNull(unlockCandidate(null, 3.0, false, 12.0))
    }

    @Test
    fun gardenJsonRoundTrip() {
        val items = listOf(
            GardenSavedStore.Item("scan", "abc-1", 1_700_000_000_000),
            GardenSavedStore.Item("combo", "67", 1_600_000_000_000),
        )
        val json = GardenSavedStore.encode(items)
        val back = GardenSavedStore.decode(json)
        assertEquals(items, back)
        // El formato de iOS (ISO8601 con Z y claves ordenadas) se lee igual.
        assertTrue(json.contains("\"savedAt\" : \"2023-11-14T22:13:20Z\""))
        assertTrue(GardenSavedStore.decode("basura").isEmpty())
    }
}

class W3FormatTest {
    @Test
    fun numerosLocalizados() {
        assertEquals("19,56", W3Format.score(19.56, Locale.forLanguageTag("es-ES")))
        assertEquals("19.56", W3Format.score(19.56, Locale.US))
        assertEquals("2,3", W3Format.deltaEValue(2.34, Locale.forLanguageTag("es-ES")))
        assertEquals(39, W3Format.percentInt(0.392))
        assertEquals("067", W3Format.paddedComboId(67))
        val color = PaletteColor.fromHex(0, "#1b1b21", weight = 0.5)!!
        assertEquals("#1B1B21", color.hex)
        assertEquals("#1B1B21", W3Format.hexList(listOf(color)))
        assertNull(PaletteColor.fromHex(0, "#xyz"))
    }
}
