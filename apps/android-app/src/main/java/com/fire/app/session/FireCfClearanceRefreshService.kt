package com.fire.app.session

import android.annotation.SuppressLint
import android.content.Context
import android.os.Handler
import android.os.Looper
import android.util.Log
import android.webkit.CookieManager
import android.webkit.JavascriptInterface
import android.webkit.WebView
import android.webkit.WebViewClient
import com.fire.app.FireApplication
import com.fire.app.ui.webview.FireWebViewSupport
import java.io.BufferedReader
import java.io.InputStreamReader
import java.io.OutputStreamWriter
import java.net.HttpURLConnection
import java.net.URL
import java.util.UUID
import java.util.concurrent.atomic.AtomicBoolean
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import org.json.JSONObject
import uniffi.fire_uniffi_session.PlatformCookieState
import uniffi.fire_uniffi_session.SessionState

/**
 * Hidden Turnstile runtime that keeps cf_clearance fresh while logged in.
 *
 * Mirrors iOS FireCfClearanceRefreshService:
 * - only runs when scene is active, login is confirmed, and sitekey exists
 * - intercepts /cdn-cgi/challenge-platform/.../rc/ and completes it natively
 * - writes accepted clearance through the trusted challenge-completion path
 * - pauses while a manual challenge WebView is open
 */
