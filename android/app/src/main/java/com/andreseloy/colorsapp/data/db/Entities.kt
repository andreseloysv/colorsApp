// Entidades Room de las cuatro tablas: mismo esquema que GRDB en
// ios/ColorsApp/DB/AppDatabase.swift (v1 + columnas de v2 y v4), mismos
// nombres de tabla y columna snake_case. Diferencia documentada en
// docs/ANDROID.md §6: las fechas son INTEGER epoch ms (GRDB guarda texto);
// la BD no se comparte entre plataformas. El CHECK (yes|no) de
// feedback.verdict no se puede declarar en una entidad Room: lo garantiza
// el enum FeedbackVerdict en la capa Kotlin.
package com.andreseloy.colorsapp.data.db

import androidx.room.ColumnInfo
import androidx.room.Entity
import androidx.room.Index
import androidx.room.PrimaryKey
import com.andreseloy.colorsapp.data.FeedbackRecord
import com.andreseloy.colorsapp.data.FeedbackVerdict
import com.andreseloy.colorsapp.data.ScanRecord
import com.andreseloy.colorsapp.data.ScanSource
import com.andreseloy.colorsapp.data.SettingRecord
import com.andreseloy.colorsapp.data.UnlockRecord

@Entity(
    tableName = "scans",
    indices = [Index(value = ["scanned_at"]), Index(value = ["asset_local_id"])],
)
data class ScanEntity(
    @PrimaryKey val id: String,
    @ColumnInfo(name = "asset_local_id") val assetLocalId: String?,
    val source: String,
    val top1: Int?,
    val top2: Int?,
    val top3: Int?,
    @ColumnInfo(defaultValue = "[]") val scores: String,
    @ColumnInfo(name = "palette_json", defaultValue = "[]") val paletteJson: String,
    @ColumnInfo(defaultValue = "0") val ambiguous: Boolean,
    @ColumnInfo(name = "engine_version") val engineVersion: String,
    @ColumnInfo(name = "dict_version") val dictVersion: String,
    @ColumnInfo(name = "scanned_at") val scannedAt: Long,
    @ColumnInfo(name = "updated_at") val updatedAt: Long,
    @ColumnInfo(name = "deleted_at") val deletedAt: Long?,
    @ColumnInfo(defaultValue = "1") val rev: Int,
    @ColumnInfo(defaultValue = "1") val dirty: Boolean,
    // v2: recorte de sujeto
    @ColumnInfo(name = "subject_mode") val subjectMode: String? = null,
    @ColumnInfo(name = "region_mode") val regionMode: String? = null,
    @ColumnInfo(name = "adaptive_skin") val adaptiveSkin: Boolean? = null,
    @ColumnInfo(name = "people_count") val peopleCount: Int? = null,
    @ColumnInfo(name = "person_index") val personIndex: Int? = null,
    @ColumnInfo(name = "mask_steps") val maskSteps: String? = null,
    @ColumnInfo(name = "mask_coverage") val maskCoverage: Double? = null,
    // v4: paleta por prenda y política de análisis
    @ColumnInfo(name = "garments_json") val garmentsJson: String? = null,
    @ColumnInfo(name = "garment_regions") val garmentRegions: Int? = null,
    @ColumnInfo(name = "engine_policy_version") val enginePolicyVersion: Int? = null,
)

@Entity(tableName = "unlocks")
data class UnlockEntity(
    @PrimaryKey @ColumnInfo(name = "combo_id") val comboId: Int,
    @ColumnInfo(name = "first_seen_at") val firstSeenAt: Long,
    val source: String,
    @ColumnInfo(name = "asset_local_id") val assetLocalId: String?,
    @ColumnInfo(name = "scan_id") val scanId: String?,
    @ColumnInfo(name = "updated_at") val updatedAt: Long,
    @ColumnInfo(name = "deleted_at") val deletedAt: Long?,
    @ColumnInfo(defaultValue = "1") val rev: Int,
    @ColumnInfo(defaultValue = "1") val dirty: Boolean,
)

@Entity(tableName = "feedback", indices = [Index(value = ["scan_id"])])
data class FeedbackEntity(
    @PrimaryKey val id: String,
    @ColumnInfo(name = "scan_id") val scanId: String,
    val verdict: String,
    @ColumnInfo(name = "created_at") val createdAt: Long,
    @ColumnInfo(name = "updated_at") val updatedAt: Long,
    @ColumnInfo(name = "deleted_at") val deletedAt: Long?,
    @ColumnInfo(defaultValue = "1") val rev: Int,
    @ColumnInfo(defaultValue = "1") val dirty: Boolean,
)

