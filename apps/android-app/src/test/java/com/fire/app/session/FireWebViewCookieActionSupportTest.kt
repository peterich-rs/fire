package com.fire.app.session

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import uniffi.fire_uniffi_session.PlatformCookieState

class FireWebViewCookieActionSupportTest {
    @Test
    fun parseCookieInfoHeadersKeepMetadataForSweepPlanning() {
        val cookies = FireWebViewCookieActionSupport.parseCookieInfoHeaders(
            listOf(
                "_t=token; Path=/; Domain=linux.do; Secure; HttpOnly; SameSite=Lax",
                "cf_clearance=clear; Path=/; Domain=.linux.do; Secure; SameSite=None",
            ),
        )

        assertEquals(listOf("_t", "cf_clearance"), cookies.map { it.name })
        assertEquals(listOf("token", "clear"), cookies.map { it.value })
        assertEquals(listOf("linux.do", ".linux.do"), cookies.map { it.domain })
        assertEquals(listOf("/", "/"), cookies.map { it.path })
        assertTrue(cookies.all { it.secure == true })
        assertEquals(false, cookies[0].hostOnly)
    }

    @Test
    fun cookieInfosFromHeadersFallsBackToLowConfidenceCookieHeader() {
        val cookies = FireWebViewCookieActionSupport.cookieInfosFromHeadersOrFallback(
            cookieInfoHeaders = emptyList(),
            cookieHeader = "_t=token; _forum_session=forum; cf_clearance=clear=with_equals; ignored; empty=",
        )

        assertEquals(listOf("_t", "_forum_session", "cf_clearance"), cookies.map { it.name })
        assertEquals(listOf("token", "forum", "clear=with_equals"), cookies.map { it.value })
        assertTrue(cookies.all { it.domain == null })
        assertTrue(cookies.all { it.path == null })
        assertTrue(cookies.all { it.hostOnly == null })
        assertEquals(null, cookies[0].sameSite)
        assertEquals(uniffi.fire_uniffi_session.CookieSameSiteState.NONE, cookies[2].sameSite)
    }

    @Test
    fun cookieInfosPreferRichCookieInfoHeadersWhenAvailable() {
        val cookies = FireWebViewCookieActionSupport.cookieInfosFromHeadersOrFallback(
            cookieInfoHeaders = listOf("cf_clearance=rich; Path=/; Domain=.linux.do; Secure; SameSite=None"),
            cookieHeader = "cf_clearance=plain",
        )

        assertEquals(1, cookies.size)
        assertEquals("rich", cookies[0].value)
        assertEquals(".linux.do", cookies[0].domain)
        assertEquals("/", cookies[0].path)
    }

    @Test
    fun deleteByNameHeadersCoverHostOnlyAndDomainVariants() {
        val headers = FireWebViewCookieActionSupport.deleteByNameHeaders(
            url = "https://connect.linux.do/session",
            name = "cf_clearance",
        )

        assertTrue(headers.any { it == "cf_clearance=; Max-Age=0; Expires=Thu, 01 Jan 1970 00:00:00 GMT; Path=/" })
        assertTrue(headers.any { it.endsWith("; Domain=connect.linux.do") })
        assertTrue(headers.any { it.endsWith("; Domain=.connect.linux.do") })
        assertTrue(headers.any { it.endsWith("; Domain=.linux.do") })
    }

    @Test
    fun expiredCookieHeaderIncludesExactPathAndDomainWhenProvided() {
        val header = FireWebViewCookieActionSupport.expiredCookieHeader(
            name = "_t",
            domain = ".linux.do",
            path = "/session",
        )

        assertEquals(
            "_t=; Max-Age=0; Expires=Thu, 01 Jan 1970 00:00:00 GMT; Path=/session; Domain=.linux.do",
            header,
        )
    }

