// Contrato del escaneo del carrete: espejo de ios/ColorsApp/Scan/ScanRunning.swift.
// La implementación real de la ola 2 usa MediaStore (versión Android del
// PhotoKitScanRunner); NoopScanRunner queda para tests y previews.
package com.andreseloy.colorsapp.scan

/** Progreso del escaneo; AppContainer lo publica para la UI. */
data class ScanProgress(
    val phase: Phase = Phase.IDLE,
    val processed: Int = 0,
    val total: Int = 0,
    val skipped: Int = 0,
    val unlocked: Int = 0,
    val startedAtMs: Long? = null,
) {
    enum class Phase { IDLE, REQUESTING_ACCESS, FETCHING, ANALYZING, FINISHED, FAILED }

    val fraction: Double get() = if (total > 0) processed.toDouble() / total else 0.0

    companion object {
        val IDLE = ScanProgress()
    }
}

data class ComboCount(val comboId: Int, val count: Int)

data class ColorCount(val colorIndex: Int, val count: Int)

/** Resumen del escaneo del carrete (ScanSummary de iOS). */
data class ScanSummary(
    val scanned: Int,
    val skipped: Int,
    val failed: Int,
    val newUnlocks: List<Int>,
    val totalUnlocked: Int,
    val topCombos: List<ComboCount>,
    val startedAtMs: Long,
    val finishedAtMs: Long,
    val topColors: List<ColorCount> = emptyList(),
    val signatureColorIndex: Int? = null,
    /** Acceso limitado a fotos: la UI debe ofrecer el selector de fotos. */
    val needsPicker: Boolean = false,
) {
    val durationMs: Long get() = finishedAtMs - startedAtMs

    companion object {
        fun empty(
            needsPicker: Boolean = false, totalUnlocked: Int = 0,
            nowMs: Long = System.currentTimeMillis(),
        ) = ScanSummary(
            scanned = 0, skipped = 0, failed = 0, newUnlocks = emptyList(),
            totalUnlocked = totalUnlocked, topCombos = emptyList(),
            startedAtMs = nowMs, finishedAtMs = nowMs, needsPicker = needsPicker,
        )
    }
}

sealed class ScanException(message: String) : Exception(message) {
    class NotImplemented : ScanException("notImplemented")
    class AccessDenied : ScanException("accessDenied")
    class LimitedAccess : ScanException("limitedAccess")
    class Cancelled : ScanException("cancelled")
}

/** Ejecuta el escaneo del carrete (ScanRunning de iOS). */
interface ScanRunning {
    val progress: ScanProgress
    var onProgress: ((ScanProgress) -> Unit)?

    /** Analiza las últimas [limit] fotos y registra scans y unlocks. */
    suspend fun runInitialScan(limit: Int = 200): ScanSummary
}

/** Runner inerte (tests, previews): no escanea nada. */
class NoopScanRunner : ScanRunning {
    override var progress: ScanProgress = ScanProgress.IDLE
        private set
    override var onProgress: ((ScanProgress) -> Unit)? = null

    override suspend fun runInitialScan(limit: Int): ScanSummary {
        progress = ScanProgress(phase = ScanProgress.Phase.FAILED)
        onProgress?.invoke(progress)
        throw ScanException.NotImplemented()
    }
}
