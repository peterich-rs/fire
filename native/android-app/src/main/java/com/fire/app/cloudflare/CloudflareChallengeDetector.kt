package com.fire.app.cloudflare

import com.fire.app.core.error.FireErrorClassifier

class CloudflareChallengeRecoveryError(
    val recoveryUrl: String,
    cause: Throwable,
) : RuntimeException(cause.message, cause)

object CloudflareChallengeDetector {
    fun isChallenge(error: Throwable?): Boolean {
        return FireErrorClassifier.isCloudflareChallenge(error)
    }

    fun recoveryUrl(error: Throwable?): String? {
        var current = error
        while (current != null) {
            if (current is CloudflareChallengeRecoveryError) {
                return current.recoveryUrl
            }
            current = current.cause
        }
        return null
    }
}
