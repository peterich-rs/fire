package com.fire.app.ui.cloudflare

import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.os.Bundle
import android.view.View
import android.webkit.WebChromeClient
import android.webkit.WebResourceRequest
import android.webkit.WebView
import android.widget.ProgressBar
import android.widget.Toast
import androidx.appcompat.app.AppCompatActivity
import androidx.core.view.isVisible
import androidx.lifecycle.lifecycleScope
import androidx.webkit.SafeBrowsingResponseCompat
import androidx.webkit.WebResourceErrorCompat
import androidx.webkit.WebViewClientCompat
import androidx.webkit.WebViewFeature
import com.fire.app.R
import com.fire.app.session.FireSessionStoreRepository
import com.google.android.material.appbar.MaterialToolbar

class CloudflareChallengeActivity : AppCompatActivity() {

    private lateinit var toolbar: MaterialToolbar
    private lateinit var loadingIndicator: ProgressBar
    private lateinit var webView: WebView
    private lateinit var cookieSyncer: CloudflareWebViewCookieSyncer

    private val initialUrl: String
        get() = intent.getStringExtra(EXTRA_URL) ?: CloudflareChallengeSupport.SITE_ROOT_URL

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_cloudflare_challenge)

        toolbar = findViewById(R.id.cloudflare_toolbar)
        loadingIndicator = findViewById(R.id.cloudflare_loading_indicator)
        webView = findViewById(R.id.cloudflare_webview)

        val sessionStore = FireSessionStoreRepository.get(this)
        cookieSyncer = CloudflareWebViewCookieSyncer(sessionStore, lifecycleScope)

        toolbar.setNavigationOnClickListener { finish() }
        CloudflareChallengeSupport.configureWebView(webView)
        configureWebViewCallbacks()

        val restoredState = savedInstanceState?.let { webView.restoreState(it) }
        if (restoredState == null) {
            webView.loadUrl(initialUrl)
        }
        updateChrome()
    }

    override fun onSaveInstanceState(outState: Bundle) {
        super.onSaveInstanceState(outState)
        webView.saveState(outState)
    }

    override fun onDestroy() {
        webView.destroy()
        super.onDestroy()
    }

    private fun configureWebViewCallbacks() {
        webView.webViewClient = object : WebViewClientCompat() {
            override fun onPageStarted(view: WebView?, url: String?, favicon: Bitmap?) {
                super.onPageStarted(view, url, favicon)
                loadingIndicator.isVisible = true
                updateChrome()
                syncIfReady(url)
            }

            override fun onPageFinished(view: WebView?, url: String?) {
                super.onPageFinished(view, url)
                loadingIndicator.isVisible = false
                updateChrome()
                syncIfReady(url)
            }

            override fun onReceivedError(
                view: WebView,
                request: WebResourceRequest,
                error: WebResourceErrorCompat,
            ) {
                super.onReceivedError(view, request, error)
                if (request.isForMainFrame) {
                    loadingIndicator.isVisible = false
                    updateChrome()
                }
            }

            override fun shouldOverrideUrlLoading(view: WebView, request: WebResourceRequest): Boolean {
                val scheme = request.url.scheme?.lowercase()
                if (scheme == "http" || scheme == "https") {
                    return false
                }
                Toast.makeText(
                    this@CloudflareChallengeActivity,
                    R.string.cloudflare_blocked_external_navigation,
                    Toast.LENGTH_SHORT,
                ).show()
                return true
            }

            override fun onSafeBrowsingHit(
                view: WebView,
                request: WebResourceRequest,
                threatType: Int,
                callback: SafeBrowsingResponseCompat,
            ) {
                loadingIndicator.isVisible = false
                Toast.makeText(
                    this@CloudflareChallengeActivity,
                    R.string.login_safe_browsing_blocked,
                    Toast.LENGTH_LONG,
                ).show()
                if (WebViewFeature.isFeatureSupported(WebViewFeature.SAFE_BROWSING_RESPONSE_BACK_TO_SAFETY)) {
                    callback.backToSafety(true)
                } else {
                    callback.showInterstitial(true)
                }
            }
        }

        webView.webChromeClient = object : WebChromeClient() {
            override fun onReceivedTitle(view: WebView?, title: String?) {
                super.onReceivedTitle(view, title)
                updateChrome()
            }

            override fun onProgressChanged(view: WebView?, newProgress: Int) {
                super.onProgressChanged(view, newProgress)
                loadingIndicator.visibility = if (newProgress < 100) View.VISIBLE else View.GONE
                loadingIndicator.progress = newProgress
                updateChrome()
                syncIfReady(webView.url)
            }
        }
    }

    private fun updateChrome() {
        toolbar.title = webView.title?.takeIf { it.isNotBlank() }
            ?: getString(R.string.cloudflare_challenge_title)
    }

    private fun syncIfReady(url: String?) {
        cookieSyncer.syncIfClearanceAvailable(webView, url)
    }

    companion object {
        private const val EXTRA_URL = "com.fire.app.extra.CLOUDFLARE_URL"

        fun createIntent(context: Context, url: String = CloudflareChallengeSupport.SITE_ROOT_URL): Intent {
            return Intent(context, CloudflareChallengeActivity::class.java)
                .putExtra(EXTRA_URL, url)
        }
    }
}
