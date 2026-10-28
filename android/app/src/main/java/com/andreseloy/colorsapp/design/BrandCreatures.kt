// Personajes originales de la barra de pestañas (W5): puerto directo de
// ios/ColorsApp/Design/Brand/BrandTabIconArt.swift + BrandPalette.swift
// (ver docs/design/FIDELITY.md §2.3). Lienzo de 32 unidades (viewBox 24 + 4
// de margen) dibujado con Canvas de Compose; poses con los periodos de
// FIDELITY (bote 2,2 s, parpadeo 3,4 s, mecido 3,2 s, balanceo 2,6 s,
// aleteo rápido). Con «quitar animaciones» del sistema, pose de reposo.
// Colores de ilustración del marco: nunca junto a un swatch.
package com.andreseloy.colorsapp.design

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.foundation.layout.size
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.StrokeJoin
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.drawscope.withTransform
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import kotlin.math.PI
import kotlin.math.cos
import kotlin.math.sin

/** Los cuatro personajes (SolarCreatureIcon de iOS). */
enum class BrandCreature { SEED, DRAGONFLY, DEWDROP, SPROUT }

/** Tintas fijas de marca (BrandInk); en oscuro los trazos aclaran. */
private class BrandInk(dark: Boolean) {
    val sunLight = Color(0xFFFEF3C7)
    val sunGold = Color(0xFFFBBF24)
    val sunAmber = Color(0xFFF59E0B)
    val sunEdge = if (dark) Color(0xFFFCD34D) else Color(0xFFB45309)
    val mossDeep = if (dark) Color(0xFFBCEFC7) else Color(0xFF144226)
    val moss = if (dark) Color(0xFF81B29A) else Color(0xFF2D5A3C)
    val sage = if (dark) Color(0xFFA1D2AC) else Color(0xFF81B29A)
    val mint = Color(0xFFA1D2AC)
    val celadon = Color(0xFF7CA99A)
    val celadonPale = Color(0xFFBDECDC)
    val celadonInk = if (dark) Color(0xFFBDECDC) else Color(0xFF2D594C)
    val terracotta = Color(0xFFC8644A)
    val terracottaLight = Color(0xFFE07A5F)
    val peach = Color(0xFFFFDCC6)
    val clayInk = if (dark) Color(0xFFFFB785) else Color(0xFF713700)
    val amberInk = if (dark) Color(0xFFFFB785) else Color(0xFF954A00)
    val face = Color(0xFF4A2308)
    val faceCool = Color(0xFF0F3A2E)
    val cheek = Color(0xFFF87171)
}

/** Un fotograma: mismas magnitudes que TabIconPose de iOS. */
private data class Pose(
    val offsetY: Float = 0f, val rotation: Float = 0f,
    val scaleX: Float = 1f, val scaleY: Float = 1f,
    val eyeScaleY: Float = 1f,
    val wingScaleY: Float = 1f, val wingOpacity: Float = 1f,
    val pingScale: Float = 1f, val pingOpacity: Float = 0f,
    val sparkOpacity: Float = 1f,
)

private fun blink(t: Float, cycle: Float = 3.4f, offset: Float = 0f): Float {
    val phase = (t + offset) % cycle
    return when {
        phase < 0.09f -> 1f - phase / 0.09f * 0.9f
        phase < 0.2f -> 0.1f + (phase - 0.09f) / 0.11f * 0.9f
        else -> 1f
    }
}

private fun ping(t: Float, cycle: Float = 1.8f): Pair<Float, Float> {
    val f = (t % cycle) / cycle
    return (1f + f * 1.7f) to (1f - f) * 0.55f
}

