package com.fire.app.core.error

import android.util.Log
import com.fire.app.session.FireSessionStore
import java.util.concurrent.atomic.AtomicLong
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.launch
import uniffi.fire_uniffi_diagnostics.HostLogLevelState
import uniffi.fire_uniffi_types.FireUniFfiException

enum class FireErrorKind {
    Configuration,
    Validation,
    Authentication,
    LoginRequired,
    StaleSession,
    Network,
    CloudflareChallenge,
    HttpStatus,
    Storage,
    Serialization,
    Runtime,
    Internal,
    Unknown,
}

data class FireReportedError(
    val errorId: String,
    val operation: String,
    val kind: FireErrorKind,
    val displayMessage: String,
    val details: String,
    val isCloudflareChallenge: Boolean,
)

object FireErrorClassifier {
    fun classify(error: Throwable): FireErrorKind {
        val fireError = fireErrorIn(error)
        return when {
            isCloudflareChallenge(error) -> FireErrorKind.CloudflareChallenge
            fireError is FireUniFfiException.Configuration -> FireErrorKind.Configuration
            fireError is FireUniFfiException.Validation -> FireErrorKind.Validation
            fireError is FireUniFfiException.Authentication -> FireErrorKind.Authentication
            fireError is FireUniFfiException.LoginRequired -> FireErrorKind.LoginRequired
            fireError is FireUniFfiException.StaleSessionResponse -> FireErrorKind.StaleSession
            fireError is FireUniFfiException.Network -> FireErrorKind.Network
            fireError is FireUniFfiException.HttpStatus -> FireErrorKind.HttpStatus
            fireError is FireUniFfiException.Storage -> FireErrorKind.Storage
            fireError is FireUniFfiException.Serialization -> FireErrorKind.Serialization
            fireError is FireUniFfiException.Runtime -> FireErrorKind.Runtime
            fireError is FireUniFfiException.Internal -> FireErrorKind.Internal
            else -> FireErrorKind.Unknown
        }
    }

    fun isCloudflareChallenge(error: Throwable?): Boolean {
        var current = error
        while (current != null) {
            when (current) {
                is FireUniFfiException.CloudflareChallenge -> return true
                is FireUniFfiException.HttpStatus -> {
                    if (current.status.toInt() in CLOUDFLARE_CHALLENGE_HTTP_STATUSES &&
                        current.body.contains(CLOUDFLARE_CHALLENGE_TEXT, ignoreCase = true)
                    ) {
                        return true
                    }
                }
            }
            current = current.cause
        }
        return false
    }

    fun displayMessage(error: Throwable, fallbackMessage: String? = null): String {
        return when (classify(error)) {
            FireErrorKind.CloudflareChallenge -> "需要完成 Cloudflare 验证"
            FireErrorKind.Network -> fallbackMessage ?: "网络请求失败，请检查连接后重试"
            FireErrorKind.Authentication,
            FireErrorKind.LoginRequired -> fallbackMessage ?: "当前请求需要有效登录会话，请稍后重试"
            FireErrorKind.StaleSession -> fallbackMessage ?: "会话已更新，请重试"
            FireErrorKind.HttpStatus -> httpStatusMessage(error, fallbackMessage)
            FireErrorKind.Storage -> fallbackMessage ?: "本地数据访问失败"
            FireErrorKind.Serialization -> fallbackMessage ?: "数据解析失败，请稍后重试"
            FireErrorKind.Configuration,
            FireErrorKind.Validation,
            FireErrorKind.Runtime,
            FireErrorKind.Internal,
            FireErrorKind.Unknown -> fallbackMessage
                ?: error.localizedMessage
                ?: "操作失败，请稍后重试"
        }
    }

    fun details(error: Throwable): String {
        val fireError = fireErrorIn(error)
        return when (fireError) {
            is FireUniFfiException.Configuration -> fireError.details
            is FireUniFfiException.Validation -> fireError.details
            is FireUniFfiException.Authentication -> fireError.details
            is FireUniFfiException.LoginRequired -> fireError.details
            is FireUniFfiException.StaleSessionResponse -> fireError.operation
            is FireUniFfiException.Network -> fireError.details
            is FireUniFfiException.CloudflareChallenge -> "cloudflare challenge required"
            is FireUniFfiException.HttpStatus ->
                "${fireError.operation} HTTP ${fireError.status}: ${fireError.body.abbreviated()}"
            is FireUniFfiException.Storage -> fireError.details
            is FireUniFfiException.Serialization -> fireError.details
            is FireUniFfiException.Runtime -> fireError.details
            is FireUniFfiException.Internal -> fireError.details
            null -> error.localizedMessage ?: error.toString()
        }.abbreviated()
    }

