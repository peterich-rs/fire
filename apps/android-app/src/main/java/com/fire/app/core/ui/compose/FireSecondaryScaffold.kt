package com.fire.app.core.ui.compose

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.sp
import com.fire.app.core.theme.compose.FireAppearancePreference
import com.fire.app.core.theme.compose.FireTheme
import com.fire.app.core.theme.compose.fireExtended

@Composable
fun FireAppTheme(content: @Composable () -> Unit) {
    val context = LocalContext.current
    val preference = FireAppearancePreference.load(context)
    FireTheme(preference = preference, content = content)
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun FireSecondaryScaffold(
    title: String,
    onBack: (() -> Unit)?,
    modifier: Modifier = Modifier,
    actions: @Composable () -> Unit = {},
    content: @Composable (PaddingValues) -> Unit,
) {
    val colors = MaterialTheme.fireExtended
    Scaffold(
        modifier = modifier.fillMaxSize(),
        containerColor = colors.canvasMid,
        topBar = {
            TopAppBar(
                title = {
                    Text(
                        text = title,
                        color = colors.ink,
                        fontSize = 17.sp,
                        fontWeight = FontWeight.SemiBold,
                    )
                },
                navigationIcon = {
                    if (onBack != null) {
                        IconButton(onClick = onBack) {
                            Icon(
                                imageVector = Icons.AutoMirrored.Filled.ArrowBack,
                                contentDescription = "返回",
                                tint = colors.accent,
                            )
                        }
                    }
                },
                actions = { actions() },
                colors = TopAppBarDefaults.topAppBarColors(
                    containerColor = colors.canvasMid,
                    titleContentColor = colors.ink,
                    navigationIconContentColor = colors.accent,
                    actionIconContentColor = colors.accent,
                ),
            )
        },
    ) { padding ->
        Box(
            modifier = Modifier
                .fillMaxSize()
                .background(colors.canvasMid)
                .padding(padding),
        ) {
            content(padding)
        }
    }
}
