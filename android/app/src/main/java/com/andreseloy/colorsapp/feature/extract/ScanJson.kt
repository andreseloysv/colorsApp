// JSON de las columnas de `scans` (scores, palette_json, garments_json,
// mask_steps): espejo de JSONCoding + PaletteEntry/GarmentEntry de
// ios/ColorsApp/DB/Records.swift. Compacto y con las claves ORDENADAS
// (.sortedKeys en iOS), para que un volcado de diagnostico se lea igual en
// las dos plataformas (docs/ANDROID.md §7). Parser minimo propio: el
// org.json de Android no existe en los tests JVM y aqui solo hacen falta
// arrays de objetos planos. Sin logica de color: solo serializa lo que el
// motor ya calculo.
package com.andreseloy.colorsapp.feature.extract

import com.andreseloy.colorsapp.data.GarmentEntry
import com.andreseloy.colorsapp.data.PaletteEntry
import com.andreseloy.colorsapp.data.ScanRecord
import com.andreseloy.colorsapp.data.ScanSource
import com.andreseloy.colorsapp.engine.AnalysisResult
import com.andreseloy.colorsapp.engine.GarmentSwatch
import com.andreseloy.colorsapp.engine.Swatch
import com.andreseloy.colorsapp.subject.MaskStep
import com.andreseloy.colorsapp.subject.RegionMode
import com.andreseloy.colorsapp.subject.SubjectMaskResult
import com.andreseloy.colorsapp.subject.SubjectOptions

/** Lo que se persiste del recorte de un scan (ScanSubjectInfo de iOS). */
data class ScanSubjectInfo(
    val modeRaw: String,
    val regionRaw: String,
    val adaptiveSkin: Boolean,
    val peopleCount: Int,
    val personIndex: Int?,
    val steps: List<MaskStep>,
    val maskCoverage: Double,
) {
    constructor(options: SubjectOptions, result: SubjectMaskResult) : this(
        modeRaw = options.mode.raw,
        regionRaw = options.region.raw,
        adaptiveSkin = options.adaptiveSkin,
        peopleCount = result.people.size,
        personIndex = result.chosenIndex,
        steps = result.steps,
        maskCoverage = result.maskCoverage,
    )
}

/** Prendas que se guardan en el scan (ScanGarmentInfo de iOS). */
data class ScanGarmentInfo(val garments: List<GarmentSwatch>, val regionCount: Int?)

object ScanJson {

    /* ---------------- Codificacion (claves ordenadas) ---------------- */

    private fun num(v: Double): String =
        if (v.isFinite()) v.toString() else "0"

    private fun esc(s: String): String = buildString {
        for (c in s) {
            when (c) {
                '"' -> append("\\\"")
                '\\' -> append("\\\\")
                '\n' -> append("\\n")
                '\r' -> append("\\r")
                '\t' -> append("\\t")
                else -> if (c.code < 0x20) append("\\u%04x".format(c.code)) else append(c)
            }
        }
    }

    fun encodeScores(scores: List<Double>): String =
        scores.joinToString(prefix = "[", postfix = "]", separator = ",") { num(it) }

    fun encodeSteps(steps: List<MaskStep>): String =
        steps.joinToString(prefix = "[", postfix = "]", separator = ",") { "\"${esc(it.raw)}\"" }

    fun paletteEntry(swatch: Swatch): PaletteEntry = PaletteEntry(
        hex = swatch.hex,
        rgb = listOf(swatch.r, swatch.g, swatch.b),
        lab = listOf(swatch.lab.l, swatch.lab.a, swatch.lab.b),
        weight = swatch.weight,
    )

    fun garmentEntry(garment: GarmentSwatch): GarmentEntry {
        val s = garment.swatch
        return GarmentEntry(
            hex = s.hex,
            rgb = listOf(s.r, s.g, s.b),
            lab = listOf(s.lab.l, s.lab.a, s.lab.b),
            weight = s.weight,
            region = garment.region.code,
            regionShare = garment.regionShare,
            mergedClusters = garment.mergedClusterCount,
        )
    }

    fun encodePalette(entries: List<PaletteEntry>): String = buildString {
        append('[')
        entries.forEachIndexed { i, e ->
            if (i > 0) append(',')
            append("{\"hex\":\"").append(esc(e.hex)).append("\",\"lab\":[")
            append(e.lab.joinToString(",") { num(it) })
            append("],\"rgb\":[").append(e.rgb.joinToString(","))
            append("],\"weight\":").append(num(e.weight)).append('}')
        }
        append(']')
    }

    fun encodeGarments(entries: List<GarmentEntry>): String = buildString {
        append('[')
        entries.forEachIndexed { i, e ->
            if (i > 0) append(',')
            append("{\"hex\":\"").append(esc(e.hex)).append("\",\"lab\":[")
            append(e.lab.joinToString(",") { num(it) })
            append("],\"mergedClusters\":").append(e.mergedClusters)
            append(",\"region\":").append(e.region)
            append(",\"regionShare\":").append(num(e.regionShare))
            append(",\"rgb\":[").append(e.rgb.joinToString(","))
            append("],\"weight\":").append(num(e.weight)).append('}')
        }
        append(']')
    }

