// Diccionario de Sanzo Wada para la UI: espejo de
// ios/ColorsApp/Model/WadaDictionary.swift. La implementación de producción
// es JsonWadaDictionary (dictionary.json + names.{es,de}.json desde los
// assets generados, con cmyk/collection y chequeo dict_version == motor);
// EngineWadaDictionary lee lo embebido en el motor C y se queda para tests
// y previews sin assets.
package com.andreseloy.colorsapp.data

import com.andreseloy.colorsapp.engine.WadaEngineDictionary
import com.andreseloy.colorsapp.engine.dictionaryVersion

/**
 * Un color del diccionario (WadaColor de iOS). `cmyk` y `swatch` vienen de
 * dictionary.json; desde el motor (EngineWadaDictionary) quedan en su valor
 * por defecto porque el C solo embebe sRGB8 y el nombre Ridgway.
 */
data class WadaColor(
    val index: Int,
    val name: String,
    val rgb: IntArray,
    val cmyk: IntArray = intArrayOf(0, 0, 0, 0),
    val swatch: Int = 0,
) {
    /** "#rrggbb" en minúsculas: formato sobre el rgb, sin conversión. */
    val hex: String get() = "#%02x%02x%02x".format(rgb[0], rgb[1], rgb[2])
    val argb: Int get() = (0xFF shl 24) or (rgb[0] shl 16) or (rgb[1] shl 8) or rgb[2]

    override fun equals(other: Any?): Boolean =
        other is WadaColor && index == other.index && name == other.name &&
            rgb.contentEquals(other.rgb) && cmyk.contentEquals(other.cmyk) && swatch == other.swatch

    override fun hashCode(): Int = 31 * index + name.hashCode()
}

/**
 * Una combinación (1..348): índices de color ascendentes. `collection` es
 * la colección curada del JSON (null hasta que el usuario la nombre).
 */
data class WadaCombo(val id: Int, val colors: IntArray, val collection: String? = null) {
    val size: Int get() = colors.size

    override fun equals(other: Any?): Boolean =
        other is WadaCombo && id == other.id && colors.contentEquals(other.colors) &&
            collection == other.collection

    override fun hashCode(): Int = id
}

/**
 * Colección para explorar (WadaCollection de iOS): curada (campo
 * `collection` de las combinaciones) o automática por tamaño (2, 3 y 4).
 */
data class WadaCollection(
    val id: String,
    val title: String,
    val kind: Kind,
    val comboIds: List<Int>,
) {
    sealed interface Kind {
        data class BySize(val size: Int) : Kind
        data class Curated(val name: String) : Kind
    }
}

/**
 * Acceso al diccionario para las vistas. displayName = nombre curado (es/de,
 * status accepted) si lo hay; si no, "Nº 012" — en Android el formato del
 * número debe salir de una string localizada (la pone la vista); aquí el
 * proveedor de formato se inyecta para no acoplar datos con recursos.
 */
interface WadaDictionary {
    val dictVersion: String
    val colors: List<WadaColor>
    val combinations: List<WadaCombo>

    /** Metadatos de dictionary.json (desde el motor: los valores por defecto). */
    val schema: Int get() = 1
    val source: String get() = ""
    val status: String get() = ""

    /** true si la versión coincide con la embebida en el motor. */
    val matchesEngine: Boolean get() = dictVersion == dictionaryVersion

    fun combo(id: Int): WadaCombo? = combinations.firstOrNull { it.id == id }
    fun color(index: Int): WadaColor? = colors.getOrNull(index)
    fun colorsOf(comboId: Int): List<WadaColor> =
        combo(comboId)?.colors?.toList()?.mapNotNull { color(it) } ?: emptyList()

    fun combosContaining(colorIndex: Int): List<WadaCombo> =
        combinations.filter { colorIndex in it.colors }

    /** Nombre curado aceptado del idioma actual; null si no lo hay. */
    fun curatedName(id: Int): String?

    /**
     * Nombre para la UI: el curado si está aceptado, si no el número que
     * formatee [numberLabel] ("Nº 012"). La vista pasa su formato localizado
     * (R.string.w1_combo_number con el id a tres cifras); por defecto se usa
     * el formato del idioma fuente, como `displayName` en iOS.
     */
    fun displayName(id: Int, numberLabel: (Int) -> String = DEFAULT_NUMBER_LABEL): String =
        curatedName(id) ?: numberLabel(id)

    /**
     * Colecciones curadas (orden alfabético) seguidas de las automáticas por
     * tamaño. El título por tamaño sale de [sizeTitle]; por defecto el
     * texto del idioma fuente, como el literal de iOS ("Combinaciones de
     * N colores"); la vista puede pasar su string localizada
     * (R.string.w1_collection_by_size).
     */
    fun collections(sizeTitle: (Int) -> String = { size -> "Combinaciones de $size colores" }):
        List<WadaCollection> {
        val curated = linkedMapOf<String, MutableList<Int>>()
        for (combo in combinations) {
            val name = combo.collection?.takeIf { it.isNotEmpty() } ?: continue
            curated.getOrPut(name) { mutableListOf() }.add(combo.id)
        }
        val curatedCollections = curated.keys.sorted().map { name ->
            WadaCollection(
                id = "curated:$name", title = name,
                kind = WadaCollection.Kind.Curated(name), comboIds = curated[name].orEmpty(),
            )
        }
        return curatedCollections + collectionsBySize(sizeTitle)
    }

    /** Colecciones automáticas para cada tamaño presente (2, 3, 4). */
    fun collectionsBySize(sizeTitle: (Int) -> String = { size -> "Combinaciones de $size colores" }):
        List<WadaCollection> =
        combinations.map { it.size }.toSortedSet().map { size ->
            WadaCollection(
                id = "size:$size", title = sizeTitle(size),
                kind = WadaCollection.Kind.BySize(size),
                comboIds = combinations.filter { it.size == size }.map { it.id },
            )
        }

    companion object {
        /** "Nº 012" (tres dígitos, ordinal º): el formato del idioma fuente. */
        val DEFAULT_NUMBER_LABEL: (Int) -> String = { id -> "Nº %03d".format(id) }
    }
}

/**
 * Implementación de la fundación: todo desde el motor C (la misma fuente que
 * puntúa), con los nombres curados del idioma dados por [curatedNames]
 * (vacío hasta cargar names.{es,de}.json en la ola 2).
 */
class EngineWadaDictionary(
    private val curatedNames: Map<Int, String> = emptyMap(),
) : WadaDictionary {
    override val dictVersion: String = dictionaryVersion

    override val colors: List<WadaColor> by lazy {
        (0 until WadaEngineDictionary.colorCount).mapNotNull { i ->
            val rgb = WadaEngineDictionary.colorRgb(i) ?: return@mapNotNull null
            WadaColor(i, WadaEngineDictionary.colorName(i) ?: "", rgb)
        }
    }

    override val combinations: List<WadaCombo> by lazy {
        (1..WadaEngineDictionary.comboCount).mapNotNull { id ->
            WadaEngineDictionary.combo(id)?.let { WadaCombo(id, it) }
        }
    }

    override fun curatedName(id: Int): String? =
        curatedNames[id]?.trim()?.takeIf { it.isNotEmpty() }
}
