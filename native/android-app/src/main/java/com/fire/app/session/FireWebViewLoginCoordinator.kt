package com.fire.app.session

import android.webkit.CookieManager
import android.webkit.WebView
import androidx.webkit.CookieManagerCompat
import androidx.webkit.WebViewFeature
import java.net.URI
import java.time.Instant
import java.time.ZoneOffset
import java.time.ZonedDateTime
import java.time.format.DateTimeFormatter
import java.time.format.DateTimeParseException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.coroutines.withContext
import org.json.JSONObject
import kotlin.coroutines.resume
import uniffi.fire_uniffi_session.CookieSameSiteState
import uniffi.fire_uniffi_session.CookieSweepPlanState
import uniffi.fire_uniffi_session.LoginPhaseState
import uniffi.fire_uniffi_session.PlatformCookieState
import uniffi.fire_uniffi_session.SessionState
import uniffi.fire_uniffi_session.WebViewCookieActionState
import uniffi.fire_uniffi_session.WebViewCookieInfoState

data class FireLoginSyncReadiness(
    val isReady: Boolean,
    val username: String?,
    val hasAuthCookies: Boolean,
    val hasBootstrapHtml: Boolean,
    val preferredBootstrapScore: Int,
)

class FireWebViewLoginCoordinator(
    private val sessionStore: FireSessionStore,
    private val loginBaseUrl: String = "https://linux.do",
) {
    suspend fun restorePersistedSessionIfAvailable(): SessionState? {
        return sessionStore.restorePersistedSessionIfAvailable()
    }

    suspend fun completeLogin(webView: WebView): SessionState {
        val captured = captureLoginState(webView)
        val readiness = loginSyncReadiness(captured)
        check(readiness.isReady) { "登录状态尚未准备完成" }
        return completeLogin(captured)
    }

    suspend fun completeLogin(captured: FireCapturedLoginState): SessionState {
        val finalization = sessionStore.finalizeLoginFromWebView(
            captured = captured,
            allowLowConfidenceSessionCookies = false,
        )
        if (finalization.session.loginPhase == LoginPhaseState.READY) {
            return finalization.session
        }

        return sessionStore.refreshBootstrapIfNeeded()
    }

    suspend fun completeJsLogin(webView: WebView, identifier: String): SessionState =
        withContext(Dispatchers.Main) {
            FireCapturedLoginState(
                currentUrl = webView.url ?: "$loginBaseUrl/",
                username = identifier,
                csrfToken = null,
                homeHtml = null,
                browserUserAgent = webView.settings.userAgentString?.takeIf { it.isNotBlank() },
                cookies = relevantCookies(webView.url ?: "$loginBaseUrl/"),
            )
        }.let { captured ->
            completeLogin(captured)
        }

    suspend fun logout(): SessionState {
        return sessionStore.logout()
    }

    suspend fun syncBrowserContext(webView: WebView): SessionState {
        return applyPlatformCookiesIfAuthoritative(relevantCookies(webView))
    }

    suspend fun primeCookies(
        webView: WebView,
        targetUrl: String = webView.url?.takeIf { it.isNotBlank() } ?: "$loginBaseUrl/",
    ) {
        val actions = sessionStore.webViewPrimingPayload(targetUrl)
        executeCookieActions(actions)
    }

    suspend fun sweepCookies(
        webView: WebView,
        names: List<String> = SESSION_COOKIE_NAMES,
        targetUrl: String = webView.url?.takeIf { it.isNotBlank() } ?: "$loginBaseUrl/",
    ): List<CookieSweepPlanState> = sweepCookies(
        names = names,
        targetUrl = targetUrl,
    )

    suspend fun sweepCookies(
        names: List<String> = SESSION_COOKIE_NAMES,
        targetUrl: String = "$loginBaseUrl/",
    ): List<CookieSweepPlanState> {
        val cookieInfos = webViewCookieInfos(targetUrl)
        return names.map { name ->
            sessionStore.cookieSweepPlan(
                targetUrl = targetUrl,
                name = name,
                webViewCookies = cookieInfos,
            ).also { plan ->
                executeCookieActions(plan.actions)
                sessionStore.commitCookieSweepResult(
                    targetUrl = targetUrl,
                    name = name,
                    intent = plan.intent,
                    webViewCookies = webViewCookieInfos(targetUrl),
                )
            }
        }
    }

    suspend fun nuclearResetCookies(
        webView: WebView,
        targetUrl: String = webView.url?.takeIf { it.isNotBlank() } ?: "$loginBaseUrl/",
    ) = nuclearResetCookies(targetUrl)

    suspend fun nuclearResetCookies(
        targetUrl: String = "$loginBaseUrl/",
    ) {
        val plan = sessionStore.cookieNuclearResetPlan(
            targetUrl = targetUrl,
            webViewCookies = webViewCookieInfos(targetUrl),
        )
        executeCookieActions(plan.actions)
        val committedCookies = webViewCookieInfos(targetUrl)
        for (name in SESSION_COOKIE_NAMES) {
            sessionStore.commitCookieSweepResult(
                targetUrl = targetUrl,
                name = name,
                intent = uniffi.fire_uniffi_session.CookieSweepIntentState.ENSURE_UNIQUE,
                webViewCookies = committedCookies,
            )
        }
    }

    suspend fun webViewCookieInfos(targetUrl: String? = "$loginBaseUrl/"): List<WebViewCookieInfoState> =
        withContext(Dispatchers.Main) {
            val cookieManager = CookieManager.getInstance()
            relevantCookieUrls(targetUrl).flatMap { url ->
                FireWebViewCookieActionSupport.cookieInfos(cookieManager, url)
            }.distinctBy { "${it.name}\u0000${it.value}\u0000${it.domain}\u0000${it.path}" }
        }

    suspend fun executeCookieActions(actions: List<WebViewCookieActionState>) {
        if (actions.isEmpty()) {
            return
        }
        withContext(Dispatchers.Main) {
            val cookieManager = CookieManager.getInstance()
            for (action in actions) {
                when (action) {
                    is WebViewCookieActionState.SetRaw -> {
                        cookieManager.setCookieSuspend(action.url, action.setCookie)
                    }
                    is WebViewCookieActionState.DeleteExact -> {
                        cookieManager.setCookieSuspend(
                            action.url,
                            FireWebViewCookieActionSupport.expiredCookieHeader(
                                name = action.name,
                                domain = action.domain,
                                path = action.path,
                            ),
                        )
                    }
                    is WebViewCookieActionState.DeleteByName -> {
                        FireWebViewCookieActionSupport.deleteByNameHeaders(
                            url = action.url,
                            name = action.name,
                        ).forEach { header ->
                            cookieManager.setCookieSuspend(action.url, header)
                        }
                    }
                }
            }
            cookieManager.flush()
        }
    }

    suspend fun probeLoginSyncReadiness(webView: WebView): FireLoginSyncReadiness {
        val captured = captureLoginState(webView)
        return loginSyncReadiness(captured)
    }

    suspend fun captureLoginState(webView: WebView): FireCapturedLoginState = withContext(Dispatchers.Main) {
        val currentUrl = webView.url ?: loginBaseUrl
        val usernameJson = webView.evaluateJavascriptSuspend(FireLoginScripts.readCurrentUsername)
        val csrfJson = webView.evaluateJavascriptSuspend(FireLoginScripts.readCsrfToken)
        val preloadedJson = webView.evaluateJavascriptSuspend(FireLoginScripts.readPreloadedData)

        val preloadedHtml = preloadedJson.decodeJsonStringOrNull()
        val resolvedUsername = usernameJson.decodeJsonStringOrNull()
            ?: FireBootstrapHtmlMetadataParser.currentUsername(preloadedHtml)
        val resolvedCsrfToken = csrfJson.decodeJsonStringOrNull()
            ?: FireBootstrapHtmlMetadataParser.csrfToken(preloadedHtml)

        FireCapturedLoginState(
            currentUrl = currentUrl,
            username = resolvedUsername,
            csrfToken = resolvedCsrfToken,
            homeHtml = preloadedHtml,
            browserUserAgent = webView.settings.userAgentString?.takeIf { it.isNotBlank() },
            cookies = relevantCookies(currentUrl),
        )
    }

    private suspend fun relevantCookies(webView: WebView): List<PlatformCookieState> = withContext(Dispatchers.Main) {
        relevantCookies(webView.url)
    }

    private fun relevantCookies(currentUrl: String?): List<PlatformCookieState> {
        val merged = LinkedHashMap<String, PlatformCookieState>()
        val cookieManager = CookieManager.getInstance()
        for (url in relevantCookieUrls(currentUrl)) {
            FireWebViewCookieActionSupport
                .platformCookies(cookieManager, url)
                .forEach { cookie ->
                    merged.putIfAbsent(cookie.variantKey(), cookie)
                }
        }
        return merged.values.toList()
    }

    private fun relevantCookieUrls(currentUrl: String?): LinkedHashSet<String> {
        return linkedSetOf<String>().also { urls ->
            currentUrl?.takeIf { it.isNotBlank() }?.let(urls::add)
            urls.add(loginBaseUrl)
            urls.add("$loginBaseUrl/")
        }
    }

    private suspend fun applyPlatformCookiesIfAuthoritative(
        cookies: List<PlatformCookieState>,
    ): SessionState {
        if (!containsActiveAuthCookies(cookies)) {
            return sessionStore.snapshot()
        }
        return sessionStore.applyPlatformCookies(cookies)
    }

    private fun loginSyncReadiness(captured: FireCapturedLoginState): FireLoginSyncReadiness {
        return loginSyncReadiness(
            username = captured.username,
            cookies = captured.cookies,
            preferredBootstrapScore = FireBootstrapHtmlHeuristics.score(captured.homeHtml),
        )
    }

    private fun loginSyncReadiness(
        username: String?,
        cookies: List<PlatformCookieState>,
        preferredBootstrapScore: Int,
    ): FireLoginSyncReadiness {
        val normalizedUsername = username?.trim()?.takeIf { it.isNotEmpty() }
        val hasAuthCookies = containsActiveAuthCookies(cookies)
        val hasBootstrapHtml =
            preferredBootstrapScore >= FireBootstrapHtmlHeuristics.REUSABLE_LOGIN_BOOTSTRAP_SCORE_THRESHOLD
        return FireLoginSyncReadiness(
            isReady = normalizedUsername != null && hasAuthCookies && hasBootstrapHtml,
            username = normalizedUsername,
            hasAuthCookies = hasAuthCookies,
            hasBootstrapHtml = hasBootstrapHtml,
            preferredBootstrapScore = preferredBootstrapScore,
        )
    }

    private suspend fun WebView.evaluateJavascriptSuspend(script: String): String =
        suspendCancellableCoroutine { continuation ->
            evaluateJavascript(script) { value ->
                continuation.resume(value ?: "null")
            }
        }

    private fun String.decodeJsonStringOrNull(): String? {
        if (this == "null") {
            return null
        }

        return runCatching {
            JSONObject("""{"value":$this}""")
                .optString("value")
                .trim()
                .takeIf { it.isNotEmpty() }
        }.getOrNull()
    }

    companion object {
        private val SESSION_COOKIE_NAMES = listOf("_t", "_forum_session", "cf_clearance", "_cfuvid")

        fun containsActiveAuthCookies(cookies: List<PlatformCookieState>): Boolean {
            val nowUnixMs = System.currentTimeMillis()
            val activeCookies = cookies.filter { cookie ->
                val value = cookie.value.trim()
                value.isNotEmpty() && (cookie.expiresAtUnixMs?.let { it > nowUnixMs } ?: true)
            }
            return activeCookies.any { it.name == "_t" } &&
                activeCookies.any { it.name == "_forum_session" }
        }
    }
}

