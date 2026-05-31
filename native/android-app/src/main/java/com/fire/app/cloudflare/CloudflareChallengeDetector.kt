package com.fire.app.cloudflare

import com.fire.app.core.error.FireErrorClassifier

object CloudflareChallengeDetector {
    fun isChallenge(error: Throwable?): Boolean {
        return FireErrorClassifier.isCloudflareChallenge(error)
    }
}
