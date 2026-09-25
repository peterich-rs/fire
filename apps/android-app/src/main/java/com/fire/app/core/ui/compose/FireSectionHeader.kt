package com.fire.app.core.ui.compose

import androidx.compose.foundation.layout.padding
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.fire.app.core.theme.compose.fireExtended

@Composable
fun FireSectionHeader(
    title: String,
    modifier: Modifier = Modifier,
) {
    val isLatin = title.all { it.isLetter() || it.isWhitespace() || it == '&' || it == '-' }
    Text(
        text = if (isLatin) title.uppercase() else title,
        modifier = modifier.padding(start = 4.dp, end = 4.dp, top = 4.dp),
        color = MaterialTheme.fireExtended.tertiaryInk,
        fontSize = 12.sp,
        fontWeight = FontWeight.SemiBold,
    )
}