internal object FireWebViewCookieActionSupport {
    fun cookieInfos(cookieManager: CookieManager, url: String): List<WebViewCookieInfoState> {
        return cookieInfosFromHeadersOrFallback(
            cookieInfoHeaders = cookieInfoHeaders(cookieManager, url),
            cookieHeader = cookieManager.getCookie(url),
        )
    }

    fun cookieInfoHeaders(cookieManager: CookieManager, url: String): List<String> {
        if (!WebViewFeature.isFeatureSupported(WebViewFeature.GET_COOKIE_INFO)) {
            return emptyList()
        }
        return runCatching {
            CookieManagerCompat.getCookieInfo(cookieManager, url)
        }.getOrDefault(emptyList())
    }

    fun platformCookies(cookieManager: CookieManager, url: String): List<PlatformCookieState> {
        return cookieInfos(cookieManager, url).map { cookie ->
            PlatformCookieState(
                name = cookie.name,
                value = cookie.value,
                domain = cookie.domain,
                path = cookie.path,
                expiresAtUnixMs = cookie.expiresAtUnixMs,
                sameSite = platformSameSite(cookie.sameSite),
            )
        }
    }

    fun parseCookieInfoHeaders(headers: List<String>): List<WebViewCookieInfoState> =
        headers.mapNotNull(::parseCookieInfoHeader)

