package com.fire.app

import android.content.Intent
import android.os.Bundle
import androidx.activity.result.contract.ActivityResultContracts
import androidx.appcompat.app.AppCompatActivity
import androidx.lifecycle.lifecycleScope
import com.fire.app.databinding.ActivityMainBinding
import com.fire.app.session.FireSessionStore
import kotlinx.coroutines.launch
import uniffi.fire_uniffi.SessionState

class MainActivity : AppCompatActivity() {
    private lateinit var binding: ActivityMainBinding
    private lateinit var sessionStore: FireSessionStore

    private val loginLauncher = registerForActivityResult(
        ActivityResultContracts.StartActivityForResult(),
    ) {
        refreshSession()
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        binding = ActivityMainBinding.inflate(layoutInflater)
        setContentView(binding.root)

        sessionStore = FireSessionStore(applicationContext)

        binding.restoreButton.setOnClickListener { restoreSession() }
        binding.openLoginButton.setOnClickListener {
            loginLauncher.launch(Intent(this, LoginActivity::class.java))
        }
        binding.refreshBootstrapButton.setOnClickListener { refreshBootstrap() }
        binding.logoutButton.setOnClickListener { logout() }

        restoreSession()
    }

    private fun restoreSession() {
        lifecycleScope.launch {
            val state = sessionStore.restorePersistedSessionIfAvailable() ?: sessionStore.snapshot()
            render(state)
        }
    }

    private fun refreshSession() {
        lifecycleScope.launch {
            render(sessionStore.snapshot())
        }
    }

    private fun refreshBootstrap() {
        lifecycleScope.launch {
            render(sessionStore.refreshBootstrapIfNeeded())
        }
    }

    private fun logout() {
        lifecycleScope.launch {
            render(sessionStore.logout())
        }
    }

    private fun render(state: SessionState) {
        binding.sessionSummaryText.text = buildString {
            appendLine("Phase: ${state.loginPhase}")
            appendLine("Has Login: ${state.hasLoginSession}")
            appendLine("Username: ${state.bootstrap.currentUsername ?: "-"}")
            appendLine("Bootstrap Ready: ${state.bootstrap.hasPreloadedData}")
            appendLine("Has CSRF: ${state.cookies.csrfToken != null}")
        }
    }
}
