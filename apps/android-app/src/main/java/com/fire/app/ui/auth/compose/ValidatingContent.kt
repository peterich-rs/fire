package com.fire.app.ui.auth.compose

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.fire.app.R
import com.fire.app.core.theme.compose.fireExtended

@Composable
fun ValidatingContent(
    message: String,
    detail: String = "",
    canCancel: Boolean,
    onCancel: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val extended = MaterialTheme.fireExtended

    Column(
        modifier = modifier
            .fillMaxWidth()
            .padding(vertical = 28.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(14.dp),
    ) {
        Row(
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            CircularProgressIndicator(
                modifier = Modifier.size(20.dp),
                strokeWidth = 2.dp,
                color = extended.subtleInk,
            )
            Text(
                text = message,
                color = extended.subtleInk,
                fontSize = 15.sp,
                maxLines = 2,
                textAlign = TextAlign.Center,
            )
        }

        if (detail.isNotBlank()) {
            Text(
                text = detail,
                color = extended.tertiaryInk,
                fontSize = 12.sp,
                maxLines = 2,
                textAlign = TextAlign.Center,
                modifier = Modifier.padding(horizontal = 16.dp),
            )
        }

        if (canCancel) {
            TextButton(onClick = onCancel) {
                Text(
                    text = stringResource(R.string.login_cancel_auto_login),
                    color = extended.accent,
                )
            }
        }
    }
}
