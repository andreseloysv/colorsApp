// Puerta de movimiento y luz ambiental (W5): espejo de MotionGate y
// LightMotesOverlay de iOS (docs/design/FIDELITY.md §1). «Quitar
// animaciones» del sistema (ANIMATOR_DURATION_SCALE = 0) deja todo en la
// pose de reposo, como accessibilityReduceMotion en iOS.
package com.andreseloy.colorsapp.design

import android.provider.Settings
import androidx.compose.foundation.Canvas
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableLongStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.runtime.withFrameMillis
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import kotlin.math.sin

/** True si el sistema pide quitar las animaciones. */
@Composable
fun rememberReduceMotion(): Boolean {
    val context = LocalContext.current
    return remember {
        runCatching {
            Settings.Global.getFloat(
                context.contentResolver, Settings.Global.ANIMATOR_DURATION_SCALE, 1f,
            ) == 0f
        }.getOrDefault(false)
    }
}

/**
 * Reloj ambiental en milisegundos (BrandMotionClock de iOS). Con movimiento
 * reducido devuelve siempre 0: todas las poses quedan en reposo.
 */
@Composable
fun rememberAmbientClockMs(reduceMotion: Boolean): Long {
    var now by remember { mutableLongStateOf(0L) }
    LaunchedEffect(reduceMotion) {
        if (reduceMotion) {
            now = 0L
            return@LaunchedEffect
        }
        var origin = -1L
        while (true) {
            withFrameMillis { frame ->
                if (origin < 0) origin = frame
                now = frame - origin
            }
        }
    }
    return now
}

// Motas deterministas (sin RNG, como en iOS): posición x/y en 0..1, rádio en
// dp, tono (0 = dorado, 1 = menta) y fase/velocidad del vaivén.
private data class Mote(val x: Float, val y: Float, val r: Float, val tone: Int, val phase: Float, val speed: Float)

private val MOTES = listOf(
    Mote(0.08f, 0.12f, 1.6f, 0, 0.0f, 0.9f), Mote(0.22f, 0.38f, 1.1f, 1, 1.7f, 0.7f),
    Mote(0.36f, 0.07f, 1.3f, 0, 3.1f, 1.1f), Mote(0.51f, 0.55f, 1.0f, 0, 0.8f, 0.6f),
    Mote(0.64f, 0.22f, 1.7f, 1, 2.4f, 0.8f), Mote(0.78f, 0.44f, 1.2f, 0, 4.2f, 1.0f),
    Mote(0.90f, 0.09f, 1.4f, 0, 1.2f, 0.7f), Mote(0.14f, 0.68f, 1.2f, 1, 5.0f, 0.9f),
    Mote(0.30f, 0.82f, 1.5f, 0, 2.9f, 0.6f), Mote(0.57f, 0.88f, 1.1f, 1, 0.4f, 1.2f),
    Mote(0.73f, 0.74f, 1.6f, 0, 3.8f, 0.8f), Mote(0.88f, 0.62f, 1.0f, 1, 2.1f, 1.0f),
    Mote(0.44f, 0.30f, 0.9f, 1, 5.6f, 0.7f), Mote(0.06f, 0.50f, 1.0f, 0, 1.9f, 1.1f),
)

/**
 * Motas de luz que derivan sobre el marco (LightMotesOverlay, FIDELITY §1.3):
 * puntos dorados/menta con halo suave, vaivén lento y parpadeo leve. No
 * interactiva. En iOS respeta las zonas neutras de los pocillos; aquí va
 * sobre el fondo de la pantalla con alfa bajo (desviación anotada en W5).
 */
@Composable
fun LightMotes(modifier: Modifier = Modifier) {
    val reduce = rememberReduceMotion()
    val now = rememberAmbientClockMs(reduce)
    val gold = Color(0xFFFBBF24)
    val mint = Color(0xFFA1D2AC)
    Canvas(modifier) {
        val t = now / 1000f
        for (m in MOTES) {
            val drift = if (reduce) 0f else sin(t * m.speed + m.phase) * 6.dp.toPx()
            val bob = if (reduce) 0f else sin(t * m.speed * 0.7f + m.phase * 2f) * 9.dp.toPx()
            // Alfa contenido: en iOS las motas no pisan los pocillos de color.
            val twinkle = (if (reduce) 0.55f else 0.35f + 0.3f * (0.5f + 0.5f * sin(t * (0.8f + m.speed * 0.4f) + m.phase * 3f))) * 0.6f
            val center = Offset(m.x * size.width + drift, m.y * size.height + bob)
            val base = if (m.tone == 0) gold else mint
            drawCircle(base.copy(alpha = 0.10f * twinkle + 0.04f), radius = m.r.dp.toPx() * 3.2f, center = center)
            drawCircle(base.copy(alpha = twinkle), radius = m.r.dp.toPx(), center = center)
        }
    }
}
