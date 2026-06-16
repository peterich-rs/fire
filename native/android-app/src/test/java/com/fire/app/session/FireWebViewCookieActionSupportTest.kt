package com.fire.app.session

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class FireWebViewCookieActionSupportTest {
    @Test
    fun parseCookieHeaderKeepsNameValuePairsForSweepPlanning() {
        val cookies = FireWebViewCookieActionSupport.parseCookieHeader(
            "_t=token; _forum_session=session; empty=; cf_clearance=clear",
        )

        assertEquals(listOf("_t", "_forum_session", "cf_clearance"), cookies.map { it.name })
        assertEquals(listOf("token", "session", "clear"), cookies.map { it.value })
        assertTrue(cookies.all { it.domain == null && it.path == null })
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
}
