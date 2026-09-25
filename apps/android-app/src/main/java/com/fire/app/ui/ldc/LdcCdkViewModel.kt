package com.fire.app.ui.ldc

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.fire.app.core.error.FireErrorReporter
import com.fire.app.session.FireSessionStore
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import uniffi.fire_uniffi_ldc.CdkAuthorizationUrlState
import uniffi.fire_uniffi_ldc.CdkUserInfoState
import uniffi.fire_uniffi_ldc.LdcApprovalStatusKindState
import uniffi.fire_uniffi_ldc.LdcApprovalStatusState
import uniffi.fire_uniffi_ldc.LdcAuthorizationUrlState
import uniffi.fire_uniffi_ldc.LdcUserInfoState

enum class LdcCdkMode {
    LDC,
    CDK,
}

sealed class LdcCdkUserInfo {
    data class Ldc(val info: LdcUserInfoState) : LdcCdkUserInfo()
    data class Cdk(val info: CdkUserInfoState) : LdcCdkUserInfo()
}

data class LdcCdkAuthorizationState(
    val url: String,
    val state: String,
    val approvalPath: String?,
    val approvalStatus: LdcApprovalStatusState?,
)

data class LdcCdkUiState(
    val userInfo: LdcCdkUserInfo? = null,
    val authorization: LdcCdkAuthorizationState? = null,
    val isLoadingUserInfo: Boolean = false,
    val isPreparingAuthorization: Boolean = false,
    val isCompletingAuthorization: Boolean = false,
    val isLoggingOut: Boolean = false,
    val noticeMessage: String? = null,
    val errorMessage: String? = null,
) {
    val isBusy: Boolean
        get() = isPreparingAuthorization || isCompletingAuthorization || isLoggingOut
}

