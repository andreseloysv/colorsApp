// Repositorios Room: implementan las interfaces de Repositories.kt con la
// misma semántica que ios/ColorsApp/DB/Repositories.swift (columnas
// sync-ready, borrado suave donde toca y borrado físico en deleteAll).
package com.andreseloy.colorsapp.data.db

import androidx.room.withTransaction
import com.andreseloy.colorsapp.data.AnalysisPolicy
import com.andreseloy.colorsapp.data.FeedbackRecord
import com.andreseloy.colorsapp.data.FeedbackRepository
import com.andreseloy.colorsapp.data.FeedbackVerdict
import com.andreseloy.colorsapp.data.ScanRecord
import com.andreseloy.colorsapp.data.ScanRepository
import com.andreseloy.colorsapp.data.ScanSource
import com.andreseloy.colorsapp.data.SettingsRepository
import com.andreseloy.colorsapp.data.UnlockRecord
import com.andreseloy.colorsapp.data.UnlockRepository
import com.andreseloy.colorsapp.data.UuidV7
import com.andreseloy.colorsapp.data.touched
import com.andreseloy.colorsapp.engine.colorEngineVersion
import com.andreseloy.colorsapp.engine.dictionaryVersion
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.map

/**
 * Versiones contra las que [RoomScanRepository.needingReanalysis] aplica
 * [AnalysisPolicy]. En producción salen del motor C; en tests se inyectan.
 */
class EngineVersions(
    val engineVersion: String,
    val dictVersion: String,
    val policyVersion: Int = AnalysisPolicy.CURRENT,
) {
    companion object {
        fun fromEngine(): EngineVersions = EngineVersions(colorEngineVersion, dictionaryVersion)
    }
}

class RoomScanRepository(
    private val db: ColorsDatabase,
    private val versions: EngineVersions,
) : ScanRepository {
    private val dao get() = db.scanDao()

    /** Inserta (o reemplaza por id), como `save` de GRDB. */
    override suspend fun insert(scan: ScanRecord) = dao.upsert(scan.toEntity())

    override suspend fun fetch(id: String): ScanRecord? = dao.fetch(id)?.toRecord()

    override suspend fun recent(limit: Int): List<ScanRecord> =
        dao.recent(limit).map { it.toRecord() }

    override suspend fun scansWithTop1(comboId: Int, limit: Int): List<ScanRecord> =
        dao.withTop1(comboId, limit).map { it.toRecord() }

    override suspend fun count(): Int = dao.liveCount()

    /** Borrado suave (deleted_at, rev + 1, dirty). */
    override suspend fun softDelete(id: String, nowMs: Long) {
        db.withTransaction {
            val entity = dao.fetch(id) ?: return@withTransaction
            val deleted = entity.toRecord().copy(deletedAtMs = nowMs).touched(nowMs)
            dao.update(deleted.toEntity())
        }
    }

    /** Borra todos los scans de un origen (físico; "Rehacer escaneo"). */
    override suspend fun deleteAll(source: ScanSource) = dao.deleteAll(source.raw)

    /** Actualiza un scan existente; el llamador ya hizo `touched`. */
    override suspend fun update(scan: ScanRecord) = dao.update(scan.toEntity())

    override suspend fun needingReanalysis(limit: Int): List<ScanRecord> =
        dao.liveByRecency().map { it.toRecord() }
            .filter {
                AnalysisPolicy.needsReanalysis(
                    it, versions.engineVersion, versions.dictVersion, versions.policyVersion,
                )
            }
            .take(limit)

    override fun observeRecent(limit: Int): Flow<List<ScanRecord>> =
        dao.observeRecent(limit).map { rows -> rows.map { it.toRecord() } }
}

class RoomUnlockRepository(private val db: ColorsDatabase) : UnlockRepository {
    private val dao get() = db.unlockDao()

    override suspend fun unlock(
        comboId: Int, source: ScanSource, assetId: String?, scanId: String?, nowMs: Long,
    ): Boolean = db.withTransaction { unlockInTransaction(comboId, source, assetId, scanId, nowMs) }

    override suspend fun unlock(
        comboIds: List<Int>, source: ScanSource, assetId: String?, scanId: String?, nowMs: Long,
    ): List<Int> = db.withTransaction {
        comboIds.filter { unlockInTransaction(it, source, assetId, scanId, nowMs) }
    }

