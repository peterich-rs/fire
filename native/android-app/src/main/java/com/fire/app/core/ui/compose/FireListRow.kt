package com.fire.app.core.ui.compose

import androidx.compose.foundation.background
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
import androidx.compose.foundation.layout.width
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.fire.app.core.theme.compose.FireDimens
import com.fire.app.core.theme.compose.FireShapes
import com.fire.app.core.theme.compose.fireExtended

data class FireListRowContent(
    val icon: ImageVector,
    val title: String,
    val subtitle: String? = null,
    val value: String? = null,
    val showsChevron: Boolean = true,
    val iconTint: Color = Color.White,
    val iconWellColor: Color,
)

@Composable
fun FireSettingsCard(
    modifier: Modifier = Modifier,
    content: @Composable () -> Unit,
) {
    Column(
        modifier = modifier
            .fillMaxWidth()
            .clip(FireShapes.card)
            .background(MaterialTheme.fireExtended.surface),
    ) {
        content()
    }
}

@Composable
fun FireListRow(
    content: FireListRowContent,
    onClick: (() -> Unit)?,
    modifier: Modifier = Modifier,
    showDivider: Boolean = false,
) {
    val interactionSource = remember { MutableInteractionSource() }
    val enabled = onClick != null
    Column(modifier = modifier.fillMaxWidth()) {
        if (showDivider) {
            HorizontalDivider(
                modifier = Modifier.padding(start = 14.dp + FireDimens.iconWellSize + 14.dp),
                thickness = 0.5.dp,
                color = MaterialTheme.fireExtended.divider,
            )
        }
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .then(
                    if (enabled) {
                        Modifier
                            .firePressBounce(interactionSource, FirePressBounceStyle.Compact)
                            .clickable(
                                interactionSource = interactionSource,
                                indication = null,
                                enabled = true,
                                role = Role.Button,
                                onClick = { onClick?.invoke() },
                            )
                    } else {
                        Modifier
                    },
                )
                .padding(horizontal = 14.dp, vertical = 14.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Box(
                modifier = Modifier
                    .size(FireDimens.iconWellSize)
                    .clip(FireShapes.iconWell)
                    .background(content.iconWellColor),
                contentAlignment = Alignment.Center,
            ) {
                Icon(
                    imageVector = content.icon,
                    contentDescription = null,
                    tint = content.iconTint,
                    modifier = Modifier.size(15.dp),
                )
            }
            Spacer(Modifier.width(14.dp))
            Column(modifier = Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                Text(
                    text = content.title,
                    color = MaterialTheme.fireExtended.ink,
                    fontSize = 16.sp,
                    fontWeight = FontWeight.Normal,
                    maxLines = 1,
                )
                val subtitle = content.subtitle?.trim().orEmpty()
                if (subtitle.isNotEmpty()) {
                    Text(
                        text = subtitle,
                        color = MaterialTheme.fireExtended.subtleInk,
                        fontSize = 13.sp,
                        maxLines = 2,
                    )
                }
            }
            val value = content.value?.trim().orEmpty()
            if (value.isNotEmpty()) {
                Text(
                    text = value,
                    color = MaterialTheme.fireExtended.tertiaryInk,
                    fontSize = 16.sp,
                    maxLines = 1,
                )
                Spacer(Modifier.width(6.dp))
            }
            if (content.showsChevron) {
                Icon(
                    imageVector = Icons.AutoMirrored.Filled.KeyboardArrowRight,
                    contentDescription = null,
                    tint = MaterialTheme.fireExtended.tertiaryInk,
                    modifier = Modifier.size(18.dp),
                )
            }
        }
    }
}

@Composable
fun FireSettingsCardRows(
    rows: List<Pair<FireListRowContent, (() -> Unit)?>>,
    modifier: Modifier = Modifier,
) {
    FireSettingsCard(modifier = modifier) {
        rows.forEachIndexed { index, (content, onClick) ->
            FireListRow(
                content = content,
                onClick = onClick,
                showDivider = index > 0,
            )
        }
    }
}

@Composable
fun FireCardSpacer() {
    Spacer(Modifier.height(16.dp))
}
