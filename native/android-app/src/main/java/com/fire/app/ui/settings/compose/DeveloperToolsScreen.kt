package com.fire.app.ui.settings.compose

import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Description
import androidx.compose.material.icons.filled.Share
import androidx.compose.material.icons.filled.Wifi
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.fire.app.core.theme.compose.fireExtended
import com.fire.app.core.ui.compose.FireListRowContent
import com.fire.app.core.ui.compose.FireSecondaryScaffold
import com.fire.app.core.ui.compose.FireSectionHeader
import com.fire.app.core.ui.compose.FireSettingsCardRows
import uniffi.fire_uniffi_diagnostics.LogFileSummaryState
import uniffi.fire_uniffi_diagnostics.NetworkTraceSummaryState

@Composable
fun DeveloperToolsScreen(
    sessionStatus: String,
    logs: List<LogFileSummaryState>,
    traces: List<NetworkTraceSummaryState>,
    statusMessage: String?,
    onExport: () -> Unit,
    onBack: () -> Unit,
) {
    val colors = MaterialTheme.fireExtended
    FireSecondaryScaffold(title = "开发者工具", onBack = onBack) {
        Column(
            modifier = Modifier
                .fillMaxSize()
                .verticalScroll(rememberScrollState())
                .padding(horizontal = 16.dp)
                .padding(top = 4.dp, bottom = 24.dp),
        ) {
            FireSectionHeader("会话")
            Spacer(Modifier.height(10.dp))
            FireSettingsCardRows(
                rows = listOf(
                    FireListRowContent(
                        icon = Icons.Filled.Wifi,
                        title = "账号状态",
                        subtitle = sessionStatus,
                        showsChevron = false,
                        iconWellColor = colors.success,
                    ) to null,
                    FireListRowContent(
                        icon = Icons.Filled.Share,
                        title = "导出诊断包",
                        subtitle = "脱敏日志与网络追踪",
                        iconWellColor = colors.info,
                    ) to onExport,
                ),
            )

            Spacer(Modifier.height(16.dp))
            FireSectionHeader("日志")
            Spacer(Modifier.height(10.dp))
            if (logs.isEmpty()) {
                Text(
                    text = "还没有可读日志。",
                    color = colors.subtleInk,
                    fontSize = 14.sp,
                )
            } else {
                FireSettingsCardRows(
                    rows = logs.take(12).map { file ->
                        FireListRowContent(
                            icon = Icons.Filled.Description,
                            title = file.fileName,
                            subtitle = "${file.sizeBytes} bytes",
                            showsChevron = false,
                            iconWellColor = colors.surfaceSecondary,
                            iconTint = colors.ink,
                        ) to null
                    },
                )
            }

            Spacer(Modifier.height(16.dp))
            FireSectionHeader("网络")
            Spacer(Modifier.height(10.dp))
            if (traces.isEmpty()) {
                Text(
                    text = "还没有捕获到网络请求。",
                    color = colors.subtleInk,
                    fontSize = 14.sp,
                )
            } else {
                FireSettingsCardRows(
                    rows = traces.take(12).map { trace ->
                        val status = trace.statusCode?.toString() ?: trace.outcome.toString()
                        FireListRowContent(
                            icon = Icons.Filled.Wifi,
                            title = trace.operation.ifBlank { trace.method },
                            subtitle = "$status · ${trace.method}",
                            showsChevron = false,
                            iconWellColor = colors.info,
                        ) to null
                    },
                )
            }

            if (!statusMessage.isNullOrBlank()) {
                Spacer(Modifier.height(16.dp))
                Text(text = statusMessage, color = colors.subtleInk, fontSize = 13.sp)
            }
        }
    }
}