@Entity(tableName = "settings")
data class SettingEntity(
    @PrimaryKey val key: String,
    val value: String,
    @ColumnInfo(name = "updated_at") val updatedAt: Long,
    @ColumnInfo(name = "deleted_at") val deletedAt: Long?,
    @ColumnInfo(defaultValue = "1") val rev: Int,
    @ColumnInfo(defaultValue = "1") val dirty: Boolean,
)

/* Mapeo entidad <-> registro de dominio (Records.kt). */

fun ScanEntity.toRecord(): ScanRecord = ScanRecord(
    id = id, assetId = assetLocalId, source = ScanSource.fromRaw(source),
    top1 = top1, top2 = top2, top3 = top3, scoresJson = scores, paletteJson = paletteJson,
    ambiguous = ambiguous, engineVersion = engineVersion, dictVersion = dictVersion,
    scannedAtMs = scannedAt, updatedAtMs = updatedAt, deletedAtMs = deletedAt,
    rev = rev, dirty = dirty, subjectMode = subjectMode, regionMode = regionMode,
    adaptiveSkin = adaptiveSkin, peopleCount = peopleCount, personIndex = personIndex,
    maskStepsJson = maskSteps, maskCoverage = maskCoverage, garmentsJson = garmentsJson,
    garmentRegions = garmentRegions, enginePolicyVersion = enginePolicyVersion,
)

fun ScanRecord.toEntity(): ScanEntity = ScanEntity(
    id = id, assetLocalId = assetId, source = source.raw, top1 = top1, top2 = top2, top3 = top3,
    scores = scoresJson, paletteJson = paletteJson, ambiguous = ambiguous,
    engineVersion = engineVersion, dictVersion = dictVersion, scannedAt = scannedAtMs,
    updatedAt = updatedAtMs, deletedAt = deletedAtMs, rev = rev, dirty = dirty,
    subjectMode = subjectMode, regionMode = regionMode, adaptiveSkin = adaptiveSkin,
    peopleCount = peopleCount, personIndex = personIndex, maskSteps = maskStepsJson,
    maskCoverage = maskCoverage, garmentsJson = garmentsJson,
    garmentRegions = garmentRegions, enginePolicyVersion = enginePolicyVersion,
)

fun UnlockEntity.toRecord(): UnlockRecord = UnlockRecord(
    comboId = comboId, firstSeenAtMs = firstSeenAt, source = ScanSource.fromRaw(source),
    assetId = assetLocalId, scanId = scanId, updatedAtMs = updatedAt,
    deletedAtMs = deletedAt, rev = rev, dirty = dirty,
)

fun UnlockRecord.toEntity(): UnlockEntity = UnlockEntity(
    comboId = comboId, firstSeenAt = firstSeenAtMs, source = source.raw,
    assetLocalId = assetId, scanId = scanId, updatedAt = updatedAtMs,
    deletedAt = deletedAtMs, rev = rev, dirty = dirty,
)

fun FeedbackEntity.toRecord(): FeedbackRecord = FeedbackRecord(
    id = id, scanId = scanId,
    verdict = FeedbackVerdict.entries.firstOrNull { it.raw == verdict } ?: FeedbackVerdict.NO,
    createdAtMs = createdAt, updatedAtMs = updatedAt, deletedAtMs = deletedAt,
    rev = rev, dirty = dirty,
)

fun FeedbackRecord.toEntity(): FeedbackEntity = FeedbackEntity(
    id = id, scanId = scanId, verdict = verdict.raw, createdAt = createdAtMs,
    updatedAt = updatedAtMs, deletedAt = deletedAtMs, rev = rev, dirty = dirty,
)

fun SettingEntity.toRecord(): SettingRecord = SettingRecord(
    key = key, value = value, updatedAtMs = updatedAt, deletedAtMs = deletedAt,
    rev = rev, dirty = dirty,
)

fun SettingRecord.toEntity(): SettingEntity = SettingEntity(
    key = key, value = value, updatedAt = updatedAtMs, deletedAt = deletedAtMs,
    rev = rev, dirty = dirty,
)
