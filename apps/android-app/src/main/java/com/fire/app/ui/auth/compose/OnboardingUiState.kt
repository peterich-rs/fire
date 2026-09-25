package com.fire.app.ui.auth.compose

import com.fire.app.ui.auth.FireLastLoginMethod

enum class OnboardingPhase { Validating, Credential, LoggingIn }

enum class OnboardingEntry { ColdStart, SignedOut, SessionExpired }

data class OnboardingUiState(
    val phase: OnboardingPhase = OnboardingPhase.Validating,
    val errorMessage: String? = null,
    val identifier: String = "",
    val password: String = "",
    val isPasswordVisible: Boolean = false,
    val rememberPassword: Boolean = false,
    val lastLoginMethod: FireLastLoginMethod? = null,
    val isLoginEnabled: Boolean = false,
    val entry: OnboardingEntry = OnboardingEntry.ColdStart,
    val validatingMessage: String = "",
    val validatingDetail: String = "",
    val canCancelAutoLogin: Boolean = false,
    /** True while an automatic login attempt owns the host loading chrome. */
    val isAutoLoginInFlight: Boolean = false,
)
