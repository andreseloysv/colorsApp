// Composicion de una combinacion como en las paginas del libro de Sanzo
// Wada: espejo de ios/ColorsApp/Design/Components/BookComposition.swift.
// 2 colores: una fila (caja 2,36:1); 3: una fila (2,85:1); 4: cruz de tres
// filas (1,252:1) con los rectangulos medidos de la edicion de Seigensha.
// Bloques planos que se tocan, dentro de su pocillo neutro (lo pone quien
// llama). Tocar un bloque copia su hex.
package com.andreseloy.colorsapp.feature.feed

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.width
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import com.andreseloy.colorsapp.design.SolarSizes
import com.andreseloy.colorsapp.design.SolarTheme
import com.andreseloy.colorsapp.feature.extract.PaletteColor

/** Rectangulo normalizado 0..1 sobre la caja de la composicion. */
data class BookRect(val x: Double, val y: Double, val width: Double, val height: Double)

object BookCompositionGeometry {
    fun rects(count: Int): List<BookRect> {
        if (count != 4) {
            val n = maxOf(count, 1)
            val w = 1.0 / n
            return (0 until n).map { BookRect(it * w, 0.0, w, 1.0) }
        }
        val row = 1.0 / 3.0
        return listOf(
            BookRect(0.248, 0.0, 0.532, row),
            BookRect(0.0, row, 0.537, row),
            BookRect(0.537, row, 0.463, row),
            BookRect(0.278, 2 * row, 0.525, row),
        )
    }

    fun aspectRatio(count: Int): Double = when (count) {
        2 -> 2.36
        3 -> 2.85
        4 -> 1.252
        else -> maxOf(count, 1) * 0.95
    }

    /** Ancho de la caja: manda la proporcion; [maxHeightDp] estrecha, nunca estira. */
    fun boxWidthDp(availableWidthDp: Float, count: Int, maxHeightDp: Float): Float {
        val ratio = aspectRatio(count).toFloat()
        return maxOf(0f, minOf(availableWidthDp, maxHeightDp * ratio))
    }
}

@Composable
fun BookComposition(
    colors: List<PaletteColor>,
    modifier: Modifier = Modifier,
    maxHeight: Dp = SolarSizes.dayComposition,
    /** Descripcion accesible por bloque («Color 1 de 3, …»), la compone la UI. */
    descriptionFor: @Composable (PaletteColor, Int) -> String = { c, _ -> c.name ?: c.hex },
    onTap: ((PaletteColor) -> Unit)? = null,
) {
    val themeColors = SolarTheme.colors
    if (colors.isEmpty()) {
        Box(
            modifier
                .fillMaxWidth()
                .height(SolarSizes.dayRibbon)
                .background(themeColors.wellPlaceholder),
        )
        return
    }
    val rects = BookCompositionGeometry.rects(colors.size)
    val ratio = BookCompositionGeometry.aspectRatio(colors.size)
    BoxWithConstraints(modifier.fillMaxWidth(), contentAlignment = Alignment.Center) {
        val boxWidth = BookCompositionGeometry.boxWidthDp(
            maxWidth.value, colors.size, maxHeight.value,
        ).dp
        val boxHeight = (boxWidth.value / ratio).dp
        Box(Modifier.width(boxWidth).height(boxHeight)) {
            colors.forEachIndexed { i, color ->
                val description = descriptionFor(color, i)
                val r = rects[i]
                val w = (boxWidth.value * r.width).dp
                val h = (boxHeight.value * r.height).dp
                val x = (boxWidth.value * r.x).dp
                val y = (boxHeight.value * r.y).dp
                Box(
                    Modifier
                        .offset(x = x, y = y)
                        .width(w)
                        .height(h)
                        .background(Color(color.argb))
                        .border(0.5.dp, themeColors.swatchHairline)
                        .then(
                            if (onTap != null) {
                                Modifier.clickable { onTap(color) }
                            } else {
                                Modifier
                            },
                        )
                        .semantics { contentDescription = description },
                )
            }
        }
    }
}