private fun pose(kind: BrandCreature, t: Float, animated: Boolean): Pose {
    if (!animated) return Pose()
    val w = (2 * PI).toFloat()
    return when (kind) {
        BrandCreature.SEED -> Pose(
            offsetY = sin(w * t / 2.2f) * 0.7f,
            scaleY = 1f + sin(w * t / 2.2f + 0.6f) * 0.03f,
            eyeScaleY = blink(t),
            sparkOpacity = 0.45f + 0.55f * (0.5f + 0.5f * sin(w * t / 2.0f)),
        )
        BrandCreature.DRAGONFLY -> Pose(
            offsetY = sin(w * t / 2.0f) * 0.8f,
            rotation = sin(w * t / 2.0f + 0.5f) * 3f,
            wingScaleY = 0.72f + 0.28f * sin(w * t / 0.36f),
            wingOpacity = 0.78f + 0.22f * sin(w * t / 0.36f + 0.8f),
        )
        BrandCreature.DEWDROP -> {
            val (ps, po) = ping(t)
            Pose(rotation = sin(w * t / 3.2f) * 4f, eyeScaleY = blink(t, offset = 1.1f),
                pingScale = ps, pingOpacity = po)
        }
        BrandCreature.SPROUT -> {
            val (ps, po) = ping(t, cycle = 2.2f)
            Pose(rotation = sin(w * t / 2.6f) * 3f, offsetY = sin(w * t / 2.6f + 0.7f) * 0.3f,
                pingScale = ps, pingOpacity = po)
        }
    }
}

/** Icono-personaje animado de una pestaña (decorativo: habla la etiqueta). */
@Composable
fun BrandCreatureIcon(
    creature: BrandCreature,
    modifier: Modifier = Modifier,
    size: Dp = 34.dp,
) {
    val reduce = rememberReduceMotion()
    val now = rememberAmbientClockMs(reduce)
    val ink = BrandInk(isSystemInDarkTheme())
    val p = pose(creature, now / 1000f, animated = !reduce)
    Canvas(modifier.size(size)) {
        val u = this.size.width / 32f
        withTransform({
            scale(u, u, Offset.Zero)
            translate(4f, 4f)
        }) {
            when (creature) {
                BrandCreature.SEED -> drawSeed(ink, p)
                BrandCreature.DRAGONFLY -> drawDragonfly(ink, p)
                BrandCreature.DEWDROP -> drawDewdrop(ink, p)
                BrandCreature.SPROUT -> drawSprout(ink, p)
            }
        }
    }
}

// --- Utilidades en unidades del viewBox (el transform ya escala) ---

private fun DrawScope.oval(cx: Float, cy: Float, rx: Float, ry: Float, color: Color) =
    drawOval(color, topLeft = Offset(cx - rx, cy - ry), size = Size(rx * 2, ry * 2))

private fun DrawScope.ovalBrush(cx: Float, cy: Float, rx: Float, ry: Float, brush: Brush) =
    drawOval(brush, topLeft = Offset(cx - rx, cy - ry), size = Size(rx * 2, ry * 2))

private fun DrawScope.ovalStroke(cx: Float, cy: Float, rx: Float, ry: Float, color: Color, width: Float) =
    drawOval(color, topLeft = Offset(cx - rx, cy - ry), size = Size(rx * 2, ry * 2), style = Stroke(width))

private fun DrawScope.dot(cx: Float, cy: Float, r: Float, color: Color) =
    drawCircle(color, radius = r, center = Offset(cx, cy))

private fun DrawScope.glow(cx: Float, cy: Float, r: Float, color: Color) =
    drawCircle(
        Brush.radialGradient(listOf(color, Color.Transparent), center = Offset(cx, cy), radius = r),
        radius = r, center = Offset(cx, cy),
    )

private fun DrawScope.pingMote(cx: Float, cy: Float, r: Float, color: Color, p: Pose) {
    if (p.pingOpacity > 0.01f) dot(cx, cy, r * p.pingScale, color.copy(alpha = p.pingOpacity))
    dot(cx, cy, r, color)
}

/** Hoja de ChromaSolGeometry.leaf (eje +x desde el origen). */
private fun leafPath(r1: Float, halfWidth: Float): Path {
    val len = r1
    return Path().apply {
        moveTo(0f, 0f)
        cubicTo(len * 0.22f, -halfWidth * 1.35f, len * 0.72f, -halfWidth * 1.05f, r1, 0f)
        cubicTo(len * 0.72f, halfWidth * 1.05f, len * 0.22f, halfWidth * 1.35f, 0f, 0f)
        close()
    }
}

// --- Feed: semilla solar ---

