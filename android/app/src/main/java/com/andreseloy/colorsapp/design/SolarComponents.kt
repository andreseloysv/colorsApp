// Componentes base que toda pantalla necesita: tarjetas, pocillo neutro,
// tiras de color, botones, chips, cabecera de marca y barra de pestañas.
// Copian las medidas y el comportamiento de ios/ColorsApp/Design/Components
// (Cards, Chrome, Controls, SwatchWell) y de RootTabBar; el movimiento
// ambiental y los personajes de marca se portan en la ola 2.
package com.andreseloy.colorsapp.design

import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.spring
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.interaction.collectIsPressedAsState
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.defaultMinSize
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Icon
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.blur
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.scale
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp

/** Pulsación con escala 0,97 (SolarPressStyle de iOS; sin comprobación de
 *  «reducir movimiento» del sistema en esta fundación). */
@Composable
fun Modifier.solarPress(
    interactionSource: MutableInteractionSource,
    scaleTarget: Float = 0.97f,
): Modifier {
    val pressed by interactionSource.collectIsPressedAsState()
    val scale by animateFloatAsState(
        targetValue = if (pressed) scaleTarget else 1f,
        animationSpec = spring(dampingRatio = 0.8f, stiffness = 900f),
        label = "solarPress",
    )
    return this.scale(scale)
}

/** Tarjeta del marco (solarCard de iOS): relleno card, radio 12, sombra sepia E1. */
@Composable
fun SolarCard(
    modifier: Modifier = Modifier,
    fill: Color = SolarTheme.colors.card,
    contentPadding: PaddingValues = PaddingValues(SolarSpacing.margin),
    content: @Composable () -> Unit,
) {
    val colors = SolarTheme.colors
    Surface(
        modifier = modifier.shadow(
            elevation = 6.dp,
            shape = SolarRadius.cardShape,
            ambientColor = if (colors.dark) Color.Black else SepiaShadow,
            spotColor = if (colors.dark) Color.Black else SepiaShadow,
        ),
        shape = SolarRadius.cardShape,
        color = fill,
        shadowElevation = 0.dp,
    ) {
        Box(Modifier.padding(contentPadding)) { content() }
    }
}

/**
 * Pocillo neutro de juicio de color (§1.4): fondo acromático donde viven los
 * swatches de datos. Ningún color del marco entra aquí.
 */
@Composable
fun WellContainer(
    modifier: Modifier = Modifier,
    compact: Boolean = false,
    content: @Composable () -> Unit,
) {
    val colors = SolarTheme.colors
    Box(
        modifier = modifier
            .clip(SolarRadius.cardShape)
            .background(colors.wellFill)
            .border(1.dp, colors.wellEdge, SolarRadius.cardShape)
            .padding(if (compact) SolarSpacing.wellPaddingCompact else SolarSpacing.wellPadding),
    ) { content() }
}

/** Tira horizontal de colores de datos (ARGB ya calculados por el motor). */
@Composable
fun SwatchStrip(
    argbColors: List<Int>,
    modifier: Modifier = Modifier,
    height: androidx.compose.ui.unit.Dp = 112.dp,
    weights: List<Float>? = null,
) {
    val colors = SolarTheme.colors
    Row(
        modifier = modifier
            .fillMaxWidth()
            .height(height)
            .clip(SolarRadius.blockShape),
        horizontalArrangement = Arrangement.spacedBy(SolarSpacing.swatchDivider),
    ) {
        argbColors.forEachIndexed { index, argb ->
            Box(
                Modifier
                    .weight(weights?.getOrNull(index) ?: 1f)
                    .fillMaxHeight()
                    .background(Color(argb))
                    .border(0.5.dp, colors.swatchHairline),
            )
        }
    }
}