    fun cookieInfosFromHeadersOrFallback(
        cookieInfoHeaders: List<String>,
        cookieHeader: String?,
    ): List<WebViewCookieInfoState> {
        val richCookies = parseCookieInfoHeaders(cookieInfoHeaders)
        return richCookies.ifEmpty { parseCookieHeader(cookieHeader) }
    }

    fun parseCookieHeader(header: String?): List<WebViewCookieInfoState> {
        return cookiePairs(header).map { (name, value) ->
            WebViewCookieInfoState(
                name = name,
                value = value,
                domain = null,
                path = null,
                hostOnly = null,
                secure = null,
                httpOnly = null,
                sameSite = if (name == "cf_clearance") CookieSameSiteState.NONE else null,
                expiresAtUnixMs = null,
            )
        }
    }

    fun expiredCookieHeader(name: String, domain: String?, path: String): String {
        return buildString {
            append(name)
            append("=; Max-Age=0; Expires=Thu, 01 Jan 1970 00:00:00 GMT")
            append("; Path=")
            append(path.ifBlank { "/" })
            if (!domain.isNullOrBlank()) {
                append("; Domain=")
                append(domain.trim())
            }
        }
    }

    fun setCookieHeader(cookie: WebViewCookieInfoState): String {
        return buildString {
            val domain = cookie.domain?.trim()?.takeIf { it.isNotBlank() }
            append(cookie.name)
            append("=")
            append(cookie.value)
            append("; Path=")
            append(cookie.path?.takeIf { it.isNotBlank() } ?: "/")
            if (domain != null) {
                append("; Domain=")
                append(domain)
            }
            if (cookie.secure == true) {
                append("; Secure")
            }
            if (cookie.httpOnly == true) {
                append("; HttpOnly")
            }
            when (cookie.sameSite) {
                CookieSameSiteState.LAX -> append("; SameSite=Lax")
                CookieSameSiteState.STRICT -> append("; SameSite=Strict")
                CookieSameSiteState.NONE -> append("; SameSite=None")
                CookieSameSiteState.UNSPECIFIED, null -> Unit
            }
            cookie.expiresAtUnixMs?.let { expiresAt ->
                append("; Expires=")
                append(
                    DateTimeFormatter.RFC_1123_DATE_TIME.format(
                        Instant.ofEpochMilli(expiresAt).atZone(ZoneOffset.UTC),
                    ),
                )
            }
        }
    }

