// Diccionario de Sanzo Wada desde los assets: espejo de la carga de
// ios/ColorsApp/Model/WadaDictionary.swift. Lee wada/dictionary.json
// (159 colores, 348 combinaciones, solo sRGB8) y los nombres curados del
// idioma de la interfaz: alemán -> names.de.json; español e inglés ->
// names.es.json (los nombres se curan en español o alemán, nunca en
// inglés; en la interfaz en inglés se muestran los españoles como nombres
// propios). Los assets los genera la tarea Gradle syncWadaAssets desde
// data/wada sin duplicarlos en git. La versión del JSON se cruza con la
// del motor (ce_dict_version()): si difieren, el match y las fichas
// hablarían de diccionarios distintos y la carga falla.
package com.andreseloy.colorsapp.data

import android.content.Context
import com.andreseloy.colorsapp.engine.dictionaryVersion
import java.io.IOException
import java.util.Locale
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.intOrNull

/** Entrada de names.{es,de}.json (curación del usuario; solo lectura). */
data class WadaName(
    val id: Int,
    val lang: String,
    val name: String,
    val notes: String,
    val status: String,
) {
    /** Nombre curado y aceptado por el usuario; null si sigue pendiente o vacío. */
    val acceptedName: String?
        get() = name.trim().takeIf { status == ACCEPTED_STATUS && it.isNotEmpty() }

    companion object {
        const val ACCEPTED_STATUS = "accepted"
    }
}

/** Errores de carga del diccionario, como WadaDictionaryError en iOS. */
sealed class WadaDictionaryException(message: String) : Exception(message) {
    class ResourceMissing(val resource: String) :
        WadaDictionaryException("falta el recurso del diccionario: $resource")

    class VersionMismatch(val bundle: String, val engine: String) :
        WadaDictionaryException("dict_version $bundle != motor $engine")

    class UnexpectedCounts(val colors: Int, val combinations: Int) :
        WadaDictionaryException("recuentos del diccionario: $colors colores, $combinations combinaciones")

    class Malformed(reason: String) : WadaDictionaryException("diccionario mal formado: $reason")
}

/**
 * Diccionario completo e inmutable cargado del JSON, con la misma interfaz
 * que EngineWadaDictionary. Se construye una vez en AppContainer.
 */
