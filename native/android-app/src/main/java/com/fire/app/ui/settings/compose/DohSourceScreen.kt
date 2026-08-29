package com.fire.app.ui.settings.compose

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.fire.app.core.theme.compose.FireShapes
import com.fire.app.core.theme.compose.fireExtended
import com.fire.app.core.ui.compose.FireSecondaryScaffold
import com.fire.app.core.ui.compose.FireSectionHeader
import uniffi.fire_uniffi_session.DohPresetState
import uniffi.fire_uniffi_session.DohSettingsState

@Composable
fun DohSourceScreen(
    settings: DohSettingsState,
    presets: List<DohPresetState>,
    customUrl: String,
    status: String,
    isProbing: Boolean,
    onEnabledChange: (Boolean) -> Unit,
    onSelectPreset: (DohPresetState) -> Unit,
    onSelectCustom: () -> Unit,
    onCustomUrlChange: (String) -> Unit,
    onTest: () -> Unit,
    onBack: () -> Unit,
) {
    val colors = MaterialTheme.fireExtended
    val selectedPresetIndex = presets.indexOfFirst { it.endpointUrl == settings.endpointUrl }
    val customSelected = selectedPresetIndex < 0

    FireSecondaryScaffold(title = "DNS over HTTPS", onBack = onBack) {
        Column(
            modifier = Modifier
                .fillMaxSize()
                .verticalScroll(rememberScrollState())
                .padding(horizontal = 16.dp)
                .padding(top = 4.dp, bottom = 24.dp),
        ) {
            Column(
                modifier = Modifier
                    .fillMaxWidth()
                    .clip(FireShapes.card)
                    .background(colors.surface)
                    .padding(horizontal = 14.dp, vertical = 8.dp),
            ) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Text(
                        text = "使用 DoH",
                        modifier = Modifier.weight(1f),
                        color = colors.ink,
                        fontSize = 16.sp,
                    )
                    Switch(
                        checked = settings.enabled,
                        onCheckedChange = onEnabledChange,
                    )
                }
            }

            Spacer(Modifier.height(16.dp))
            FireSectionHeader("解析源")
            Spacer(Modifier.height(10.dp))
            Column(
                modifier = Modifier
                    .fillMaxWidth()
                    .clip(FireShapes.card)
                    .background(colors.surface),
            ) {
                presets.forEachIndexed { index, preset ->
                    val selected = index == selectedPresetIndex
                    Text(
                        text = preset.displayName,
                        modifier = Modifier
                            .fillMaxWidth()
                            .clickable { onSelectPreset(preset) }
                            .padding(horizontal = 14.dp, vertical = 14.dp),
                        color = if (selected) colors.accent else colors.ink,
                        fontSize = 16.sp,
                    )
                }
                Text(
                    text = "自定义",
                    modifier = Modifier
                        .fillMaxWidth()
                        .clickable(onClick = onSelectCustom)
                        .padding(horizontal = 14.dp, vertical = 14.dp),
                    color = if (customSelected) colors.accent else colors.ink,
                    fontSize = 16.sp,
                )
            }

            if (customSelected) {
                Spacer(Modifier.height(12.dp))
                OutlinedTextField(
                    value = customUrl,
                    onValueChange = onCustomUrlChange,
                    modifier = Modifier.fillMaxWidth(),
                    placeholder = { Text("https://example/dns-query") },
                    singleLine = true,
                )
            }

            Spacer(Modifier.height(16.dp))
            Button(
                onClick = onTest,
                enabled = !isProbing,
                modifier = Modifier.fillMaxWidth(),
                colors = ButtonDefaults.buttonColors(containerColor = colors.accent),
                shape = FireShapes.chip,
            ) {
                Text(if (isProbing) "正在测试…" else "测试连接")
            }
            Spacer(Modifier.height(12.dp))
            Text(
                text = status,
                color = colors.tertiaryInk,
                fontSize = 13.sp,
            )
        }
    }
}
