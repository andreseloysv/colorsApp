// Reglas de re-análisis: los mismos casos que GarmentDatabaseTests de iOS.
package com.andreseloy.colorsapp.data

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class AnalysisPolicyTest {

    private fun scan(
        source: ScanSource = ScanSource.CAMERA,
        engineVersion: String = "1.0.0",
        dictVersion: String = "fd95ac692777",
        policy: Int? = AnalysisPolicy.CURRENT,
    ) = ScanRecord(
        id = UuidV7.string(), assetId = null, source = source, top1 = 27, top2 = null,
        top3 = null, engineVersion = engineVersion, dictVersion = dictVersion,
        scannedAtMs = 1_700_000_000_000L, updatedAtMs = 1_700_000_000_000L,
        enginePolicyVersion = policy,
    )

    @Test
    fun scanAlDiaNoSeReanaliza() {
        assertFalse(AnalysisPolicy.needsReanalysis(scan(), "1.0.0", "fd95ac692777"))
        assertFalse(scan().needsReanalysis("1.0.0", "fd95ac692777"))
    }

    @Test
    fun politicaMotorODiccionarioNuevosPidenReanalisis() {
        val scan = scan()
        assertTrue(
            AnalysisPolicy.needsReanalysis(
                scan, "1.0.0", "fd95ac692777", AnalysisPolicy.CURRENT + 1,
            ),
        )
        assertTrue(AnalysisPolicy.needsReanalysis(scan, "9.9.9", "fd95ac692777"))
        assertTrue(AnalysisPolicy.needsReanalysis(scan, "1.0.0", "otro"))
    }

    @Test
    fun anteriorAV4SeReanalizaYManualNunca() {
        assertTrue(AnalysisPolicy.needsReanalysis(scan(policy = null), "1.0.0", "fd95ac692777"))
        assertFalse(
            AnalysisPolicy.needsReanalysis(
                scan(source = ScanSource.MANUAL, policy = null), "9.9.9", "otro",
            ),
        )
    }
}
