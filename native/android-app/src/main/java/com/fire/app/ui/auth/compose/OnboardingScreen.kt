package com.fire.app.ui.auth.compose

import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.togetherWith
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawing
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.windowInsetsPadding
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
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalFocusManager
import androidx.compose.ui.platform.LocalSoftwareKeyboardController
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.fire.app.R
import com.fire.app.core.theme.compose.FireDimens
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
    val horizontalInset = FireDimens.loginHorizontalInset
    val brandPhaseSpacing = 32.dp
    val focusManager = LocalFocusManager.current
    val keyboardController = LocalSoftwareKeyboardController.current

    Box(
        modifier = modifier
            .fillMaxSize()
            .background(extended.canvasMid)
            .windowInsetsPadding(WindowInsets.safeDrawing)
            .imePadding()
            .pointerInput(Unit) {
                detectTapGestures {
                    focusManager.clearFocus()
                    keyboardController?.hide()
                }
            }
            .verticalScroll(rememberScrollState()),
        contentAlignment = Alignment.Center,
    ) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = horizontalInset)
                .padding(bottom = 24.dp)
                // Optical lift matching iOS centerY −24.
                .offset(y = (-24).dp),
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
                    fadeIn().togetherWith(fadeOut())
                },
                label = "phaseTransition",
            ) { phase ->
                when (phase) {
                    OnboardingPhase.Validating, OnboardingPhase.LoggingIn -> {
                        ValidatingContent(
                            message = state.validatingMessage
                                .ifEmpty { stringResource(R.string.onboarding_checking_login_state) },
                            detail = state.validatingDetail,
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
                                enabled = true,
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
            contentDescription = stringResource(R.string.app_name),
            tint = extended.accent,
            modifier = Modifier.size(44.dp),
        )
        Text(
            text = stringResource(R.string.app_name),
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
                contentDescription = stringResource(R.string.login_dismiss_error),
                tint = extended.subtleInk,
                modifier = Modifier.size(16.dp),
            )
        }
    }
}
