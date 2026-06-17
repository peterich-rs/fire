package com.fire.app.session

import android.os.Bundle
import android.view.View
import android.webkit.CookieManager
import android.webkit.JavascriptInterface
import android.webkit.WebChromeClient
import android.webkit.WebResourceRequest
import android.webkit.WebResourceResponse
import android.webkit.WebView
import android.widget.ProgressBar
import android.widget.TextView
import androidx.activity.OnBackPressedCallback
import androidx.activity.ComponentActivity
import androidx.core.view.ViewCompat
import androidx.core.view.WindowInsetsCompat
import androidx.core.view.updatePadding
import androidx.lifecycle.lifecycleScope
import com.fire.app.R
import com.fire.app.ui.webview.FireWebViewSupport
import kotlin.coroutines.resume
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.coroutines.withContext
import uniffi.fire_uniffi_session.CloudflareChallengeResultState
import uniffi.fire_uniffi_session.PlatformCookieState
import uniffi.fire_uniffi_session.WebViewCookieInfoState

class FireCloudflareChallengeActivity : ComponentActivity() {
    private lateinit var pendingToken: String
    private lateinit var targetUrl: String
    private lateinit var webView: WebView
    private lateinit var progressBar: ProgressBar
    private var baselineClearance: String? = null
    private var preservedClearanceCookies: List<WebViewCookieInfoState> = emptyList()
    private var completionPollingJob: Job? = null
    private var completionCheckInFlight = false
    private var finishedResult = false

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        pendingToken = intent.getStringExtra(EXTRA_PENDING_TOKEN).orEmpty()
        targetUrl = intent.getStringExtra(EXTRA_TARGET_URL).orEmpty()
        if (pendingToken.isBlank() || targetUrl.isBlank()) {
            finishWithResult(cancelledResult(userCancelled = false))
            return
        }

        setContentView(R.layout.activity_cloudflare_challenge)
        applySystemBarInsets()
        webView = findViewById(R.id.challenge_webview)
        progressBar = findViewById(R.id.challenge_progress)
        findViewById<TextView>(R.id.challenge_close).setOnClickListener {
            finishWithResult(cancelledResult(userCancelled = true))
        }

