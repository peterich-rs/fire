package com.fire.app.ui.settings

import android.content.Context
import android.content.Intent
import android.os.Bundle
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.appcompat.app.AppCompatActivity
import androidx.appcompat.app.AppCompatDelegate
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.core.content.FileProvider
import androidx.lifecycle.lifecycleScope
import com.fire.app.MainActivity
import com.fire.app.core.theme.compose.FireAppearancePreference
import com.fire.app.core.ui.compose.FireAppTheme
import com.fire.app.session.FireSessionStoreRepository
import com.fire.app.ui.settings.compose.DeveloperToolsScreen
import com.fire.app.ui.settings.compose.DohSourceScreen
import com.fire.app.ui.settings.compose.SettingsHost
import java.io.File
import kotlinx.coroutines.launch
import uniffi.fire_uniffi_diagnostics.LogFileSummaryState
import uniffi.fire_uniffi_diagnostics.NetworkTraceSummaryState
import uniffi.fire_uniffi_session.DohPresetState
import uniffi.fire_uniffi_session.DohSettingsState

class SettingsActivity : AppCompatActivity() {

    private val appearanceState = mutableStateOf(FireAppearancePreference.System)
    private val dohSettingsState = mutableStateOf(DohSettingsState(enabled = false, endpointUrl = ""))
    private val dohPresetsState = mutableStateOf<List<DohPresetState>>(emptyList())
    private val customUrlState = mutableStateOf("")
    private val dohStatusState = mutableStateOf("仅对 API 请求生效。关闭后使用系统 DNS。")
    private val probingState = mutableStateOf(false)
    private val loggingOutState = mutableStateOf(false)
    private val logsState = mutableStateOf<List<LogFileSummaryState>>(emptyList())
    private val tracesState = mutableStateOf<List<NetworkTraceSummaryState>>(emptyList())
    private val toolsStatusState = mutableStateOf<String?>(null)

    override fun onCreate(savedInstanceState: Bundle?) {
        enableEdgeToEdge()
        super.onCreate(savedInstanceState)
        appearanceState.value = FireAppearancePreference.load(this)

        setContent {
            FireAppTheme {
                var appearance by remember { appearanceState }
                val dohSettings by remember { dohSettingsState }
                val presets by remember { dohPresetsState }
                var customUrl by remember { customUrlState }
                val status by remember { dohStatusState }
                val probing by remember { probingState }
                val loggingOut by remember { loggingOutState }
                val logs by remember { logsState }
                val traces by remember { tracesState }
                val toolsStatus by remember { toolsStatusState }

                SettingsHost(
                    appearance = appearance,
                    dohSubtitle = dohSubtitle(dohSettings, presets),
                    versionText = versionText(),
                    canLogout = true,
                    isLoggingOut = loggingOut,
                    onAppearanceChange = { preference ->
                        appearance = preference
                        applyAppearance(preference)
                    },
                    onLogout = { logout() },
                    onBack = { finish() },
                    dohContent = { onBack ->
                        DohSourceScreen(
                            settings = dohSettings,
                            presets = presets,
                            customUrl = customUrl,
                            status = status,
                            isProbing = probing,
                            onEnabledChange = { enabled -> persistDoh(dohSettings.copy(enabled = enabled)) },
                            onSelectPreset = { preset ->
                                customUrlState.value = ""
                                persistDoh(dohSettings.copy(endpointUrl = preset.endpointUrl))
                            },
                            onSelectCustom = {
                                if (customUrl.isBlank()) {
                                    customUrl = dohSettings.endpointUrl
                                }
                                persistDoh(dohSettings.copy(endpointUrl = customUrl.ifBlank { dohSettings.endpointUrl }))
                            },
                            onCustomUrlChange = { value ->
                                customUrl = value
                                persistDoh(dohSettings.copy(endpointUrl = value))
                            },
                            onTest = { probeDoh() },
                            onBack = onBack,
                        )
                    },
                    developerToolsContent = { onBack ->
                        DeveloperToolsScreen(
                            sessionStatus = sessionStatusText(),
                            logs = logs,
                            traces = traces,
                            statusMessage = toolsStatus,
                            onExport = { exportDiagnostics() },
                            onBack = onBack,
                        )
                    },
                )
            }
        }

        lifecycleScope.launch { loadDoh() }
        lifecycleScope.launch { loadDiagnostics() }
    }

    private fun applyAppearance(preference: FireAppearancePreference) {
        FireAppearancePreference.save(this, preference)
        AppCompatDelegate.setDefaultNightMode(
            when (preference) {
                FireAppearancePreference.System -> AppCompatDelegate.MODE_NIGHT_FOLLOW_SYSTEM
                FireAppearancePreference.Dark -> AppCompatDelegate.MODE_NIGHT_YES
                FireAppearancePreference.Light -> AppCompatDelegate.MODE_NIGHT_NO
            },
        )
    }

