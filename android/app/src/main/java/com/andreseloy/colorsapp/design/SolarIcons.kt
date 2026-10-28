// Iconos de la app como ImageVector (sin dependencia de iconos de Material:
// el APK no crece y no hay fuentes de iconos). Equivalen a los SF Symbols que
// usa iOS como respaldo de los personajes de marca (SolarTabs: sun.max,
// drop.halffull, square.grid.2x2, leaf). Los personajes originales animados de
// la barra (BrandTabIcon) se portan en la ola 2 (ver docs/ANDROID.md);
// mientras tanto la barra usa estos glifos, como hacía iOS antes de F45–F50.
package com.andreseloy.colorsapp.design

import androidx.compose.ui.graphics.PathFillType
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.graphics.vector.PathBuilder
import androidx.compose.ui.unit.dp

private fun solarIcon(name: String, builder: PathBuilder.() -> Unit): ImageVector =
    ImageVector.Builder(
        name = name,
        defaultWidth = 24.dp,
        defaultHeight = 24.dp,
        viewportWidth = 24f,
        viewportHeight = 24f,
    ).apply {
        addPath(
            pathData = PathBuilder().apply(builder).nodes,
            // Sin relleno explícito VectorPainter no pinta la ruta; el
            // Icon(tint=...) de Material sustituye este negro por el tinte.
            fill = SolidColor(androidx.compose.ui.graphics.Color.Black),
            pathFillType = PathFillType.EvenOdd,
        )
    }.build()

// Los vectores se pintan con LocalContentColor: las rutas usan relleno
// EvenOdd sin color propio (Black placeholder; Icon(tint=...) lo sustituye).

/** Sol (Feed): círculo central con 8 rayos. */
val SolarIconSun: ImageVector = solarIcon("SolarSun") {
    // círculo central
    moveTo(12.0f, 7.2f)
    curveToRelative(2.65f, 0f, 4.8f, 2.15f, 4.8f, 4.8f)
    curveToRelative(0f, 2.65f, -2.15f, 4.8f, -4.8f, 4.8f)
    curveToRelative(-2.65f, 0f, -4.8f, -2.15f, -4.8f, -4.8f)
    curveToRelative(0f, -2.65f, 2.15f, -4.8f, 4.8f, -4.8f)
    close()
    // rayos (rombos alargados en las 8 direcciones)
    val rays = listOf(
        0f to -8.6f, 6.1f to -6.1f, 8.6f to 0f, 6.1f to 6.1f,
        0f to 8.6f, -6.1f to 6.1f, -8.6f to 0f, -6.1f to -6.1f,
    )
    for ((dx, dy) in rays) {
        val cx = 12f + dx
        val cy = 12f + dy
        val ux = if (dx == 0f) 0f else dx / kotlin.math.abs(dx) * 0.7071f * if (dy == 0f) 1.4142f else 1f
        val uy = if (dy == 0f) 0f else dy / kotlin.math.abs(dy) * 0.7071f * if (dx == 0f) 1.4142f else 1f
        val px = -uy
        val py = ux
        moveTo(cx + ux * 1.5f, cy + uy * 1.5f)
        lineTo(cx + px * 0.55f, cy + py * 0.55f)
        lineTo(cx - ux * 1.5f, cy - uy * 1.5f)
        lineTo(cx - px * 0.55f, cy - py * 0.55f)
        close()
    }
}

/** Gota (Extraer). */
val SolarIconDrop: ImageVector = solarIcon("SolarDrop") {
    moveTo(12.0f, 2.6f)
    curveToRelative(0.5f, 0f, 0.9f, 0.25f, 1.15f, 0.75f)
    curveToRelative(0.55f, 1.05f, 1.35f, 2.25f, 2.2f, 3.45f)
    curveToRelative(1.7f, 2.4f, 3.25f, 4.75f, 3.25f, 7.2f)
    curveToRelative(0f, 4.1f, -2.95f, 7.4f, -6.6f, 7.4f)
    curveToRelative(-3.65f, 0f, -6.6f, -3.3f, -6.6f, -7.4f)
    curveToRelative(0f, -2.45f, 1.55f, -4.8f, 3.25f, -7.2f)
    curveToRelative(0.85f, -1.2f, 1.65f, -2.4f, 2.2f, -3.45f)
    curveToRelative(0.25f, -0.5f, 0.65f, -0.75f, 1.15f, -0.75f)
    close()
    // brillo interior (hueco con EvenOdd)
    moveTo(9.4f, 12.4f)
    curveToRelative(-0.55f, 0.85f, -1.0f, 1.8f, -1.0f, 2.7f)
    curveToRelative(0f, 1.55f, 1.05f, 2.8f, 2.35f, 2.95f)
    curveToRelative(0.45f, 0.05f, 0.8f, -0.4f, 0.65f, -0.85f)
    curveToRelative(-0.3f, -0.9f, -0.45f, -2.3f, -0.55f, -3.5f)
    curveToRelative(-0.1f, -0.9f, -1.05f, -1.05f, -1.45f, -0.3f)
    close()
}

