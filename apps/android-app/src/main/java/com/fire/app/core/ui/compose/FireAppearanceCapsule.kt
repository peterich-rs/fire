package com.fire.app.core.ui.compose

import androidx.compose.animation.animateColorAsState
import androidx.compose.animation.core.animateDpAsState
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.BrightnessAuto
import androidx.compose.material.icons.filled.DarkMode
import androidx.compose.material.icons.filled.LightMode
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.fire.app.core.theme.compose.FireAppearancePreference
import com.fire.app.core.theme.compose.FireShapes
import com.fire.app.core.theme.compose.fireExtended

private val SelectedTint = Color(0xFF2ED159)

data class FireAppearanceOption(
    val preference: FireAppearancePreference,
    val label: String,
    val icon: ImageVector,
)

@Composable
fun FireAppearanceCapsule(
    selected: FireAppearancePreference,
    onSelect: (FireAppearancePreference) -> Unit,
    modifier: Modifier = Modifier,
    options: List<FireAppearanceOption> = defaultAppearanceOptions(),
) {
    val normalized = when (selected) {
        FireAppearancePreference.Dark, FireAppearancePreference.System, FireAppearancePreference.Light -> selected
    }
    val selectedIndex = options.indexOfFirst { it.preference == normalized }.coerceAtLeast(0)

    BoxWithConstraints(
        modifier = modifier
            .fillMaxWidth()
            .height(52.dp)
            .clip(FireShapes.card)
            .background(MaterialTheme.fireExtended.surface)
            .padding(4.dp),
    ) {
        val segmentWidth = maxWidth / options.size
        val pillOffset by animateDpAsState(
            targetValue = segmentWidth * selectedIndex,
            animationSpec = tween(durationMillis = 220),
            label = "appearancePill",
        )
        Box(
            modifier = Modifier
                .offset(x = pillOffset)
                .width(segmentWidth)
                .fillMaxHeight()
                .shadow(2.dp, RoundedCornerShape(12.dp), clip = false)
                .clip(RoundedCornerShape(12.dp))
                .background(MaterialTheme.fireExtended.surfaceSecondary),
        )
        Row(modifier = Modifier.fillMaxWidth()) {
            options.forEach { option ->
                val isSelected = option.preference == normalized
                val tint by animateColorAsState(
                    targetValue = if (isSelected) SelectedTint else MaterialTheme.fireExtended.tertiaryInk,
                    label = "appearanceTint",
                )
                val interactionSource = remember(option.preference) { MutableInteractionSource() }
                Row(
                    modifier = Modifier
                        .weight(1f)
                        .fillMaxHeight()
                        .firePressBounce(interactionSource, FirePressBounceStyle.Chip)
                        .clickable(
                            interactionSource = interactionSource,
                            indication = null,
                            role = Role.Button,
                            onClick = { onSelect(option.preference) },
                        ),
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = androidx.compose.foundation.layout.Arrangement.Center,
                ) {
                    Icon(
                        imageVector = option.icon,
                        contentDescription = null,
                        tint = tint,
                        modifier = Modifier.padding(end = 4.dp),
                    )
                    Text(
                        text = option.label,
                        color = tint,
                        fontSize = 13.sp,
                        fontWeight = if (isSelected) FontWeight.SemiBold else FontWeight.Medium,
                    )
                }
            }
        }
    }
}

@Composable
private fun defaultAppearanceOptions(): List<FireAppearanceOption> = listOf(
    FireAppearanceOption(FireAppearancePreference.Dark, "深色", Icons.Filled.DarkMode),
    FireAppearanceOption(FireAppearancePreference.System, "系统", Icons.Filled.BrightnessAuto),
    FireAppearanceOption(FireAppearancePreference.Light, "浅色", Icons.Filled.LightMode),
)
