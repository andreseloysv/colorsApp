// JSON de las columnas: claves ordenadas y formato como JSONEncoder de iOS.
package com.andreseloy.colorsapp.data

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class JsonCodingTest {

    @Test
    fun scoresComoEnIos() {
        assertEquals("[0.5,2,3]", JsonCoding.encodeScores(listOf(0.5, 2.0, 3.0)))
        assertEquals("[]", JsonCoding.encodeScores(emptyList()))
        assertEquals(listOf(17.18, 19.56, 21.56), JsonCoding.decodeScores("[17.18,19.56,21.56]"))
    }

    @Test
    fun paletteConClavesOrdenadas() {
        val entry = PaletteEntry("#c5a56e", listOf(197, 165, 110), listOf(70.0, 3.0, 33.0), 1.0)
        assertEquals(
            "[{\"hex\":\"#c5a56e\",\"lab\":[70,3,33],\"rgb\":[197,165,110],\"weight\":1}]",
            JsonCoding.encodePalette(listOf(entry)),
        )
        assertEquals(listOf(entry), JsonCoding.decodePalette(JsonCoding.encodePalette(listOf(entry))))
    }

    @Test
    fun garmentsConClavesOrdenadas() {
        val entry = GarmentEntry(
            "#ddc0c8", listOf(221, 192, 200), listOf(79.5, 8.1, 0.4),
            weight = 0.6, region = 2, regionShare = 0.45, mergedClusters = 4,
        )
        assertEquals(
            "[{\"hex\":\"#ddc0c8\",\"lab\":[79.5,8.1,0.4],\"mergedClusters\":4,\"region\":2," +
                "\"regionShare\":0.45,\"rgb\":[221,192,200],\"weight\":0.6}]",
            JsonCoding.encodeGarments(listOf(entry)),
        )
        assertEquals(listOf(entry), JsonCoding.decodeGarments(JsonCoding.encodeGarments(listOf(entry))))
    }

    @Test
    fun pasosDeMascaraYJsonRoto() {
        assertEquals(
            "[\"poseRegions\",\"skinGuard\"]",
            JsonCoding.encodeStrings(listOf("poseRegions", "skinGuard")),
        )
        assertTrue(JsonCoding.decodeScores("no es json").isEmpty())
        assertTrue(JsonCoding.decodePalette("[{\"hex\":1}]").isEmpty())
        assertTrue(JsonCoding.decodeGarments(null).isEmpty())
    }

    @Test
    fun helpersDelScanDecodifican() {
        val scan = ScanRecord(
            id = UuidV7.string(), assetId = null, source = ScanSource.PICKER, top1 = 5,
            top2 = null, top3 = null, scoresJson = "[1.5]",
            paletteJson = "[{\"hex\":\"#222524\",\"lab\":[14.2,-0.4,0.3],\"rgb\":[34,37,36],\"weight\":0.39}]",
            engineVersion = "1", dictVersion = "d", scannedAtMs = 1L, updatedAtMs = 1L,
            maskStepsJson = "[\"poseRegions\",\"skinExcluded\",\"pasoFuturo\"]",
            garmentsJson = "[{\"hex\":\"#ddc0c8\",\"lab\":[79.5,8.1,0.4],\"mergedClusters\":4," +
                "\"region\":2,\"regionShare\":0.45,\"rgb\":[221,192,200],\"weight\":0.6}]",
        )
        assertEquals(listOf(1.5), scan.scoreValues)
        assertEquals("#222524", scan.palette.first().hex)
        assertEquals(listOf(2), scan.garmentColors.map { it.region })
        // Un paso futuro del motor se ignora, como el compactMap de iOS.
        assertEquals(
            listOf(
                com.andreseloy.colorsapp.subject.MaskStep.POSE_REGIONS,
                com.andreseloy.colorsapp.subject.MaskStep.SKIN_EXCLUDED,
            ),
            scan.maskStepValues,
        )
    }
}
