// Diagnósticos de W4: espejo de ios/ColorsApp/Support/Diagnostics*.swift.
// Construye el zip (resumen.txt, scans.csv, feedback.csv) solo cuando el
// usuario pulsa «Exportar diagnóstico»; ninguna foto sale del teléfono
// salvo las que el usuario decida compartir. Lógica pura, sin Android,
// para poder probarla en JVM; la escritura y el Intent viven en Ajustes.
package com.andreseloy.colorsapp.data

import java.io.ByteArrayOutputStream
import java.util.zip.ZipEntry
import java.util.zip.ZipOutputStream

/** Datos que entran en el zip (Diagnostics.swift + DiagnosticsZip.swift). */
data class DiagnosticsSnapshot(
    val appVersion: String,
    val appBuild: String,
    val engineVersion: String,
    val dictVersion: String,
    val launches: Int,
    val comboCount: Int,
    val colorCount: Int,
    val unlockedCount: Int,
    val scanCount: Int,
    val feedbackYes: Int,
    val feedbackNo: Int,
    val scans: List<ScanRecord>,
    val feedback: List<FeedbackRecord>,
    val subjectMode: String,
    val regionMode: String,
    val adaptiveSkin: Boolean,
    val unlockMaxScore: Double,
    val extraFiles: Map<String, ByteArray> = emptyMap(),
)

object Diagnostics {
    /** Nombre del fichero, como DiagnosticsZip.fileName en iOS. */
    fun fileName(nowMs: Long): String = "chromasol-diagnostics-$nowMs.zip"

    fun summaryText(s: DiagnosticsSnapshot): String = buildString {
        appendLine("ChromaSol diagnostics")
        appendLine("app=${s.appVersion} (${s.appBuild})")
        appendLine("engine=${s.engineVersion}")
        appendLine("dict=${s.dictVersion} combos=${s.comboCount} colors=${s.colorCount}")
        appendLine("launches=${s.launches} scans=${s.scanCount} unlocked=${s.unlockedCount}/${s.comboCount}")
        appendLine("feedback yes=${s.feedbackYes} no=${s.feedbackNo}")
        appendLine("subject mode=${s.subjectMode} region=${s.regionMode} adaptiveSkin=${s.adaptiveSkin} unlockMaxScore=${s.unlockMaxScore}")
        appendLine("files: resumen.txt, scans.csv, feedback.csv" + if (s.extraFiles.isEmpty()) "" else ", " + s.extraFiles.keys.sorted().joinToString(","))
    }

    private fun csvCell(v: String?): String {
        val t = v ?: ""
        return if (t.any { it == ',' || it == '"' || it == '\n' }) "\"" + t.replace("\"", "\"\"") + "\"" else t
    }

    fun scansCsv(scans: List<ScanRecord>): String = buildString {
        appendLine("id,asset_id,source,top1,top2,top3,ambiguous,engine,dict,scanned_at_ms,subject_mode,region_mode,people,mask_coverage")
        for (r in scans) {
            appendLine(listOf(r.id, r.assetId ?: "", r.source.raw, "${r.top1 ?: ""}", "${r.top2 ?: ""}", "${r.top3 ?: ""}", "${r.ambiguous}", r.engineVersion, r.dictVersion, "${r.scannedAtMs}", r.subjectMode ?: "", r.regionMode ?: "", "${r.peopleCount ?: ""}", "${r.maskCoverage ?: ""}").joinToString(",") { csvCell(it) })
        }
    }

    fun feedbackCsv(rows: List<FeedbackRecord>): String = buildString {
        appendLine("id,scan_id,verdict,created_at_ms")
        for (r in rows) appendLine(listOf(r.id, r.scanId, r.verdict.raw, "${r.createdAtMs}").joinToString(",") { csvCell(it) })
    }

    /** Zip completo en memoria (sin niveles de compresión imprevisibles). */
    fun buildZip(s: DiagnosticsSnapshot): ByteArray {
        val out = ByteArrayOutputStream()
        ZipOutputStream(out).use { zip ->
            fun put(name: String, bytes: ByteArray) {
                zip.putNextEntry(ZipEntry(name)); zip.write(bytes); zip.closeEntry()
            }
            put("resumen.txt", summaryText(s).toByteArray(Charsets.UTF_8))
            put("scans.csv", scansCsv(s.scans).toByteArray(Charsets.UTF_8))
            put("feedback.csv", feedbackCsv(s.feedback).toByteArray(Charsets.UTF_8))
            for ((name, bytes) in s.extraFiles.toSortedMap()) put(name, bytes)
        }
        return out.toByteArray()
    }
}

/** Resumen corto para la UI («Listo: …» de DiagnosticsExportAction). */
fun DiagnosticsSnapshot.shortSummary(): String =
    "scans=$scanCount unlocked=$unlockedCount/$comboCount feedback=${feedbackYes + feedbackNo}"
