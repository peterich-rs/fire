package com.fire.app.ui.auth

import android.content.Intent
import android.net.Uri
import android.os.Bundle
import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import androidx.compose.runtime.getValue
import androidx.compose.ui.platform.ComposeView
import androidx.compose.ui.platform.ViewCompositionStrategy
import androidx.fragment.app.Fragment
import androidx.fragment.app.viewModels
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.lifecycleScope
import androidx.navigation.fragment.findNavController
import com.fire.app.R
import com.fire.app.core.theme.compose.FireAppearancePreference
import com.fire.app.core.theme.compose.FireTheme
import com.fire.app.ui.auth.compose.OnboardingEntry
import com.fire.app.ui.auth.compose.OnboardingScreen
import kotlinx.coroutines.launch

class OnboardingFragment : Fragment() {

    private val viewModel: OnboardingViewModel by viewModels {
        val entryArg = OnboardingFragmentArgs.fromBundle(requireArguments()).onboardingEntry
        val entry = when (entryArg.lowercase()) {
            "signedout" -> OnboardingEntry.SignedOut
            "sessionexpired" -> OnboardingEntry.SessionExpired
            else -> OnboardingEntry.ColdStart
        }
        OnboardingViewModel.factory(
            requireContext().applicationContext,
            entry = entry,
        )
    }

    private var hasNavigatedToWebSurface = false

    override fun onCreateView(
        inflater: LayoutInflater,
        container: ViewGroup?,
        savedInstanceState: Bundle?,
    ): View {
        return ComposeView(requireContext()).apply {
            setViewCompositionStrategy(
                ViewCompositionStrategy.DisposeOnViewTreeLifecycleDestroyed,
            )
            val preference = FireAppearancePreference.load(requireContext())
            setContent {
                FireTheme(preference = preference) {
                    val state by viewModel.uiState.collectAsStateWithLifecycle()
                    OnboardingScreen(
                        state = state,
                        onIdentifierChange = viewModel::onIdentifierChange,
                        onPasswordChange = viewModel::onPasswordChange,
                        onTogglePasswordVisibility = viewModel::onTogglePasswordVisibility,
                        onToggleRemember = viewModel::onToggleRemember,
                        onLogin = viewModel::onLogin,
                        onForgotPassword = viewModel::onForgotPassword,
                        onExternal = viewModel::onExternal,
                        onDismissError = viewModel::onDismissError,
                        onCancelAutoLogin = viewModel::onCancelAutoLogin,
                    )
                }
            }
        }
    }

    override fun onViewCreated(view: View, savedInstanceState: Bundle?) {
        super.onViewCreated(view, savedInstanceState)
        observeNavigationEvents()
    }

    override fun onResume() {
        super.onResume()
        if (hasNavigatedToWebSurface) {
            hasNavigatedToWebSurface = false
            viewModel.onWebSurfaceCancelled()
        }
    }

    private fun observeNavigationEvents() {
        viewLifecycleOwner.lifecycleScope.launch {
            viewModel.navigationEvents.collect { event ->
                if (shouldSuppressNavigation(event)) return@collect
                when (event) {
                    is LoginNavigationEvent.PasswordCaptcha -> {
                        hasNavigatedToWebSurface = true
                        val direction = OnboardingFragmentDirections
                            .actionOnboardingToLoginWebView(
                                loginMode = LoginWebViewFragment.MODE_PASSWORD_CAPTCHA,
                                loginIdentifier = event.identifier,
                                loginPassword = event.password,
                                loginProvider = "",
                                loginRemember = event.remember,
                            )
                        findNavController().navigate(direction)
                    }

                    is LoginNavigationEvent.OAuth -> {
                        hasNavigatedToWebSurface = true
                        val direction = OnboardingFragmentDirections
                            .actionOnboardingToLoginWebView(
                                loginMode = LoginWebViewFragment.MODE_OAUTH,
                                loginIdentifier = "",
                                loginPassword = "",
                                loginProvider = event.provider,
                                loginRemember = false,
                            )
                        findNavController().navigate(direction)
                    }

                    is LoginNavigationEvent.Passkey -> {
                        hasNavigatedToWebSurface = true
                        val direction = OnboardingFragmentDirections
                            .actionOnboardingToLoginWebView(
                                loginMode = LoginWebViewFragment.MODE_PASSKEY,
                                loginIdentifier = "",
                                loginPassword = "",
                                loginProvider = event.provider,
                                loginRemember = false,
                            )
                        findNavController().navigate(direction)
                    }

                    LoginNavigationEvent.ForgotPassword -> {
                        openForgotPassword()
                    }
                }
            }
        }
    }

    private fun openForgotPassword() {
        runCatching {
            startActivity(Intent(Intent.ACTION_VIEW, Uri.parse("https://linux.do/password-reset")))
        }
    }

    private fun shouldSuppressNavigation(event: LoginNavigationEvent): Boolean {
        val phase = viewModel.uiState.value.phase
        if (event is LoginNavigationEvent.PasswordCaptcha && event.isAutoLogin) {
            return phase != com.fire.app.ui.auth.compose.OnboardingPhase.Validating
        }
        return false
    }
}
