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
import androidx.fragment.app.setFragmentResultListener
import androidx.fragment.app.viewModels
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.lifecycleScope
import androidx.navigation.fragment.findNavController
import com.fire.app.R
import com.fire.app.core.theme.compose.FireAppearancePreference
import com.fire.app.core.theme.compose.FireTheme
import com.fire.app.ui.auth.compose.OnboardingEntry
import com.fire.app.ui.auth.compose.OnboardingPhase
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

    /** Full-screen OAuth/Passkey: wait for fragment result; onResume is fallback only. */
    private var awaitingWebSurfaceResult = false
    private var webSurfaceResultHandled = false
    private var captchaDialogShowing = false

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
        observeCaptchaResults()
        observeOAuthResults()
    }

    override fun onResume() {
        super.onResume()
        if (awaitingWebSurfaceResult && !webSurfaceResultHandled) {
            awaitingWebSurfaceResult = false
            // Fallback when the web surface closed without delivering a result.
            viewModel.onWebSurfaceCancelled()
        }
    }

    private fun observeCaptchaResults() {
        setFragmentResultListener(CaptchaLoginDialogFragment.REQUEST_KEY) { _, bundle ->
            captchaDialogShowing = false
            when (bundle.getString(CaptchaLoginDialogFragment.KEY_STATUS)) {
                CaptchaLoginDialogFragment.RESULT_SUCCESS -> {
                    viewModel.onLoginSucceeded()
                    if (isAdded) {
                        findNavController().navigate(R.id.action_onboarding_to_home)
                    }
                }
                CaptchaLoginDialogFragment.RESULT_FAILED -> {
                    viewModel.onLoginFailure(
                        bundle.getString(CaptchaLoginDialogFragment.KEY_MESSAGE),
                    )
                }
                else -> {
                    viewModel.onWebSurfaceDismissed(failureMessage = null)
                }
            }
        }
    }

    private fun observeOAuthResults() {
        setFragmentResultListener(LoginWebViewFragment.REQUEST_KEY) { _, bundle ->
            webSurfaceResultHandled = true
            awaitingWebSurfaceResult = false
            when (bundle.getString(LoginWebViewFragment.KEY_STATUS)) {
                LoginWebViewFragment.RESULT_SUCCESS -> {
                    viewModel.onLoginSucceeded()
                    // LoginWebView navigates home itself on success.
                }
                LoginWebViewFragment.RESULT_FAILED -> {
                    viewModel.onLoginFailure(bundle.getString(LoginWebViewFragment.KEY_MESSAGE))
                }
                else -> {
                    viewModel.onWebSurfaceDismissed(failureMessage = null)
                }
            }
        }
    }

    private fun observeNavigationEvents() {
        viewLifecycleOwner.lifecycleScope.launch {
            viewModel.navigationEvents.collect { event ->
                if (shouldSuppressNavigation(event)) return@collect
                when (event) {
                    is LoginNavigationEvent.PasswordCaptcha -> {
                        showCaptchaDialog(event)
                    }

                    is LoginNavigationEvent.OAuth -> {
                        awaitingWebSurfaceResult = true
                        webSurfaceResultHandled = false
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
                        awaitingWebSurfaceResult = true
                        webSurfaceResultHandled = false
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

    private fun showCaptchaDialog(event: LoginNavigationEvent.PasswordCaptcha) {
        if (captchaDialogShowing) return
        if (childFragmentManager.findFragmentByTag(CaptchaLoginDialogFragment.TAG) != null) return
        captchaDialogShowing = true
        CaptchaLoginDialogFragment.newInstance(
            identifier = event.identifier,
            password = event.password,
            remember = event.remember,
            isAutoLogin = event.isAutoLogin,
        ).show(childFragmentManager, CaptchaLoginDialogFragment.TAG)
    }

    private fun openForgotPassword() {
        runCatching {
            startActivity(Intent(Intent.ACTION_VIEW, Uri.parse("https://linux.do/password-reset")))
        }
    }

    private fun shouldSuppressNavigation(event: LoginNavigationEvent): Boolean {
        val state = viewModel.uiState.value
        if (event is LoginNavigationEvent.PasswordCaptcha && event.isAutoLogin) {
            return !state.isAutoLoginInFlight || state.phase != OnboardingPhase.LoggingIn
        }
        if (event is LoginNavigationEvent.OAuth || event is LoginNavigationEvent.Passkey) {
            // External auto-login uses the same in-flight flag.
            if (state.isAutoLoginInFlight) {
                return state.phase != OnboardingPhase.LoggingIn
            }
        }
        return false
    }
}