private fun DrawScope.drawSeed(ink: BrandInk, p: Pose) {
    val cx = 12f; val cy = 12.9f
    withTransform({
        translate(0f, p.offsetY)
        scale(p.scaleX, p.scaleY, Offset(12f, 12f))
    }) {
        glow(12f, 12.6f, 11.5f, ink.sunGold.copy(alpha = 0.20f))
        // Rayitos (sin el de arriba: ahí nace el brote).
        for (i in 0 until 8) {
            val a = (22.5 + i * 45.0) * PI / 180.0
            val dx = sin(a).toFloat(); val dy = -cos(a).toFloat()
            drawLine(ink.sunAmber, Offset(cx + dx * 9.2f, cy + dy * 9.0f),
                Offset(cx + dx * 10.9f, cy + dy * 10.6f), strokeWidth = 1.35f, cap = StrokeCap.Round)
        }
        // Brote.
        drawPath(Path().apply {
            moveTo(12f, 6.4f); quadraticBezierTo(11.7f, 4.8f, 12.5f, 3.4f)
        }, ink.moss, style = Stroke(0.95f, cap = StrokeCap.Round))
        withTransform({ translate(12.45f, 3.9f); rotate(-25.8f, Offset.Zero) }) {
            drawPath(leafPath(3.7f, 1.15f), ink.sage)
            drawPath(leafPath(3.7f, 1.15f), ink.mossDeep, style = Stroke(0.4f))
        }
        withTransform({ translate(12.15f, 4.9f); rotate(208.6f, Offset.Zero) }) {
            drawPath(leafPath(3.0f, 0.95f), ink.moss)
        }
        // Cuerpo dorado con degradado radial.
        ovalBrush(cx, cy, 7.4f, 7.0f, Brush.radialGradient(
            listOf(ink.sunLight, ink.sunGold, ink.sunAmber),
            center = Offset(9.8f, 10.2f), radius = 10f))
        ovalStroke(cx, cy, 7.4f, 7.0f, ink.sunEdge, 0.8f)
        dot(7.9f, 15.0f, 1.05f, ink.cheek.copy(alpha = 0.5f))
        dot(16.1f, 15.0f, 1.05f, ink.cheek.copy(alpha = 0.5f))
        drawPath(Path().apply {
            moveTo(10.9f, 15.4f); quadraticBezierTo(12f, 16.6f, 13.1f, 15.4f)
        }, ink.face, style = Stroke(0.75f, cap = StrokeCap.Round))
        for (x in listOf(9.7f, 14.3f)) {
            oval(x, 12.6f, 1.05f, 1.3f * p.eyeScaleY, ink.face)
            if (p.eyeScaleY > 0.5f) dot(x + 0.38f, 12.1f, 0.4f, Color.White)
        }
    }
    drawPath(sparklePath(19.6f, 4.4f, 1.9f), ink.sunGold.copy(alpha = p.sparkOpacity))
}

// --- Extraer: libélula ---

