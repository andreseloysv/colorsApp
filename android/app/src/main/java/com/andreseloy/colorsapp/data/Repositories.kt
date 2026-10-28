// Repositorios: interfaces espejo de ios/ColorsApp/DB/Repositories.swift
// (las observaciones de GRDB son Flow aquí). La ola 2 las implementa con
// Room; la fundación trae versiones en memoria para que la app y los tests
// corran ya contra el contrato final.
package com.andreseloy.colorsapp.data

import com.andreseloy.colorsapp.subject.RegionMode
import com.andreseloy.colorsapp.subject.SubjectMode
import com.andreseloy.colorsapp.subject.SubjectSettings
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.map

interface ScanRepository {
    suspend fun insert(scan: ScanRecord)
    suspend fun fetch(id: String): ScanRecord?
    suspend fun recent(limit: Int = 50): List<ScanRecord>
    suspend fun scansWithTop1(comboId: Int, limit: Int = 50): List<ScanRecord>
    suspend fun count(): Int
    suspend fun softDelete(id: String, nowMs: Long = System.currentTimeMillis())
    suspend fun deleteAll(source: ScanSource)
    suspend fun update(scan: ScanRecord)
    suspend fun needingReanalysis(limit: Int = 50): List<ScanRecord>
    fun observeRecent(limit: Int = 50): Flow<List<ScanRecord>>
}

interface UnlockRepository {
    /** Devuelve true si la combinación se desbloqueó ahora. */
    suspend fun unlock(
        comboId: Int, source: ScanSource, assetId: String? = null, scanId: String? = null,
        nowMs: Long = System.currentTimeMillis(),
    ): Boolean

    /** Devuelve los ids recién desbloqueados. */
    suspend fun unlock(
        comboIds: List<Int>, source: ScanSource, assetId: String? = null, scanId: String? = null,
        nowMs: Long = System.currentTimeMillis(),
    ): List<Int>

    suspend fun record(comboId: Int): UnlockRecord?
    suspend fun isUnlocked(comboId: Int): Boolean
    suspend fun all(): List<UnlockRecord>
    suspend fun unlockedIds(): Set<Int>
    suspend fun count(): Int
    suspend fun deleteAll(source: ScanSource? = null)
    fun observeAll(): Flow<List<UnlockRecord>>
    fun observeUnlockedIds(): Flow<Set<Int>>
    fun observeCount(): Flow<Int>
}

interface FeedbackRepository {
    suspend fun record(
        scanId: String, verdict: FeedbackVerdict,
        nowMs: Long = System.currentTimeMillis(),
    ): FeedbackRecord

    suspend fun forScan(id: String): List<FeedbackRecord>
    suspend fun latest(forScanId: String): FeedbackRecord?
    suspend fun all(): List<FeedbackRecord>
    suspend fun counts(): Pair<Int, Int>
    fun observeLatest(forScanId: String): Flow<FeedbackRecord?>
}

interface SettingsRepository {
    enum class Key(val raw: String) {
        PERSON_MASK("person_mask"),
        SUBJECT_MODE("subject_mode"),
        REGION_MODE("region_mode"),
        ADAPTIVE_SKIN("adaptive_skin"),
        UNLOCK_MAX_SCORE("unlock_max_score"),
        SCAN_ONBOARDING_SKIPPED("scan_onboarding_skipped"),
        INITIAL_SCAN_DONE("initial_scan_done"),
        INITIAL_SCAN_AT("initial_scan_at"),
        INITIAL_SCAN_COUNT("initial_scan_count"),
    }

    suspend fun get(key: Key): String?
    suspend fun set(key: Key, value: String?, nowMs: Long = System.currentTimeMillis())
    // Como en iOS: "true" y "1" son verdadero; cualquier otro valor presente, falso.
    suspend fun bool(key: Key, defaultValue: Boolean = false): Boolean {
        val raw = get(key) ?: return defaultValue
        return raw == "true" || raw == "1"
    }

    suspend fun setBool(key: Key, value: Boolean) = set(key, if (value) "true" else "false")
    suspend fun int(key: Key, defaultValue: Int = 0): Int =
        get(key)?.toIntOrNull() ?: defaultValue