        val cookieManager = CookieManager.getInstance()
        val baselineCookies = collectRelevantCookies()
        baselineClearance = baselineCookies.firstOrNull { it.name == "cf_clearance" }?.value
        preservedClearanceCookies = FireWebViewCookieActionSupport
            .cookieInfos(cookieManager, targetUrl)
            .filter { it.name == "cf_clearance" && it.value.isNotBlank() }
        deleteCloudflareClearanceCookies(cookieManager)
        FireWebViewSupport.configureBrowserLikeWebView(webView)
        webView.addJavascriptInterface(ChallengeBridge(), "FireCfChallenge")
        webView.webViewClient = object : android.webkit.WebViewClient() {
            override fun onPageFinished(view: WebView, url: String?) {
                super.onPageFinished(view, url)
                injectChallengeSignalScript()
                maybeCompleteChallenge()
            }

            override fun doUpdateVisitedHistory(view: WebView, url: String?, isReload: Boolean) {
                super.doUpdateVisitedHistory(view, url, isReload)
                injectChallengeSignalScript()
                maybeCompleteChallenge()
            }

            override fun onLoadResource(view: WebView, url: String?) {
                super.onLoadResource(view, url)
                if (url?.contains(CHALLENGE_PLATFORM_PATH, ignoreCase = true) == true) {
                    maybeCompleteChallenge()
                }
            }

            override fun shouldInterceptRequest(
                view: WebView?,
                request: WebResourceRequest?,
            ): WebResourceResponse? {
                if (request?.url?.toString()?.contains(CHALLENGE_PLATFORM_PATH, ignoreCase = true) == true) {
                    view?.post { maybeCompleteChallenge() }
                }
                return super.shouldInterceptRequest(view, request)
            }

            override fun onPageCommitVisible(view: WebView, url: String?) {
                super.onPageCommitVisible(view, url)
                injectChallengeSignalScript()
                maybeCompleteChallenge()
            }

            override fun shouldOverrideUrlLoading(
                view: WebView,
                request: WebResourceRequest,
            ): Boolean {
                return false
            }
        }
        webView.webChromeClient = object : WebChromeClient() {
            override fun onProgressChanged(view: WebView?, newProgress: Int) {
                super.onProgressChanged(view, newProgress)
                progressBar.progress = newProgress
                progressBar.visibility = if (newProgress >= 100) View.GONE else View.VISIBLE
            }
        }
        onBackPressedDispatcher.addCallback(
            this,
            object : OnBackPressedCallback(true) {
                override fun handleOnBackPressed() {
                    finishWithResult(cancelledResult(userCancelled = true))
                }
            },
        )
        startCompletionPolling()
        webView.loadUrl(targetUrl)
    }

    override fun onDestroy() {
        completionPollingJob?.cancel()
        completionPollingJob = null
        if (::webView.isInitialized) {
            webView.destroy()
        }
        if (!finishedResult && isFinishing) {
            finishWithResult(cancelledResult(userCancelled = true))
        }
        super.onDestroy()
    }

    private fun maybeCompleteChallenge() {
        if (finishedResult || completionCheckInFlight) {
            return
        }
        completionCheckInFlight = true
        lifecycleScope.launch {
            try {
                val cookies = withContext(Dispatchers.Main) { collectRelevantCookies() }
                val newClearance = cookies
                    .firstOrNull { it.name == "cf_clearance" && it.value != baselineClearance }
                    ?.value
                if (newClearance.isNullOrBlank() || newClearance == baselineClearance) {
                    return@launch
                }
                val stillBlocked = runCatching { challengeStillPresent() }.getOrDefault(true)
                if (stillBlocked) {
                    return@launch
                }
                finishWithResult(
                    CloudflareChallengeResultState(
                        completed = true,
                        userCancelled = false,
                        freshCfClearance = newClearance,
                        cookies = challengeResultCookies(cookies, newClearance),
                        browserUserAgent = webView.settings.userAgentString,
                    ),
                )
            } finally {
                completionCheckInFlight = false
            }
        }
    }

    private fun startCompletionPolling() {
        completionPollingJob?.cancel()
        completionPollingJob = lifecycleScope.launch {
            while (isActive && !finishedResult) {
                delay(1_000)
                maybeCompleteChallenge()
            }
        }
    }

    private fun injectChallengeSignalScript() {
        if (finishedResult || !::webView.isInitialized) {
            return
        }
        webView.evaluateJavascript(
            """
            (function() {
              if (window.__fireCfChallengeMonitorInstalled) {
                return;
              }
              window.__fireCfChallengeMonitorInstalled = true;

              function signal() {
                try {
                  if (window.FireCfChallenge && window.FireCfChallenge.signal) {
                    window.FireCfChallenge.signal();
                  }
                } catch (error) {}
              }

              if (window.fetch) {
                var originalFetch = window.fetch.bind(window);
                window.fetch = function(input, init) {
                  var result = originalFetch(input, init);
                  try {
                    var url = typeof input === 'string' ? input : ((input && input.url) || '');
                    if (String(url).indexOf('/cdn-cgi/challenge-platform/') !== -1) {
                      Promise.resolve(result).then(signal, signal);
                    }
                  } catch (error) {}
                  return result;
                };
              }

              if (window.XMLHttpRequest && window.XMLHttpRequest.prototype) {
                var originalOpen = window.XMLHttpRequest.prototype.open;
                var originalSend = window.XMLHttpRequest.prototype.send;
                window.XMLHttpRequest.prototype.open = function(method, url) {
                  this.__fireCfChallengeUrl = url;
                  return originalOpen.apply(this, arguments);
                };
                window.XMLHttpRequest.prototype.send = function() {
                  try {
                    var url = String(this.__fireCfChallengeUrl || '');
                    if (url.indexOf('/cdn-cgi/challenge-platform/') !== -1) {
                      this.addEventListener('loadend', signal);
                    }
                  } catch (error) {}
                  return originalSend.apply(this, arguments);
                };
              }

              window.addEventListener('beforeunload', signal);
              window.addEventListener('pagehide', signal);
            })();
            """.trimIndent(),
            null,
        )
    }

    private suspend fun challengeStillPresent(): Boolean = withContext(Dispatchers.Main) {
        val result = webView.evaluateJavascriptSuspend(
            """
            (function() {
              try {
                var title = (document.title || '').toLowerCase();
                var html = ((document.documentElement && document.documentElement.outerHTML) || '')
                  .slice(0, 12000)
                  .toLowerCase();
                return html.indexOf('cf_chl_opt') !== -1 ||
                  (html.indexOf('challenge-platform') !== -1 && html.indexOf('cloudflare') !== -1) ||
                  title.indexOf('just a moment') !== -1 ||
                  (html.indexOf('just a moment') !== -1 &&
                    (html.indexOf('cloudflare') !== -1 || html.indexOf('cf-challenge') !== -1));
              } catch (error) {
                return true;
              }
            })();
            """.trimIndent(),
        )
        result == "true"
    }

    private fun collectRelevantCookies(): List<PlatformCookieState> {
        val cookieManager = CookieManager.getInstance()
        val urls = linkedSetOf(targetUrl, "https://linux.do", "https://linux.do/")
        val merged = LinkedHashMap<String, PlatformCookieState>()
        urls.forEach { url ->
            FireWebViewCookieActionSupport
                .platformCookies(cookieManager, url)
                .filter { it.value.isNotEmpty() && it.name in RELEVANT_COOKIE_NAMES }
                .forEach { cookie ->
                    merged.putIfAbsent(
                        listOf(
                            cookie.name,
                            cookie.value,
                            cookie.domain.orEmpty(),
                            cookie.path.orEmpty(),
                        ).joinToString(separator = "\u0000"),
                        cookie,
                    )
                }
        }
        return merged.values.toList()
    }

    private fun deleteCloudflareClearanceCookies(cookieManager: CookieManager) {
        val infos = FireWebViewCookieActionSupport
            .cookieInfos(cookieManager, targetUrl)
            .filter { it.name == "cf_clearance" }
        if (infos.isNotEmpty()) {
            infos.forEach { cookie ->
                cookieManager.setCookie(
                    targetUrl,
                    FireWebViewCookieActionSupport.expiredCookieHeader(
                        name = cookie.name,
                        domain = cookie.domain,
                        path = cookie.path ?: "/",
                    ),
                )
            }
        }
        FireWebViewCookieActionSupport.deleteByNameHeaders(
            url = targetUrl,
            name = "cf_clearance",
        ).forEach { header ->
            cookieManager.setCookie(targetUrl, header)
        }
        cookieManager.flush()
    }

    private fun restorePreservedClearanceCookies() {
        if (preservedClearanceCookies.isEmpty()) {
            return
        }
        val cookieManager = CookieManager.getInstance()
        preservedClearanceCookies.forEach { cookie ->
            cookieManager.setCookie(
                targetUrl,
                FireWebViewCookieActionSupport.setCookieHeader(cookie),
            )
        }
        cookieManager.flush()
    }

    private fun finishWithResult(result: CloudflareChallengeResultState) {
        if (finishedResult) {
            return
        }
        completionPollingJob?.cancel()
        completionPollingJob = null
        if (!result.completed) {
            restorePreservedClearanceCookies()
        }
        finishedResult = true
        PendingChallenges.finish(pendingToken, result)
        finish()
    }

    private fun cancelledResult(userCancelled: Boolean): CloudflareChallengeResultState {
        return CloudflareChallengeResultState(
            completed = false,
            userCancelled = userCancelled,
            freshCfClearance = null,
            cookies = emptyList(),
            browserUserAgent = null,
        )
    }

    private fun applySystemBarInsets() {
        val root = findViewById<View>(R.id.challenge_root)
        val topBar = findViewById<View>(R.id.challenge_top_bar)
        val initialRootLeft = root.paddingLeft
        val initialRootRight = root.paddingRight
        val initialRootBottom = root.paddingBottom
        val initialTopBarTop = topBar.paddingTop
        ViewCompat.setOnApplyWindowInsetsListener(root) { _, insets ->
            val systemBars = insets.getInsets(WindowInsetsCompat.Type.systemBars())
            root.updatePadding(
                left = initialRootLeft + systemBars.left,
                right = initialRootRight + systemBars.right,
                bottom = initialRootBottom + systemBars.bottom,
            )
            topBar.updatePadding(top = initialTopBarTop + systemBars.top)
            insets
        }
        ViewCompat.requestApplyInsets(root)
    }

    private suspend fun WebView.evaluateJavascriptSuspend(script: String): String =
        suspendCancellableCoroutine { continuation ->
            evaluateJavascript(script) { value ->
                continuation.resume(value ?: "null")
            }
        }

    companion object {
        const val EXTRA_PENDING_TOKEN = "fire.pending_token"
        const val EXTRA_TARGET_URL = "fire.target_url"

        private const val CHALLENGE_PLATFORM_PATH = "/cdn-cgi/challenge-platform/"
        private val RELEVANT_COOKIE_NAMES = setOf("_t", "_forum_session", "cf_clearance", "_cfuvid")

        internal fun challengeResultCookies(
            cookies: List<PlatformCookieState>,
            freshCfClearance: String,
        ): List<PlatformCookieState> {
            val acceptedClearance = freshCfClearance.trim()
            return cookies.filter { cookie ->
                if (!cookie.name.equals("cf_clearance", ignoreCase = true)) {
                    true
                } else {
                    acceptedClearance.isNotEmpty() && cookie.value.trim() == acceptedClearance
                }
            }
        }
    }

    private inner class ChallengeBridge {
        @JavascriptInterface
        fun signal() {
            runOnUiThread { maybeCompleteChallenge() }
        }
    }
}
