// «Guardar» del Feed y de Resultado: espejo de GardenStore de iOS
// (Views/Garden/GardenStore.swift). Mismo fichero y formato: garden.json con
// {"items":[{"id":…,"kind":"scan|combo","savedAt":ISO8601}],"version":1}
// en filesDir, para que el Jardin de W4 lea exactamente lo mismo que iOS
// escribe en Application Support. Solo lo que W3 necesita (guardar scans y
// quitarlos al borrar); las colecciones del Jardin son de W4.
package com.andreseloy.colorsapp.feature.feed

import android.content.Context
import com.andreseloy.colorsapp.feature.extract.ScanJson
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import java.io.File
import java.time.Instant
import java.time.ZoneOffset
import java.time.format.DateTimeFormatter

class GardenSavedStore(context: Context) {

    data class Item(val kind: String, val id: String, val savedAtMs: Long) {
        val key: String get() = "$kind:$id"
    }

    private val file = File(context.applicationContext.filesDir, FILE_NAME)

    private val _items = MutableStateFlow(load(file))
    val items: StateFlow<List<Item>> = _items

    val savedScanIds: Set<String>
        get() = _items.value.filter { it.kind == KIND_SCAN }.map { it.id }.toSet()

    fun isSaved(scanId: String): Boolean =
        _items.value.any { it.kind == KIND_SCAN && it.id == scanId }

    /** Guarda o quita un analisis. Devuelve true si queda guardado. */
    fun toggle(scanId: String, nowMs: Long = System.currentTimeMillis()): Boolean {
        val item = Item(KIND_SCAN, scanId, nowMs)
        val current = _items.value
        _items.value = if (current.any { it.key == item.key }) {
            current.filterNot { it.key == item.key }
        } else {
            (listOf(item) + current).sortedByDescending { it.savedAtMs }
        }
        persist()
        return _items.value.any { it.key == item.key }
    }

    fun remove(scanId: String) {
        _items.value = _items.value.filterNot { it.kind == KIND_SCAN && it.id == scanId }
        persist()
    }

    /** Quita los analisis que ya no existen (al borrar del Feed, como iOS). */
    fun prune(liveScanIds: Set<String>) {
        val next = _items.value.filterNot { it.kind == KIND_SCAN && it.id !in liveScanIds }
        if (next.size != _items.value.size) {
            _items.value = next
            persist()
        }
    }

    private fun persist() {
        runCatching {
            file.parentFile?.mkdirs()
            val tmp = File(file.parentFile, "$FILE_NAME.tmp")
            tmp.writeText(encode(_items.value))
            if (!tmp.renameTo(file)) {
                file.writeText(encode(_items.value))
                tmp.delete()
            }
        }
    }

    companion object {
        @Volatile
        private var instance: GardenSavedStore? = null

        /** Instancia compartida del proceso (GardenStore.shared de iOS). */
        fun getInstance(context: Context): GardenSavedStore =
            instance ?: synchronized(this) {
                instance ?: GardenSavedStore(context).also { instance = it }
            }

        const val FILE_NAME = "garden.json"
        const val FORMAT_VERSION = 1
        const val KIND_SCAN = "scan"
        const val KIND_COMBO = "combo"

        private val iso: DateTimeFormatter =
            DateTimeFormatter.ofPattern("yyyy-MM-dd'T'HH:mm:ss'Z'").withZone(ZoneOffset.UTC)

        /** Codifica con claves ordenadas, como el JSONEncoder de iOS. */
        fun encode(items: List<Item>): String = buildString {
            append("{\n  \"items\" : [")
            items.forEachIndexed { i, item ->
                if (i > 0) append(',')
                append("\n    {\n      \"id\" : \"").append(ScanJson.escapeString(item.id))
                append("\",\n      \"kind\" : \"").append(ScanJson.escapeString(item.kind))
                append("\",\n      \"savedAt\" : \"")
                append(iso.format(Instant.ofEpochMilli(item.savedAtMs)))
                append("\"\n    }")
            }
            append(if (items.isEmpty()) "],\n  \"version\" : 1\n}" else "\n  ],\n  \"version\" : 1\n}")
        }

        fun decode(json: String): List<Item> {
            val root = ScanJson.parseAnyOrNull(json) as? Map<*, *> ?: return emptyList()
            val rows = root["items"] as? List<*> ?: return emptyList()
            return rows.mapNotNull { row ->
                val m = row as? Map<*, *> ?: return@mapNotNull null
                val kind = m["kind"] as? String ?: return@mapNotNull null
                val id = m["id"] as? String ?: return@mapNotNull null
                val savedAt = (m["savedAt"] as? String)?.let {
                    runCatching { Instant.parse(it).toEpochMilli() }.getOrNull()
                        ?: runCatching {
                            // ISO8601 de Foundation puede venir sin fraccion y con Z.
                            Instant.from(iso.parse(it)).toEpochMilli()
                        }.getOrDefault(0L)
                } ?: 0L
                Item(kind, id, savedAt)
            }.sortedByDescending { it.savedAtMs }
        }

        private fun load(file: File): List<Item> =
            runCatching { decode(file.readText()) }.getOrDefault(emptyList())
    }
}
