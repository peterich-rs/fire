package com.fire.app.ui.auth

import android.os.Bundle
import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import android.widget.TextView
import androidx.fragment.app.Fragment
import androidx.lifecycle.lifecycleScope
import androidx.navigation.fragment.findNavController
import com.fire.app.R
import com.fire.app.session.FireSessionStoreRepository
import com.google.android.material.button.MaterialButton
import kotlinx.coroutines.flow.collectLatest
import kotlinx.coroutines.launch

class OnboardingFragment : Fragment() {

    private var viewModel: AuthViewModel? = null

    override fun onCreateView(
        inflater: LayoutInflater,
        container: ViewGroup?,
        savedInstanceState: Bundle?,
    ): View? {
        return inflater.inflate(R.layout.fragment_onboarding, container, false)
    }

    override fun onViewCreated(view: View, savedInstanceState: Bundle?) {
        super.onViewCreated(view, savedInstanceState)

        val sessionStore = FireSessionStoreRepository.get(requireContext())
        viewModel = AuthViewModel.create(sessionStore)

        val loginButton: MaterialButton = view.findViewById(R.id.login_button)
        val restoreButton: TextView = view.findViewById(R.id.restore_session_button)
        val bootstrappingLayout: View = view.findViewById(R.id.bootstrapping_layout)
        val errorBanner: View = view.findViewById(R.id.error_banner)
        val errorText: TextView = view.findViewById(R.id.error_text)
        val dismissError: View = view.findViewById(R.id.dismiss_error)

        viewModel?.let { vm ->
            viewLifecycleOwner.lifecycleScope.launch {
                vm.isBootstrapping.collectLatest { bootstrapping ->
                    bootstrappingLayout.visibility = if (bootstrapping) View.VISIBLE else View.GONE
                    loginButton.visibility = if (!bootstrapping) View.VISIBLE else View.GONE
                    restoreButton.visibility = if (!bootstrapping) View.VISIBLE else View.GONE
                }
            }

            viewLifecycleOwner.lifecycleScope.launch {
                vm.session.collectLatest { session ->
                    if (session?.readiness?.canReadAuthenticatedApi == true) {
                        findNavController().navigate(R.id.action_onboarding_to_home)
                    }
                }
            }

            viewLifecycleOwner.lifecycleScope.launch {
                vm.errorMessage.collectLatest { error ->
                    if (error != null) {
                        errorBanner.visibility = View.VISIBLE
                        errorText.text = error
                    } else {
                        errorBanner.visibility = View.GONE
                    }
                }
            }
        }

        loginButton.setOnClickListener {
            findNavController().navigate(R.id.action_onboarding_to_loginWebView)
        }

        restoreButton.setOnClickListener {
            viewModel?.restoreSession()
        }

        dismissError.setOnClickListener {
            viewModel?.dismissError()
        }

        viewModel?.restoreSession()
    }
}
