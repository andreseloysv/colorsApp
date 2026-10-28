// Forma, espacio y medidas: copia de ios/ColorsApp/Design/Metrics.swift.
// 1 pt de iOS = 1 dp aquí.
package com.andreseloy.colorsapp.design

import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.ui.unit.dp

/** Espaciados (Spacing de iOS). */
object SolarSpacing {
    val xs = 4.dp
    val sm = 8.dp
    val md = 12.dp
    val lg = 20.dp
    val xl = 32.dp

    /** Margen lateral de pantalla. */
    val margin = 16.dp

    /** Hueco de cuadrícula (Rejilla, prendas, estudio). */
    val gutter = 12.dp

    /** Relleno vertical de chips / botones secundarios / CTA. */
    val chipVertical = 6.dp
    val buttonVertical = 10.dp
    val ctaVertical = 14.dp

    /** Relleno mínimo del pocillo neutro (6 en la cuadrícula de la Rejilla). */
    val wellPadding = 8.dp
    val wellPaddingCompact = 6.dp

    /** Separación entre segmentos de una tira de color. */
    val swatchDivider = 2.dp
}

/** Radios de esquina (Radius de iOS). */
object SolarRadius {
    val tag = 4.dp
    val block = 8.dp
    val card = 12.dp
    val sheet = 24.dp

    val tagShape = RoundedCornerShape(tag)
    val blockShape = RoundedCornerShape(block)
    val cardShape = RoundedCornerShape(card)
}

/** Medidas recurrentes (Sizes de iOS). */
object SolarSizes {
    val header = 64.dp
    val headerButton = 44.dp
    val brandMark = 32.dp
    val avatar = 32.dp
    val sourceIcon = 36.dp
    val viewfinderMaxHeight = 400.dp
    val droplet = 44.dp
    val garmentBlock = 64.dp
    val dayRibbon = 24.dp
    val dayComposition = 260.dp
    val extractRibbon = 12.dp
    val harvestStrip = 32.dp
    val weightBar = 16.dp
    val randomTile = 48.dp
    val gridStripes = 112.dp
    val pinBead = 24.dp
    val harvestThumb = 48.dp
    val minTouch = 44.dp
    val tabBar = 64.dp
    val profileBadge = 56.dp

    /** Proporción admitida de la foto de una publicación: 4:5 … 4:3. */
    val postAspectRange: ClosedFloatingPointRange<Float> = (4f / 5f)..(4f / 3f)
}