    /* ---------------- Decodificacion ---------------- */

    /** Parser JSON minimo (objetos, arrays, strings, numeros, bool, null). */
    internal class Parser(private val text: String) {
        private var i = 0

        fun parse(): Any? {
            val v = value()
            ws()
            check(i == text.length) { "JSON con cola en $i" }
            return v
        }

        private fun ws() {
            while (i < text.length && text[i].isWhitespace()) i++
        }

        private fun value(): Any? {
            ws()
            check(i < text.length) { "JSON truncado" }
            return when (text[i]) {
                '{' -> obj()
                '[' -> arr()
                '"' -> str()
                't' -> lit("true", true)
                'f' -> lit("false", false)
                'n' -> lit("null", null)
                else -> number()
            }
        }

        private fun lit(word: String, v: Any?): Any? {
            check(text.startsWith(word, i)) { "literal JSON en $i" }
            i += word.length
            return v
        }

        private fun obj(): Map<String, Any?> {
            val out = LinkedHashMap<String, Any?>()
            i++
            ws()
            if (i < text.length && text[i] == '}') {
                i++
                return out
            }
            while (true) {
                ws()
                val k = str()
                ws()
                check(i < text.length && text[i] == ':') { "':' en $i" }
                i++
                out[k] = value()
                ws()
                check(i < text.length) { "objeto sin cerrar" }
                when (text[i]) {
                    ',' -> i++
                    '}' -> {
                        i++
                        return out
                    }
                    else -> error("objeto JSON en $i")
                }
            }
        }

        private fun arr(): List<Any?> {
            val out = mutableListOf<Any?>()
            i++
            ws()
            if (i < text.length && text[i] == ']') {
                i++
                return out
            }
            while (true) {
                out += value()
                ws()
                check(i < text.length) { "array sin cerrar" }
                when (text[i]) {
                    ',' -> i++
                    ']' -> {
                        i++
                        return out
                    }
                    else -> error("array JSON en $i")
                }
            }
        }

        private fun str(): String {
            check(i < text.length && text[i] == '"') { "string en $i" }
            i++
            val sb = StringBuilder()
            while (i < text.length) {
                val c = text[i++]
                when (c) {
                    '"' -> return sb.toString()
                    '\\' -> {
                        check(i < text.length) { "escape truncado" }
                        when (val e = text[i++]) {
                            '"' -> sb.append('"')
                            '\\' -> sb.append('\\')
                            '/' -> sb.append('/')
                            'b' -> sb.append('\b')
                            'f' -> sb.append('\u000C')
                            'n' -> sb.append('\n')
                            'r' -> sb.append('\r')
                            't' -> sb.append('\t')
                            'u' -> {
                                check(i + 4 <= text.length) { "unicode truncado" }
                                sb.append(text.substring(i, i + 4).toInt(16).toChar())
                                i += 4
                            }
                            else -> error("escape JSON \\$e")
                        }
                    }
                    else -> sb.append(c)
                }
            }
            error("string sin cerrar")
        }

        private fun number(): Double {
            val start = i
            if (i < text.length && text[i] == '-') i++
            while (i < text.length && (text[i].isDigit() || text[i] in ".eE+-")) i++
            check(i > start) { "numero en $start" }
            return text.substring(start, i).toDouble()
        }
    }

    private fun parseOrNull(json: String): Any? = runCatching { Parser(json).parse() }.getOrNull()

    /** Acceso del carril W3 al parser (garden.json del Feed). */
    internal fun parseAnyOrNull(json: String): Any? = parseOrNull(json)

    /** Escape de string JSON (garden.json). */
    internal fun escapeString(s: String): String = esc(s)

    @Suppress("UNCHECKED_CAST")
    private fun asList(v: Any?): List<Any?> = v as? List<Any?> ?: emptyList()

    @Suppress("UNCHECKED_CAST")
    private fun asMap(v: Any?): Map<String, Any?> = v as? Map<String, Any?> ?: emptyMap()

    private fun Map<String, Any?>.dbl(key: String): Double = (this[key] as? Number)?.toDouble() ?: 0.0
    private fun Map<String, Any?>.int(key: String): Int = (this[key] as? Number)?.toInt() ?: 0
    private fun Map<String, Any?>.strg(key: String): String = this[key] as? String ?: ""
    private fun Map<String, Any?>.dblList(key: String): List<Double> =
        asList(this[key]).map { (it as? Number)?.toDouble() ?: 0.0 }

    private fun Map<String, Any?>.intList(key: String): List<Int> =
        asList(this[key]).map { (it as? Number)?.toInt() ?: 0 }

