// Diccionario de Sanzo Wada para la UI: espejo de
// ios/ColorsApp/Model/WadaDictionary.swift. En esta fundación los datos salen
// del motor C (colores, nombres Ridgway y combinaciones embebidos) y los
// nombres curados llegan por un mapa inyectado; la ola 2 añade la carga de
// dictionary.json + names.{es,de}.json (con el campo collection y los cmyk)
// con la misma interfaz y la comprobación dict_version == motor.
package com.andreseloy.colorsapp.data

import com.andreseloy.colorsapp.engine.WadaEngineDictionary
import com.andreseloy.colorsapp.engine.dictionaryVersion

/** Un color del diccionario (WadaColor de iOS, sin cmyk/swatch hasta tener el JSON). */
data class WadaColor(
    val index: Int,
    val name: String,
    val rgb: IntArray,
) {
    /** "#rrggbb" en minúsculas: formato sobre el rgb del motor, sin conversión. */
    val hex: String get() = "#%02x%02x%02x".format(rgb[0], rgb[1], rgb[2])
    val argb: Int get() = (0xFF shl 24) or (rgb[0] shl 16) or (rgb[1] shl 8) or rgb[2]

    override fun equals(other: Any?): Boolean =
        other is WadaColor && index == other.index && name == other.name && rgb.contentEquals(other.rgb)

    override fun hashCode(): Int = 31 * index + name.hashCode()
}

/** Una combinación (1..348): índices de color ascendentes. */
data class WadaCombo(val id: Int, val colors: IntArray) {
    val size: Int get() = colors.size

    override fun equals(other: Any?): Boolean =
        other is WadaCombo && id == other.id && colors.contentEquals(other.colors)

    override fun hashCode(): Int = id
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
