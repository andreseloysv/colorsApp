// Glifos de accion de la marca (W5): los equivalentes Android de los SF
// Symbols pequenos de iOS (FIDELITY §2.4: heart, hand.thumbsdown,
// doc.on.doc, square.and.arrow.up, checkmark.seal, eye, lock, person,
// paintpalette, gearshape…). Trazo 24x24 tintable con Icon(tint=...); los
// trae W3 como SolarIcons y W5 los adopta en el sistema de diseno con los
// nombres SolarIcon*. Los personajes de pestana viven en BrandCreatures.kt.
package com.andreseloy.colorsapp.design

import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.PathFillType
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.StrokeJoin
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.graphics.vector.PathBuilder
import androidx.compose.ui.graphics.vector.path
import androidx.compose.ui.unit.dp

private fun solarStrokeIcon(
    name: String,
    filled: Boolean = false,
    builder: PathBuilder.() -> Unit,
): ImageVector = ImageVector.Builder(
    name = name, defaultWidth = 24.dp, defaultHeight = 24.dp,
    viewportWidth = 24f, viewportHeight = 24f,
).apply {
    path(
        fill = if (filled) SolidColor(Color.Black) else SolidColor(Color.Transparent),
        stroke = if (filled) SolidColor(Color.Transparent) else SolidColor(Color.Black),
        strokeLineWidth = 1.8f,
        strokeLineCap = StrokeCap.Round,
        strokeLineJoin = StrokeJoin.Round,
        pathFillType = PathFillType.NonZero,
        pathBuilder = builder,
    )
}.build()

val SolarIconHeart: ImageVector = solarStrokeIcon("SolarHeart") {
    moveTo(12f, 20.5f)
    curveTo(5f, 15.5f, 3f, 12f, 3f, 8.8f)
    curveTo(3f, 6f, 5f, 4f, 7.6f, 4f)
    curveTo(9.5f, 4f, 11.2f, 5.2f, 12f, 7f)
    curveTo(12.8f, 5.2f, 14.5f, 4f, 16.4f, 4f)
    curveTo(19f, 4f, 21f, 6f, 21f, 8.8f)
    curveTo(21f, 12f, 19f, 15.5f, 12f, 20.5f)
    close()
}

val SolarIconHeartFilled: ImageVector = solarStrokeIcon("SolarHeartFilled", filled = true) {
    moveTo(12f, 20.5f)
    curveTo(5f, 15.5f, 3f, 12f, 3f, 8.8f)
    curveTo(3f, 6f, 5f, 4f, 7.6f, 4f)
    curveTo(9.5f, 4f, 11.2f, 5.2f, 12f, 7f)
    curveTo(12.8f, 5.2f, 14.5f, 4f, 16.4f, 4f)
    curveTo(19f, 4f, 21f, 6f, 21f, 8.8f)
    curveTo(21f, 12f, 19f, 15.5f, 12f, 20.5f)
    close()
}

val SolarIconThumbDown: ImageVector = solarStrokeIcon("SolarThumbDown") {
    moveTo(7f, 11f)
    lineTo(4f, 11f)
    lineTo(4f, 4f)
    lineTo(7f, 4f)
    close()
    moveTo(7f, 11f)
    lineTo(16.5f, 11f)
    curveTo(18.5f, 11f, 20f, 9.5f, 20f, 7.6f)
    lineTo(20f, 7f)
    curveTo(20f, 5.3f, 18.7f, 4f, 17f, 4f)
    lineTo(10f, 4f)
    lineTo(11.6f, 8.2f)
    curveTo(11.9f, 9.2f, 11.2f, 10f, 10.2f, 10f)
    moveTo(10.5f, 11f)
    lineTo(12f, 17.5f)
    curveTo(12.3f, 18.8f, 13.3f, 19.6f, 14.6f, 19.4f)
    curveTo(16f, 19.2f, 17f, 18f, 16.8f, 16.6f)
    lineTo(16.3f, 12.6f)
}