    fun deleteByNameHeaders(url: String, name: String): List<String> {
        val domains = linkedSetOf<String?>()
        domains.add(null)
        runCatching { URI(url).host }
            .getOrNull()
            ?.trim()
            ?.lowercase()
            ?.takeIf { it.isNotEmpty() }
            ?.let { host ->
                domains.add(host)
                domains.add(".$host")
                if (host == "linux.do" || host.endsWith(".linux.do")) {
                    domains.add(".linux.do")
                }
            }
        return domains.map { domain ->
            expiredCookieHeader(name = name, domain = domain, path = "/")
        }
    }

    private fun parseCookieInfoHeader(header: String): WebViewCookieInfoState? {
        val segments = header.split(";").map { it.trim() }.filter { it.isNotEmpty() }
        val first = segments.firstOrNull() ?: return null
        val separator = first.indexOf('=')
        if (separator <= 0) {
            return null
        }
        val name = first.substring(0, separator).trim()
        val value = first.substring(separator + 1).trim()
        if (name.isEmpty() || value.isEmpty()) {
            return null
        }

        var domain: String? = null
        var path: String? = null
        var secure: Boolean? = null
        var httpOnly: Boolean? = null
        var sameSite: CookieSameSiteState? = null
        var expiresAtUnixMs: Long? = null
        for (segment in segments.drop(1)) {
            val attrSeparator = segment.indexOf('=')
            val attrName = if (attrSeparator > 0) {
                segment.substring(0, attrSeparator).trim().lowercase()
            } else {
                segment.trim().lowercase()
            }
            val attrValue = if (attrSeparator > 0) {
                segment.substring(attrSeparator + 1).trim()
            } else {
                ""
            }
            when (attrName) {
                "domain" -> domain = attrValue.takeIf { it.isNotBlank() }
                "path" -> path = attrValue.takeIf { it.isNotBlank() }
                "secure" -> secure = true
                "httponly" -> httpOnly = true
                "samesite" -> sameSite = sameSite(attrValue)
                "expires" -> expiresAtUnixMs = parseExpiresUnixMs(attrValue)
                "max-age" -> expiresAtUnixMs = parseMaxAgeUnixMs(attrValue)
            }
        }

        return WebViewCookieInfoState(
            name = name,
            value = value,
            domain = domain,
            path = path,
            hostOnly = if (domain == null) true else false,
            secure = secure,
            httpOnly = httpOnly,
            sameSite = sameSite ?: if (name == "cf_clearance") CookieSameSiteState.NONE else null,
            expiresAtUnixMs = expiresAtUnixMs,
        )
    }

