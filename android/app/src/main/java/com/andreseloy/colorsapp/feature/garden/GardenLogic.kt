// Lógica pura del Jardín: espejo de GardenModel/GardenText de iOS
// (colecciones por tamaño, acierto del feedback, colores frecuentes y
// exportación). Sin Android: probada en JVM.
package com.andreseloy.colorsapp.feature.garden

import com.andreseloy.colorsapp.data.FeedbackVerdict
import com.andreseloy.colorsapp.data.ScanRecord
import com.andreseloy.colorsapp.data.UnlockRecord
import com.andreseloy.colorsapp.data.WadaDictionary

data class SizeCollection(val size: Int, val unlocked: Int, val total: Int) {
    val fraction: Double get() = if (total > 0) unlocked.toDouble() / total else 0.0
}

object GardenLogic {
    fun sizeCollections(dictionary: WadaDictionary, unlocks: List<UnlockRecord>): List<SizeCollection> {
        val ids = unlocks.map { it.comboId }.toSet()
        return listOf(2, 3, 4).map { size ->
            val combos = dictionary.combinations.filter { it.size == size }
            SizeCollection(size, combos.count { it.id in ids }, combos.size)
        }
    }

    /** (sí, total) del último veredicto por scan, como GardenText. */
    fun accuracy(latestVerdicts: Collection<FeedbackVerdict>): Pair<Int, Int> =
        latestVerdicts.count { it == FeedbackVerdict.YES } to latestVerdicts.size

    fun accuracyText(yes: Int, total: Int): String? =
        if (total == 0) null else "${(100.0 * yes / total).toInt()} %"

    /** Colores más frecuentes entre las combinaciones desbloqueadas. */
    fun topColors(dictionary: WadaDictionary, unlockedIds: Set<Int>, limit: Int = 8): List<Pair<Int, Int>> {
        val counts = HashMap<Int, Int>()
        for (id in unlockedIds) dictionary.combo(id)?.colors?.forEach { counts[it] = (counts[it] ?: 0) + 1 }
        return counts.entries.sortedWith(compareByDescending<Map.Entry<Int, Int>> { it.value }.thenBy { it.key })
            .take(limit).map { it.key to it.value }
    }

    fun collectionJson(dictionary: WadaDictionary, unlocks: List<UnlockRecord>): String = buildString {
        append("{\"dict_version\":\"").append(dictionary.dictVersion).append("\",\"unlocked\":[")
        unlocks.sortedBy { it.comboId }.forEachIndexed { i, u ->
            if (i > 0) append(",")
            val colors = dictionary.colorsOf(u.comboId)
            append("{\"id\":").append(u.comboId)
            append(",\"name\":\"").append((dictionary.curatedName(u.comboId) ?: "").replace("\"", "'")).append("\"")
            append(",\"first_seen_ms\":").append(u.firstSeenAtMs)
            append(",\"source\":\"").append(u.source.raw).append("\"")
            append(",\"colors\":[")
            colors.forEachIndexed { j, c ->
                if (j > 0) append(",")
                append("{\"index\":").append(c.index).append(",\"name\":\"").append(c.name.replace("\"", "'"))
                    .append("\",\"hex\":\"").append(c.hex).append("\"}")
            }
            append("]}")
        }
        append("]}")
    }

    fun harvestsCsv(scans: List<ScanRecord>): String = buildString {
        appendLine("scan_id,scanned_at_ms,source,top1,top2,top3,ambiguous")
        for (s in scans) appendLine("${s.id},${s.scannedAtMs},${s.source.raw},${s.top1 ?: ""},${s.top2 ?: ""},${s.top3 ?: ""},${s.ambiguous}")
    }
}