    /** Desbloquea o restaura uno borrado; true si es nuevo. Dentro de transacción. */
    private suspend fun unlockInTransaction(
        comboId: Int, source: ScanSource, assetId: String?, scanId: String?, nowMs: Long,
    ): Boolean {
        val existing = dao.fetchAny(comboId)?.toRecord()
        if (existing != null) {
            if (existing.deletedAtMs == null) return false
            val restored = existing.copy(
                firstSeenAtMs = nowMs, source = source, assetId = assetId,
                scanId = scanId, deletedAtMs = null,
            ).touched(nowMs)
            dao.update(restored.toEntity())
            return true
        }
        dao.insert(
            UnlockRecord(
                comboId = comboId, firstSeenAtMs = nowMs, source = source,
                assetId = assetId, scanId = scanId, updatedAtMs = nowMs,
            ).toEntity(),
        )
        return true
    }

    override suspend fun record(comboId: Int): UnlockRecord? = dao.fetchLive(comboId)?.toRecord()

    override suspend fun isUnlocked(comboId: Int): Boolean = dao.fetchLive(comboId) != null

    override suspend fun all(): List<UnlockRecord> = dao.liveAll().map { it.toRecord() }

    override suspend fun unlockedIds(): Set<Int> = dao.liveAll().map { it.comboId }.toSet()

    override suspend fun count(): Int = dao.liveCount()

    /** Borra todos los desbloqueos de un origen (físico), o todos si es null. */
    override suspend fun deleteAll(source: ScanSource?) {
        if (source != null) dao.deleteBySource(source.raw) else dao.deleteEverything()
    }

    override fun observeAll(): Flow<List<UnlockRecord>> =
        dao.observeLiveAll().map { rows -> rows.map { it.toRecord() } }

    override fun observeUnlockedIds(): Flow<Set<Int>> =
        dao.observeLiveAll().map { rows -> rows.map { it.comboId }.toSet() }

    override fun observeCount(): Flow<Int> = dao.observeLiveAll().map { it.size }
}

class RoomFeedbackRepository(private val db: ColorsDatabase) : FeedbackRepository {
    private val dao get() = db.feedbackDao()

    override suspend fun record(
        scanId: String, verdict: FeedbackVerdict, nowMs: Long,
    ): FeedbackRecord {
        val record = FeedbackRecord(
            id = UuidV7.string(nowMs), scanId = scanId, verdict = verdict,
            createdAtMs = nowMs, updatedAtMs = nowMs,
        )
        dao.insert(record.toEntity())
        return record
    }

    override suspend fun forScan(id: String): List<FeedbackRecord> =
        dao.forScan(id).map { it.toRecord() }

    override suspend fun latest(forScanId: String): FeedbackRecord? = forScan(forScanId).firstOrNull()

    override suspend fun all(): List<FeedbackRecord> = dao.liveAll().map { it.toRecord() }

    override suspend fun counts(): Pair<Int, Int> =
        dao.liveCount(FeedbackVerdict.YES.raw) to dao.liveCount(FeedbackVerdict.NO.raw)

    override fun observeLatest(forScanId: String): Flow<FeedbackRecord?> =
        dao.observeLatest(forScanId).map { it?.toRecord() }
}

class RoomSettingsRepository(private val db: ColorsDatabase) : SettingsRepository {
    private val dao get() = db.settingDao()

    override suspend fun get(key: SettingsRepository.Key): String? = dao.fetchLiveValue(key.raw)

    /** Escribe (`value` null = borrado suave), manteniendo rev/dirty. */
    override suspend fun set(key: SettingsRepository.Key, value: String?, nowMs: Long) {
        db.withTransaction {
            val existing = dao.fetchAny(key.raw)?.toRecord()
            if (existing != null) {
                val updated = if (value != null) {
                    existing.copy(value = value, deletedAtMs = null)
                } else {
                    existing.copy(deletedAtMs = nowMs)
                }.touched(nowMs)
                dao.update(updated.toEntity())
            } else if (value != null) {
                dao.insert(
                    com.andreseloy.colorsapp.data.SettingRecord(
                        key = key.raw, value = value, updatedAtMs = nowMs,
                    ).toEntity(),
                )
            }
        }
    }

    override fun observe(key: SettingsRepository.Key): Flow<String?> = dao.observeLiveValue(key.raw)
}
