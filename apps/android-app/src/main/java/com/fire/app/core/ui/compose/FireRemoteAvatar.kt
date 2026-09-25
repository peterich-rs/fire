package com.fire.app.core.ui.compose

import android.widget.ImageView
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.viewinterop.AndroidView
import com.fire.app.core.image.FireAvatarUrls
import com.fire.app.core.image.FireImageLoader
import com.fire.app.core.theme.compose.fireExtended

@Composable
fun FireRemoteAvatar(
    username: String,
    avatarTemplate: String?,
    modifier: Modifier = Modifier,
    size: Dp = 40.dp,
) {
    val url = FireAvatarUrls.build(avatarTemplate)
    val well = MaterialTheme.fireExtended.iconWell
    AndroidView(
        modifier = modifier
            .size(size)
            .clip(CircleShape)
            .background(well),
        factory = { context ->
            ImageView(context).apply {
                scaleType = ImageView.ScaleType.CENTER_CROP
                contentDescription = username
            }
        },
        update = { view ->
            if (url != null) {
                FireImageLoader.load(url, view)
            } else {
                view.setImageDrawable(null)
            }
        },
    )
}