/** Rejilla 2x2 (Rejilla). */
val SolarIconGrid: ImageVector = solarIcon("SolarGrid") {
    val cells = listOf(3.5f to 3.5f, 13.0f to 3.5f, 3.5f to 13.0f, 13.0f to 13.0f)
    for ((x, y) in cells) {
        moveTo(x + 1.2f, y)
        lineTo(x + 6.3f, y)
        curveToRelative(0.66f, 0f, 1.2f, 0.54f, 1.2f, 1.2f)
        lineTo(x + 7.5f, y + 6.3f)
        curveToRelative(0f, 0.66f, -0.54f, 1.2f, -1.2f, 1.2f)
        lineTo(x + 1.2f, y + 7.5f)
        curveToRelative(-0.66f, 0f, -1.2f, -0.54f, -1.2f, -1.2f)
        lineTo(x, y + 1.2f)
        curveToRelative(0f, -0.66f, 0.54f, -1.2f, 1.2f, -1.2f)
        close()
    }
}

/** Hoja con tallo (Jardín). */
val SolarIconLeaf: ImageVector = solarIcon("SolarLeaf") {
    moveTo(20.2f, 3.8f)
    curveToRelative(0.4f, -0.05f, 0.75f, 0.3f, 0.7f, 0.7f)
    curveToRelative(-0.3f, 5.6f, -1.6f, 9.4f, -4.1f, 12.05f)
    curveToRelative(-2.2f, 2.35f, -5.2f, 3.5f, -8.55f, 3.3f)
    curveToRelative(-0.55f, -0.03f, -1.1f, -0.09f, -1.62f, -0.19f)
    curveToRelative(-0.22f, 0.57f, -0.5f, 1.03f, -0.83f, 1.37f)
    curveToRelative(-0.35f, 0.38f, -0.95f, 0.4f, -1.35f, 0.05f)
    curveToRelative(-0.4f, -0.35f, -0.42f, -0.95f, -0.07f, -1.35f)
    curveToRelative(0.5f, -0.55f, 0.95f, -1.23f, 1.34f, -2.03f)
    curveToRelative(-0.65f, -1.1f, -1.05f, -2.4f, -1.15f, -3.95f)
    curveToRelative(-0.25f, -3.55f, 1.0f, -6.65f, 3.55f, -8.95f)
    curveToRelative(2.65f, -2.4f, 6.4f, -3.6f, 11.7f, -3.8f)
    close()
    // nervio (hueco con EvenOdd)
    moveTo(17.0f, 7.2f)
    curveToRelative(-3.9f, 0.5f, -6.8f, 1.7f, -8.9f, 3.75f)
    curveToRelative(-1.5f, 1.45f, -2.6f, 3.3f, -3.45f, 5.55f)
    curveToRelative(0.35f, 0.05f, 0.7f, 0.08f, 1.05f, 0.09f)
    curveToRelative(0.8f, -1.95f, 1.8f, -3.5f, 3.1f, -4.8f)
    curveToRelative(1.9f, -1.8f, 4.45f, -2.85f, 7.9f, -3.3f)
    curveToRelative(0.1f, -0.42f, 0.16f, -0.85f, 0.2f, -1.29f)
    close()
}

/** Cámara (cabecera del Feed en iOS). */
val SolarIconCamera: ImageVector = solarIcon("SolarCamera") {
    moveTo(8.2f, 4.0f)
    curveToRelative(0.35f, -0.7f, 1.05f, -1.15f, 1.85f, -1.15f)
    lineTo(13.95f, 2.85f)
    curveToRelative(0.8f, 0f, 1.5f, 0.45f, 1.85f, 1.15f)
    lineTo(16.45f, 5.3f)
    lineTo(20.0f, 5.3f)
    curveToRelative(1.25f, 0f, 2.25f, 1.0f, 2.25f, 2.25f)
    lineTo(22.25f, 18.9f)
    curveToRelative(0f, 1.25f, -1.0f, 2.25f, -2.25f, 2.25f)
    lineTo(4.0f, 21.15f)
    curveToRelative(-1.25f, 0f, -2.25f, -1.0f, -2.25f, -2.25f)
    lineTo(1.75f, 7.55f)
    curveToRelative(0f, -1.25f, 1.0f, -2.25f, 2.25f, -2.25f)
    lineTo(7.55f, 5.3f)
    lineTo(8.2f, 4.0f)
    close()
    // objetivo (hueco)
    moveTo(12.0f, 8.2f)
    curveToRelative(-2.75f, 0f, -5.0f, 2.25f, -5.0f, 5.0f)
    curveToRelative(0f, 2.75f, 2.25f, 5.0f, 5.0f, 5.0f)
    curveToRelative(2.75f, 0f, 5.0f, -2.25f, 5.0f, -5.0f)
    curveToRelative(0f, -2.75f, -2.25f, -5.0f, -5.0f, -5.0f)
    close()
}