    private suspend fun loadDoh() {
        runCatching {
            val store = FireSessionStoreRepository.get(this)
            dohPresetsState.value = store.listDohPresets()
            dohSettingsState.value = store.getDohSettings()
            val settings = dohSettingsState.value
            val match = dohPresetsState.value.any { it.endpointUrl == settings.endpointUrl }
            if (!match) customUrlState.value = settings.endpointUrl
        }.onFailure { error ->
            dohStatusState.value = error.message ?: "无法加载 DoH 设置"
        }
    }

    private fun persistDoh(next: DohSettingsState) {
        lifecycleScope.launch {
            runCatching {
                val store = FireSessionStoreRepository.get(this@SettingsActivity)
                dohSettingsState.value = store.setDohSettings(next)
            }.onFailure { error ->
                dohStatusState.value = error.message ?: "无法保存 DoH 设置"
            }
        }
    }

    private fun probeDoh() {
        probingState.value = true
        dohStatusState.value = "正在测试…"
        lifecycleScope.launch {
            runCatching {
                val store = FireSessionStoreRepository.get(this@SettingsActivity)
                store.probeDohSettings(dohSettingsState.value)
            }.onSuccess { result ->
                dohStatusState.value = if (result.ok) {
                    "成功：${result.host} → ${result.resolvedAddresses.joinToString()}（${result.elapsedMs}ms）"
                } else {
                    result.errorMessage ?: "测试失败"
                }
            }.onFailure { error ->
                dohStatusState.value = error.message ?: "测试失败"
            }
            probingState.value = false
        }
    }

    private suspend fun loadDiagnostics() {
        runCatching {
            val store = FireSessionStoreRepository.get(this)
            logsState.value = store.listLogFiles()
            tracesState.value = store.listNetworkTraces(12uL)
        }.onFailure { error ->
            toolsStatusState.value = error.message
        }
    }

    private fun exportDiagnostics() {
        toolsStatusState.value = "正在导出…"
        lifecycleScope.launch {
            runCatching {
                val store = FireSessionStoreRepository.get(this@SettingsActivity)
                val info = packageManager.getPackageInfo(packageName, 0)
                val exported = store.exportFeedbackBundle(
                    platform = "android",
                    appVersion = info.versionName,
                    buildNumber = info.longVersionCode.toString(),
                    scenePhase = "settings",
                )
                val file = File(exported.absolutePath)
                if (!file.exists()) {
                    toolsStatusState.value = "诊断包导出失败"
                    return@runCatching
                }
                val uri = FileProvider.getUriForFile(
                    this@SettingsActivity,
                    "$packageName.fileprovider",
                    file,
                )
                val share = Intent(Intent.ACTION_SEND).apply {
                    type = "application/zip"
                    putExtra(Intent.EXTRA_STREAM, uri)
                    addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                }
                startActivity(Intent.createChooser(share, "导出诊断包"))
                toolsStatusState.value = "已导出 ${file.name}"
            }.onFailure { error ->
                toolsStatusState.value = error.message ?: "诊断包导出失败"
            }
        }
    }

    private fun logout() {
        if (loggingOutState.value) return
        loggingOutState.value = true
        lifecycleScope.launch {
            runCatching {
                FireSessionStoreRepository.get(this@SettingsActivity).logout()
            }
            val intent = Intent(this@SettingsActivity, MainActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TASK
                putExtra(MainActivity.EXTRA_ONBOARDING_ENTRY, "signedOut")
            }
            startActivity(intent)
            finish()
        }
    }

    private fun dohSubtitle(
        settings: DohSettingsState,
        presets: List<DohPresetState>,
    ): String {
        if (!settings.enabled) return "关闭"
        return presets.firstOrNull { it.endpointUrl == settings.endpointUrl }?.displayName
            ?: settings.endpointUrl.ifBlank { "自定义" }
    }

    private fun sessionStatusText(): String {
        val snapshot = runCatching {
            // Snapshot is cheap enough after store init; Settings already loaded DoH via the same store.
            null
        }.getOrNull()
        return snapshot ?: "已登录设备可在此导出日志与网络追踪"
    }

    private fun versionText(): String {
        val info = packageManager.getPackageInfo(packageName, 0)
        val version = info.versionName ?: "?"
        val build = info.longVersionCode
        return "Fire $version ($build)"
    }

    companion object {
        fun start(context: Context) {
            context.startActivity(Intent(context, SettingsActivity::class.java))
        }
    }
}