    private fun sameSite(value: String): CookieSameSiteState =
        when (value.trim().lowercase()) {
            "lax" -> CookieSameSiteState.LAX
            "strict" -> CookieSameSiteState.STRICT
            "none" -> CookieSameSiteState.NONE
            else -> CookieSameSiteState.UNSPECIFIED
        }

    private fun platformSameSite(value: CookieSameSiteState?): String? =
        when (value) {
            CookieSameSiteState.LAX -> "lax"
            CookieSameSiteState.STRICT -> "strict"
            CookieSameSiteState.NONE -> "none"
            CookieSameSiteState.UNSPECIFIED, null -> null
        }

    private fun parseExpiresUnixMs(value: String): Long? {
        return try {
            ZonedDateTime.parse(value, DateTimeFormatter.RFC_1123_DATE_TIME)
                .toInstant()
                .toEpochMilli()
        } catch (_: DateTimeParseException) {
            null
        }
    }

    private fun parseMaxAgeUnixMs(value: String): Long? {
        val seconds = value.toLongOrNull() ?: return null
        return System.currentTimeMillis() + seconds * 1_000
    }

    private fun cookiePairs(header: String?): List<Pair<String, String>> {
        return header.orEmpty()
            .split(";")
            .mapNotNull { segment ->
                val trimmed = segment.trim()
                if (trimmed.isEmpty()) {
                    return@mapNotNull null
                }
                val separator = trimmed.indexOf('=')
                if (separator <= 0) {
                    return@mapNotNull null
                }
                val name = trimmed.substring(0, separator).trim()
                val value = trimmed.substring(separator + 1).trim()
                if (name.isEmpty() || value.isEmpty()) {
                    return@mapNotNull null
                }
                name to value
            }
    }
}

private fun PlatformCookieState.variantKey(): String =
    listOf(
        name,
        value,
        domain.orEmpty(),
        path.orEmpty(),
    ).joinToString(separator = "\u0000")

private suspend fun CookieManager.setCookieSuspend(url: String, value: String): Boolean =
    suspendCancellableCoroutine { continuation ->
        setCookie(url, value) { accepted ->
            continuation.resume(accepted)
        }
    }

private object FireBootstrapHtmlHeuristics {
    const val REUSABLE_LOGIN_BOOTSTRAP_SCORE_THRESHOLD = 8

    fun score(html: String?): Int {
        if (html.isNullOrBlank()) {
            return 0
        }

        val normalized = html.lowercase()
        var score = 0
        if (
            normalized.contains("id=\"data-discourse-setup\"") ||
            normalized.contains("id='data-discourse-setup'") ||
            normalized.contains("data-preloaded")
        ) {
            score += 8
        }
        if (
            normalized.contains("meta name=\"shared_session_key\"") ||
            normalized.contains("meta name='shared_session_key'")
        ) {
            score += 4
        }
        if (
            normalized.contains("meta name=\"current-username\"") ||
            normalized.contains("meta name='current-username'")
        ) {
            score += 2
        }
        if (
            normalized.contains("meta name=\"csrf-token\"") ||
            normalized.contains("meta name='csrf-token'")
        ) {
            score += 1
        }
        return score
    }
}

private object FireBootstrapHtmlMetadataParser {
    fun currentUsername(html: String?): String? = metaContent("current-username", html)

    fun csrfToken(html: String?): String? = metaContent("csrf-token", html)

    private fun metaContent(name: String, html: String?): String? {
        if (html.isNullOrBlank()) {
            return null
        }

        val escapedName = Regex.escape(name)
        val patterns = listOf(
            """<meta\b[^>]*\bname\s*=\s*["']$escapedName["'][^>]*\bcontent\s*=\s*["']([^"']+)["'][^>]*>""",
            """<meta\b[^>]*\bcontent\s*=\s*["']([^"']+)["'][^>]*\bname\s*=\s*["']$escapedName["'][^>]*>""",
        )
        return patterns.firstNotNullOfOrNull { pattern ->
            Regex(pattern, RegexOption.IGNORE_CASE)
                .find(html)
                ?.groupValues
                ?.getOrNull(1)
                ?.trim()
                ?.takeIf { it.isNotEmpty() }
        }
    }
}