class LdcCdkViewModel(
    private val sessionStore: FireSessionStore,
    private val mode: LdcCdkMode,
) : ViewModel() {

    private val _state = MutableStateFlow(LdcCdkUiState())
    val state = _state.asStateFlow()

    private var didLoadInitialUserInfo = false

    fun loadUserInfo(force: Boolean = false) {
        val current = _state.value
        if (current.isLoadingUserInfo || (!force && didLoadInitialUserInfo)) return
        didLoadInitialUserInfo = true
        val shouldSurfaceErrors = force || current.userInfo == null

        viewModelScope.launch {
            _state.update {
                it.copy(
                    isLoadingUserInfo = true,
                    errorMessage = if (it.userInfo == null) null else it.errorMessage,
                )
            }
            try {
                val info = when (mode) {
                    LdcCdkMode.LDC -> LdcCdkUserInfo.Ldc(sessionStore.ldcUserInfo())
                    LdcCdkMode.CDK -> LdcCdkUserInfo.Cdk(sessionStore.cdkUserInfo())
                }
                _state.update {
                    it.copy(
                        userInfo = info,
                        isLoadingUserInfo = false,
                        errorMessage = null,
                    )
                }
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                val displayMessage = reportError("user_info", e)
                _state.update {
                    it.copy(
                        isLoadingUserInfo = false,
                        errorMessage = if (shouldSurfaceErrors) displayMessage else it.errorMessage,
                    )
                }
            }
        }
    }

    fun prepareAuthorization(linkReadyMessage: String) {
        if (_state.value.isBusy) return

        viewModelScope.launch {
            _state.update {
                it.copy(
                    isPreparingAuthorization = true,
                    noticeMessage = null,
                    errorMessage = null,
                )
            }
            try {
                val auth = when (mode) {
                    LdcCdkMode.LDC -> sessionStore.ldcAuthorizationUrl().toCommon()
                    LdcCdkMode.CDK -> sessionStore.cdkAuthorizationUrl().toCommon()
                }
                val approvalPath = when (mode) {
                    LdcCdkMode.LDC -> sessionStore.ldcApprovalLink(auth.url)
                    LdcCdkMode.CDK -> sessionStore.cdkApprovalLink(auth.url)
                }
                _state.update {
                    it.copy(
                        authorization = LdcCdkAuthorizationState(
                            url = auth.url,
                            state = auth.state,
                            approvalPath = approvalPath,
                            approvalStatus = null,
                        ),
                        isPreparingAuthorization = false,
                        noticeMessage = linkReadyMessage,
                        errorMessage = null,
                    )
                }
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                _state.update {
                    it.copy(
                        isPreparingAuthorization = false,
                        errorMessage = reportError("prepare_authorization", e),
                    )
                }
            }
        }
    }

    fun completeAuthorization(
        callbackMissingMessage: String,
        completedMessage: String,
        pendingMessage: String,
        deniedMessage: String,
    ) {
        val approvalPath = _state.value.authorization?.approvalPath ?: return
        if (_state.value.isBusy) return

        viewModelScope.launch {
            _state.update {
                it.copy(
                    isCompletingAuthorization = true,
                    noticeMessage = null,
                    errorMessage = null,
                )
            }
            try {
                val status = when (mode) {
                    LdcCdkMode.LDC -> sessionStore.ldcApprove(approvalPath)
                    LdcCdkMode.CDK -> sessionStore.cdkApprove(approvalPath)
                }
                when (status.kind) {
                    LdcApprovalStatusKindState.APPROVED -> {
                        val code = status.code
                        val state = status.state
                        if (code.isNullOrBlank() || state.isNullOrBlank()) {
                            _state.update {
                                it.copy(
                                    isCompletingAuthorization = false,
                                    authorization = it.authorization?.copy(approvalStatus = status),
                                    errorMessage = callbackMissingMessage,
                                )
                            }
                            return@launch
                        }
                        val userInfo = when (mode) {
                            LdcCdkMode.LDC -> {
                                sessionStore.ldcCallback(code, state)
                                LdcCdkUserInfo.Ldc(sessionStore.ldcUserInfo())
                            }
                            LdcCdkMode.CDK -> {
                                sessionStore.cdkCallback(code, state)
                                LdcCdkUserInfo.Cdk(sessionStore.cdkUserInfo())
                            }
                        }
                        _state.update {
                            it.copy(
                                userInfo = userInfo,
                                isCompletingAuthorization = false,
                                authorization = it.authorization?.copy(approvalStatus = status),
                                noticeMessage = completedMessage,
                                errorMessage = null,
                            )
                        }
                    }
                    LdcApprovalStatusKindState.PENDING -> {
                        _state.update {
                            it.copy(
                                isCompletingAuthorization = false,
                                authorization = it.authorization?.copy(approvalStatus = status),
                                noticeMessage = pendingMessage,
                                errorMessage = null,
                            )
                        }
                    }
                    LdcApprovalStatusKindState.DENIED -> {
                        _state.update {
                            it.copy(
                                isCompletingAuthorization = false,
                                authorization = it.authorization?.copy(approvalStatus = status),
                                noticeMessage = null,
                                errorMessage = deniedMessage,
                            )
                        }
                    }
                }
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                _state.update {
                    it.copy(
                        isCompletingAuthorization = false,
                        errorMessage = reportError("complete_authorization", e),
                    )
                }
            }
        }
    }

    fun logout(completedMessage: String) {
        if (_state.value.isBusy) return

        viewModelScope.launch {
            _state.update {
                it.copy(
                    isLoggingOut = true,
                    noticeMessage = null,
                    errorMessage = null,
                )
            }
            try {
                when (mode) {
                    LdcCdkMode.LDC -> sessionStore.ldcLogout()
                    LdcCdkMode.CDK -> sessionStore.cdkLogout()
                }
                _state.value = LdcCdkUiState(noticeMessage = completedMessage)
                didLoadInitialUserInfo = false
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                _state.update {
                    it.copy(
                        isLoggingOut = false,
                        errorMessage = reportError("logout", e),
                    )
                }
            }
        }
    }

    private data class CommonAuthorizationUrlState(
        val url: String,
        val state: String,
    )

    private fun LdcAuthorizationUrlState.toCommon(): CommonAuthorizationUrlState =
        CommonAuthorizationUrlState(url = url, state = state)

    private fun CdkAuthorizationUrlState.toCommon(): CommonAuthorizationUrlState =
        CommonAuthorizationUrlState(url = url, state = state)

    private fun reportError(action: String, error: Exception): String {
        val reported = FireErrorReporter.report(
            operation = "ldc_cdk.${mode.name.lowercase()}.$action",
            error = error,
            sessionStore = sessionStore,
        )
        return reported.displayMessage
    }

    companion object {
        fun create(sessionStore: FireSessionStore, mode: LdcCdkMode): LdcCdkViewModel {
            return LdcCdkViewModel(sessionStore, mode)
        }
    }
}