    fun decodeScores(json: String): List<Double> =
        asList(parseOrNull(json)).map { (it as? Number)?.toDouble() ?: 0.0 }

    fun decodeSteps(json: String?): List<MaskStep> {
        if (json == null) return emptyList()
        return asList(parseOrNull(json)).mapNotNull { (it as? String)?.let(MaskStep::fromRaw) }
    }

    fun decodePalette(json: String): List<PaletteEntry> =
        asList(parseOrNull(json)).map {
            val m = asMap(it)
            PaletteEntry(m.strg("hex"), m.intList("rgb"), m.dblList("lab"), m.dbl("weight"))
        }

    fun decodeGarments(json: String?): List<GarmentEntry> {
        if (json == null) return emptyList()
        return asList(parseOrNull(json)).map {
            val m = asMap(it)
            GarmentEntry(
                m.strg("hex"), m.intList("rgb"), m.dblList("lab"), m.dbl("weight"),
                m.int("region"), m.dbl("regionShare"), m.int("mergedClusters"),
            )
        }
    }

    /* ---------------- ScanRecord.make / updated ---------------- */

    /**
     * Construye el registro desde el resultado del motor (ScanRecord.make de
     * iOS). [id] nuevo si no se pasa (el UUIDv7 canonico llega con W1; ver
     * ScanAnalyzer.newScanId).
     */
    fun makeRecord(
        id: String,
        result: AnalysisResult,
        source: ScanSource,
        assetId: String? = null,
        subject: ScanSubjectInfo? = null,
        garments: ScanGarmentInfo? = null,
        policyVersion: Int? = null,
        engineVersion: String,
        dictVersion: String,
        nowMs: Long,
    ): ScanRecord {
        val ids = result.hits.map { it.comboId }
        var record = ScanRecord(
            id = id,
            assetId = assetId,
            source = source,
            top1 = ids.getOrNull(0),
            top2 = ids.getOrNull(1),
            top3 = ids.getOrNull(2),
            scoresJson = encodeScores(result.hits.map { it.score }),
            paletteJson = encodePalette(result.swatches.map { paletteEntry(it) }),
            ambiguous = result.ambiguous,
            engineVersion = engineVersion,
            dictVersion = dictVersion,
            scannedAtMs = nowMs,
            updatedAtMs = nowMs,
        )
        if (subject != null) record = applySubject(record, subject)
        record = applyGarments(record, garments)
        return record.copy(enginePolicyVersion = policyVersion)
    }

    /** Sustituye resultado y recorte: mismo id/origen, rev + 1, dirty (iOS `updated`). */
    fun updatedRecord(
        old: ScanRecord,
        result: AnalysisResult,
        subject: ScanSubjectInfo?,
        garments: ScanGarmentInfo? = null,
        policyVersion: Int? = null,
        engineVersion: String = old.engineVersion,
        dictVersion: String = old.dictVersion,
        nowMs: Long,
    ): ScanRecord {
        val fresh = makeRecord(
            id = old.id, result = result, source = old.source, assetId = old.assetId,
            subject = subject, garments = garments, policyVersion = policyVersion,
            engineVersion = engineVersion, dictVersion = dictVersion, nowMs = old.scannedAtMs,
        )
        return fresh.copy(
            updatedAtMs = nowMs, deletedAtMs = old.deletedAtMs,
            rev = old.rev + 1, dirty = true,
        )
    }

    private fun applySubject(record: ScanRecord, subject: ScanSubjectInfo): ScanRecord =
        record.copy(
            subjectMode = subject.modeRaw,
            regionMode = subject.regionRaw,
            adaptiveSkin = subject.adaptiveSkin,
            peopleCount = subject.peopleCount,
            personIndex = subject.personIndex,
            maskStepsJson = encodeSteps(subject.steps),
            maskCoverage = subject.maskCoverage,
        )

    private fun applyGarments(record: ScanRecord, info: ScanGarmentInfo?): ScanRecord {
        if (info == null || info.garments.isEmpty()) {
            return record.copy(garmentsJson = null, garmentRegions = null)
        }
        return record.copy(
            garmentsJson = encodeGarments(info.garments.map { garmentEntry(it) }),
            garmentRegions = info.regionCount,
        )
    }
}

/** Version de la politica de analisis (AnalysisPolicy de iOS). */
object AnalysisPolicy {
    const val CURRENT = 1

    fun needsReanalysis(
        scan: ScanRecord,
        engineVersion: String,
        dictVersion: String,
        policyVersion: Int = CURRENT,
    ): Boolean {
        if (scan.source == ScanSource.MANUAL) return false
        val version = scan.enginePolicyVersion ?: return true
        return version != policyVersion ||
            scan.engineVersion != engineVersion || scan.dictVersion != dictVersion
    }
}

/** Region guardada de un scan como enum (null si el raw no se conoce). */
fun ScanRecord.regionModeOrNull(): RegionMode? =
    RegionMode.entries.firstOrNull { it.raw == regionMode }
