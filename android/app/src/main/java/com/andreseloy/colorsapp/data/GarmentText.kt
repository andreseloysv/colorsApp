// Textos de la paleta POR PRENDA: espejo de
// ios/ColorsApp/Model/GarmentText.swift. Un único sitio para el nombre de
// cada región (1 arriba, 2 abajo, 3 prenda entera, como GarmentRegion del
// motor), para que el Feed, Extraer, la tarjeta compartible y el inspector
// de capas digan lo mismo. En Android el texto vive en recursos
// (strings_w1.xml): aquí solo se elige el recurso; sin lógica de color.
package com.andreseloy.colorsapp.data

import androidx.annotation.StringRes
import com.andreseloy.colorsapp.R
import com.andreseloy.colorsapp.engine.GarmentRegion

object GarmentText {
    /** Etiqueta larga de la tarjeta («Parte de arriba»…). El else cubre los
     *  valores futuros del motor, como el `default` de iOS. */
    @StringRes
    fun regionLabelRes(region: Int): Int = when (region) {
        GarmentRegion.UPPER.code -> R.string.w1_garment_region_upper
        GarmentRegion.LOWER.code -> R.string.w1_garment_region_lower
        GarmentRegion.WHOLE.code -> R.string.w1_garment_region_whole
        else -> R.string.w1_garment_region_other
    }

    @StringRes
    fun regionLabelRes(region: GarmentRegion): Int = regionLabelRes(region.code)

    /** Etiqueta corta para las gotas del Feed y la tarjeta compartible («Arriba»…). */
    @StringRes
    fun shortRegionLabelRes(region: Int): Int = when (region) {
        GarmentRegion.UPPER.code -> R.string.w1_garment_short_upper
        GarmentRegion.LOWER.code -> R.string.w1_garment_short_lower
        GarmentRegion.WHOLE.code -> R.string.w1_garment_region_whole
        else -> R.string.w1_garment_region_other
    }

    @StringRes
    fun shortRegionLabelRes(region: GarmentRegion): Int = shortRegionLabelRes(region.code)

    /**
     * Por qué el motor juntó varios tonos en un color. Con
     * [mergedClusters] > 1 el recurso lleva un %1$d con el recuento (una
     * sola clave: el orden de las frases cambia entre idiomas).
     */
    @StringRes
    fun groupingReasonRes(mergedClusters: Int): Int =
        if (mergedClusters > 1) R.string.w1_garment_grouping_merged
        else R.string.w1_garment_grouping_single
}

/** Etiqueta de región de una entrada guardada (GarmentEntry.regionLabel en iOS). */
@StringRes
fun GarmentEntry.regionLabelRes(): Int = GarmentText.regionLabelRes(region)

/** Etiqueta corta de una entrada guardada (GarmentEntry.shortRegionLabel en iOS). */
@StringRes
fun GarmentEntry.shortRegionLabelRes(): Int = GarmentText.shortRegionLabelRes(region)

/** Parsea "#rrggbb" o "rrggbb" a (r, g, b) 0..255; null si no es válido.
 *  Espejo de parseHexRGB en ios/ColorsApp/Model/Color+Wada.swift: solo
 *  conversión de representación, sin lógica de color. */
fun parseHexRGB(hex: String): IntArray? {
    var s = hex.trim()
    if (s.startsWith("#")) s = s.substring(1)
    if (s.length != 6) return null
    val v = s.toIntOrNull(16) ?: return null
    return intArrayOf((v shr 16) and 0xFF, (v shr 8) and 0xFF, v and 0xFF)
}