class FireCfClearanceRefreshService private constructor(
    context: Context,
) {
    private val appContext = context.applicationContext
    private val mainHandler = Handler(Looper.getMainLooper())
    private val scope = FireApplication.applicationScope()

    @Volatile private var sessionStore: FireSessionStore? = null
    @Volatile private var session: SessionState? = null
    @Volatile private var loginStateConfirmed = false
    @Volatile private var sceneActive = false
    @Volatile private var manualChallengePauseCount = 0
    @Volatile private var generation = 0L
    @Volatile private var consecutiveFailures = 0
    @Volatile private var activeSitekey: String? = null
    @Volatile private var activeBaseUrl: String? = null
    @Volatile private var activeRuntimeToken: String? = null
    @Volatile private var isCallingRc = false

    private var webView: WebView? = null
    private var startupJob: Job? = null
    private var retryJob: Job? = null
    private var initialTimeoutJob: Job? = null
    private val started = AtomicBoolean(false)

    fun bind(sessionStore: FireSessionStore) {
        this.sessionStore = sessionStore
    }

    fun updateSession(session: SessionState) {
        this.session = session
        if (!session.readiness.hasCurrentUser) {
            loginStateConfirmed = false
        }
        reconfigure(reason = "session_update")
    }

    fun setSceneActive(active: Boolean) {
        sceneActive = active
        reconfigure(reason = if (active) "scene_active" else "scene_inactive")
    }

    fun setLoginStateConfirmed(confirmed: Boolean) {
        loginStateConfirmed = confirmed
        reconfigure(reason = if (confirmed) "login_state_confirmed" else "login_state_unconfirmed")
    }

    fun beginManualChallenge(reason: String) {
        manualChallengePauseCount += 1
        stopRuntime(reason)
    }

    fun endManualChallenge(reason: String) {
        if (manualChallengePauseCount > 0) {
            manualChallengePauseCount -= 1
        }
        if (manualChallengePauseCount == 0) {
            reconfigure(reason)
        }
    }

    fun noteTurnstileSitekey(sitekey: String?) {
        val normalized = sitekey?.trim().orEmpty()
        if (normalized.isEmpty()) return
        val current = session?.bootstrap?.turnstileSitekey?.trim().orEmpty()
        if (current.isNotEmpty()) return
        // Session bootstrap is owned by Rust; keep a local active key so the
        // runtime can start even when bootstrap lags the challenge body.
        activeSitekey = normalized
        reconfigure(reason = "sitekey_from_challenge")
    }

    private fun reconfigure(reason: String) {
        if (shouldRun()) {
            startRuntimeIfNeeded(reason)
        } else {
            stopRuntime(reason)
        }
    }

    private fun shouldRun(): Boolean {
        val snapshot = session ?: return false
        val sitekey = effectiveSitekey(snapshot)
        return manualChallengePauseCount == 0 &&
            sceneActive &&
            loginStateConfirmed &&
            snapshot.readiness.canReadAuthenticatedApi &&
            snapshot.readiness.hasCurrentUser &&
            snapshot.readiness.hasCloudflareClearance &&
            !sitekey.isNullOrBlank()
    }

    private fun effectiveSitekey(snapshot: SessionState): String? {
        val fromBootstrap = snapshot.bootstrap.turnstileSitekey?.trim().orEmpty()
        if (fromBootstrap.isNotEmpty()) return fromBootstrap
        return activeSitekey?.trim()?.takeIf { it.isNotEmpty() }
    }

    private fun startRuntimeIfNeeded(reason: String) {
        if (!shouldRun()) return
        if (startupJob?.isActive == true || retryJob?.isActive == true || webView != null) return
        val snapshot = session ?: return
        val sitekey = effectiveSitekey(snapshot) ?: return
        val runtimeToken = UUID.randomUUID().toString()
        val gen = advanceGeneration()
        activeSitekey = sitekey
        activeBaseUrl = snapshot.bootstrap.baseUrl
        activeRuntimeToken = runtimeToken
        consecutiveFailures = 0
        Log.i(TAG, "starting clearance refresh reason=$reason")
        startupJob = scope.launch(Dispatchers.Main) {
            try {
                bootstrapRuntime(sitekey = sitekey, runtimeToken = runtimeToken, generation = gen)
            } catch (error: Exception) {
                Log.w(TAG, "startup failed: ${error.message}")
                handleFailure("startup_failed", gen, runtimeToken)
            } finally {
                startupJob = null
            }
        }
    }

    private fun stopRuntime(reason: String) {
        if (webView == null && startupJob == null && retryJob == null) return
        cancelRuntime(resetFailures = true)
        Log.i(TAG, "stopped clearance refresh reason=$reason")
    }

    private fun cancelRuntime(resetFailures: Boolean) {
        advanceGeneration()
        startupJob?.cancel()
        startupJob = null
        retryJob?.cancel()
        retryJob = null
        initialTimeoutJob?.cancel()
        initialTimeoutJob = null
        tearDownWebView()
        if (resetFailures) {
            consecutiveFailures = 0
        }
        isCallingRc = false
        started.set(false)
    }

    private fun advanceGeneration(): Long {
        generation += 1
        return generation
    }

    @SuppressLint("SetJavaScriptEnabled")
    private suspend fun bootstrapRuntime(
        sitekey: String,
        runtimeToken: String,
        generation: Long,
    ) {
        if (!isCurrent(generation, runtimeToken)) return
        val view = ensureWebView(runtimeToken)
        val html = turnstileHtml(sitekey = sitekey, runtimeToken = runtimeToken)
        val baseUrl = (session?.bootstrap?.baseUrl ?: "https://linux.do").let {
            if (it.endsWith("/")) it else "$it/"
        }
        withContext(Dispatchers.Main) {
            view.loadDataWithBaseURL(baseUrl, html, "text/html", "UTF-8", null)
        }
        scheduleInitialTimeout(generation, runtimeToken)
    }

    @SuppressLint("SetJavaScriptEnabled")
    private fun ensureWebView(runtimeToken: String): WebView {
        webView?.let { return it }
        val view = WebView(appContext)
        FireWebViewSupport.configureBrowserLikeWebView(view)
        view.addJavascriptInterface(RcBridge(runtimeToken), JS_BRIDGE)
        view.webViewClient = object : WebViewClient() {
            override fun onPageFinished(view: WebView?, url: String?) {
                super.onPageFinished(view, url)
                injectFetchInterceptor(runtimeToken)
            }
        }
        // Keep off-screen; never attach to a window.
        view.layout(0, 0, 1, 1)
        webView = view
        started.set(true)
        return view
    }

    private fun tearDownWebView() {
        val view = webView ?: return
        webView = null
        mainHandler.post {
            runCatching {
                view.stopLoading()
                view.destroy()
            }
        }
    }

    private fun injectFetchInterceptor(runtimeToken: String) {
        val tokenLiteral = JSONObject.quote(runtimeToken)
        val script = """
            (function() {
              if (window.__fireCfFetchInstalled) { return; }
              window.__fireCfFetchInstalled = true;
              window.__fireCfRuntimeToken = $tokenLiteral;
              var originalFetch = window.fetch ? window.fetch.bind(window) : null;
              var pendingRc = Object.create(null);
              var rcId = 0;
              function parseBody(body) {
                if (!body) return {};
                if (typeof body === 'string') {
                  try { return JSON.parse(body); } catch (e) { return {}; }
                }
                return {};
              }
              window._resolveRc = function(id, status, body) {
                var resolve = pendingRc[id];
                if (!resolve) return;
                delete pendingRc[id];
                resolve(new Response(body || '{}', {
                  status: status,
                  headers: { 'Content-Type': 'application/json' }
                }));
              };
              if (!originalFetch) return;
              window.fetch = function(input, init) {
                var requestURL = typeof input === 'string' ? input : ((input && input.url) || '');
                if (requestURL.indexOf('/cdn-cgi/challenge-platform/') !== -1 &&
                    requestURL.indexOf('/rc/') !== -1) {
                  var id = 'rc_' + (++rcId);
                  var challengeID = '';
                  var parts = requestURL.split('/rc/');
                  if (parts.length > 1) {
                    challengeID = parts[1].split(/[?#]/)[0];
                  }
                  var parsedBody = parseBody(init && init.body);
                  if (window.FireCfRefresh && window.FireCfRefresh.onRc) {
                    window.FireCfRefresh.onRc(
                      id,
                      challengeID,
                      parsedBody.secondaryToken || '',
                      parsedBody.sitekey || '',
                      window.__fireCfRuntimeToken || ''
                    );
                  }
                  return new Promise(function(resolve) { pendingRc[id] = resolve; });
                }
                return originalFetch(input, init);
              };
            })();
        """.trimIndent()
        webView?.evaluateJavascript(script, null)
    }

    private fun scheduleInitialTimeout(generation: Long, runtimeToken: String) {
        initialTimeoutJob?.cancel()
        initialTimeoutJob = scope.launch {
            delay(INITIAL_SOLVE_TIMEOUT_MS)
            if (!isCurrent(generation, runtimeToken)) return@launch
            handleFailure("initial_timeout", generation, runtimeToken)
        }
    }

    private fun handleFailure(reason: String, generation: Long, runtimeToken: String) {
        if (!isCurrent(generation, runtimeToken)) return
        consecutiveFailures += 1
        Log.w(TAG, "refresh failure reason=$reason count=$consecutiveFailures")
        if (consecutiveFailures >= MAX_FAILURES) {
            stopRuntime("max_failures")
            return
        }
        cancelRuntime(resetFailures = false)
        val expectedGeneration = this.generation
        retryJob = scope.launch {
            delay(RETRY_DELAY_MS)
            if (this@FireCfClearanceRefreshService.generation != expectedGeneration) return@launch
            startRuntimeIfNeeded("retry_after_$reason")
        }
    }

    private fun isCurrent(generation: Long, runtimeToken: String): Boolean {
        return this.generation == generation && activeRuntimeToken == runtimeToken
    }

    private suspend fun handleRcIntercepted(
        id: String,
        challengeId: String,
        secondaryToken: String,
        sitekey: String,
        runtimeToken: String,
    ) {
        val generation = this.generation
        if (!isCurrent(generation, runtimeToken)) return
        initialTimeoutJob?.cancel()
        if (isCallingRc) {
            resolveRc(id, 503, "{}")
            return
        }
        val snapshot = session ?: run {
            resolveRc(id, 400, "{}")
            return
        }
        val effectiveSitekey = sitekey.trim().ifEmpty { effectiveSitekey(snapshot) }.orEmpty()
        if (challengeId.isBlank() || effectiveSitekey.isBlank()) {
            resolveRc(id, 400, "{}")
            return
        }
        val baseUrl = (snapshot.bootstrap.baseUrl.ifBlank { "https://linux.do" }).trimEnd('/')
        val rcUrl = "$baseUrl/cdn-cgi/challenge-platform/h/g/rc/$challengeId"
        isCallingRc = true
        try {
            val response = withContext(Dispatchers.IO) {
                postRc(rcUrl, effectiveSitekey, secondaryToken, baseUrl)
            }
            if (!isCurrent(generation, runtimeToken)) return
            resolveRc(id, response.first, response.second)
            delay(COOKIE_PROPAGATION_DELAY_MS)
            if (!isCurrent(generation, runtimeToken)) return
            val store = sessionStore ?: return
            val previous = snapshot.cookies.cfClearance
            val cookies = collectPlatformCookies()
            val fresh = cloudflareClearanceValue(cookies, previous)
                ?: throw IllegalStateException("missing cf_clearance after rc")
            val filtered = FireCloudflareChallengeActivity.challengeResultCookies(cookies, fresh)
            val refreshed = store.completeCloudflareChallenge(
                cookies = filtered,
                freshCfClearance = fresh,
                browserUserAgent = withContext(Dispatchers.Main) {
                    webView?.settings?.userAgentString
                },
            )
            if (!isCurrent(generation, runtimeToken)) return
            consecutiveFailures = 0
            session = refreshed
            Log.i(TAG, "clearance refresh succeeded")
        } catch (error: Exception) {
            Log.w(TAG, "rc call failed: ${error.message}")
            resolveRc(id, 500, "{}")
            handleFailure("rc_failed", generation, runtimeToken)
        } finally {
            if (isCurrent(generation, runtimeToken)) {
                isCallingRc = false
            }
        }
    }

    private fun collectPlatformCookies(): List<PlatformCookieState> {
        val cookieManager = CookieManager.getInstance()
        val urls = listOf("https://linux.do/", "https://linux.do")
        val merged = LinkedHashMap<String, PlatformCookieState>()
        urls.forEach { url ->
            FireWebViewCookieActionSupport.platformCookies(cookieManager, url)
                .filter { it.value.isNotBlank() }
                .forEach { cookie ->
                    merged.putIfAbsent(
                        listOf(cookie.name, cookie.value, cookie.domain.orEmpty(), cookie.path.orEmpty())
                            .joinToString("\u0000"),
                        cookie,
                    )
                }
        }
        return merged.values.toList()
    }

    private fun resolveRc(id: String, status: Int, body: String) {
        val idLiteral = JSONObject.quote(id)
        val bodyLiteral = JSONObject.quote(body)
        val script = "window._resolveRc && window._resolveRc($idLiteral, $status, $bodyLiteral);"
        mainHandler.post {
            webView?.evaluateJavascript(script, null)
        }
    }

    private fun postRc(
        rcUrl: String,
        sitekey: String,
        secondaryToken: String,
        origin: String,
    ): Pair<Int, String> {
        val connection = (URL(rcUrl).openConnection() as HttpURLConnection).apply {
            requestMethod = "POST"
            connectTimeout = 30_000
            readTimeout = 30_000
            doOutput = true
            setRequestProperty("Content-Type", "application/json")
            setRequestProperty("Origin", origin)
            setRequestProperty("Referer", if (origin.endsWith("/")) origin else "$origin/")
            // Attach browser cookies so CF sees the same jar as WebView.
            val cookieHeader = CookieManager.getInstance().getCookie(origin)
            if (!cookieHeader.isNullOrBlank()) {
                setRequestProperty("Cookie", cookieHeader)
            }
            instanceFollowRedirects = false
        }
        val payload = JSONObject().apply {
            put("sitekey", sitekey)
            if (secondaryToken.isNotBlank()) {
                put("secondaryToken", secondaryToken)
            }
        }
        OutputStreamWriter(connection.outputStream, Charsets.UTF_8).use { writer ->
            writer.write(payload.toString())
        }
        val code = connection.responseCode
        val stream = if (code in 200..299) connection.inputStream else connection.errorStream
        val body = stream?.use { input ->
            BufferedReader(InputStreamReader(input, Charsets.UTF_8)).readText()
        } ?: "{}"
        // Mirror Set-Cookie into WebView store.
        connection.headerFields
            ?.filterKeys { it.equals("Set-Cookie", ignoreCase = true) }
            ?.values
            ?.flatten()
            ?.forEach { header ->
                CookieManager.getInstance().setCookie(origin, header)
            }
        CookieManager.getInstance().flush()
        connection.disconnect()
        return code to body
    }

    private inner class RcBridge(
        private val expectedRuntimeToken: String,
    ) {
        @JavascriptInterface
        fun onRc(
            id: String,
            challengeId: String,
            secondaryToken: String,
            sitekey: String,
            runtimeToken: String,
        ) {
            if (runtimeToken != expectedRuntimeToken && runtimeToken != activeRuntimeToken) {
                return
            }
            scope.launch {
                handleRcIntercepted(
                    id = id,
                    challengeId = challengeId,
                    secondaryToken = secondaryToken,
                    sitekey = sitekey,
                    runtimeToken = runtimeToken.ifBlank { expectedRuntimeToken },
                )
            }
        }
    }

    companion object {
        private const val TAG = "FireCfRefresh"
        private const val JS_BRIDGE = "FireCfRefresh"
        private const val INITIAL_SOLVE_TIMEOUT_MS = 30_000L
        private const val RETRY_DELAY_MS = 2_000L
        private const val COOKIE_PROPAGATION_DELAY_MS = 500L
        private const val MAX_FAILURES = 3

        @Volatile
        private var instance: FireCfClearanceRefreshService? = null

        fun get(context: Context): FireCfClearanceRefreshService {
            return instance ?: synchronized(this) {
                instance ?: FireCfClearanceRefreshService(context.applicationContext).also {
                    instance = it
                }
            }
        }

        fun shouldAutoRefresh(
            session: SessionState,
            sceneActive: Boolean,
            loginStateConfirmed: Boolean,
        ): Boolean {
            return sceneActive &&
                loginStateConfirmed &&
                session.readiness.canReadAuthenticatedApi &&
                session.readiness.hasCurrentUser &&
                session.readiness.hasCloudflareClearance &&
                !(session.bootstrap.turnstileSitekey.isNullOrBlank())
        }

        fun cloudflareClearanceValue(
            cookies: List<PlatformCookieState>,
            previousValue: String?,
        ): String? {
            val values = cookies
                .filter { it.name.equals("cf_clearance", ignoreCase = true) }
                .map { it.value.trim() }
                .filter { it.isNotEmpty() }
            if (values.isEmpty()) return null
            val previous = previousValue?.trim().orEmpty()
            if (previous.isNotEmpty()) {
                values.firstOrNull { it != previous }?.let { return it }
            }
            return values.firstOrNull()
        }

        fun turnstileHtml(sitekey: String, runtimeToken: String): String {
            val sitekeyLiteral = JSONObject.quote(sitekey)
            val runtimeTokenLiteral = JSONObject.quote(runtimeToken)
            return """
                <!DOCTYPE html>
                <html>
                <head>
                  <meta charset="utf-8">
                  <meta name="viewport" content="width=device-width, initial-scale=1">
                  <style>
                    html, body { margin:0; padding:0; background:transparent; width:1px; height:1px; overflow:hidden; }
                    #fire-turnstile { width:1px; height:1px; overflow:hidden; }
                  </style>
                  <script>
                    window.__fireCfRuntimeToken = $runtimeTokenLiteral;
                    function fireReportTurnstileError(error) {
                      try {
                        if (window.FireCfRefresh && window.FireCfRefresh.onRc) {
                          // Reuse bridge for observability only; empty challenge id is ignored.
                          console.log('turnstile_error', String(error || ''));
                        }
                      } catch (e) {}
                    }
                  </script>
                  <script src="https://challenges.cloudflare.com/turnstile/v0/api.js?onload=fireTurnstileOnLoad" async defer></script>
                </head>
                <body>
                  <div id="fire-turnstile"></div>
                  <script>
                    function fireTurnstileOnLoad() {
                      try {
                        turnstile.render('#fire-turnstile', {
                          sitekey: $sitekeyLiteral,
                          appearance: 'interaction-only',
                          'refresh-expired': 'auto',
                          'error-callback': fireReportTurnstileError
                        });
                      } catch (error) {
                        fireReportTurnstileError(error);
                      }
                    }
                  </script>
                </body>
                </html>
            """.trimIndent()
        }
    }
}