    suspend fun setInt(key: Key, value: Int) = set(key, value.toString())

    // Como en iOS: un Double no finito ("nan", "inf") cuenta como ausente.
    suspend fun double(key: Key, defaultValue: Double): Double =
        get(key)?.toDoubleOrNull()?.takeIf { it.isFinite() } ?: defaultValue

    suspend fun setDouble(key: Key, value: Double) = set(key, value.toString())

    /**
     * Ajustes del recorte con sus valores por defecto, como en iOS: un valor
     * ilegible, o `selectedPerson` (que no es un ajuste), cuenta como ausente.
     */
    suspend fun subjectSettings(): SubjectSettings {
        val defaults = SubjectSettings()
        val rawMode = get(Key.SUBJECT_MODE)
        val mode = SubjectMode.entries.firstOrNull { it.raw == rawMode }
            ?.takeIf { it != SubjectMode.SELECTED_PERSON } ?: defaults.mode
        val rawRegion = get(Key.REGION_MODE)
        val region = RegionMode.entries.firstOrNull { it.raw == rawRegion } ?: defaults.region
        return SubjectSettings(
            mode = mode,
            region = region,
            adaptiveSkin = bool(Key.ADAPTIVE_SKIN, defaults.adaptiveSkin),
            unlockMaxScore = double(Key.UNLOCK_MAX_SCORE, defaults.unlockMaxScore),
        )
    }

    fun observe(key: Key): Flow<String?>
}

/* ------------------------------------------------------------------ */
/* Implementaciones en memoria de la fundación (se sustituyen por Room) */
/* ------------------------------------------------------------------ */

private fun <T> List<T>.live() = MutableStateFlow(this)

class InMemoryScanRepository : ScanRepository {
    private val rows = MutableStateFlow<List<ScanRecord>>(emptyList())
    private fun liveRows() = rows.value.filter { it.deletedAtMs == null }

    // Como `save` de GRDB: inserta o reemplaza por id.
    override suspend fun insert(scan: ScanRecord) {
        rows.value = rows.value.filterNot { it.id == scan.id } + scan
    }

    override suspend fun fetch(id: String) = rows.value.firstOrNull { it.id == id }

    override suspend fun recent(limit: Int) =
        liveRows().sortedByDescending { it.scannedAtMs }.take(limit)

    override suspend fun scansWithTop1(comboId: Int, limit: Int) =
        liveRows().filter { it.top1 == comboId }
            .sortedByDescending { it.scannedAtMs }.take(limit)

    override suspend fun count() = liveRows().size

    override suspend fun softDelete(id: String, nowMs: Long) {
        rows.value = rows.value.map {
            if (it.id == id) it.copy(deletedAtMs = nowMs, updatedAtMs = nowMs, rev = it.rev + 1, dirty = true) else it
        }
    }

    // Borrado físico, como el deleteAll de GRDB ("Rehacer escaneo").
    override suspend fun deleteAll(source: ScanSource) {
        rows.value = rows.value.filterNot { it.source == source }
    }

    override suspend fun update(scan: ScanRecord) {
        rows.value = rows.value.map { if (it.id == scan.id) scan else it }
    }

    // Sin versiones del motor inyectadas solo se puede aplicar el criterio
    // de la columna ausente y la exención manual; la versión Room sí compara
    // motor y diccionario (AnalysisPolicy completo).
    override suspend fun needingReanalysis(limit: Int) =
        liveRows().filter { it.source != ScanSource.MANUAL && it.enginePolicyVersion == null }
            .sortedByDescending { it.scannedAtMs }.take(limit)

    override fun observeRecent(limit: Int): Flow<List<ScanRecord>> =
        rows.map { all ->
            all.filter { it.deletedAtMs == null }
                .sortedByDescending { it.scannedAtMs }.take(limit)
        }
}

class InMemoryUnlockRepository : UnlockRepository {
    private val rows = MutableStateFlow<List<UnlockRecord>>(emptyList())
    private fun liveRows() = rows.value.filter { it.deletedAtMs == null }

