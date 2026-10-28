// Tipografía por rol: copia de ios/ColorsApp/Design/Typography.swift (§2.2).
// Literata (titulares) y Plus Jakarta Sans (cuerpo), fuentes variables SIL OFL
// 1.1 empaquetadas en res/font; mono del sistema para hex/Lab. Sin Dynamic
// Type en Android: los tamaños están en sp y escalan con el tamaño de letra
// del sistema, igual que relativeTo en iOS a falta de granularidad por rol.
package com.andreseloy.colorsapp.design

import androidx.compose.runtime.Composable
import androidx.compose.runtime.Immutable
import androidx.compose.runtime.remember
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.ExperimentalTextApi
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.Font
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontVariation
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.sp
import com.andreseloy.colorsapp.R

/** Pesos del eje wght de las fuentes variables. */
@OptIn(ExperimentalTextApi::class)
private fun variableFamily(resId: Int): FontFamily = FontFamily(
    Font(resId, FontWeight.Normal, variationSettings = FontVariation.Settings(FontVariation.weight(400))),
    Font(resId, FontWeight.Medium, variationSettings = FontVariation.Settings(FontVariation.weight(500))),
    Font(resId, FontWeight.SemiBold, variationSettings = FontVariation.Settings(FontVariation.weight(600))),
    Font(resId, FontWeight.Bold, variationSettings = FontVariation.Settings(FontVariation.weight(700))),
)

val LiterataFamily: FontFamily = variableFamily(R.font.literata)
val JakartaFamily: FontFamily = variableFamily(R.font.plus_jakarta_sans)

/** Los 16 roles de TextRole en iOS, con su tamaño, altura y tracking. */
@Immutable
data class SolarType(
    val headlineXl: TextStyle,
    val headlineXlMobile: TextStyle,
    val headlineLg: TextStyle,
    val headlineLgMobile: TextStyle,
    val headlineMd: TextStyle,
    val headlineSm: TextStyle,
    val brand: TextStyle,
    val cardTitle: TextStyle,
    val bodyLg: TextStyle,
    val bodyMd: TextStyle,
    val bodySm: TextStyle,
    val labelLg: TextStyle,
    val labelMd: TextStyle,
    val labelSm: TextStyle,
    val overline: TextStyle,
    val hex: TextStyle,
) {
    companion object {
        private fun serif(weight: FontWeight, size: Int, line: Int, tracking: Float = 0f) = TextStyle(
            fontFamily = LiterataFamily, fontWeight = weight,
            fontSize = size.sp, lineHeight = line.sp, letterSpacing = tracking.sp,
        )

        private fun sans(weight: FontWeight, size: Int, line: Int, tracking: Float = 0f) = TextStyle(
            fontFamily = JakartaFamily, fontWeight = weight,
            fontSize = size.sp, lineHeight = line.sp, letterSpacing = tracking.sp,
        )

        /** tracking en iOS va en pt; en Compose letterSpacing también acepta sp. */
        val DEFAULT = SolarType(
            headlineXl = serif(FontWeight.SemiBold, 36, 44, -0.72f),
            headlineXlMobile = serif(FontWeight.SemiBold, 28, 36, -0.28f),
            headlineLg = serif(FontWeight.SemiBold, 30, 38),
            headlineLgMobile = serif(FontWeight.SemiBold, 24, 32),
            headlineMd = serif(FontWeight.Medium, 20, 28),
            headlineSm = serif(FontWeight.Medium, 18, 24),
            brand = serif(FontWeight.Medium, 18, 24, -0.45f),
            cardTitle = serif(FontWeight.SemiBold, 15, 19),
            bodyLg = sans(FontWeight.Normal, 16, 24),
            bodyMd = sans(FontWeight.Normal, 14, 20),
            bodySm = sans(FontWeight.Normal, 12, 16),
            labelLg = sans(FontWeight.SemiBold, 14, 18, 0.14f),
            labelMd = sans(FontWeight.SemiBold, 12, 16, 0.24f),
            labelSm = sans(FontWeight.Bold, 11, 13, 0.44f),
            overline = sans(FontWeight.Bold, 11, 13, 1.10f),
            hex = TextStyle(
                fontFamily = FontFamily.Monospace, fontWeight = FontWeight.Medium,
                fontSize = 12.sp, lineHeight = 16.sp,
            ),
        )
    }
}

/** ¿Están las fuentes empaquetadas? (para diagnósticos; espejo de FontRegistry). */
@Composable
fun rememberBundledFontsAvailable(): Boolean {
    val context = LocalContext.current
    return remember(context) {
        runCatching {
            context.resources.getFont(R.font.literata)
            context.resources.getFont(R.font.plus_jakarta_sans)
            true
        }.getOrDefault(false)
    }
}
