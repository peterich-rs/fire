package com.fire.app.ui.auth

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
import com.fire.app.core.theme.compose.FireTheme
import com.fire.app.ui.auth.compose.OnboardingEntry
import com.fire.app.ui.auth.compose.OnboardingScreen

class OnboardingFragment : Fragment() {

    private val viewModel: OnboardingViewModel by viewModels {
        OnboardingViewModel.factory(
            requireContext().applicationContext,
            entry = OnboardingEntry.ColdStart,
        )
    }

    override fun onCreateView(
        inflater: LayoutInflater,
        container: ViewGroup?,
        savedInstanceState: Bundle?,
    ): View {
        return ComposeView(requireContext()).apply {
            setViewCompositionStrategy(
                ViewCompositionStrategy.DisposeOnViewTreeLifecycleDestroyed,
            )
            setContent {
                FireTheme {
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
}
