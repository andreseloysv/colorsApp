// Repositorios Room en memoria: la semántica de Repositories.swift (borrado
// suave, borrado físico en deleteAll, desbloqueo idempotente y que restaura).
package com.andreseloy.colorsapp.data

import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.andreseloy.colorsapp.data.db.ColorsDatabase
import com.andreseloy.colorsapp.data.db.EngineVersions
import com.andreseloy.colorsapp.data.db.RoomFeedbackRepository
import com.andreseloy.colorsapp.data.db.RoomScanRepository
import com.andreseloy.colorsapp.data.db.RoomSettingsRepository
import com.andreseloy.colorsapp.data.db.RoomUnlockRepository
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.runBlocking
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class RoomRepositoriesTest {

    private lateinit var db: ColorsDatabase
    private val versions = EngineVersions(engineVersion = "1.0.0", dictVersion = "fd95ac692777")

    @Before
    fun setUp() {
        db = ColorsDatabase.inMemory(InstrumentationRegistry.getInstrumentation().targetContext)
    }

    @After
    fun tearDown() = db.close()

    private fun scan(
        id: String = UuidV7.string(),
        source: ScanSource = ScanSource.PICKER,
        top1: Int? = 12,
        scannedAt: Long = 1_700_000_000_000L,
        policy: Int? = AnalysisPolicy.CURRENT,
    ) = ScanRecord(
        id = id, assetId = "content://media/1", source = source, top1 = top1, top2 = null,
        top3 = null, engineVersion = "1.0.0", dictVersion = "fd95ac692777",
        scannedAtMs = scannedAt, updatedAtMs = scannedAt, enginePolicyVersion = policy,
    )

    @Test
    fun scansInsertFetchRecentYSoftDelete() = runBlocking {
        val repo = RoomScanRepository(db, versions)
        val older = scan(scannedAt = 1_700_000_000_000L)
        val newer = scan(scannedAt = 1_700_000_100_000L)
        repo.insert(older)
        repo.insert(newer)
        assertEquals(listOf(newer.id, older.id), repo.recent().map { it.id })
        assertEquals(2, repo.count())
        assertEquals(listOf(newer.id), repo.scansWithTop1(12).map { it.id }.take(1))
        // Insert por id reemplaza (save de GRDB), no duplica.
        repo.insert(older.copy(top1 = 99))
        assertEquals(2, repo.count())
        assertEquals(99, repo.fetch(older.id)?.top1)
        // Borrado suave: sale de las lecturas y sube rev.
        val revBefore = repo.fetch(newer.id)!!.rev
        repo.softDelete(newer.id, nowMs = 1_700_000_200_000L)
        assertEquals(1, repo.count())
        assertEquals(revBefore + 1, repo.fetch(newer.id)?.rev)
        assertEquals(listOf(older.id), repo.observeRecent().first().map { it.id })
    }

    @Test
    fun scansDeleteAllEsFisicoYNeedingReanalysis() = runBlocking {
        val repo = RoomScanRepository(db, versions)
        val stale = scan(source = ScanSource.LIBRARY, policy = null)
        val fresh = scan(source = ScanSource.LIBRARY)
        val manual = scan(source = ScanSource.MANUAL, policy = null)
        repo.insert(stale)
        repo.insert(fresh)
        repo.insert(manual)
        assertEquals(listOf(stale.id), repo.needingReanalysis().map { it.id })
        repo.deleteAll(ScanSource.LIBRARY)
        assertNull(repo.fetch(stale.id))
        assertEquals(1, repo.count())
    }

    @Test
    fun unlocksIdempotenteBulkYDeleteAll() = runBlocking {
        val repo = RoomUnlockRepository(db)
        assertTrue(repo.unlock(12, ScanSource.PICKER, nowMs = 10L))
        assertFalse(repo.unlock(12, ScanSource.PICKER, nowMs = 20L))
        assertEquals(listOf(13), repo.unlock(listOf(12, 13), ScanSource.CAMERA, nowMs = 30L))
        assertEquals(setOf(12, 13), repo.unlockedIds())
        assertEquals(2, repo.observeCount().first())
        repo.deleteAll(ScanSource.CAMERA)
        assertEquals(setOf(12), repo.unlockedIds())
        // Tras el borrado físico se puede desbloquear de nuevo.
        assertTrue(repo.unlock(13, ScanSource.PICKER))
    }

    @Test
    fun unlocksRestauraUnBorradoSuave() = runBlocking {
        val repo = RoomUnlockRepository(db)
        assertTrue(repo.unlock(7, ScanSource.PICKER, nowMs = 100L))
        // Borrado suave a mano (lo que dejaría una sincronización futura).
        db.openHelper.writableDatabase.execSQL(
            "UPDATE unlocks SET deleted_at = 200, updated_at = 200, rev = rev + 1 WHERE combo_id = 7",
        )
        assertNull(repo.record(7))
        assertFalse(repo.isUnlocked(7))
        assertTrue(repo.unlock(7, ScanSource.LIBRARY, assetId = "a", nowMs = 300L))
        val restored = repo.record(7)!!
        assertEquals(300L, restored.firstSeenAtMs)
        assertEquals(ScanSource.LIBRARY, restored.source)
        assertEquals(3, restored.rev)
    }

    @Test
    fun feedbackOrdenYRecuentos() = runBlocking {
        val repo = RoomFeedbackRepository(db)
        repo.record("scan-1", FeedbackVerdict.YES, nowMs = 1_000L)
        val last = repo.record("scan-1", FeedbackVerdict.NO, nowMs = 2_000L)
        assertTrue(UuidV7.isV7(last.id))
        assertEquals(FeedbackVerdict.NO, repo.latest("scan-1")?.verdict)
        assertEquals(
            listOf(FeedbackVerdict.NO, FeedbackVerdict.YES),
            repo.forScan("scan-1").map { it.verdict },
        )
        assertEquals(1 to 1, repo.counts())
        assertEquals(FeedbackVerdict.NO, repo.observeLatest("scan-1").first()?.verdict)
    }

    @Test
    fun settingsBorradoSuaveYReescritura() = runBlocking {
        val repo = RoomSettingsRepository(db)
        val key = SettingsRepository.Key.SUBJECT_MODE
        repo.set(key, "off", nowMs = 100L)
        assertEquals("off", repo.get(key))
        assertEquals("off", repo.observe(key).first())
        repo.set(key, null, nowMs = 200L)
        assertNull(repo.get(key))
        // La fila queda como borrado suave con rev 2 (sync-ready).
        db.openHelper.readableDatabase.query(
            "SELECT deleted_at, rev FROM settings WHERE `key` = 'subject_mode'",
        ).use { cursor ->
            assertTrue(cursor.moveToFirst())
            assertEquals(200L, cursor.getLong(0))
            assertEquals(2, cursor.getInt(1))
        }
        // Reescribir resucita la misma fila.
        repo.set(key, "allPeople", nowMs = 300L)
        assertEquals("allPeople", repo.get(key))
        db.openHelper.readableDatabase.query(
            "SELECT deleted_at, rev FROM settings WHERE `key` = 'subject_mode'",
        ).use { cursor ->
            assertTrue(cursor.moveToFirst())
            assertTrue(cursor.isNull(0))
            assertEquals(3, cursor.getInt(1))
        }
        // subjectSettings con los defectos y las conversiones de tipo de iOS.
        assertEquals(
            com.andreseloy.colorsapp.subject.SubjectMode.ALL_PEOPLE,
            repo.subjectSettings().mode,
        )
    }
}