private fun DrawScope.drawDragonfly(ink: BrandInk, p: Pose) {
    withTransform({
        rotate(p.rotation, Offset(12f, 12f))
        translate(0f, p.offsetY)
    }) {
        // Alas translúcidas que vibran (escala Y alrededor del centro).
        withTransform({ scale(1f, p.wingScaleY, Offset(12f, 12f)) }) {
            fun wing(cx: Float, cy: Float, rx: Float, ry: Float, angle: Float, fill: Color, edge: Color, vein: Boolean) {
                withTransform({ rotate(angle, Offset(cx, cy)) }) {
                    oval(cx, cy, rx, ry, fill.copy(alpha = p.wingOpacity))
                    ovalStroke(cx, cy, rx, ry, edge.copy(alpha = p.wingOpacity), 0.75f)
                    if (vein) drawLine(edge.copy(alpha = 0.5f * p.wingOpacity),
                        Offset(cx - rx * 0.8f, cy), Offset(cx + rx * 0.8f, cy), strokeWidth = 0.35f)
                }
            }
            wing(6.6f, 8.3f, 5.3f, 2.15f, -16f, ink.celadonPale, ink.celadonInk, true)
            wing(17.4f, 8.3f, 5.3f, 2.15f, 16f, ink.celadonPale, ink.celadonInk, true)
            wing(7.2f, 12.0f, 4.5f, 1.8f, 12f, ink.peach, ink.amberInk, false)
            wing(16.8f, 12.0f, 4.5f, 1.8f, -12f, ink.peach, ink.amberInk, false)
        }
        // Abdomen afilado con anillos ámbar.
        val abdomen = Path().apply {
            moveTo(10.75f, 10.6f)
            cubicTo(10.7f, 14f, 11.1f, 18.5f, 11.55f, 20.9f)
            quadraticBezierTo(12f, 21.9f, 12.45f, 20.9f)
            cubicTo(12.9f, 18.5f, 13.3f, 14f, 13.25f, 10.6f)
            close()
        }
        drawPath(abdomen, ink.moss)
        drawContext.canvas.save()
        drawContext.canvas.clipPath(abdomen)
        for (y in listOf(13.3f, 15.8f, 18.2f)) {
            drawLine(ink.sunAmber, Offset(10.5f, y), Offset(13.5f, y), strokeWidth = 0.85f)
        }
        drawContext.canvas.restore()
        // Tórax con lente ámbar y cabeza.
        oval(12f, 9.1f, 2.05f, 2.35f, ink.mossDeep)
        dot(12f, 9.1f, 0.95f, ink.sunGold)
        dot(11.7f, 8.8f, 0.32f, Color.White.copy(alpha = 0.9f))
        for (x in listOf(10.85f, 13.15f)) {
            dot(x, 5.7f, 1.65f, ink.celadon)
            drawCircle(ink.celadonInk, radius = 1.65f, center = Offset(x, 5.7f), style = Stroke(0.5f))
            dot(x - 0.45f, 5.2f, 0.52f, Color.White)
        }
        drawPath(Path().apply {
            moveTo(11.35f, 7.25f); quadraticBezierTo(12f, 7.85f, 12.65f, 7.25f)
        }, ink.face, style = Stroke(0.5f, cap = StrokeCap.Round))
    }
}

// --- Rejilla: gotita de rocío ---

private fun DrawScope.drawDewdrop(ink: BrandInk, p: Pose) {
    glow(12f, 7f, 7.5f, Color(0xFF6EE7B7).copy(alpha = 0.30f))
    withTransform({ rotate(p.rotation, Offset(12f, 24f)) }) {
        val drop = Path().apply {
            moveTo(12f, 3.4f)
            cubicTo(13.3f, 5.9f, 18.3f, 9.6f, 18.3f, 14.4f)
            cubicTo(18.3f, 18.1f, 15.5f, 21.0f, 12f, 21.0f)
            cubicTo(8.5f, 21.0f, 5.7f, 18.1f, 5.7f, 14.4f)
            cubicTo(5.7f, 9.6f, 10.7f, 5.9f, 12f, 3.4f)
            close()
        }
        withTransform({ translate(12.1f, 3.9f); rotate(-24.1f, Offset.Zero) }) {
            drawPath(leafPath(4.6f, 1.35f), ink.sage)
            drawPath(leafPath(4.6f, 1.35f), ink.mossDeep, style = Stroke(0.4f))
        }
        drawPath(drop, Brush.linearGradient(
            listOf(Color(0xFFECFBF5), ink.celadonPale, Color(0xFF8CC7B5)),
            start = Offset(9f, 6f), end = Offset(15f, 21f)))
        drawPath(drop, ink.celadonInk, style = Stroke(0.8f))
        // Reflejo en rejilla 2 × 2.
        for (row in 0 until 2) for (col in 0 until 2) {
            drawRoundRect(Color.White.copy(alpha = 0.92f),
                topLeft = Offset(8.0f + col * 2.0f, 9.4f + row * 2.0f),
                size = Size(1.5f, 1.5f),
                cornerRadius = androidx.compose.ui.geometry.CornerRadius(0.35f, 0.35f))
        }
        dot(9.5f, 17.0f, 0.9f, ink.cheek.copy(alpha = 0.42f))
        dot(15.6f, 17.0f, 0.9f, ink.cheek.copy(alpha = 0.42f))
        for (x in listOf(10.8f, 14.2f)) {
            oval(x, 15.3f, 0.75f, 0.95f * p.eyeScaleY, ink.faceCool)
            if (p.eyeScaleY > 0.5f) dot(x + 0.25f, 14.95f, 0.28f, Color.White)
        }
        drawPath(Path().apply {
            moveTo(11.6f, 17.1f); quadraticBezierTo(12.5f, 18.0f, 13.4f, 17.1f)
        }, ink.faceCool, style = Stroke(0.65f, cap = StrokeCap.Round))
    }
    pingMote(18.6f, 4.6f, 0.95f, ink.mint, p)
}