/** Destellos (CTA «Otra combinación» y momentos de marca). */
val SolarIconSparkles: ImageVector = solarIcon("SolarSparkles") {
    // estrella de 4 puntas grande
    moveTo(10.0f, 2.5f)
    curveToRelative(0.3f, 0f, 0.55f, 0.18f, 0.68f, 0.47f)
    curveToRelative(0.52f, 1.1f, 1.28f, 2.73f, 1.79f, 3.83f)
    curveToRelative(1.1f, 0.51f, 2.73f, 1.27f, 3.83f, 1.79f)
    curveToRelative(0.65f, 0.3f, 0.65f, 1.22f, 0f, 1.53f)
    curveToRelative(-1.1f, 0.51f, -2.73f, 1.27f, -3.83f, 1.78f)
    curveToRelative(-0.51f, 1.1f, -1.27f, 2.73f, -1.79f, 3.84f)
    curveToRelative(-0.3f, 0.65f, -1.22f, 0.65f, -1.53f, 0f)
    curveToRelative(-0.51f, -1.11f, -1.27f, -2.74f, -1.78f, -3.84f)
    curveToRelative(-1.1f, -0.51f, -2.73f, -1.27f, -3.84f, -1.78f)
    curveToRelative(-0.65f, -0.31f, -0.65f, -1.23f, 0f, -1.53f)
    curveToRelative(1.11f, -0.52f, 2.74f, -1.28f, 3.84f, -1.79f)
    curveToRelative(0.51f, -1.1f, 1.27f, -2.73f, 1.78f, -3.83f)
    curveToRelative(0.15f, -0.31f, 0.4f, -0.47f, 0.69f, -0.47f)
    close()
    // estrella pequeña
    moveTo(18.6f, 13.4f)
    curveToRelative(0.3f, 0.8f, 0.62f, 1.68f, 0.92f, 2.5f)
    curveToRelative(0.8f, 0.3f, 1.68f, 0.62f, 2.5f, 0.93f)
    curveToRelative(0.45f, 0.17f, 0.45f, 0.83f, 0f, 1.0f)
    curveToRelative(-0.82f, 0.31f, -1.7f, 0.63f, -2.5f, 0.93f)
    curveToRelative(-0.3f, 0.82f, -0.62f, 1.7f, -0.92f, 2.5f)
    curveToRelative(-0.17f, 0.45f, -0.83f, 0.45f, -1.0f, 0f)
    curveToRelative(-0.31f, -0.8f, -0.63f, -1.68f, -0.93f, -2.5f)
    curveToRelative(-0.82f, -0.3f, -1.7f, -0.62f, -2.5f, -0.93f)
    curveToRelative(-0.45f, -0.17f, -0.45f, -0.83f, 0f, -1.0f)
    curveToRelative(0.8f, -0.31f, 1.68f, -0.63f, 2.5f, -0.92f)
    curveToRelative(0.3f, -0.82f, 0.62f, -1.7f, 0.93f, -2.5f)
    curveToRelative(0.17f, -0.45f, 0.83f, -0.45f, 0.99f, 0f)
    close()
}

/** Flecha atrás. */
val SolarIconBack: ImageVector = solarIcon("SolarBack") {
    moveTo(15.6f, 4.2f)
    curveToRelative(0.45f, -0.42f, 1.13f, -0.42f, 1.55f, 0f)
    curveToRelative(0.42f, 0.42f, 0.42f, 1.1f, 0f, 1.52f)
    lineTo(11.2f, 11.65f)
    curveToRelative(-0.2f, 0.2f, -0.2f, 0.5f, 0f, 0.7f)
    lineTo(17.15f, 18.28f)
    curveToRelative(0.42f, 0.42f, 0.42f, 1.1f, 0f, 1.52f)
    curveToRelative(-0.42f, 0.42f, -1.1f, 0.42f, -1.55f, 0f)
    lineTo(8.35f, 12.75f)
    curveToRelative(-0.42f, -0.42f, -0.42f, -1.08f, 0f, -1.5f)
    lineTo(15.6f, 4.2f)
    close()
}
