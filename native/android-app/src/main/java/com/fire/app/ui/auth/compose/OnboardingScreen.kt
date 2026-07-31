package com.fire.app.ui.auth.compose

import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.togetherWith
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.ime
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.Warning
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.fire.app.R
import com.fire.app.core.theme.compose.FireShapes
import com.fire.app.core.theme.compose.fireExtended
import com.fire.app.ui.auth.FireExternalLoginMethod

@Composable
fun OnboardingScreen(
    state: OnboardingUiState,
    onIdentifierChange: (String) -> Unit,
    onPasswordChange: (String) -> Unit,
    onTogglePasswordVisibility: () -> Unit,
    onToggleRemember: () -> Unit,
    onLogin: () -> Unit,
    onForgotPassword: () -> Unit,
    onExternal: (FireExternalLoginMethod) -> Unit,
    onDismissError: () -> Unit,
    onCancelAutoLogin: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val extended = MaterialTheme.fireExtended
    val horizontalInset = 24.dp
    val brandPhaseSpacing = 32.dp

    Box(
        modifier = modifier
            .fillMaxSize()
            .background(extended.canvasMid)
            .windowInsetsPadding(WindowInsets.ime)
            .verticalScroll(rememberScrollState()),
        contentAlignment = Alignment.Center,
    ) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = horizontalInset)
                .padding(bottom = 24.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(brandPhaseSpacing),
        ) {
            BrandHeader()

            if (state.errorMessage != null) {
                ErrorBanner(
                    message = state.errorMessage,
                    onDismiss = onDismissError,
                )
            }

            AnimatedContent(
                targetState = state.phase,
                transitionSpec = {
                    androidx.compose.animation.fadeIn()
                        .togetherWith(androidx.compose.animation.fadeOut())
                },
                label = "phaseTransition",
            ) { phase ->
                when (phase) {
                    OnboardingPhase.Validating -> {
                        ValidatingContent(
                            message = state.validatingMessage
                                .ifEmpty { stringResource(R.string.onboarding_checking_login_state) },
                            canCancel = state.canCancelAutoLogin,
                            onCancel = onCancelAutoLogin,
                        )
                    }

                    OnboardingPhase.Credential -> {
                        Column(
                            modifier = Modifier.fillMaxWidth(),
                            verticalArrangement = Arrangement.spacedBy(12.dp),
                        ) {
                            CredentialForm(
                                identifier = state.identifier,
                                password = state.password,
                                isPasswordVisible = state.isPasswordVisible,
                                rememberPassword = state.rememberPassword,
                                isLoginEnabled = state.isLoginEnabled,
                                isLoading = false,
                                lastLoginMethod = state.lastLoginMethod,
                                onIdentifierChange = onIdentifierChange,
                                onPasswordChange = onPasswordChange,
                                onTogglePasswordVisibility = onTogglePasswordVisibility,
                                onToggleRemember = onToggleRemember,
                                onLogin = onLogin,
                                onForgotPassword = onForgotPassword,
                            )
                            ExternalLoginRow(
                                highlightedMethod = state.lastLoginMethod?.toExternalLoginMethod(),
                                onExternal = onExternal,
                            )
                        }
                    }

                    OnboardingPhase.LoggingIn -> {
                        Column(
                            modifier = Modifier.fillMaxWidth(),
                            verticalArrangement = Arrangement.spacedBy(12.dp),
                        ) {
                            CredentialForm(
                                identifier = state.identifier,
                                password = state.password,
                                isPasswordVisible = state.isPasswordVisible,
                                rememberPassword = state.rememberPassword,
                                isLoginEnabled = state.isLoginEnabled,
                                isLoading = true,
                                lastLoginMethod = state.lastLoginMethod,
                                onIdentifierChange = onIdentifierChange,
                                onPasswordChange = onPasswordChange,
                                onTogglePasswordVisibility = onTogglePasswordVisibility,
                                onToggleRemember = onToggleRemember,
                                onLogin = onLogin,
                                onForgotPassword = onForgotPassword,
                            )
                            ExternalLoginRow(
                                highlightedMethod = state.lastLoginMethod?.toExternalLoginMethod(),
                                onExternal = onExternal,
                            )
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun BrandHeader() {
    val extended = MaterialTheme.fireExtended

    Column(
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(10.dp),
    ) {
        Icon(
            painter = painterResource(R.drawable.ic_fire_flame),
            contentDescription = null,
            tint = extended.accent,
            modifier = Modifier.size(44.dp),
        )
        Text(
            text = "Fire",
            color = extended.ink,
            fontSize = 28.sp,
            fontWeight = FontWeight.Bold,
        )
        Text(
            text = stringResource(R.string.onboarding_subtitle),
            color = extended.subtleInk,
            fontSize = 15.sp,
            textAlign = TextAlign.Center,
        )
    }
}

@Composable
private fun ErrorBanner(
    message: String,
    onDismiss: () -> Unit,
) {
    val extended = MaterialTheme.fireExtended

    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clip(FireShapes.smallControl)
            .background(extended.surfaceSecondary)
            .padding(12.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        Icon(
            imageVector = Icons.Filled.Warning,
            contentDescription = null,
            tint = extended.warning,
            modifier = Modifier.size(18.dp),
        )
        Text(
            text = message,
            color = extended.subtleInk,
            fontSize = 12.sp,
            maxLines = 2,
            modifier = Modifier.weight(1f),
        )
        Box(
            modifier = Modifier
                .size(30.dp)
                .clip(CircleShape)
                .clickable(onClick = onDismiss),
            contentAlignment = Alignment.Center,
        ) {
            Icon(
                imageVector = Icons.Filled.Close,
                contentDescription = null,
                tint = extended.subtleInk,
                modifier = Modifier.size(16.dp),
            )
        }
    }
}
