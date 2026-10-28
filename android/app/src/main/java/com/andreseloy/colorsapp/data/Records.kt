// Registros persistidos: espejo de ios/ColorsApp/DB/Records.swift con los
// mismos nombres de columna snake_case. La ola 2 los mapea a entidades Room
// con el esquema idéntico al de GRDB (migraciones v1–v4, ver
// docs/ANDROID.md §Base de datos). Fechas como milisegundos epoch (Room las
// guarda como INTEGER; GRDB usa texto ISO: la BD no se comparte entre
// plataformas y el contrato es de columnas y semántica, no de fichero).
package com.andreseloy.colorsapp.data

/** Origen de un scan (ScanSource; valor guardado en scans.source). */
enum class ScanSource(val raw: String) {
    CAMERA("camera"), PICKER("picker"), LIBRARY("library"), MANUAL("manual");

    companion object {
        fun fromRaw(raw: String?): ScanSource = entries.firstOrNull { it.raw == raw } ?: MANUAL
    }
}

/** Veredicto del feedback (columna feedback.verdict con CHECK yes|no). */
enum class FeedbackVerdict(val raw: String) {
    YES("yes"), NO("no"),
}

/** Entrada de paleta tal como viaja en scans.palette_json (PaletteEntry). */
data class PaletteEntry(
    val hex: String,
    val rgb: List<Int>,
    val lab: List<Double>,
    val weight: Double,
)

/** Entrada de prenda en scans.garments_json (GarmentEntry). */
data class GarmentEntry(
    val hex: String,
    val rgb: List<Int>,
    val lab: List<Double>,
    val weight: Double,
    val region: Int,
    val regionShare: Double,
    val mergedClusters: Int,
)

/** Fila de `scans` (v1 + columnas nullable de v2/v3/v4). */
data class ScanRecord(
    val id: String,
    /** MediaStore id / content Uri en Android (asset_local_id en iOS). */
    val assetId: String?,
    val source: ScanSource,
    val top1: Int?,
    val top2: Int?,
    val top3: Int?,
    /** JSON compacto [Double] (columna scores). */
    val scoresJson: String = "[]",
    /** JSON compacto [PaletteEntry] (columna palette_json). */
    val paletteJson: String = "[]",
    val ambiguous: Boolean = false,
    val engineVersion: String,
    val dictVersion: String,
    val scannedAtMs: Long,
    val updatedAtMs: Long,
    val deletedAtMs: Long? = null,
    val rev: Int = 1,
    val dirty: Boolean = true,
    // v2: recorte de sujeto
    val subjectMode: String? = null,
    val regionMode: String? = null,
    val adaptiveSkin: Boolean? = null,
    val peopleCount: Int? = null,
    val personIndex: Int? = null,
    /** JSON [MaskStep.raw] (columna mask_steps). */
    val maskStepsJson: String? = null,
    val maskCoverage: Double? = null,
    // v3/v4: prendas y política de análisis
    val garmentsJson: String? = null,
    val garmentRegions: Int? = null,
    val enginePolicyVersion: Int? = null,
) {
    val topIds: List<Int> get() = listOfNotNull(top1, top2, top3)
}

/** Fila de `unlocks` (clave primaria combo_id). */
data class UnlockRecord(
    val comboId: Int,
    val firstSeenAtMs: Long,
    val source: ScanSource,
    val assetId: String? = null,
    val scanId: String? = null,
    val updatedAtMs: Long,
    val deletedAtMs: Long? = null,
    val rev: Int = 1,
    val dirty: Boolean = true,
)

/** Fila de `feedback`. */
data class FeedbackRecord(
    val id: String,
    val scanId: String,
    val verdict: FeedbackVerdict,
    val createdAtMs: Long,
    val updatedAtMs: Long,
    val deletedAtMs: Long? = null,
    val rev: Int = 1,
    val dirty: Boolean = true,
)

/** Fila de `settings` (clave/valor texto). */
data class SettingRecord(
    val key: String,
    val value: String,
    val updatedAtMs: Long,
    val deletedAtMs: Long? = null,
    val rev: Int = 1,
    val dirty: Boolean = true,
)