val SolarIconCopy: ImageVector = solarStrokeIcon("SolarCopy") {
    moveTo(9f, 9f)
    lineTo(20f, 9f)
    lineTo(20f, 20f)
    lineTo(9f, 20f)
    close()
    moveTo(5f, 15f)
    lineTo(4f, 15f)
    curveTo(3.4f, 15f, 3f, 14.6f, 3f, 14f)
    lineTo(3f, 4f)
    curveTo(3f, 3.4f, 3.4f, 3f, 4f, 3f)
    lineTo(14f, 3f)
    curveTo(14.6f, 3f, 15f, 3.4f, 15f, 4f)
    lineTo(15f, 5f)
}

val SolarIconCheck: ImageVector = solarStrokeIcon("SolarCheck") {
    moveTo(4f, 12.5f)
    lineTo(9.5f, 18f)
    lineTo(20f, 6.5f)
}

val SolarIconShare: ImageVector = solarStrokeIcon("SolarShare") {
    moveTo(12f, 15f)
    lineTo(12f, 3.5f)
    moveTo(8f, 6.5f)
    lineTo(12f, 3f)
    lineTo(16f, 6.5f)
    moveTo(5f, 12f)
    lineTo(5f, 19f)
    curveTo(5f, 20.1f, 5.9f, 21f, 7f, 21f)
    lineTo(17f, 21f)
    curveTo(18.1f, 21f, 19f, 20.1f, 19f, 19f)
    lineTo(19f, 12f)
}

val SolarIconExpand: ImageVector = solarStrokeIcon("SolarExpand") {
    moveTo(9f, 4f)
    lineTo(4f, 4f)
    lineTo(4f, 9f)
    moveTo(4f, 4f)
    lineTo(10f, 10f)
    moveTo(15f, 20f)
    lineTo(20f, 20f)
    lineTo(20f, 15f)
    moveTo(20f, 20f)
    lineTo(14f, 14f)
}

val SolarIconPhoto: ImageVector = solarStrokeIcon("SolarPhoto") {
    moveTo(4f, 5f)
    lineTo(20f, 5f)
    lineTo(20f, 19f)
    lineTo(4f, 19f)
    close()
    moveTo(4f, 16f)
    lineTo(9f, 11f)
    lineTo(13f, 15f)
    lineTo(16f, 12.5f)
    lineTo(20f, 16f)
    moveTo(7.6f, 9f)
    arcTo(1.4f, 1.4f, 0f, false, true, 10.4f, 9f)
    arcTo(1.4f, 1.4f, 0f, false, true, 7.6f, 9f)
}

val SolarIconPhotoStack: ImageVector = solarStrokeIcon("SolarPhotoStack") {
    moveTo(7f, 7f)
    lineTo(21f, 7f)
    lineTo(21f, 20f)
    lineTo(7f, 20f)
    close()
    moveTo(4f, 17f)
    lineTo(3.5f, 17f)
    curveTo(3.2f, 17f, 3f, 16.8f, 3f, 16.5f)
    lineTo(3f, 4.5f)
    curveTo(3f, 4.2f, 3.2f, 4f, 3.5f, 4f)
    lineTo(17.5f, 4f)
    curveTo(17.8f, 4f, 18f, 4.2f, 18f, 4.5f)
    lineTo(18f, 5f)
}

val SolarIconLayers: ImageVector = solarStrokeIcon("SolarLayers") {
    moveTo(12f, 3.5f)
    lineTo(21f, 8.5f)
    lineTo(12f, 13.5f)
    lineTo(3f, 8.5f)
    close()
    moveTo(3.5f, 13f)
    lineTo(12f, 17.8f)
    lineTo(20.5f, 13f)
    moveTo(3.5f, 17f)
    lineTo(12f, 21.8f)
    lineTo(20.5f, 17f)
}

val SolarIconEye: ImageVector = solarStrokeIcon("SolarEye") {
    moveTo(2.5f, 12f)
    curveTo(5f, 6.5f, 8.5f, 4.5f, 12f, 4.5f)
    curveTo(15.5f, 4.5f, 19f, 6.5f, 21.5f, 12f)
    curveTo(19f, 17.5f, 15.5f, 19.5f, 12f, 19.5f)
    curveTo(8.5f, 19.5f, 5f, 17.5f, 2.5f, 12f)
    close()
    moveTo(9f, 12f)
    arcTo(3f, 3f, 0f, false, true, 15f, 12f)
    arcTo(3f, 3f, 0f, false, true, 9f, 12f)
}

