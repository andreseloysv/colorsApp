// DAO de las cuatro tablas. Las consultas replican las de
// ios/ColorsApp/DB/Repositories.swift: las lecturas de la UI filtran los
// borrados suaves (deleted_at IS NULL) y ordenan igual que GRDB.
package com.andreseloy.colorsapp.data.db

import androidx.room.Dao
import androidx.room.Insert
import androidx.room.OnConflictStrategy
import androidx.room.Query
import androidx.room.Update
import kotlinx.coroutines.flow.Flow

@Dao
interface ScanDao {
    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun upsert(scan: ScanEntity)

    @Update
    suspend fun update(scan: ScanEntity)

    @Query("SELECT * FROM scans WHERE id = :id")
    suspend fun fetch(id: String): ScanEntity?

    @Query(
        "SELECT * FROM scans WHERE deleted_at IS NULL " +
            "ORDER BY scanned_at DESC LIMIT :limit",
    )
    suspend fun recent(limit: Int): List<ScanEntity>

    @Query(
        "SELECT * FROM scans WHERE deleted_at IS NULL AND top1 = :comboId " +
            "ORDER BY scanned_at DESC LIMIT :limit",
    )
    suspend fun withTop1(comboId: Int, limit: Int): List<ScanEntity>

    @Query("SELECT * FROM scans WHERE deleted_at IS NULL ORDER BY scanned_at DESC")
    suspend fun liveByRecency(): List<ScanEntity>

    @Query("SELECT COUNT(*) FROM scans WHERE deleted_at IS NULL")
    suspend fun liveCount(): Int

    @Query("DELETE FROM scans WHERE source = :source")
    suspend fun deleteAll(source: String)

    @Query(
        "SELECT * FROM scans WHERE deleted_at IS NULL " +
            "ORDER BY scanned_at DESC LIMIT :limit",
    )
    fun observeRecent(limit: Int): Flow<List<ScanEntity>>
}

@Dao
interface UnlockDao {
    @Insert(onConflict = OnConflictStrategy.ABORT)
    suspend fun insert(unlock: UnlockEntity)

    @Update
    suspend fun update(unlock: UnlockEntity)

    @Query("SELECT * FROM unlocks WHERE combo_id = :comboId")
    suspend fun fetchAny(comboId: Int): UnlockEntity?

    @Query("SELECT * FROM unlocks WHERE combo_id = :comboId AND deleted_at IS NULL")
    suspend fun fetchLive(comboId: Int): UnlockEntity?

    @Query("SELECT * FROM unlocks WHERE deleted_at IS NULL ORDER BY combo_id ASC")
    suspend fun liveAll(): List<UnlockEntity>

    @Query("SELECT COUNT(*) FROM unlocks WHERE deleted_at IS NULL")
    suspend fun liveCount(): Int

    @Query("DELETE FROM unlocks WHERE source = :source")
    suspend fun deleteBySource(source: String)

    @Query("DELETE FROM unlocks")
    suspend fun deleteEverything()

    @Query("SELECT * FROM unlocks WHERE deleted_at IS NULL ORDER BY combo_id ASC")
    fun observeLiveAll(): Flow<List<UnlockEntity>>
}

@Dao
interface FeedbackDao {
    @Insert(onConflict = OnConflictStrategy.ABORT)
    suspend fun insert(feedback: FeedbackEntity)

    @Query(
        "SELECT * FROM feedback WHERE scan_id = :scanId AND deleted_at IS NULL " +
            "ORDER BY created_at DESC",
    )
    suspend fun forScan(scanId: String): List<FeedbackEntity>

    @Query("SELECT * FROM feedback WHERE deleted_at IS NULL ORDER BY created_at DESC")
    suspend fun liveAll(): List<FeedbackEntity>

    @Query("SELECT COUNT(*) FROM feedback WHERE verdict = :verdict AND deleted_at IS NULL")
    suspend fun liveCount(verdict: String): Int

    @Query(
        "SELECT * FROM feedback WHERE scan_id = :scanId AND deleted_at IS NULL " +
            "ORDER BY created_at DESC LIMIT 1",
    )
    fun observeLatest(scanId: String): Flow<FeedbackEntity?>
}

@Dao
interface SettingDao {
    @Insert(onConflict = OnConflictStrategy.ABORT)
    suspend fun insert(setting: SettingEntity)

    @Update
    suspend fun update(setting: SettingEntity)

    @Query("SELECT * FROM settings WHERE `key` = :key")
    suspend fun fetchAny(key: String): SettingEntity?

    @Query("SELECT value FROM settings WHERE `key` = :key AND deleted_at IS NULL")
    suspend fun fetchLiveValue(key: String): String?

    @Query("SELECT value FROM settings WHERE `key` = :key AND deleted_at IS NULL")
    fun observeLiveValue(key: String): Flow<String?>
}
