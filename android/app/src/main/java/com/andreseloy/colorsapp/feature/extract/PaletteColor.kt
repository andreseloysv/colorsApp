// Color de DATOS para la interfaz de W3: espejo de PaletteColor y
// DesignFormat de ios/ColorsApp/Design/PaletteColor.swift. Sin logica de
// color en Kotlin: el nombre de Wada mas cercano y su ΔE00 vienen del motor
// (WadaEngineDictionary.nearestColor sobre el Lab del propio motor).
package com.andreseloy.colorsapp.feature.extract

import com.andreseloy.colorsapp.data.WadaColor
import com.andreseloy.colorsapp.data.WadaDictionary
import com.andreseloy.colorsapp.engine.ColorMath
import com.andreseloy.colorsapp.engine.Swatch
import com.andreseloy.colorsapp.engine.WadaEngineDictionary
import java.text.NumberFormat
import java.util.Locale
import kotlin.math.roundToInt

/** Un color que pinta la UI: sRGB8 + nombre + peso + ΔE al color nombrado. */
data class PaletteColor(
    val id: Int,
    val r: Int,
    val g: Int,
    val b: Int,
    val name: String? = null,
    val weight: Double? = null,
    val deltaE: Double? = null,
) {
    /** "#RRGGBB" en mayusculas, como se muestra y se copia en iOS. */
    // Hex = dato legible por máquina: siempre Locale.ROOT (sin dígitos locales).
    val hex: String get() = String.format(Locale.ROOT, "#%02X%02X%02X", r, g, b)
    val argb: Int get() = (0xFF shl 24) or (r shl 16) or (g shl 8) or b

    companion object {
        /** Desde "#rrggbb"; null si el hex no es valido (como el init? de iOS). */
        fun fromHex(
            id: Int, hex: String, name: String? = null, weight: Double? = null,
        ): PaletteColor? {
            val digits = hex.removePrefix("#")
            if (digits.length != 6) return null
            val v = digits.toIntOrNull(16) ?: return null
            return PaletteColor(id, (v shr 16) and 0xFF, (v shr 8) and 0xFF, v and 0xFF, name, weight)
        }

        /** Color de Wada tal cual (nombre Ridgway del diccionario). */
        fun fromWada(id: Int, color: WadaColor): PaletteColor =
            PaletteColor(id, color.rgb[0], color.rgb[1], color.rgb[2], name = color.name)

        /** Swatch del motor nombrado con el color de Wada mas cercano (motor). */
        fun fromSwatch(id: Int, swatch: Swatch, dictionary: WadaDictionary?): PaletteColor {
            var out = PaletteColor(id, swatch.r, swatch.g, swatch.b, weight = swatch.weight)
            if (dictionary != null) {
                val (index, de) = WadaEngineDictionary.nearestColor(swatch.lab)
                out = out.copy(name = dictionary.color(index)?.name, deltaE = de)
            }
            return out
        }

        /** Colores de una combinacion en el orden del diccionario. */
        fun combo(comboId: Int, dictionary: WadaDictionary): List<PaletteColor> =
            dictionary.colorsOf(comboId).mapIndexed { i, c -> fromWada(i, c) }
    }

    /** Nombra el color con el color de Wada mas cercano segun el motor. */
    fun namedByNearestWada(dictionary: WadaDictionary): PaletteColor {
        val lab = ColorMath.srgbToLab(r, g, b)
        val (index, de) = WadaEngineDictionary.nearestColor(lab)
        return copy(name = dictionary.color(index)?.name, deltaE = de)
    }
}

/** Formatos numericos de DesignFormat/SubjectExplanation (idioma del sistema). */
object W3Format {
    /** 0,392 -> 39 (el % y el texto los pone el recurso localizado). */
    fun percentInt(weight: Double): Int = (weight * 100).roundToInt()

    /** Fraccion con [digits] decimales y coma/punto del idioma: 0,036 -> "3,6". */
    fun percentValue(fraction: Double, digits: Int, locale: Locale): String =
        number(fraction * 100, digits, locale)

    /** Numero con [digits] decimales fijos en el idioma dado (2,34 / 2.34). */
    fun number(value: Double, digits: Int, locale: Locale): String {
        val format = NumberFormat.getNumberInstance(locale)
        format.minimumFractionDigits = digits
        format.maximumFractionDigits = digits
        format.isGroupingUsed = false
        return format.format(value)
    }

    /** Score del match con 2 decimales (19,56 en es). */
    fun score(value: Double, locale: Locale): String = number(value, 2, locale)

    /** Valor ΔE con 1 decimal (el "ΔE " lo pone el recurso). */
    fun deltaEValue(value: Double, locale: Locale): String = number(value, 1, locale)

    /** Hex separados por espacios (lo que copia «Copiar hex»). */
    fun hexList(colors: List<PaletteColor>): String = colors.joinToString(" ") { it.hex }

    /** Id de combinacion con tres cifras: 67 -> "067" (el «Nº» es recurso). */
    fun paddedComboId(id: Int): String = String.format(Locale.ROOT, "%03d", id)
}
