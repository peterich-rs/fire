package com.fire.app.ui.startup

import android.os.Bundle
import android.os.SystemClock
import android.util.Log
import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import android.widget.TextView
import androidx.fragment.app.Fragment
import androidx.lifecycle.lifecycleScope
import androidx.navigation.fragment.findNavController
import com.fire.app.R
import com.fire.app.session.FireAppStateRefreshRepository
import com.fire.app.session.FireSessionStore
import com.fire.app.session.FireSessionStoreRepository
import com.google.android.material.button.MaterialButton
import kotlinx.coroutines.launch
import uniffi.fire_uniffi_session.LoginStateDeterminationState
import uniffi.fire_uniffi_session.RefreshTriggerState

class PreheatGateFragment : Fragment() {
    private companion object {
        private const val TAG = "FirePreheatGate"
    }

    private lateinit var errorText: TextView
    private lateinit var statusButton: MaterialButton

    override fun onCreateView(
        inflater: LayoutInflater,
        container: ViewGroup?,
        savedInstanceState: Bundle?,
    ): View {
        return inflater.inflate(R.layout.fragment_onboarding, container, false)
    }

    override fun onViewCreated(view: View, savedInstanceState: Bundle?) {
        super.onViewCreated(view, savedInstanceState)
        errorText = view.findViewById(R.id.onboarding_error)
        statusButton = view.findViewById(R.id.login_button)
        statusButton.visibility = View.VISIBLE
        statusButton.setOnClickListener { awaitPreloadedData() }
        awaitPreloadedData()
    }

    private fun awaitPreloadedData() {
        statusButton.isEnabled = false
        statusButton.text = getString(R.string.onboarding_checking_login_state)
        errorText.visibility = View.GONE

        viewLifecycleOwner.lifecycleScope.launch {
            try {
                val storeStartedAt = SystemClock.elapsedRealtime()
                val store = FireSessionStoreRepository.get(requireContext())
                logStartupStep("session_store_get_ms", storeStartedAt)

                val prepareStartedAt = SystemClock.elapsedRealtime()
                store.prepareStartupSession()
                logStartupStep("prepare_startup_session_ms", prepareStartedAt)

                val preloadedStartedAt = SystemClock.elapsedRealtime()
                store.awaitPreloadedData()
                logStartupStep("await_preloaded_ms", preloadedStartedAt)

                onPreloadedDataReady(store)
            } catch (e: Exception) {
                showError(e.message ?: "\u52a0\u8f7d\u5931\u8d25")
            }
        }
    }

    private suspend fun onPreloadedDataReady(store: FireSessionStore) {
        val loginProbeStartedAt = SystemClock.elapsedRealtime()
        when (store.determineLoginStateWithProbe().also {
            logStartupStep("login_probe_ms", loginProbeStartedAt)
        }) {
            is LoginStateDeterminationState.LoggedIn -> {
                store.triggerAppStateRefresh(
                    RefreshTriggerState.SESSION_RESTORED,
                    FireAppStateRefreshRepository,
                )
                findNavController().navigate(R.id.action_preheatGate_to_home)
            }
            LoginStateDeterminationState.NetworkErrorPreserveState -> {
                showError(getString(R.string.onboarding_login_check_failed))
            }
            else -> {
                findNavController().navigate(R.id.action_preheatGate_to_onboarding)
            }
        }
    }

    private fun showError(message: String) {
        errorText.visibility = View.VISIBLE
        errorText.text = message
        statusButton.isEnabled = true
        statusButton.text = getString(R.string.onboarding_retry_login_check)
    }

    private fun logStartupStep(field: String, startedAtMs: Long) {
        Log.d(TAG, "startup preheat timing $field=${SystemClock.elapsedRealtime() - startedAtMs}")
    }
}
