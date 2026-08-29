package com.fire.app.core.ui.compose

import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.tween
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.interaction.collectIsPressedAsState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.graphicsLayer

enum class FirePressBounceStyle {
    Button,
    Compact,
    Chip,
}

@Composable
fun Modifier.firePressBounce(
    interactionSource: MutableInteractionSource,
    style: FirePressBounceStyle = FirePressBounceStyle.Compact,
    enabled: Boolean = true,
): Modifier {
    val pressed by interactionSource.collectIsPressedAsState()
    val target = if (enabled && pressed) {
        when (style) {
            FirePressBounceStyle.Button -> 0.97f
            FirePressBounceStyle.Compact -> 0.96f
            FirePressBounceStyle.Chip -> 0.94f
        }
    } else {
        1f
    }
    val scale by animateFloatAsState(
        targetValue = target,
        animationSpec = tween(durationMillis = if (pressed) 70 else 160),
        label = "firePressBounce",
    )
    return graphicsLayer {
        scaleX = scale
        scaleY = scale
    }
}
