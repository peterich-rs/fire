package com.fire.app.session

import android.os.Bundle
import android.view.View
import android.webkit.CookieManager
import android.webkit.WebChromeClient
import android.webkit.WebResourceRequest
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
import kotlinx.coroutines.launch
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.coroutines.withContext
import uniffi.fire_uniffi_session.CloudflareChallengeResultState
import uniffi.fire_uniffi_session.PlatformCookieState

class FireCloudflareChallengeActivity : ComponentActivity() {
    private lateinit var pendingToken: String
    private lateinit var targetUrl: String
    private lateinit var webView: WebView
    private lateinit var progressBar: ProgressBar
    private var baselineClearance: String? = null
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

        baselineClearance = extractCfClearance(CookieManager.getInstance().getCookie(targetUrl))
        FireWebViewSupport.configureBrowserLikeWebView(webView)
        webView.webViewClient = object : android.webkit.WebViewClient() {
            override fun onPageFinished(view: WebView, url: String?) {
                super.onPageFinished(view, url)
                maybeCompleteChallenge()
            }

            override fun doUpdateVisitedHistory(view: WebView, url: String?, isReload: Boolean) {
                super.doUpdateVisitedHistory(view, url, isReload)
                maybeCompleteChallenge()
            }

            override fun onLoadResource(view: WebView, url: String?) {
                super.onLoadResource(view, url)
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
        webView.loadUrl(targetUrl)
    }

    override fun onDestroy() {
        if (::webView.isInitialized) {
            webView.destroy()
        }
        if (!finishedResult && isFinishing) {
            finishWithResult(cancelledResult(userCancelled = true))
        }
        super.onDestroy()
    }

    private fun maybeCompleteChallenge() {
        if (finishedResult) {
            return
        }
        lifecycleScope.launch {
            val cookies = withContext(Dispatchers.Main) { collectRelevantCookies() }
            val newClearance = cookies.firstOrNull { it.name == "cf_clearance" }?.value
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
                    cookies = cookies,
                    browserUserAgent = webView.settings.userAgentString,
                ),
            )
        }
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
            cookieManager.getCookie(url)
                .orEmpty()
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
                    PlatformCookieState(
                        name = trimmed.substring(0, separator),
                        value = trimmed.substring(separator + 1).trim(),
                        domain = null,
                        path = null,
                        expiresAtUnixMs = null,
                        sameSite = null,
                    )
                }
                .filter { it.value.isNotEmpty() && it.name in RELEVANT_COOKIE_NAMES }
                .forEach { cookie ->
                    merged.putIfAbsent(cookie.name, cookie)
                }
        }
        return merged.values.toList()
    }

    private fun extractCfClearance(rawCookieHeader: String?): String? {
        return rawCookieHeader
            ?.split(";")
            ?.map { it.trim() }
            ?.firstOrNull { it.startsWith("cf_clearance=") }
            ?.substringAfter("=")
            ?.takeIf { it.isNotEmpty() }
    }

    private fun finishWithResult(result: CloudflareChallengeResultState) {
        if (finishedResult) {
            return
        }
        finishedResult = true
        PendingChallenges.finish(pendingToken, result)
        finish()
    }

    private fun cancelledResult(userCancelled: Boolean): CloudflareChallengeResultState {
        return CloudflareChallengeResultState(
            completed = false,
            userCancelled = userCancelled,
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

        private val RELEVANT_COOKIE_NAMES = setOf("_t", "_forum_session", "cf_clearance")
    }
}