class JsonWadaDictionary(
    override val schema: Int,
    override val source: String,
    override val dictVersion: String,
    override val status: String,
    override val colors: List<WadaColor>,
    override val combinations: List<WadaCombo>,
    names: List<WadaName>,
    private val engineDictVersion: String,
) : WadaDictionary {

    /** Nombres del fichero de curación indexados por id (el último gana). */
    val names: Map<Int, WadaName> = names.associateBy { it.id }

    private val comboPosition: Map<Int, Int> =
        combinations.mapIndexed { i, c -> c.id to i }.toMap()
    private val colorPosition: Map<Int, Int> =
        colors.mapIndexed { i, c -> c.index to i }.toMap()

    override val matchesEngine: Boolean get() = dictVersion == engineDictVersion

    override fun combo(id: Int): WadaCombo? = comboPosition[id]?.let { combinations[it] }

    override fun color(index: Int): WadaColor? = colorPosition[index]?.let { colors[it] }

    override fun curatedName(id: Int): String? = names[id]?.acceptedName

    fun checkEngineVersion() {
        if (!matchesEngine) throw WadaDictionaryException.VersionMismatch(dictVersion, engineDictVersion)
    }

    fun checkCounts() {
        if (colors.size != EXPECTED_COLOR_COUNT || combinations.size != EXPECTED_COMBO_COUNT) {
            throw WadaDictionaryException.UnexpectedCounts(colors.size, combinations.size)
        }
    }

    companion object {
        const val ASSET_DIRECTORY = "wada"
        const val DICTIONARY_ASSET = "dictionary.json"
        const val SOURCE_NAMES_ASSET = "names.es.json"
        const val GERMAN_NAMES_ASSET = "names.de.json"
        const val EXPECTED_COLOR_COUNT = 159
        const val EXPECTED_COMBO_COUNT = 348

        /**
         * Fichero de nombres de una localización: alemán -> names.de.json;
         * el resto (español e inglés incluidos) -> names.es.json, como
         * `WadaDictionary.namesResource(forLocalization:)` en iOS.
         */
        fun namesAssetFor(languageTag: String?): String {
            val code = (languageTag ?: "es").lowercase(Locale.ROOT)
            return if (code == "de" || code.startsWith("de-") || code.startsWith("de_")) {
                GERMAN_NAMES_ASSET
            } else {
                SOURCE_NAMES_ASSET
            }
        }

        fun namesAssetFor(locale: Locale?): String = namesAssetFor(locale?.language)

        /**
         * Decodifica dictionary.json y, si llega, el fichero de nombres
         * (sin nombres todo cae al "Nº 012"). No comprueba recuentos ni la
         * versión del motor: ver checkCounts/checkEngineVersion. Puro: la
         * versión del motor se inyecta para probarlo sin el JNI.
         */
        fun decode(
            dictionaryJson: String,
            namesJson: String?,
            engineDictVersion: String,
        ): JsonWadaDictionary {
            val root = parseObject(dictionaryJson, "dictionary.json")
            val colors = (root["colors"] as? JsonArray
                ?: throw WadaDictionaryException.Malformed("sin lista colors")).map { el ->
                val o = el as? JsonObject ?: throw WadaDictionaryException.Malformed("color no objeto")
                WadaColor(
                    index = o.requiredInt("index"),
                    name = o.requiredString("name"),
                    rgb = o.requiredIntArray("rgb"),
                    cmyk = o.requiredIntArray("cmyk"),
                    swatch = o.requiredInt("swatch"),
                )
            }
            val combinations = (root["combinations"] as? JsonArray
                ?: throw WadaDictionaryException.Malformed("sin lista combinations")).map { el ->
                val o = el as? JsonObject
                    ?: throw WadaDictionaryException.Malformed("combinación no objeto")
                WadaCombo(
                    id = o.requiredInt("id"),
                    colors = o.requiredIntArray("colors"),
                    collection = (o["collection"] as? JsonPrimitive)
                        ?.takeIf { it.isString }?.content,
                )
            }
            val names = namesJson?.let { decodeNames(it) } ?: emptyList()
            return JsonWadaDictionary(
                schema = root.requiredInt("schema"),
                source = root.requiredString("source"),
                dictVersion = root.requiredString("dict_version"),
                status = root.requiredString("status"),
                colors = colors,
                combinations = combinations,
                names = names,
                engineDictVersion = engineDictVersion,
            )
        }

        /** Decodifica la lista de nombres curados ([WadaName]). */
        fun decodeNames(namesJson: String): List<WadaName> {
            val array = runCatching { Json.parseToJsonElement(namesJson) }.getOrNull() as? JsonArray
                ?: throw WadaDictionaryException.Malformed("nombres: se esperaba una lista")
            return array.map { el ->
                val o = el as? JsonObject
                    ?: throw WadaDictionaryException.Malformed("nombre no objeto")
                WadaName(
                    id = o.requiredInt("id"),
                    lang = o.requiredString("lang"),
                    name = o.requiredString("name"),
                    notes = o.requiredString("notes"),
                    status = o.requiredString("status"),
                )
            }
        }

        /**
         * Carga desde los assets (wada/dictionary.json + nombres del
         * idioma) y comprueba recuentos y versión del motor. Como en iOS:
         * si falta el fichero de nombres del idioma se usan los del fuente
         * (es); si también falta ese, es un recurso ausente.
         */
        fun load(
            context: Context,
            locale: Locale? = context.resources.configuration.locales[0],
            engineDictVersion: String = dictionaryVersion,
        ): JsonWadaDictionary {
            val assets = context.assets
            val dictionaryJson = readAsset(assets, DICTIONARY_ASSET)
                ?: throw WadaDictionaryException.ResourceMissing(DICTIONARY_ASSET)
            val localized = namesAssetFor(locale)
            val namesJson = readAsset(assets, localized) ?: readAsset(assets, SOURCE_NAMES_ASSET)
                ?: throw WadaDictionaryException.ResourceMissing(SOURCE_NAMES_ASSET)
            val dict = decode(dictionaryJson, namesJson, engineDictVersion)
            dict.checkCounts()
            dict.checkEngineVersion()
            return dict
        }

        private fun readAsset(assets: android.content.res.AssetManager, name: String): String? =
            try {
                assets.open("$ASSET_DIRECTORY/$name").bufferedReader(Charsets.UTF_8).use { it.readText() }
            } catch (_: IOException) {
                null
            }

        private fun parseObject(text: String, what: String): JsonObject =
            runCatching { Json.parseToJsonElement(text) }.getOrNull() as? JsonObject
                ?: throw WadaDictionaryException.Malformed("$what no es un objeto JSON")

        private fun JsonObject.requiredString(key: String): String =
            (this[key] as? JsonPrimitive)?.takeIf { it.isString }?.content
                ?: throw WadaDictionaryException.Malformed("falta la clave $key")

        private fun JsonObject.requiredInt(key: String): Int =
            (this[key] as? JsonPrimitive)?.intOrNull
                ?: throw WadaDictionaryException.Malformed("falta la clave $key")

        private fun JsonObject.requiredIntArray(key: String): IntArray {
            val array = this[key] as? JsonArray
                ?: throw WadaDictionaryException.Malformed("falta la lista $key")
            return IntArray(array.size) { i ->
                (array[i] as? JsonPrimitive)?.intOrNull
                    ?: throw WadaDictionaryException.Malformed("$key[$i] no es entero")
            }
        }
    }
}
