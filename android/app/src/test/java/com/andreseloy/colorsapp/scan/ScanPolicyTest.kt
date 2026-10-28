// Tests JVM de la política y el resumen del escaneo (sin MediaStore).
package com.andreseloy.colorsapp.scan

import com.andreseloy.colorsapp.data.WadaCombo
import com.andreseloy.colorsapp.data.WadaDictionary
import com.andreseloy.colorsapp.engine.AnalysisResult
import com.andreseloy.colorsapp.engine.Hit
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

private class FakeDictionary : WadaDictionary {
    override val dictVersion: String = "x"
    override val matchesEngine: Boolean = true
    override val colors: List<com.andreseloy.colorsapp.data.WadaColor> = emptyList()
    override val combinations: List<WadaCombo> = listOf(
        WadaCombo(117, intArrayOf(1, 2)),
        WadaCombo(69, intArrayOf(2, 3)),
    )

    override fun curatedName(id: Int): String? = null
}

class ScanPolicyTest {
    @Test
    fun unlockCandidateRespectsScore() {
        val policy = ScanPolicy(unlockMaxScore = 12.0)
        val good = AnalysisResult(emptyList(), listOf(Hit(117, 3.5)), ambiguous = false, hash = 0)
        val bad = AnalysisResult(emptyList(), listOf(Hit(117, 12.5)), ambiguous = false, hash = 0)
        assertEquals(117, policy.unlockCandidate(good))
        assertNull(policy.unlockCandidate(bad))
        assertNull(policy.unlockCandidate(AnalysisResult(emptyList(), emptyList(), false, 0)))
    }

    @Test
    fun sortedCountsAndColorCounts() {
        val counts = mapOf(117 to 3, 69 to 5, 200 to 5)
        val sorted = MediaStoreScanRunner.sortedCounts(counts)
        assertEquals(listOf(69 to 5, 200 to 5, 117 to 3), sorted.map { it.key to it.value })
        val colors = MediaStoreScanRunner.colorCounts(counts, FakeDictionary())
        // Color 2: 117(3) + 69(5) = 8; color 3: 5; color 1: 3. (200 no existe.)
        assertEquals(listOf(2 to 8, 3 to 5, 1 to 3), colors.map { it.key to it.value })
    }

    @Test
    fun stepsTextAlphabetical() {
        assertEquals("headCut 3, noPeople 17", MediaStoreScanRunner.stepsText(mapOf("noPeople" to 17, "headCut" to 3)))
        assertEquals("-", MediaStoreScanRunner.stepsText(emptyMap()))
    }

    @Test
    fun jsonEncodingSortedKeys() {
        assertEquals("[3.5,7]", PhotoAnalyzer.encodeScores(listOf(3.5, 7.0)))
        assertEquals("[\"poseRegions\",\"skinExcluded\"]", PhotoAnalyzer.encodeSteps(listOf("poseRegions", "skinExcluded")))
    }
}