val SolarIconEyeSlash: ImageVector = solarStrokeIcon("SolarEyeSlash") {
    moveTo(4f, 4f)
    lineTo(20f, 20f)
    moveTo(10.6f, 5.2f)
    curveTo(11.1f, 5f, 11.5f, 5f, 12f, 5f)
    curveTo(15.5f, 5f, 19f, 7f, 21.5f, 12f)
    curveTo(20.4f, 14.4f, 18.9f, 16.3f, 17.1f, 17.6f)
    moveTo(6.6f, 6.9f)
    curveTo(5f, 8.2f, 3.6f, 9.9f, 2.5f, 12f)
    curveTo(5f, 17f, 8.5f, 19f, 12f, 19f)
    curveTo(13f, 19f, 14f, 18.8f, 15f, 18.4f)
}

val SolarIconLock: ImageVector = solarStrokeIcon("SolarLock") {
    moveTo(6f, 11f)
    lineTo(18f, 11f)
    lineTo(18f, 20f)
    lineTo(6f, 20f)
    close()
    moveTo(9f, 11f)
    lineTo(9f, 8f)
    curveTo(9f, 5.8f, 10.3f, 4f, 12f, 4f)
    curveTo(13.7f, 4f, 15f, 5.8f, 15f, 8f)
    lineTo(15f, 11f)
}

val SolarIconLockOpen: ImageVector = solarStrokeIcon("SolarLockOpen") {
    moveTo(6f, 11f)
    lineTo(18f, 11f)
    lineTo(18f, 20f)
    lineTo(6f, 20f)
    close()
    moveTo(9f, 11f)
    lineTo(9f, 8f)
    curveTo(9f, 5.8f, 10.3f, 4f, 12f, 4f)
    curveTo(13.7f, 4f, 15f, 5.8f, 15f, 8f)
}

val SolarIconChevronRight: ImageVector = solarStrokeIcon("SolarChevronRight") {
    moveTo(9f, 5f)
    lineTo(16f, 12f)
    lineTo(9f, 19f)
}

val SolarIconClose: ImageVector = solarStrokeIcon("SolarClose") {
    moveTo(5f, 5f)
    lineTo(19f, 19f)
    moveTo(19f, 5f)
    lineTo(5f, 19f)
}

val SolarIconPerson: ImageVector = solarStrokeIcon("SolarPerson") {
    moveTo(8.8f, 7.8f)
    arcTo(3.2f, 3.2f, 0f, false, true, 15.2f, 7.8f)
    arcTo(3.2f, 3.2f, 0f, false, true, 8.8f, 7.8f)
    moveTo(5f, 20f)
    curveTo(6f, 16.5f, 8.8f, 14.8f, 12f, 14.8f)
    curveTo(15.2f, 14.8f, 18f, 16.5f, 19f, 20f)
}

val SolarIconPalette: ImageVector = solarStrokeIcon("SolarPalette") {
    moveTo(12f, 3.5f)
    curveTo(7f, 3.5f, 3f, 7.4f, 3f, 12.2f)
    curveTo(3f, 17f, 7f, 20.5f, 12f, 20.5f)
    curveTo(13f, 20.5f, 13.8f, 19.6f, 13.6f, 18.6f)
    curveTo(13.4f, 17.7f, 14.1f, 17f, 15f, 17f)
    lineTo(17f, 17f)
    curveTo(19.5f, 17f, 21f, 15f, 21f, 12.4f)
    curveTo(21f, 7.6f, 17f, 3.5f, 12f, 3.5f)
    close()
    moveTo(6.4f, 10.5f)
    arcTo(1.1f, 1.1f, 0f, false, true, 8.6f, 10.5f)
    arcTo(1.1f, 1.1f, 0f, false, true, 6.4f, 10.5f)
    moveTo(10.9f, 8f)
    arcTo(1.1f, 1.1f, 0f, false, true, 13.1f, 8f)
    arcTo(1.1f, 1.1f, 0f, false, true, 10.9f, 8f)
    moveTo(15.4f, 10.5f)
    arcTo(1.1f, 1.1f, 0f, false, true, 17.6f, 10.5f)
    arcTo(1.1f, 1.1f, 0f, false, true, 15.4f, 10.5f)
}