    @Test
    fun cloudflareChallengeResultCookiesAcceptOnlyFreshClearance() {
        val cookies = listOf(
            PlatformCookieState(
                name = "_t",
                value = "token",
                domain = "linux.do",
                path = "/",
                expiresAtUnixMs = null,
                sameSite = null,
            ),
            PlatformCookieState(
                name = "cf_clearance",
                value = "old-clearance",
                domain = ".linux.do",
                path = "/",
                expiresAtUnixMs = null,
                sameSite = null,
            ),
            PlatformCookieState(
                name = "cf_clearance",
                value = "fresh-clearance",
                domain = ".linux.do",
                path = "/",
                expiresAtUnixMs = null,
                sameSite = "none",
            ),
        )

        val result = FireCloudflareChallengeActivity.challengeResultCookies(
            cookies = cookies,
            freshCfClearance = " fresh-clearance ",
        )

        assertEquals(listOf("_t", "cf_clearance"), result.map { it.name })
        assertEquals("fresh-clearance", result.last().value)
    }

    @Test
    fun challengeResultCookies_dropClearanceWhenPageClearsWithoutNewCookie() {
        val cookies = listOf(
            PlatformCookieState(
                name = "_t",
                value = "token",
                domain = "linux.do",
                path = "/",
                expiresAtUnixMs = null,
                sameSite = null,
            ),
            PlatformCookieState(
                name = "cf_clearance",
                value = "old-clearance",
                domain = ".linux.do",
                path = "/",
                expiresAtUnixMs = null,
                sameSite = null,
            ),
        )

        val result = FireCloudflareChallengeActivity.challengeResultCookies(
            cookies = cookies,
            freshCfClearance = null,
        )

        assertEquals(listOf("_t"), result.map { it.name })
    }

    @Test
    fun sourceSiteChallengeClearance_acceptsOnlyOrigin404WithoutMitigation() {
        assertFalse(
            FireCloudflareChallengeActivity.isSourceSiteChallengeClearance(
                statusCode = 200,
                headers = emptyMap(),
            ),
        )
        assertTrue(
            FireCloudflareChallengeActivity.isSourceSiteChallengeClearance(
                statusCode = 404,
                headers = emptyMap(),
            ),
        )
        assertFalse(
            FireCloudflareChallengeActivity.isSourceSiteChallengeClearance(
                statusCode = 403,
                headers = emptyMap(),
            ),
        )
        assertFalse(
            FireCloudflareChallengeActivity.isSourceSiteChallengeClearance(
                statusCode = 404,
                headers = mapOf("cf-mitigated" to "challenge"),
            ),
        )
    }

    @Test
    fun emptyChallengeFirstPaint_doesNotFinishUntilChallengeWasSeen() {
        assertFalse(
            FireCloudflareChallengeActivity.shouldFinishFromPageState(
                isOriginFallback = false,
                isPassedNonChallenge = true,
                hasSeenActiveChallenge = false,
            ),
        )
        assertTrue(
            FireCloudflareChallengeActivity.shouldFinishFromPageState(
                isOriginFallback = false,
                isPassedNonChallenge = true,
                hasSeenActiveChallenge = true,
            ),
        )
        assertTrue(
            FireCloudflareChallengeActivity.shouldFinishFromPageState(
                isOriginFallback = true,
                isPassedNonChallenge = false,
                hasSeenActiveChallenge = false,
            ),
        )
    }

    @Test
    fun completionClearance_prefersNewValueThenRewritesReturnedIncumbent() {
        assertEquals(
            "new-clearance",
            FireCloudflareChallengeActivity.clearanceValueForCompletion(
                currentValues = listOf("old-clearance", "new-clearance"),
                baselineValues = setOf("old-clearance"),
            ),
        )
        assertEquals(
            "old-clearance",
            FireCloudflareChallengeActivity.clearanceValueForCompletion(
                currentValues = listOf("old-clearance"),
                baselineValues = setOf("old-clearance"),
            ),
        )
        assertEquals(
            null,
            FireCloudflareChallengeActivity.clearanceValueForCompletion(
                currentValues = emptyList(),
                baselineValues = setOf("old-clearance"),
            ),
        )
    }
}
