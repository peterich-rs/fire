package com.fire.app.ui.auth.compose

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.fire.app.R
import com.fire.app.core.theme.compose.FireShapes
import com.fire.app.core.theme.compose.fireExtended
import com.fire.app.ui.auth.FireExternalLoginMethod

@Composable
fun ExternalLoginRow(
    highlightedMethod: FireExternalLoginMethod?,
    onExternal: (FireExternalLoginMethod) -> Unit,
    modifier: Modifier = Modifier,
    enabled: Boolean = true,
) {
    val extended = MaterialTheme.fireExtended

    Column(
        modifier = modifier
            .fillMaxWidth()
            .alpha(if (enabled) 1f else 0.45f),
    ) {
        Text(
            text = stringResource(R.string.login_other_methods),
            color = extended.tertiaryInk,
            fontSize = 13.sp,
            modifier = Modifier
                .padding(top = 18.dp, bottom = 14.dp)
                .fillMaxWidth(),
            textAlign = TextAlign.Center,
        )

        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            FireExternalLoginMethod.entries.forEach { method ->
                val isHighlighted = highlightedMethod == method
                Box(
                    modifier = Modifier
                        .weight(1f)
                        .height(52.dp)
                        .clip(FireShapes.card)
                        .background(extended.surfaceSecondary)
                        .border(
                            width = if (isHighlighted) 1.5.dp else 1.dp,
                            color = if (isHighlighted) extended.accent else extended.divider,
                            shape = FireShapes.card,
                        )
                        .clickable(enabled = enabled) { onExternal(method) },
                    contentAlignment = Alignment.Center,
                ) {
                    Icon(
                        painter = painterResource(method.iconRes),
                        contentDescription = stringResource(providerContentDescription(method)),
                        tint = Color.Unspecified,
                        modifier = Modifier.size(24.dp),
                    )
                }
            }
        }
    }
}

private fun providerContentDescription(method: FireExternalLoginMethod): Int = when (method) {
    FireExternalLoginMethod.Google -> R.string.login_provider_google
    FireExternalLoginMethod.GitHub -> R.string.login_provider_github
    FireExternalLoginMethod.X -> R.string.login_provider_x
    FireExternalLoginMethod.Discord -> R.string.login_provider_discord
    FireExternalLoginMethod.Apple -> R.string.login_provider_apple
    FireExternalLoginMethod.Passkey -> R.string.login_provider_passkey
}
