package com.fire.app.ui.auth.compose

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.Visibility
import androidx.compose.material.icons.filled.VisibilityOff
import androidx.compose.material.icons.outlined.Circle
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.platform.LocalSoftwareKeyboardController
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.text.input.VisualTransformation
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.fire.app.R
import com.fire.app.core.theme.compose.FireShapes
import com.fire.app.core.theme.compose.fireExtended
import com.fire.app.ui.auth.FireLastLoginMethod

/** iOS login CTA uses system orange rather than brand accent alone. */
private val LoginSystemOrange = Color(0xFFFF9500)

/** iOS “忘记密码?” uses system blue. */
private val LoginSystemBlue = Color(0xFF007AFF)

@Composable
fun CredentialForm(
    identifier: String,
    password: String,
    isPasswordVisible: Boolean,
    rememberPassword: Boolean,
    isLoginEnabled: Boolean,
    isLoading: Boolean,
    lastLoginMethod: FireLastLoginMethod?,
    onIdentifierChange: (String) -> Unit,
    onPasswordChange: (String) -> Unit,
    onTogglePasswordVisibility: () -> Unit,
    onToggleRemember: () -> Unit,
    onLogin: () -> Unit,
    onForgotPassword: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val extended = MaterialTheme.fireExtended
    val fieldHeight = 48.dp
    val fieldCorner = FireShapes.smallControl

    Column(
        modifier = modifier.fillMaxWidth(),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        BasicTextField(
            value = identifier,
            onValueChange = onIdentifierChange,
            modifier = Modifier
                .fillMaxWidth()
                .height(fieldHeight),
            enabled = !isLoading,
            singleLine = true,
            textStyle = MaterialTheme.typography.bodyLarge.copy(
                color = extended.ink,
            ),
            cursorBrush = SolidColor(extended.accent),
            keyboardOptions = KeyboardOptions(
                capitalization = KeyboardCapitalization.None,
                imeAction = ImeAction.Next,
            ),
            decorationBox = { innerTextField ->
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .height(fieldHeight)
                        .clip(fieldCorner)
                        .background(extended.surfaceSecondary)
                        .border(1.dp, extended.divider, fieldCorner),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Box(
                        modifier = Modifier
                            .weight(1f)
                            .padding(start = 12.dp),
                        contentAlignment = Alignment.CenterStart,
                    ) {
                        if (identifier.isEmpty()) {
                            Text(
                                text = stringResource(R.string.login_identifier_hint),
                                color = extended.tertiaryInk,
                                style = MaterialTheme.typography.bodyLarge,
                            )
                        }
                        innerTextField()
                    }
                    if (identifier.isNotEmpty()) {
                        IconButton(
                            onClick = { onIdentifierChange("") },
                            modifier = Modifier.size(fieldHeight),
                        ) {
                            Icon(
                                imageVector = Icons.Filled.Close,
                                contentDescription = stringResource(R.string.login_clear_identifier),
                                tint = extended.tertiaryInk,
                            )
                        }
                    }
                }
            },
        )

        val keyboardController = LocalSoftwareKeyboardController.current
        BasicTextField(
            value = password,
            onValueChange = onPasswordChange,
            modifier = Modifier
                .fillMaxWidth()
                .height(fieldHeight),
            enabled = !isLoading,
            singleLine = true,
            visualTransformation = if (isPasswordVisible) {
                VisualTransformation.None
            } else {
                PasswordVisualTransformation()
            },
            textStyle = MaterialTheme.typography.bodyLarge.copy(
                color = extended.ink,
            ),
            cursorBrush = SolidColor(extended.accent),
            keyboardOptions = KeyboardOptions(
                keyboardType = KeyboardType.Password,
                imeAction = ImeAction.Done,
            ),
            keyboardActions = KeyboardActions(
                onDone = {
                    if (isLoginEnabled) {
                        keyboardController?.hide()
                        onLogin()
                    }
                },
            ),
            decorationBox = { innerTextField ->
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .height(fieldHeight)
                        .clip(fieldCorner)
                        .background(extended.surfaceSecondary)
                        .border(1.dp, extended.divider, fieldCorner),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Box(
                        modifier = Modifier
                            .weight(1f)
                            .padding(start = 12.dp),
                        contentAlignment = Alignment.CenterStart,
                    ) {
                        if (password.isEmpty()) {
                            Text(
                                text = stringResource(R.string.login_password_hint),
                                color = extended.tertiaryInk,
                                style = MaterialTheme.typography.bodyLarge,
                            )
                        }
                        innerTextField()
                    }
                    IconButton(
                        onClick = onTogglePasswordVisibility,
                        modifier = Modifier.size(fieldHeight),
                    ) {
                        Icon(
                            imageVector = if (isPasswordVisible) {
                                Icons.Filled.VisibilityOff
                            } else {
                                Icons.Filled.Visibility
                            },
                            contentDescription = stringResource(
                                if (isPasswordVisible) {
                                    R.string.login_password_visibility_hide
                                } else {
                                    R.string.login_password_visibility_show
                                },
                            ),
                            tint = extended.tertiaryInk,
                        )
                    }
                }
            },
        )

        val rememberDescription = if (rememberPassword) {
            stringResource(R.string.login_remember_password_checked)
        } else {
            stringResource(R.string.login_remember_password)
        }
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .height(24.dp),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Row(
                verticalAlignment = Alignment.CenterVertically,
                modifier = Modifier
                    .semantics {
                        role = Role.Checkbox
                        selected = rememberPassword
                        contentDescription = rememberDescription
                    }
                    .clickable(enabled = !isLoading) { onToggleRemember() },
            ) {
                Icon(
                    imageVector = if (rememberPassword) {
                        Icons.Filled.CheckCircle
                    } else {
                        Icons.Outlined.Circle
                    },
                    contentDescription = null,
                    tint = if (rememberPassword) extended.accent else extended.tertiaryInk,
                    modifier = Modifier.size(16.dp),
                )
                Spacer(Modifier.width(5.dp))
                Text(
                    text = stringResource(R.string.login_remember_password),
                    color = extended.subtleInk,
                    fontSize = 13.sp,
                )
            }

            Text(
                text = stringResource(R.string.login_forgot_password),
                color = LoginSystemBlue,
                fontSize = 13.sp,
                modifier = Modifier.clickable(enabled = !isLoading) { onForgotPassword() },
            )
        }

        // iOS: 16pt between options row and login button (extra 4 over field spacing).
        Spacer(Modifier.height(4.dp))

        val isPasswordLastLogin = lastLoginMethod == FireLastLoginMethod.Password
        // iOS uses medium corner style (~12), not a full pill.
        val loginShape = FireShapes.cardMedium
        Button(
            onClick = onLogin,
            modifier = Modifier
                .fillMaxWidth()
                .height(50.dp)
                .then(
                    if (isPasswordLastLogin) {
                        Modifier.border(
                            width = 1.5.dp,
                            color = extended.accent,
                            shape = loginShape,
                        )
                    } else {
                        Modifier
                    },
                ),
            enabled = isLoginEnabled && !isLoading,
            shape = loginShape,
            colors = ButtonDefaults.buttonColors(
                containerColor = LoginSystemOrange,
                contentColor = Color.White,
                disabledContainerColor = LoginSystemOrange.copy(alpha = 0.4f),
                disabledContentColor = Color.White,
            ),
        ) {
            if (isLoading) {
                CircularProgressIndicator(
                    modifier = Modifier.size(20.dp),
                    strokeWidth = 2.dp,
                    color = Color.White,
                )
                Spacer(Modifier.width(8.dp))
                Text(
                    text = stringResource(R.string.login_in_progress),
                    color = Color.White,
                )
            } else {
                Text(
                    text = stringResource(R.string.login_action),
                    color = Color.White,
                )
            }
        }

        if (lastLoginMethod != null) {
            Spacer(Modifier.height(10.dp))
            Text(
                text = stringResource(R.string.login_last_used, lastLoginMethod.displayName),
                color = extended.subtleInk,
                fontSize = 12.sp,
                textAlign = TextAlign.Center,
                modifier = Modifier.fillMaxWidth(),
            )
        }
    }
}
