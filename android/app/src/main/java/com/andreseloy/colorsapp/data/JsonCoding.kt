// Codificación JSON compacta y determinista para las columnas `scores`,
// `palette_json`, `garments_json` y `mask_steps`: espejo de `JSONCoding`
// en ios/ColorsApp/DB/Records.swift. Las claves van ordenadas (sortedKeys)
// para que un volcado de diagnóstico se lea igual en las dos plataformas
// (docs/ANDROID.md §7); los Double enteros se escriben sin decimales, como
// hace JSONEncoder en iOS (2.0 -> "2"). La decodificación usa
// kotlinx-serialization y devuelve null / lista vacía si el JSON no vale,
// igual que el `try?` de Swift.
package com.andreseloy.colorsapp.data

import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.doubleOrNull
import kotlinx.serialization.json.intOrNull

object JsonCoding {
    private val json = Json { ignoreUnknownKeys = true }

    // MARK: Codificación (orden de claves alfabético, sin espacios)

    fun encodeScores(scores: List<Double>): String =
        scores.joinToString(prefix = "[", postfix = "]", separator = ",") { formatDouble(it) }

    fun encodeStrings(values: List<String>): String =
        values.joinToString(prefix = "[", postfix = "]", separator = ",") { quote(it) }

    fun encodePalette(entries: List<PaletteEntry>): String =
        entries.joinToString(prefix = "[", postfix = "]", separator = ",") { e ->
            // Claves ordenadas: hex, lab, rgb, weight.
            "{\"hex\":${quote(e.hex)},\"lab\":${encodeScores(e.lab)}," +
                "\"rgb\":${e.rgb.joinToString(prefix = "[", postfix = "]", separator = ",")}," +
                "\"weight\":${formatDouble(e.weight)}}"
        }

    fun encodeGarments(entries: List<GarmentEntry>): String =
        entries.joinToString(prefix = "[", postfix = "]", separator = ",") { e ->
            // Claves ordenadas: hex, lab, mergedClusters, region,
            // regionShare, rgb, weight.
            "{\"hex\":${quote(e.hex)},\"lab\":${encodeScores(e.lab)}," +
                "\"mergedClusters\":${e.mergedClusters},\"region\":${e.region}," +
                "\"regionShare\":${formatDouble(e.regionShare)}," +
                "\"rgb\":${e.rgb.joinToString(prefix = "[", postfix = "]", separator = ",")}," +
                "\"weight\":${formatDouble(e.weight)}}"
        }

    // MARK: Decodificación (null / vacío si el JSON no es válido)

    fun decodeScores(value: String): List<Double> = runCatching {
        parseArray(value).map { (it as? JsonPrimitive)?.doubleOrNull ?: return emptyList() }
    }.getOrDefault(emptyList())

    fun decodeStrings(value: String): List<String> = runCatching {
        parseArray(value).map { (it as? JsonPrimitive)?.takeIf { p -> p.isString }?.content ?: return emptyList() }
    }.getOrDefault(emptyList())

    fun decodePalette(value: String): List<PaletteEntry> = runCatching {
        parseArray(value).map { el ->
            val o = el as? JsonObject ?: return emptyList()
            PaletteEntry(
                hex = o.string("hex") ?: return emptyList(),
                rgb = o.intList("rgb") ?: return emptyList(),
                lab = o.doubleList("lab") ?: return emptyList(),
                weight = o.double("weight") ?: return emptyList(),
            )
        }
    }.getOrDefault(emptyList())

    fun decodeGarments(value: String?): List<GarmentEntry> {
        if (value == null) return emptyList()
        return runCatching {
            parseArray(value).map { el ->
                val o = el as? JsonObject ?: return emptyList()
                GarmentEntry(
                    hex = o.string("hex") ?: return emptyList(),
                    rgb = o.intList("rgb") ?: return emptyList(),
                    lab = o.doubleList("lab") ?: return emptyList(),
                    weight = o.double("weight") ?: return emptyList(),
                    region = o.int("region") ?: return emptyList(),
                    regionShare = o.double("regionShare") ?: return emptyList(),
                    mergedClusters = o.int("mergedClusters") ?: return emptyList(),
                )
            }
        }.getOrDefault(emptyList())
    }

    // MARK: Utilidades

    internal fun parseArray(value: String): JsonArray =
        json.parseToJsonElement(value) as? JsonArray
            ?: throw IllegalArgumentException("se esperaba un array JSON")

    private fun JsonObject.string(key: String): String? =
        (this[key] as? JsonPrimitive)?.takeIf { it.isString }?.content

    private fun JsonObject.double(key: String): Double? =
        (this[key] as? JsonPrimitive)?.doubleOrNull

    private fun JsonObject.int(key: String): Int? =
        (this[key] as? JsonPrimitive)?.intOrNull

    private fun JsonObject.intList(key: String): List<Int>? =
        (this[key] as? JsonArray)?.map { (it as? JsonPrimitive)?.intOrNull ?: return null }

    private fun JsonObject.doubleList(key: String): List<Double>? =
        (this[key] as? JsonArray)?.map { (it as? JsonPrimitive)?.doubleOrNull ?: return null }

    /** Double como JSONEncoder: entero sin decimales; el resto, la forma corta. */
    fun formatDouble(value: Double): String {
        require(value.isFinite()) { "Double no finito en JSON: $value" }
        return if (value == value.toLong().toDouble() && kotlin.math.abs(value) < 1e15) {
            value.toLong().toString()
        } else {
            value.toString()
        }
    }

    private fun quote(value: String): String = buildString {
        append('"')
        for (c in value) {
            when (c) {
                '"' -> append("\\\"")
                '\\' -> append("\\\\")
                '\n' -> append("\\n")
                '\r' -> append("\\r")
                '\t' -> append("\\t")
                else -> if (c < ' ') append("\\u%04x".format(c.code)) else append(c)
            }
        }
        append('"')
    }
}
