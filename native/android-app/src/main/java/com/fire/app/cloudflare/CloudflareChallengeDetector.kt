package com.fire.app.cloudflare

import uniffi.fire_uniffi_types.FireUniFfiException

object CloudflareChallengeDetector {
    fun isChallenge(error: Throwable?): Boolean {
        var current = error
        while (current != null) {
            when (current) {
                is FireUniFfiException.CloudflareChallenge -> return true
                is FireUniFfiException.HttpStatus -> {
                    if (current.status.toInt() == 403 &&
                        current.body.contains("Just a moment", ignoreCase = true)
                    ) {
                        return true
                    }
                }
            }
            current = current.cause
        }
        return false
    }
}
