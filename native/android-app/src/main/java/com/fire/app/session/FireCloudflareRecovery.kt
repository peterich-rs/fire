package com.fire.app.session

import android.content.Context
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import uniffi.fire_uniffi_session.CloudflareChallengeRequestState
import uniffi.fire_uniffi_types.FireUniFfiException

object FireCloudflareRecovery {
    suspend fun <T> perform(
        context: Context,
        sessionStore: FireSessionStore,
        operation: String,
        originUrl: String = "https://linux.do/",
        work: suspend () -> T,
    ): T {
        return try {
            work()
        } catch (error: Exception) {
            if (!isCloudflareChallenge(error)) {
                throw error
            }
            val recovered = completeManualVerification(
                context = context,
                sessionStore = sessionStore,
                operation = operation,
                originUrl = originUrl,
            )
            if (!recovered) {
                throw error
            }
            work()
        }
    }

    suspend fun completeManualVerification(
        context: Context,
        sessionStore: FireSessionStore,
        operation: String = "manual.verify",
        originUrl: String = "https://linux.do/",
    ): Boolean = withContext(Dispatchers.IO) {
        val epoch = runCatching { sessionStore.currentSessionEpoch() }.getOrDefault(0u)
        val result = FireCloudflareChallengeCoordinator(context.applicationContext)
            .completeSynchronously(
                CloudflareChallengeRequestState(
                    operation = operation,
                    requestUrl = originUrl,
                    originUrl = originUrl,
                    isForeground = true,
                    sessionEpoch = epoch,
                ),
            )
        val fresh = result.freshCfClearance?.trim().orEmpty()
        if (!result.completed || result.userCancelled || fresh.isEmpty()) {
            return@withContext false
        }
        val session = sessionStore.completeCloudflareChallenge(
            cookies = result.cookies,
            freshCfClearance = fresh,
            browserUserAgent = result.browserUserAgent,
        )
        val accepted = session.cookies.cfClearance == fresh
        if (accepted) {
            FireCfClearanceRefreshService.get(context).setLoginStateConfirmed(
                session.readiness.hasCurrentUser && session.readiness.canReadAuthenticatedApi,
            )
            FireCfClearanceRefreshService.get(context).updateSession(session)
        }
        accepted
    }

    fun isCloudflareChallenge(error: Throwable?): Boolean {
        var current = error
        while (current != null) {
            when (current) {
                is FireUniFfiException.CloudflareChallenge -> return true
                is FireUniFfiException.HttpStatus -> {
                    if (current.status.toInt() in setOf(403, 429) &&
                        current.body.contains("Just a moment", ignoreCase = true)
                    ) {
                        return true
                    }
                }
            }
            val message = current.message.orEmpty()
            if (message.contains("Cloudflare challenge", ignoreCase = true) ||
                message.contains("cloudflare challenge", ignoreCase = true)
            ) {
                return true
            }
            current = current.cause
        }
        return false
    }

    fun reason(error: Throwable?): String {
        var current = error
        while (current != null) {
            if (current is FireUniFfiException.CloudflareChallenge) {
                val reason = current.reason.trim()
                if (reason.isNotEmpty()) {
                    return reason
                }
            }
            val message = current.message.orEmpty()
            for (token in REASONS) {
                if (message.contains("($token)") || message.contains(token)) {
                    return token
                }
            }
            current = current.cause
        }
        return "required"
    }

    private val REASONS = listOf(
        "in_progress",
        "cooldown",
        "cancelled",
        "failed",
        "background_suppressed",
        "required",
    )
}