    private fun httpStatusMessage(error: Throwable, fallbackMessage: String?): String {
        val fireError = fireErrorIn(error) as? FireUniFfiException.HttpStatus
            ?: return fallbackMessage ?: "请求失败，请稍后重试"
        return when (fireError.status.toInt()) {
            HTTP_UNAUTHORIZED -> "登录状态已失效，请重新登录"
            HTTP_FORBIDDEN -> fallbackMessage ?: "没有权限执行当前操作"
            HTTP_TOO_MANY_REQUESTS -> "请求过于频繁，请稍后重试"
            in 500..599 -> fallbackMessage ?: "服务器暂时不可用，请稍后重试"
            else -> fallbackMessage ?: "请求失败，请稍后重试"
        }
    }

    private fun fireErrorIn(error: Throwable?): FireUniFfiException? {
        var current = error
        while (current != null) {
            if (current is FireUniFfiException) return current
            current = current.cause
        }
        return null
    }

    private const val HTTP_UNAUTHORIZED = 401
    private const val HTTP_FORBIDDEN = 403
    private const val HTTP_TOO_MANY_REQUESTS = 429
    private const val CLOUDFLARE_CHALLENGE_TEXT = "Just a moment"
    private val CLOUDFLARE_CHALLENGE_HTTP_STATUSES = setOf(HTTP_FORBIDDEN, HTTP_TOO_MANY_REQUESTS)
}

object FireErrorReporter {
    private const val TAG = "FireError"
    private const val MAX_STACK_LINES = 24
    private val nextErrorId = AtomicLong()

    fun report(
        operation: String,
        error: Throwable,
        sessionStore: FireSessionStore? = null,
        fallbackMessage: String? = null,
    ): FireReportedError {
        val normalizedOperation = operation.ifBlank { "unknown" }
        val kind = FireErrorClassifier.classify(error)
        val report = FireReportedError(
            errorId = newErrorId(),
            operation = normalizedOperation,
            kind = kind,
            displayMessage = FireErrorClassifier.displayMessage(error, fallbackMessage),
            details = FireErrorClassifier.details(error),
            isCloudflareChallenge = FireErrorClassifier.isCloudflareChallenge(error),
        )
        val message = buildLogMessage(report)
        if (kind.shouldLogAsError()) {
            Log.e(TAG, message, error)
        } else {
            Log.w(TAG, message, error)
        }
        sessionStore?.let { store ->
            runCatching {
                store.logHost(
                    level = kind.hostLogLevel(),
                    target = "android.$normalizedOperation",
                    message = "$message\n${error.stackTraceForDiagnostics()}",
                )
            }
            runCatching { store.flushLogs(sync = false) }
        }
        return report
    }

    private fun buildLogMessage(report: FireReportedError): String {
        return "error_id=${report.errorId} operation=${report.operation} " +
            "kind=${report.kind} cloudflare=${report.isCloudflareChallenge} " +
            "details=${report.details.oneLine()}"
    }

    private fun FireErrorKind.shouldLogAsError(): Boolean {
        return when (this) {
            FireErrorKind.Network,
            FireErrorKind.CloudflareChallenge,
            FireErrorKind.HttpStatus,
            FireErrorKind.StaleSession -> false
            else -> true
        }
    }

    private fun FireErrorKind.hostLogLevel(): HostLogLevelState {
        return if (shouldLogAsError()) HostLogLevelState.ERROR else HostLogLevelState.WARN
    }

    private fun newErrorId(): String {
        return "android-${System.currentTimeMillis().toString(36)}-" +
            nextErrorId.incrementAndGet().toString(36)
    }

    private fun Throwable.stackTraceForDiagnostics(): String {
        return stackTraceToString()
            .lineSequence()
            .take(MAX_STACK_LINES)
            .joinToString("\n")
            .ifBlank { toString() }
    }
}

fun CoroutineScope.launchWithFireErrorHandling(
    operation: String,
    sessionStore: FireSessionStore? = null,
    fallbackMessage: String? = null,
    onError: (FireReportedError) -> Unit = {},
    block: suspend CoroutineScope.() -> Unit,
): Job = launch {
    try {
        block()
    } catch (error: CancellationException) {
        throw error
    } catch (error: Exception) {
        onError(
            FireErrorReporter.report(
                operation = operation,
                error = error,
                sessionStore = sessionStore,
                fallbackMessage = fallbackMessage,
            ),
        )
    }
}

private fun String.abbreviated(maxLength: Int = 700): String {
    return if (length <= maxLength) this else take(maxLength) + "..."
}

private fun String.oneLine(): String {
    return lineSequence()
        .map { it.trim() }
        .filter { it.isNotEmpty() }
        .joinToString(" ")
        .abbreviated()
}
