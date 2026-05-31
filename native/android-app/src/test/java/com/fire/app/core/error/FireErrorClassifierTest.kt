package com.fire.app.core.error

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import uniffi.fire_uniffi_types.FireUniFfiException

class FireErrorClassifierTest {
    @Test
    fun classify_mapsUniFfiNetworkErrors() {
        val error = FireUniFfiException.Network("connect: TCP connect failed")

        assertEquals(FireErrorKind.Network, FireErrorClassifier.classify(error))
        assertTrue(FireErrorClassifier.displayMessage(error).contains("网络请求失败"))
    }

    @Test
    fun isCloudflareChallenge_acceptsExplicitChallengeError() {
        val error = FireUniFfiException.CloudflareChallenge()

        assertTrue(FireErrorClassifier.isCloudflareChallenge(error))
        assertEquals(FireErrorKind.CloudflareChallenge, FireErrorClassifier.classify(error))
    }

    @Test
    fun isCloudflareChallenge_acceptsForbiddenChallengeHtml() {
        val error = FireUniFfiException.HttpStatus(
            operation = "fetch_topic_screen",
            status = 403.toUShort(),
            body = "<html><title>Just a moment...</title></html>",
        )

        assertTrue(FireErrorClassifier.isCloudflareChallenge(error))
        assertEquals(FireErrorKind.CloudflareChallenge, FireErrorClassifier.classify(error))
    }
}
