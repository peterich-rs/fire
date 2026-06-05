package com.fire.app.ui.startup

import android.os.Bundle
import android.view.Gravity
import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import android.widget.FrameLayout
import android.widget.ProgressBar
import android.widget.TextView
import androidx.fragment.app.Fragment
import androidx.lifecycle.lifecycleScope
import androidx.navigation.fragment.findNavController
import com.fire.app.R
import com.fire.app.session.FireSessionStoreRepository
import kotlinx.coroutines.launch
import uniffi.fire_uniffi_session.LoginStateDeterminationState
import uniffi.fire_uniffi_session.RefreshTriggerState

class PreheatGateFragment : Fragment() {

    private lateinit var statusText: TextView
    private lateinit var errorText: TextView
    private lateinit var retryButton: TextView
    private lateinit var progressBar: ProgressBar

    override fun onCreateView(
        inflater: LayoutInflater,
        container: ViewGroup?,
        savedInstanceState: Bundle?,
    ): View {
        val root = FrameLayout(requireContext()).apply {
            layoutParams = FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.MATCH_PARENT,
                FrameLayout.LayoutParams.MATCH_PARENT,
            )
        }

        progressBar = ProgressBar(requireContext()).apply {
            layoutParams = FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.WRAP_CONTENT,
                FrameLayout.LayoutParams.WRAP_CONTENT,
                Gravity.CENTER,
            )
            isIndeterminate = true
        }
        root.addView(progressBar)

        statusText = TextView(requireContext()).apply {
            text = "\u6b63\u5728\u52a0\u8f7d..."
            textSize = 14f
            gravity = Gravity.CENTER
            layoutParams = FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.MATCH_PARENT,
                FrameLayout.LayoutParams.WRAP_CONTENT,
                Gravity.CENTER,
            ).apply {
                topMargin = 120
            }
        }
        root.addView(statusText)

        errorText = TextView(requireContext()).apply {
            textSize = 16f
            gravity = Gravity.CENTER
            visibility = View.GONE
            layoutParams = FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.MATCH_PARENT,
                FrameLayout.LayoutParams.WRAP_CONTENT,
                Gravity.CENTER,
            )
        }
        root.addView(errorText)

        retryButton = TextView(requireContext()).apply {
            text = "\u91cd\u8bd5"
            textSize = 16f
            gravity = Gravity.CENTER
            visibility = View.GONE
            setOnClickListener { awaitPreloadedData() }
            layoutParams = FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.WRAP_CONTENT,
                FrameLayout.LayoutParams.WRAP_CONTENT,
                Gravity.CENTER,
            ).apply {
                topMargin = 200
            }
        }
        root.addView(retryButton)

        return root
    }

    override fun onViewCreated(view: View, savedInstanceState: Bundle?) {
        super.onViewCreated(view, savedInstanceState)
        awaitPreloadedData()
    }

    private fun awaitPreloadedData() {
        progressBar.visibility = View.VISIBLE
        statusText.visibility = View.VISIBLE
        statusText.text = "\u6b63\u5728\u52a0\u8f7d..."
        errorText.visibility = View.GONE
        retryButton.visibility = View.GONE

        val store = FireSessionStoreRepository.get(requireContext())
        viewLifecycleOwner.lifecycleScope.launch {
            try {
                store.prepareStartupSession()
                store.awaitPreloadedData()
                onPreloadedDataReady(store)
            } catch (e: Exception) {
                showError(e.message ?: "\u52a0\u8f7d\u5931\u8d25")
            }
        }
    }

    private suspend fun onPreloadedDataReady(store: com.fire.app.session.FireSessionStore) {
        when (store.determineLoginStateWithProbe()) {
            is LoginStateDeterminationState.LoggedIn -> {
                store.triggerAppStateRefresh(RefreshTriggerState.SESSION_RESTORED)
                findNavController().navigate(R.id.action_preheatGate_to_home)
            }
            else -> {
                findNavController().navigate(R.id.action_preheatGate_to_onboarding)
            }
        }
    }

    private fun showError(message: String) {
        progressBar.visibility = View.GONE
        statusText.visibility = View.GONE
        errorText.visibility = View.VISIBLE
        errorText.text = message
        retryButton.visibility = View.VISIBLE
    }
}
