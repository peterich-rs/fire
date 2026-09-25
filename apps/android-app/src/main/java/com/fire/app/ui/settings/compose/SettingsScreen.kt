package com.fire.app.ui.settings.compose

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.Logout
import androidx.compose.material.icons.filled.Build
import androidx.compose.material.icons.filled.Security
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.fire.app.core.theme.compose.FireAppearancePreference
import com.fire.app.core.theme.compose.fireExtended
import com.fire.app.core.ui.compose.FireAppearanceCapsule
import com.fire.app.core.ui.compose.FireListRowContent
import com.fire.app.core.ui.compose.FireSecondaryScaffold
import com.fire.app.core.ui.compose.FireSectionHeader
import com.fire.app.core.ui.compose.FireSettingsCardRows

enum class SettingsDestination {
    Root,
    Doh,
    DeveloperTools,
}

@Composable
fun SettingsHost(
    appearance: FireAppearancePreference,
    dohSubtitle: String,
    versionText: String,
    canLogout: Boolean,
    isLoggingOut: Boolean,
    onAppearanceChange: (FireAppearancePreference) -> Unit,
    onLogout: () -> Unit,
    onBack: () -> Unit,
    dohContent: @Composable (onBack: () -> Unit) -> Unit,
    developerToolsContent: @Composable (onBack: () -> Unit) -> Unit,
) {
    var destination by remember { mutableStateOf(SettingsDestination.Root) }
    var confirmLogout by remember { mutableStateOf(false) }

    when (destination) {
        SettingsDestination.Root -> {
            SettingsScreen(
                appearance = appearance,
                dohSubtitle = dohSubtitle,
                versionText = versionText,
                canLogout = canLogout,
                isLoggingOut = isLoggingOut,
                onAppearanceChange = onAppearanceChange,
                onOpenDoh = { destination = SettingsDestination.Doh },
                onOpenDeveloperTools = { destination = SettingsDestination.DeveloperTools },
                onRequestLogout = { confirmLogout = true },
                onBack = onBack,
            )
        }
        SettingsDestination.Doh -> {
            BackHandler { destination = SettingsDestination.Root }
            dohContent { destination = SettingsDestination.Root }
        }
        SettingsDestination.DeveloperTools -> {
            BackHandler { destination = SettingsDestination.Root }
            developerToolsContent { destination = SettingsDestination.Root }
        }
    }

    if (confirmLogout) {
        AlertDialog(
            onDismissRequest = { confirmLogout = false },
            title = { Text("确认退出") },
            text = {
                Text("会先尝试通知服务端退出；即使网络请求失败，也会清空本地登录态并回到登录页。")
            },
            confirmButton = {
                TextButton(
                    onClick = {
                        confirmLogout = false
                        onLogout()
                    },
                ) {
                    Text("退出登录", color = MaterialTheme.fireExtended.error)
                }
            },
            dismissButton = {
                TextButton(onClick = { confirmLogout = false }) {
                    Text("取消")
                }
            },
        )
    }
}

@Composable
fun SettingsScreen(
    appearance: FireAppearancePreference,
    dohSubtitle: String,
    versionText: String,
    canLogout: Boolean,
    isLoggingOut: Boolean,
    onAppearanceChange: (FireAppearancePreference) -> Unit,
    onOpenDoh: () -> Unit,
    onOpenDeveloperTools: () -> Unit,
    onRequestLogout: () -> Unit,
    onBack: () -> Unit,
) {
    val colors = MaterialTheme.fireExtended
    FireSecondaryScaffold(title = "设置", onBack = onBack) {
        Column(
            modifier = Modifier
                .fillMaxSize()
                .verticalScroll(rememberScrollState())
                .padding(horizontal = 16.dp)
                .padding(top = 4.dp, bottom = 24.dp),
        ) {
            FireSectionHeader("外观")
            Spacer(Modifier.height(10.dp))
            FireAppearanceCapsule(
                selected = appearance,
                onSelect = onAppearanceChange,
            )
            Spacer(Modifier.height(16.dp))

            FireSectionHeader("网络")
            Spacer(Modifier.height(10.dp))
            FireSettingsCardRows(
                rows = listOf(
                    FireListRowContent(
                        icon = Icons.Filled.Security,
                        title = "DNS over HTTPS",
                        subtitle = dohSubtitle,
                        iconWellColor = colors.info,
                    ) to onOpenDoh,
                ),
            )
            Spacer(Modifier.height(16.dp))

            FireSectionHeader("诊断")
            Spacer(Modifier.height(10.dp))
            FireSettingsCardRows(
                rows = listOf(
                    FireListRowContent(
                        icon = Icons.Filled.Build,
                        title = "开发者工具",
                        subtitle = "日志、网络与诊断导出",
                        iconWellColor = ColorIndigo,
                    ) to onOpenDeveloperTools,
                ),
            )
            Spacer(Modifier.height(16.dp))

            if (canLogout) {
                FireSettingsCardRows(
                    rows = listOf(
                        FireListRowContent(
                            icon = Icons.AutoMirrored.Filled.Logout,
                            title = if (isLoggingOut) "退出中…" else "退出登录",
                            showsChevron = false,
                            iconWellColor = colors.error,
                        ) to if (isLoggingOut) null else onRequestLogout,
                    ),
                )
                Spacer(Modifier.height(28.dp))
            }

            Text(
                text = versionText,
                modifier = Modifier.fillMaxWidth(),
                color = colors.tertiaryInk,
                fontSize = 13.sp,
                textAlign = TextAlign.Center,
            )
        }
    }
}

private val ColorIndigo = androidx.compose.ui.graphics.Color(0xFF5856D6)
