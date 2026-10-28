// Cabecera de marca (FeedHeader / Chrome de iOS): emblema + «ChromaSol» con
// punto ámbar y la sección en mayúsculas debajo; acciones circulares a la
// derecha (la ola 2 pone las suyas: cámara, jardín, ajustes…).
package com.andreseloy.colorsapp.design

import androidx.compose.foundation.Image
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.background
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import com.andreseloy.colorsapp.R

@Composable
fun SolarHeader(
    section: String,
    modifier: Modifier = Modifier,
    trailing: @Composable () -> Unit = {},
) {
    val colors = SolarTheme.colors
    Row(
        modifier = modifier
            .fillMaxWidth()
            .height(SolarSizes.header)
            .padding(horizontal = SolarSpacing.margin),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Image(
            // No el icono adaptativo (XML): painterResource no lo carga; el
            // brand_mark es un recorte del máster generado a mano (ola 2 lo
            // mete en make_icon o lo sustituye por el emblema vectorial).
            painter = painterResource(R.drawable.brand_mark),
            contentDescription = null,
            modifier = Modifier
                .size(SolarSizes.brandMark)
                .clip(androidx.compose.foundation.shape.RoundedCornerShape(8.dp)),
        )
        Column(Modifier.padding(start = SolarSpacing.sm)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text(
                    text = stringResource(R.string.app_name),
                    style = SolarTheme.type.brand,
                    color = colors.primary,
                )
                Box(
                    Modifier
                        .padding(start = 3.dp)
                        .size(6.dp)
                        .clip(CircleShape)
                        .background(colors.sunAmber),
                )
            }
            Text(
                text = section,
                style = SolarTheme.type.overline,
                color = colors.secondary,
            )
        }
        Spacer(Modifier.weight(1f))
        Row(horizontalArrangement = Arrangement.spacedBy(SolarSpacing.sm)) { trailing() }
    }
}

/**
 * Botón de cabecera con personaje de marca (W5): el sol-espíritu y el avatar
 * del Jardín de iOS (FIDELITY §2.2). Mismo círculo y pulsación que
 * SolarHeaderButton; el personaje es decorativo y habla la descripción.
 */
@Composable
fun SolarHeaderCreatureButton(
    creature: BrandCreature,
    contentDescription: String,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val colors = SolarTheme.colors
    val interaction = remember { MutableInteractionSource() }
    Box(
        modifier = modifier
            .size(SolarSizes.headerButton)
            .solarPress(interaction, 0.95f)
            .clip(CircleShape)
            .background(colors.card)
            .clickable(interactionSource = interaction, indication = null) { onClick() }
            .semantics { this.contentDescription = contentDescription },
        contentAlignment = Alignment.Center,
    ) {
        BrandCreatureIcon(creature, size = 30.dp)
    }
}

@Composable
fun SolarHeaderButton(
    icon: androidx.compose.ui.graphics.vector.ImageVector,
    contentDescription: String,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val colors = SolarTheme.colors
    val interaction = remember { MutableInteractionSource() }
    Box(
        modifier = modifier
            .size(SolarSizes.headerButton)
            .solarPress(interaction, 0.95f)
            .clip(CircleShape)
            .background(colors.card)
            .clickable(interactionSource = interaction, indication = null) { onClick() },
        contentAlignment = Alignment.Center,
    ) {
        Icon(
            icon, contentDescription = contentDescription,
            tint = colors.primary, modifier = Modifier.size(22.dp),
        )
    }
}