    override suspend fun unlock(
        comboId: Int, source: ScanSource, assetId: String?, scanId: String?, nowMs: Long,
    ): Boolean {
        val existing = rows.value.firstOrNull { it.comboId == comboId }
        if (existing != null && existing.deletedAtMs == null) return false
        rows.value = if (existing != null) {
            // Restaurar un desbloqueo borrado, como en iOS.
            rows.value.map {
                if (it.comboId == comboId) {
                    it.copy(
                        firstSeenAtMs = nowMs, source = source, assetId = assetId,
                        scanId = scanId, deletedAtMs = null,
                    ).touched(nowMs)
                } else {
                    it
                }
            }
        } else {
            rows.value + UnlockRecord(
                comboId = comboId, firstSeenAtMs = nowMs, source = source,
                assetId = assetId, scanId = scanId, updatedAtMs = nowMs,
            )
        }
        return true
    }

    override suspend fun unlock(
        comboIds: List<Int>, source: ScanSource, assetId: String?, scanId: String?, nowMs: Long,
    ): List<Int> = comboIds.filter { unlock(it, source, assetId, scanId, nowMs) }

    // Solo desbloqueos vivos, como en iOS.
    override suspend fun record(comboId: Int) =
        rows.value.firstOrNull { it.comboId == comboId && it.deletedAtMs == null }
    override suspend fun isUnlocked(comboId: Int) = liveRows().any { it.comboId == comboId }
    override suspend fun all() = liveRows().sortedBy { it.comboId }
    override suspend fun unlockedIds() = liveRows().map { it.comboId }.toSet()
    override suspend fun count() = liveRows().size

    // Borrado físico, como en iOS.
    override suspend fun deleteAll(source: ScanSource?) {
        rows.value = rows.value.filterNot { source == null || it.source == source }
    }

    override fun observeAll(): Flow<List<UnlockRecord>> =
        rows.map { all ->
            all.filter { it.deletedAtMs == null }.sortedBy { it.comboId }
        }

    override fun observeUnlockedIds(): Flow<Set<Int>> =
        rows.map { all ->
            all.filter { it.deletedAtMs == null }.map { it.comboId }.toSet()
        }

    override fun observeCount(): Flow<Int> =
        rows.map { all -> all.count { it.deletedAtMs == null } }
}

class InMemoryFeedbackRepository : FeedbackRepository {
    private val rows = MutableStateFlow<List<FeedbackRecord>>(emptyList())
    private fun liveRows() = rows.value.filter { it.deletedAtMs == null }

    override suspend fun record(scanId: String, verdict: FeedbackVerdict, nowMs: Long): FeedbackRecord {
        val record = FeedbackRecord(
            id = UuidV7.string(nowMs), scanId = scanId, verdict = verdict,
            createdAtMs = nowMs, updatedAtMs = nowMs,
        )
        rows.value = rows.value + record
        return record
    }

    // Más reciente primero, como en iOS.
    override suspend fun forScan(id: String) =
        liveRows().filter { it.scanId == id }.sortedByDescending { it.createdAtMs }

    override suspend fun latest(forScanId: String) = forScan(forScanId).firstOrNull()
    override suspend fun all() = liveRows().sortedByDescending { it.createdAtMs }
    override suspend fun counts(): Pair<Int, Int> {
        val all = liveRows()
        return all.count { it.verdict == FeedbackVerdict.YES } to all.count { it.verdict == FeedbackVerdict.NO }
    }

    override fun observeLatest(forScanId: String): Flow<FeedbackRecord?> =
        rows.map { all ->
            all.filter { it.deletedAtMs == null && it.scanId == forScanId }.maxByOrNull { it.createdAtMs }
        }
}

class InMemorySettingsRepository : SettingsRepository {
    private val rows = MutableStateFlow<Map<String, String>>(emptyMap())

    override suspend fun get(key: SettingsRepository.Key) = rows.value[key.raw]

    override suspend fun set(key: SettingsRepository.Key, value: String?, nowMs: Long) {
        rows.value = if (value == null) rows.value - key.raw else rows.value + (key.raw to value)
    }

    override fun observe(key: SettingsRepository.Key): Flow<String?> =
        rows.map { it[key.raw] }
}
