package com.fire.app.ui.settings

import android.content.Context
import android.content.Intent
import android.os.Bundle
import android.view.View
import android.widget.AdapterView
import android.widget.ArrayAdapter
import android.widget.EditText
import android.widget.Spinner
import android.widget.TextView
import androidx.activity.enableEdgeToEdge
import androidx.appcompat.app.AppCompatActivity
import androidx.appcompat.app.AppCompatDelegate
import androidx.appcompat.widget.SwitchCompat
import androidx.lifecycle.lifecycleScope
import com.fire.app.R
import com.fire.app.core.theme.compose.FireAppearancePreference
import com.fire.app.session.FireSessionStoreRepository
import com.google.android.material.appbar.MaterialToolbar
import com.google.android.material.button.MaterialButton
import kotlinx.coroutines.launch
import uniffi.fire_uniffi_session.DohPresetState
import uniffi.fire_uniffi_session.DohSettingsState

class SettingsActivity : AppCompatActivity() {

    private lateinit var appearanceSpinner: Spinner
    private lateinit var dohEnabled: SwitchCompat
    private lateinit var presetSpinner: Spinner
    private lateinit var customUrl: EditText
    private lateinit var testButton: MaterialButton
    private lateinit var statusLabel: TextView

    private var presets: List<DohPresetState> = emptyList()
    private var settings = DohSettingsState(enabled = false, endpointUrl = "")
    private var suppressPersistence = false

    override fun onCreate(savedInstanceState: Bundle?) {
        enableEdgeToEdge()
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_settings)

        val toolbar = findViewById<MaterialToolbar>(R.id.settings_toolbar)
        toolbar.setNavigationOnClickListener { finish() }
        toolbar.title = getString(R.string.settings_title)

        appearanceSpinner = findViewById(R.id.settings_appearance)
        dohEnabled = findViewById(R.id.settings_doh_enabled)
        presetSpinner = findViewById(R.id.settings_doh_preset)
        customUrl = findViewById(R.id.settings_doh_custom)
        testButton = findViewById(R.id.settings_doh_test)
        statusLabel = findViewById(R.id.settings_doh_status)

        val appearanceOptions = listOf(
            FireAppearancePreference.System,
            FireAppearancePreference.Dark,
            FireAppearancePreference.Light,
        )
        appearanceSpinner.adapter = ArrayAdapter(
            this,
            android.R.layout.simple_spinner_dropdown_item,
            appearanceOptions.map { option ->
                when (option) {
                    FireAppearancePreference.System -> getString(R.string.settings_appearance_system)
                    FireAppearancePreference.Dark -> getString(R.string.settings_appearance_dark)
                    FireAppearancePreference.Light -> getString(R.string.settings_appearance_light)
                }
            },
        )
        val currentAppearance = FireAppearancePreference.load(this)
        appearanceSpinner.setSelection(appearanceOptions.indexOf(currentAppearance).coerceAtLeast(0))
        appearanceSpinner.onItemSelectedListener = object : AdapterView.OnItemSelectedListener {
            override fun onItemSelected(parent: AdapterView<*>?, view: View?, position: Int, id: Long) {
                val preference = appearanceOptions[position]
                FireAppearancePreference.save(this@SettingsActivity, preference)
                AppCompatDelegate.setDefaultNightMode(
                    when (preference) {
                        FireAppearancePreference.System -> AppCompatDelegate.MODE_NIGHT_FOLLOW_SYSTEM
                        FireAppearancePreference.Dark -> AppCompatDelegate.MODE_NIGHT_YES
                        FireAppearancePreference.Light -> AppCompatDelegate.MODE_NIGHT_NO
                    },
                )
            }

            override fun onNothingSelected(parent: AdapterView<*>?) = Unit
        }

        dohEnabled.setOnCheckedChangeListener { _, enabled ->
            if (suppressPersistence) return@setOnCheckedChangeListener
            persist(settings.copy(enabled = enabled))
        }
        presetSpinner.onItemSelectedListener = object : AdapterView.OnItemSelectedListener {
            override fun onItemSelected(parent: AdapterView<*>?, view: View?, position: Int, id: Long) {
                if (suppressPersistence) return
                val customIndex = presets.size
                if (position == customIndex) {
                    customUrl.visibility = View.VISIBLE
                    if (customUrl.text.isBlank()) {
                        customUrl.setText(settings.endpointUrl)
                    }
                    val url = customUrl.text.toString().ifBlank { settings.endpointUrl }
                    persist(settings.copy(endpointUrl = url))
                } else {
                    customUrl.visibility = View.GONE
                    persist(settings.copy(endpointUrl = presets[position].endpointUrl))
                }
            }

            override fun onNothingSelected(parent: AdapterView<*>?) = Unit
        }
        testButton.setOnClickListener { probe() }

        lifecycleScope.launch { loadDoh() }
    }

    private suspend fun loadDoh() {
        val store = FireSessionStoreRepository.get(this)
        presets = store.listDohPresets()
        settings = store.getDohSettings()
        bindDoh()
    }

    private fun bindDoh() {
        suppressPersistence = true
        dohEnabled.isChecked = settings.enabled
        val labels = presets.map { it.displayName } + getString(R.string.settings_doh_custom)
        presetSpinner.adapter = ArrayAdapter(
            this,
            android.R.layout.simple_spinner_dropdown_item,
            labels,
        )
        val presetIndex = presets.indexOfFirst { it.endpointUrl == settings.endpointUrl }
        if (presetIndex >= 0) {
            presetSpinner.setSelection(presetIndex)
            customUrl.visibility = View.GONE
        } else {
            presetSpinner.setSelection(presets.size)
            customUrl.visibility = View.VISIBLE
            customUrl.setText(settings.endpointUrl)
        }
        suppressPersistence = false
    }

    private fun persist(next: DohSettingsState) {
        val resolved = if (presetSpinner.selectedItemPosition == presets.size) {
            next.copy(endpointUrl = customUrl.text.toString().ifBlank { next.endpointUrl })
        } else {
            next
        }
        lifecycleScope.launch {
            runCatching {
                val store = FireSessionStoreRepository.get(this@SettingsActivity)
                settings = store.setDohSettings(resolved)
                bindDoh()
            }.onFailure { error ->
                statusLabel.text = error.message
            }
        }
    }

    private fun probe() {
        val candidate = if (presetSpinner.selectedItemPosition == presets.size) {
            settings.copy(endpointUrl = customUrl.text.toString())
        } else {
            settings
        }
        statusLabel.text = getString(R.string.settings_doh_testing)
        lifecycleScope.launch {
            runCatching {
                val store = FireSessionStoreRepository.get(this@SettingsActivity)
                store.probeDohSettings(candidate)
            }.onSuccess { result ->
                statusLabel.text = if (result.ok) {
                    getString(
                        R.string.settings_doh_ok,
                        result.host,
                        result.resolvedAddresses.joinToString(),
                        result.elapsedMs.toString(),
                    )
                } else {
                    result.errorMessage ?: getString(R.string.settings_doh_failed)
                }
            }.onFailure { error ->
                statusLabel.text = error.message ?: getString(R.string.settings_doh_failed)
            }
        }
    }

    companion object {
        fun start(context: Context) {
            context.startActivity(Intent(context, SettingsActivity::class.java))
        }
    }
}
