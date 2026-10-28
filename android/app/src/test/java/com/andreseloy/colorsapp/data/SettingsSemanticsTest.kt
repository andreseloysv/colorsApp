// Semántica de ajustes de iOS sobre el repo en memoria (la misma interfaz
// que Room): "1" es verdadero, selectedPerson no es un ajuste y un Double
// no finito cuenta como ausente.
package com.andreseloy.colorsapp.data

import com.andreseloy.colorsapp.subject.RegionMode
import com.andreseloy.colorsapp.subject.SubjectMode
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class SettingsSemanticsTest {

    @Test
    fun boolAceptaTrueYUno() = runTest {
        val repo = InMemorySettingsRepository()
        repo.set(SettingsRepository.Key.ADAPTIVE_SKIN, "1")
        assertTrue(repo.bool(SettingsRepository.Key.ADAPTIVE_SKIN, defaultValue = false))
        repo.set(SettingsRepository.Key.ADAPTIVE_SKIN, "cualquier otra cosa")
        assertFalse(repo.bool(SettingsRepository.Key.ADAPTIVE_SKIN, defaultValue = true))
    }

    @Test
    fun subjectSettingsComoEnIos() = runTest {
        val repo = InMemorySettingsRepository()
        repo.set(SettingsRepository.Key.SUBJECT_MODE, "selectedPerson")
        repo.set(SettingsRepository.Key.UNLOCK_MAX_SCORE, "nan")
        var settings = repo.subjectSettings()
        assertEquals(SubjectMode.LARGEST_PERSON, settings.mode)
        assertEquals(RegionMode.CLOTHING, settings.region)
        assertEquals(12.0, settings.unlockMaxScore, 0.0)
        repo.set(SettingsRepository.Key.SUBJECT_MODE, "off")
        repo.set(SettingsRepository.Key.REGION_MODE, "wholePerson")
        repo.setBool(SettingsRepository.Key.ADAPTIVE_SKIN, false)
        repo.setDouble(SettingsRepository.Key.UNLOCK_MAX_SCORE, 7.5)
        settings = repo.subjectSettings()
        assertEquals(SubjectMode.OFF, settings.mode)
        assertEquals(RegionMode.WHOLE_PERSON, settings.region)
        assertFalse(settings.adaptiveSkin)
        assertEquals(7.5, settings.unlockMaxScore, 0.0)
    }

    @Test
    fun feedbackMasRecientePrimeroConIdsV7() = runTest {
        val repo = InMemoryFeedbackRepository()
        val first = repo.record("scan-1", FeedbackVerdict.YES, nowMs = 1_700_000_000_000L)
        repo.record("scan-1", FeedbackVerdict.NO, nowMs = 1_700_000_001_000L)
        assertTrue(UuidV7.isV7(first.id))
        assertEquals(FeedbackVerdict.NO, repo.latest("scan-1")?.verdict)
        assertEquals(
            listOf(FeedbackVerdict.NO, FeedbackVerdict.YES),
            repo.forScan("scan-1").map { it.verdict },
        )
        assertEquals(1 to 1, repo.counts())
    }
}
