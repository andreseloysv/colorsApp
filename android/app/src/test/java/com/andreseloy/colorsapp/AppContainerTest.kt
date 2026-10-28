// Tests de host del contenedor y los repos en memoria (sin motor nativo:
// el diccionario del motor solo se toca perezosamente vía colors/combinations,
// que estos tests no fuerzan).
package com.andreseloy.colorsapp

import com.andreseloy.colorsapp.data.InMemorySettingsRepository
import com.andreseloy.colorsapp.data.InMemoryUnlockRepository
import com.andreseloy.colorsapp.data.ScanSource
import com.andreseloy.colorsapp.data.SettingsRepository
import com.andreseloy.colorsapp.scan.NoopScanRunner
import com.andreseloy.colorsapp.scan.ScanException
import com.andreseloy.colorsapp.subject.RegionMode
import com.andreseloy.colorsapp.subject.SubjectMode
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class RepositoriesStubTest {

    @Test
    fun unlockEsIdempotente() = runTest {
        val repo = InMemoryUnlockRepository()
        assertTrue(repo.unlock(12, ScanSource.PICKER))
        assertFalse(repo.unlock(12, ScanSource.PICKER))
        assertEquals(setOf(12), repo.unlockedIds())
        assertEquals(1, repo.count())
    }

    @Test
    fun subjectSettingsPorDefecto() = runTest {
        val repo = InMemorySettingsRepository()
        val defaults = repo.subjectSettings()
        assertEquals(SubjectMode.LARGEST_PERSON, defaults.mode)
        assertEquals(RegionMode.CLOTHING, defaults.region)
        assertTrue(defaults.adaptiveSkin)
        repo.set(SettingsRepository.Key.SUBJECT_MODE, "off")
        assertEquals(SubjectMode.OFF, repo.subjectSettings().mode)
    }

    @Test
    fun noopScanRunnerFallaComoEnIos() = runTest {
        val runner = NoopScanRunner()
        try {
            runner.runInitialScan()
            throw AssertionError("debía lanzar NotImplemented")
        } catch (e: ScanException.NotImplemented) {
            // es el contrato de iOS: progreso failed + notImplemented
        }
    }
}