// --- Jardín: brote en maceta ---

private fun DrawScope.drawSprout(ink: BrandInk, p: Pose) {
    withTransform({
        rotate(p.rotation, Offset(12f, 24f))
        translate(0f, p.offsetY)
    }) {
        glow(12f, 12f, 11.5f, Color(0xFF34D399).copy(alpha = 0.20f))
        drawPath(Path().apply {
            moveTo(12f, 13.2f); cubicTo(12.05f, 11.3f, 11.7f, 9.6f, 12f, 7.6f)
        }, ink.moss, style = Stroke(1.35f, cap = StrokeCap.Round))
        val left = Path().apply {
            moveTo(11.9f, 10.4f)
            cubicTo(10.2f, 8.0f, 6.9f, 8.3f, 7.2f, 10.7f)
            cubicTo(7.5f, 12.4f, 10.5f, 12.1f, 11.9f, 10.4f)
            close()
        }
        val right = Path().apply {
            moveTo(12.0f, 8.9f)
            cubicTo(13.9f, 6.4f, 17.3f, 6.9f, 16.9f, 9.4f)
            cubicTo(16.5f, 11.2f, 13.4f, 10.9f, 12.0f, 8.9f)
            close()
        }
        drawPath(left, ink.sage); drawPath(left, ink.mossDeep, style = Stroke(0.55f))
        drawPath(right, ink.mint); drawPath(right, ink.mossDeep, style = Stroke(0.55f))
        pingMote(12f, 6.5f, 1.05f, ink.sunGold, p)
        val pot = Path().apply {
            moveTo(7.7f, 14.6f); lineTo(16.3f, 14.6f); lineTo(15.1f, 20.7f)
            quadraticBezierTo(14.95f, 21.5f, 14.2f, 21.5f); lineTo(9.8f, 21.5f)
            quadraticBezierTo(9.05f, 21.5f, 8.9f, 20.7f); close()
        }
        drawPath(pot, ink.terracotta)
        drawPath(pot, ink.clayInk, style = Stroke(0.6f, join = StrokeJoin.Round))
        drawRoundRect(ink.terracottaLight, topLeft = Offset(6.9f, 13.0f), size = Size(10.2f, 2.3f),
            cornerRadius = androidx.compose.ui.geometry.CornerRadius(1.15f, 1.15f))
        drawRoundRect(ink.clayInk, topLeft = Offset(6.9f, 13.0f), size = Size(10.2f, 2.3f),
            cornerRadius = androidx.compose.ui.geometry.CornerRadius(1.15f, 1.15f), style = Stroke(0.6f))
        dot(9.7f, 18.4f, 0.75f, ink.peach.copy(alpha = 0.55f))
        dot(14.3f, 18.4f, 0.75f, ink.peach.copy(alpha = 0.55f))
        dot(10.8f, 17.2f, 0.58f, Color.White)
        dot(13.2f, 17.2f, 0.58f, Color.White)
        drawPath(Path().apply {
            moveTo(11.3f, 18.6f); quadraticBezierTo(12f, 19.3f, 12.7f, 18.6f)
        }, Color.White, style = Stroke(0.6f, cap = StrokeCap.Round))
    }
}

/** Estrella de cuatro puntas (ChromaSolGeometry.sparkle). */
private fun sparklePath(cx: Float, cy: Float, r: Float): Path {
    val k = r * 0.28f
    return Path().apply {
        moveTo(cx, cy - r)
        quadraticBezierTo(cx + k, cy - k, cx + r, cy)
        quadraticBezierTo(cx + k, cy + k, cx, cy + r)
        quadraticBezierTo(cx - k, cy + k, cx - r, cy)
        quadraticBezierTo(cx - k, cy - k, cx, cy - r)
        close()
    }
}
