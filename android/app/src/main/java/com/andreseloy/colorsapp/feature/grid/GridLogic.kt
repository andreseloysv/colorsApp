// Lógica pura de la Rejilla: espejo de RejillaSearch.swift y RejillaModel.swift.
// Sin Android ni motor: el hex se clasifica aquí y lo resuelve la vista con
// ColorMath/WadaEngineDictionary (motor C), como hace ColorSearch en iOS.
package com.andreseloy.colorsapp.feature.grid

import com.andreseloy.colorsapp.data.WadaCombo
import com.andreseloy.colorsapp.data.WadaDictionary
import java.text.Normalizer
import kotlin.random.Random

enum class StatusFilter { UNLOCKED, LOCKED }

sealed interface GridQuery {
    data object Empty : GridQuery
    data class Number(val id: Int) : GridQuery
    data class NumberOutOfRange(val n: Int) : GridQuery
    /** Hex normalizado "#RRGGBB" pendiente de resolver con el motor. */
    data class Hex(val normalized: String) : GridQuery
    data class Text(val folded: String) : GridQuery
}

object GridSearch {
    private val numberRe = Regex("""^\s*(?:[nN][º°oO.]?\s*)?(\d{1,3})\s*$""")
    private val hexRe = Regex("""^\s*#?([0-9a-fA-F]{6})\s*$""")

    fun numberValue(text: String): Int? = numberRe.matchEntire(text)?.groupValues?.getOrNull(1)?.toIntOrNull()
    fun normalizedHex(text: String): String? = hexRe.matchEntire(text)?.groupValues?.getOrNull(1)?.let { "#" + it.uppercase() }
    fun parseHexRgb(normalized: String): IntArray? {
        val d = normalized.removePrefix("#")
        if (d.length != 6) return null
        return runCatching { intArrayOf(d.substring(0, 2).toInt(16), d.substring(2, 4).toInt(16), d.substring(4, 6).toInt(16)) }.getOrNull()
    }

    fun fold(text: String): String =
        Normalizer.normalize(text.lowercase(), Normalizer.Form.NFD)
            .replace(Regex("\\p{Mn}+"), "")
            .split(Regex("\\s+")).filter { it.isNotEmpty() }.joinToString(" ")

    /** Hex gana a número, como en iOS. */
    fun interpret(raw: String, count: Int): GridQuery {
        val t = raw.trim()
        if (t.isEmpty()) return GridQuery.Empty
        normalizedHex(t)?.let { return GridQuery.Hex(it) }
        numberValue(t)?.let { return if (it in 1..maxOf(count, 1)) GridQuery.Number(it) else GridQuery.NumberOutOfRange(it) }
        val f = fold(t)
        return if (f.isEmpty()) GridQuery.Empty else GridQuery.Text(f)
    }

    fun haystack(combo: WadaCombo, name: String, colorNames: List<String>): String =
        fold("$name | nº ${combo.id} | ${colorNames.joinToString(" | ")}")

    fun filter(combos: List<WadaCombo>, query: GridQuery, nearestColorIndex: Int?, haystacks: Map<Int, String>): List<WadaCombo> = when (query) {
        GridQuery.Empty -> combos
        is GridQuery.Number -> combos.filter { it.id == query.id }
        is GridQuery.NumberOutOfRange -> emptyList()
        is GridQuery.Hex -> if (nearestColorIndex == null) emptyList() else combos.filter { nearestColorIndex in it.colors }
        is GridQuery.Text -> combos.filter { haystacks[it.id]?.contains(query.folded) == true }
    }
}

object GridFilters {
    fun apply(combos: List<WadaCombo>, size: Int?, status: StatusFilter?, unlocked: Set<Int>): List<WadaCombo> =
        combos.filter { c ->
            (size == null || c.size == size) && when (status) {
                StatusFilter.UNLOCKED -> c.id in unlocked
                StatusFilter.LOCKED -> c.id !in unlocked
                null -> true
            }
        }

    fun sizeScope(dictionary: WadaDictionary, size: Int?): List<WadaCombo> =
        if (size == null) dictionary.combinations else dictionary.combinations.filter { it.size == size }

    fun unlockedInScope(dictionary: WadaDictionary, size: Int?, unlocked: Set<Int>): Int =
        sizeScope(dictionary, size).count { it.id in unlocked }

    /** Combinación al azar distinta de la actual (RejillaRandom de iOS). */
    fun nextRandom(after: Int?, total: Int, random: Random = Random.Default): Int {
        if (total <= 1) return 1
        var id = random.nextInt(1, total + 1)
        if (after != null && id == after) id = id % total + 1
        return id
    }
}