val SolarIconWarning: ImageVector = solarStrokeIcon("SolarWarning") {
    moveTo(12f, 4f)
    lineTo(22f, 20f)
    lineTo(2f, 20f)
    close()
    moveTo(12f, 10f)
    lineTo(12f, 14.5f)
    moveTo(11.4f, 17.2f)
    arcTo(0.6f, 0.6f, 0f, false, true, 12.6f, 17.2f)
    arcTo(0.6f, 0.6f, 0f, false, true, 11.4f, 17.2f)
}

val SolarIconSeal: ImageVector = solarStrokeIcon("SolarSeal") {
    moveTo(4.5f, 12f)
    arcTo(7.5f, 7.5f, 0f, false, true, 19.5f, 12f)
    arcTo(7.5f, 7.5f, 0f, false, true, 4.5f, 12f)
    moveTo(8.8f, 12.2f)
    lineTo(11f, 14.4f)
    lineTo(15.4f, 9.8f)
}

val SolarIconRefresh: ImageVector = solarStrokeIcon("SolarRefresh") {
    moveTo(20f, 12f)
    arcTo(8f, 8f, 0f, true, true, 5.7f, 5.7f)
    moveTo(20f, 4.5f)
    lineTo(20f, 9f)
    lineTo(15.5f, 9f)
}

val SolarIconGear: ImageVector = solarStrokeIcon("SolarGear") {
    moveTo(8.5f, 12f)
    arcTo(3.5f, 3.5f, 0f, false, true, 15.5f, 12f)
    arcTo(3.5f, 3.5f, 0f, false, true, 8.5f, 12f)
    moveTo(12f, 2.8f)
    lineTo(12f, 5.2f)
    moveTo(12f, 18.8f)
    lineTo(12f, 21.2f)
    moveTo(4.3f, 5.5f)
    lineTo(6f, 7.2f)
    moveTo(18f, 16.8f)
    lineTo(19.7f, 18.5f)
    moveTo(2.8f, 12f)
    lineTo(5.2f, 12f)
    moveTo(18.8f, 12f)
    lineTo(21.2f, 12f)
    moveTo(4.3f, 18.5f)
    lineTo(6f, 16.8f)
    moveTo(18f, 7.2f)
    lineTo(19.7f, 5.5f)
}

/** Lupa del buscador (magnifyingglass en iOS). W5. */
val SolarIconSearch: ImageVector = solarStrokeIcon("SolarSearch") {
    moveTo(4.5f, 11f)
    arcTo(6.5f, 6.5f, 0f, false, true, 17.5f, 11f)
    arcTo(6.5f, 6.5f, 0f, false, true, 4.5f, 11f)
    moveTo(15.8f, 15.8f)
    lineTo(20.5f, 20.5f)
}

/** Deslizadores de filtros (slider.horizontal.3 en iOS). W5. */
val SolarIconSliders: ImageVector = solarStrokeIcon("SolarSliders") {
    moveTo(4f, 7f)
    lineTo(20f, 7f)
    moveTo(4f, 12f)
    lineTo(20f, 12f)
    moveTo(4f, 17f)
    lineTo(20f, 17f)
    moveTo(8.6f, 7f)
    arcTo(1.6f, 1.6f, 0f, false, true, 11.8f, 7f)
    arcTo(1.6f, 1.6f, 0f, false, true, 8.6f, 7f)
    moveTo(13.4f, 12f)
    arcTo(1.6f, 1.6f, 0f, false, true, 16.6f, 12f)
    arcTo(1.6f, 1.6f, 0f, false, true, 13.4f, 12f)
    moveTo(6.4f, 17f)
    arcTo(1.6f, 1.6f, 0f, false, true, 9.6f, 17f)
    arcTo(1.6f, 1.6f, 0f, false, true, 6.4f, 17f)
}