/** CTA principal ámbar (como «Otra combinación» del Feed): cápsula con degradado. */
@Composable
fun SolarPrimaryButton(
    text: String,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    icon: ImageVector? = null,
    enabled: Boolean = true,
) {
    val colors = SolarTheme.colors
    val interaction = remember { MutableInteractionSource() }
    Button(
        onClick = onClick,
        enabled = enabled,
        modifier = modifier
            .fillMaxWidth()
            .solarPress(interaction)
            .shadow(10.dp, RoundedCornerShape(50), ambientColor = colors.mossGlow, spotColor = colors.mossGlow),
        interactionSource = interaction,
        shape = RoundedCornerShape(50),
        colors = ButtonDefaults.buttonColors(
            containerColor = colors.secondary,
            contentColor = colors.onSecondary,
        ),
        contentPadding = PaddingValues(
            horizontal = SolarSpacing.lg, vertical = SolarSpacing.ctaVertical,
        ),
    ) {
        if (icon != null) {
            Icon(icon, contentDescription = null, Modifier.size(18.dp))
            Box(Modifier.width(SolarSpacing.sm))
        }
        Text(text, style = SolarTheme.type.labelLg)
    }
}

/** Botón secundario musgo (contorno). */
@Composable
fun SolarSecondaryButton(
    text: String,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    enabled: Boolean = true,
) {
    val interaction = remember { MutableInteractionSource() }
    Button(
        onClick = onClick,
        enabled = enabled,
        modifier = modifier.solarPress(interaction),
        interactionSource = interaction,
        shape = RoundedCornerShape(50),
        colors = ButtonDefaults.buttonColors(
            containerColor = SolarTheme.colors.primary,
            contentColor = SolarTheme.colors.onPrimary,
        ),
        contentPadding = PaddingValues(
            horizontal = SolarSpacing.lg, vertical = SolarSpacing.buttonVertical,
        ),
    ) {
        Text(text, style = SolarTheme.type.labelLg)
    }
}

