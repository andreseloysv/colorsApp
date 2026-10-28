// Tema Compose de ChromaSol: vuelca los tokens Solar en un ColorScheme de
// Material 3 (para que los componentes de Material hereden el aspecto) y
// expone la tabla completa con CompositionLocal (LocalSolarColors), la
// tipografía por rol (LocalSolarType) y el acceso estático SolarTheme.colors
// (equivalente al `Theme.*` de SwiftUI). Claro/oscuro sigue al sistema, sin
// ajuste en la app, igual que iOS.
package com.andreseloy.colorsapp.design

import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.material3.ColorScheme
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Shapes
import androidx.compose.material3.Typography
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.ReadOnlyComposable
import androidx.compose.runtime.compositionLocalOf

val LocalSolarColors = compositionLocalOf { SolarLight }
val LocalSolarType = compositionLocalOf { SolarType.DEFAULT }

/** Acceso estático estilo Swift: SolarTheme.colors.primary, SolarTheme.type.bodyMd. */
object SolarTheme {
    val colors: SolarColors
        @Composable @ReadOnlyComposable get() = LocalSolarColors.current
    val type: SolarType
        @Composable @ReadOnlyComposable get() = LocalSolarType.current
}

private fun SolarColors.toColorScheme(): ColorScheme {
    val base = if (dark) darkColorScheme() else lightColorScheme()
    return base.copy(
        primary = primary,
        onPrimary = onPrimary,
        primaryContainer = primaryContainer,
        onPrimaryContainer = onPrimaryContainer,
        inversePrimary = inversePrimary,
        secondary = secondary,
        onSecondary = onSecondary,
        secondaryContainer = secondaryContainer,
        onSecondaryContainer = onSecondaryContainer,
        tertiary = tertiary,
        onTertiary = onTertiary,
        tertiaryContainer = tertiaryContainer,
        onTertiaryContainer = onTertiaryContainer,
        error = error,
        onError = onError,
        errorContainer = errorContainer,
        onErrorContainer = onErrorContainer,
        background = surface,
        onBackground = onSurface,
        surface = surface,
        onSurface = onSurface,
        surfaceVariant = surfaceVariant,
        onSurfaceVariant = onSurfaceVariant,
        surfaceDim = surfaceDim,
        surfaceBright = surfaceBright,
        surfaceContainerLowest = containerLowest,
        surfaceContainerLow = containerLow,
        surfaceContainer = container,
        surfaceContainerHigh = containerHigh,
        surfaceContainerHighest = containerHighest,
        surfaceTint = surfaceTint,
        inverseSurface = inverseSurface,
        inverseOnSurface = inverseOnSurface,
        outline = outline,
        outlineVariant = outlineVariant,
    )
}

private fun SolarType.toMaterialTypography(): Typography = Typography(
    displayLarge = headlineXl,
    displayMedium = headlineLg,
    headlineLarge = headlineLgMobile,
    headlineMedium = headlineMd,
    headlineSmall = headlineSm,
    titleLarge = headlineMd,
    titleMedium = cardTitle,
    titleSmall = labelLg,
    bodyLarge = bodyLg,
    bodyMedium = bodyMd,
    bodySmall = bodySm,
    labelLarge = labelLg,
    labelMedium = labelMd,
    labelSmall = labelSm,
)

/** Tono de acento para insignias e iconos en círculo (Tone de iOS). */
enum class SolarTone { MOSS, AMBER, CELADON }

@Composable
fun SolarTone.accent(): androidx.compose.ui.graphics.Color = when (this) {
    SolarTone.MOSS -> SolarTheme.colors.primary
    SolarTone.AMBER -> SolarTheme.colors.secondary
    SolarTone.CELADON -> SolarTheme.colors.tertiary
}

@Composable
fun SolarTone.badgeFill(): androidx.compose.ui.graphics.Color = when (this) {
    SolarTone.MOSS -> SolarTheme.colors.mossBadge
    SolarTone.AMBER -> SolarTheme.colors.amberBadge
    SolarTone.CELADON -> SolarTheme.colors.celadonBadge
}

@Composable
fun SolarTone.onBadge(): androidx.compose.ui.graphics.Color = when (this) {
    SolarTone.MOSS -> SolarTheme.colors.onMossBadge
    SolarTone.AMBER -> SolarTheme.colors.onAmberBadge
    SolarTone.CELADON -> SolarTheme.colors.onCeladonBadge
}

/** Raíz del sistema de diseño (DesignSystemRoot de iOS). */
@Composable
fun ChromaSolTheme(
    darkTheme: Boolean = isSystemInDarkTheme(),
    content: @Composable () -> Unit,
) {
    val colors = if (darkTheme) SolarDark else SolarLight
    val type = SolarType.DEFAULT
    CompositionLocalProvider(
        LocalSolarColors provides colors,
        LocalSolarType provides type,
    ) {
        MaterialTheme(
            colorScheme = colors.toColorScheme(),
            typography = type.toMaterialTypography(),
            shapes = Shapes(
                extraSmall = SolarRadius.tagShape,
                small = SolarRadius.blockShape,
                medium = SolarRadius.cardShape,
                large = SolarRadius.cardShape,
            ),
            content = content,
        )
    }
}