/** Chip de filtro (Todo / 2 colores / …): cápsula musgo si está activo. */
@Composable
fun SolarChip(
    text: String,
    selected: Boolean,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    dot: Color? = null,
) {
    val colors = SolarTheme.colors
    val interaction = remember { MutableInteractionSource() }
    val bg = if (selected) colors.primary else colors.containerLow
    val fg = if (selected) colors.onPrimary else colors.onSurfaceVariant
    Row(
        modifier = modifier
            .solarPress(interaction, 0.95f)
            .clip(RoundedCornerShape(50))
            .background(bg)
            .clickable(interactionSource = interaction, indication = null, role = Role.Tab) { onClick() }
            .semantics { this.selected = selected }
            .padding(horizontal = SolarSpacing.md, vertical = SolarSpacing.chipVertical)
            .defaultMinSize(minHeight = 32.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(6.dp),
    ) {
        if (dot != null) {
            Box(Modifier.size(8.dp).clip(CircleShape).background(dot))
        }
        Text(text, style = SolarTheme.type.labelMd, color = fg)
    }
}

/** Insignia circular con icono en un tono (insignias de tarjetas en iOS). */
@Composable
fun ToneBadgeIcon(
    icon: ImageVector,
    tone: SolarTone,
    contentDescription: String?,
    modifier: Modifier = Modifier,
    size: androidx.compose.ui.unit.Dp = SolarSizes.sourceIcon,
) {
    Box(
        modifier = modifier
            .size(size)
            .clip(CircleShape)
            .background(tone.badgeFill()),
        contentAlignment = Alignment.Center,
    ) {
        Icon(
            icon, contentDescription = contentDescription,
            tint = tone.onBadge(), modifier = Modifier.size(size * 0.55f),
        )
    }
}

/** Lavado difuso cálido o verde de una esquina de tarjeta (SolarWash de iOS). */
@Composable
fun SolarWash(warm: Boolean, modifier: Modifier = Modifier) {
    val colors = SolarTheme.colors
    Box(
        modifier
            .size(144.dp)
            .blur(40.dp)
            .clip(CircleShape)
            .background(if (warm) colors.washWarm else colors.washGreen),
    )
}

/**
 * Pergamino esmerilado (ParchmentFrost de iOS): tinte frostTint al 78 % con
 * filo de latón. En iOS lleva además desenfoque ultraThin; en Android un
 * desenfoque real de fondo exige API 31+ y coste en listas, así que esta
 * fundación usa solo el tinte (docs/ANDROID.md §No idéntico).
 */
fun Modifier.parchmentFrost(colors: SolarColors): Modifier = this
    .background(colors.frostTint)
    .border(0.5.dp, colors.brassHairline)

/** Una pestaña de la barra inferior. */
data class SolarTabItem(
    val route: String,
    val title: String,
    val icon: ImageVector,
    val badge: String? = null,
    val contentDescription: String = title,
    /** Personaje de marca (W5): si está, sustituye al glifo como en iOS. */
    val creature: BrandCreature? = null,
)

/**
 * Barra de pestañas (RootTabBar de iOS): 64 dp, elementos centrados con
 * icono 24 y etiqueta labelSm, halo musgo en la activa, pulsación 0,95.
 * Sin NavigationBar de Material: en iOS es una barra propia y el aspecto
 * manda.
 */
@Composable
fun SolarTabBar(
    items: List<SolarTabItem>,
    selectedRoute: String?,
    onSelect: (SolarTabItem) -> Unit,
    modifier: Modifier = Modifier,
) {
    val colors = SolarTheme.colors
    Row(
        modifier = modifier
            .fillMaxWidth()
            .height(SolarSizes.tabBar)
            .background(colors.frostTint)
            .border(0.5.dp, colors.brassHairline)
            .padding(horizontal = SolarSpacing.gutter),
        horizontalArrangement = Arrangement.SpaceAround,
        verticalAlignment = Alignment.CenterVertically,
    ) {
        for (item in items) {
            val selected = item.route == selectedRoute
            val interaction = remember(item.route) { MutableInteractionSource() }
            Box(
                modifier = Modifier
                    .weight(1f)
                    .fillMaxHeight()
                    .solarPress(interaction, 0.95f)
                    .clickable(interactionSource = interaction, indication = null, role = Role.Tab) {
                        onSelect(item)
                    }
                    .semantics {
                        this.selected = selected
                        contentDescription = item.badge?.let { "${item.title}, $it" } ?: item.title
                    },
                contentAlignment = Alignment.Center,
            ) {
                Column(
                    modifier = Modifier.width(64.dp),
                    horizontalAlignment = Alignment.CenterHorizontally,
                    verticalArrangement = Arrangement.spacedBy(2.dp),
                ) {
                    Box(contentAlignment = Alignment.Center) {
                        if (selected) {
                            Box(
                                Modifier
                                    .size(40.dp)
                                    .clip(CircleShape)
                                    .background(colors.mossGlow),
                            )
                        }
                        if (item.creature != null) {
                            // Personaje original animado (FIDELITY §2.3); el
                            // glifo queda como respaldo sin personaje.
                            BrandCreatureIcon(item.creature)
                        } else {
                            Icon(
                                imageVector = item.icon,
                                contentDescription = null,
                                tint = if (selected) colors.primary else colors.onSurfaceVariant,
                                modifier = Modifier.size(26.dp),
                            )
                        }
                        if (item.badge != null) {
                            Box(
                                Modifier
                                    .align(Alignment.TopEnd)
                                    .clip(RoundedCornerShape(50))
                                    .background(colors.secondary)
                                    .padding(horizontal = 4.dp),
                            ) {
                                Text(
                                    item.badge,
                                    style = SolarTheme.type.labelSm,
                                    color = colors.onSecondary,
                                )
                            }
                        }
                    }
                    Text(
                        text = item.title,
                        style = SolarTheme.type.labelSm.copy(
                            fontWeight = if (selected) FontWeight.Bold else FontWeight.Medium,
                        ),
                        color = if (selected) colors.primary else colors.onSurfaceVariant,
                        maxLines = 1,
                    )
                }
            }
        }
    }
}
