package com.fire.app.ui.webview

import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.net.Uri
import android.os.Bundle
import android.view.View
import android.webkit.WebChromeClient
import android.webkit.WebResourceRequest
import android.webkit.WebView
import android.widget.FrameLayout
import android.widget.ProgressBar
import androidx.appcompat.app.AppCompatActivity
import androidx.webkit.WebViewClientCompat
import com.fire.app.R
import com.google.android.material.appbar.MaterialToolbar

class FireInAppWebViewActivity : AppCompatActivity() {

    private lateinit var webView: WebView
    private lateinit var progressBar: ProgressBar
    private lateinit var toolbar: MaterialToolbar

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val url = intent.getStringExtra(EXTRA_URL)?.takeIf(::isWebUrl)
        if (url == null) {
            finish()
            return
        }

        val root = android.widget.LinearLayout(this).apply {
            orientation = android.widget.LinearLayout.VERTICAL
            setBackgroundColor(getColor(android.R.color.background_light))
        }
        toolbar = MaterialToolbar(this).apply {
            title = Uri.parse(url).host ?: getString(R.string.in_app_web_title)
            setNavigationIcon(R.drawable.ic_arrow_back)
            setNavigationContentDescription(R.string.action_back)
            setNavigationOnClickListener { finish() }
        }
        progressBar = ProgressBar(this, null, android.R.attr.progressBarStyleHorizontal).apply {
            max = 100
            visibility = View.GONE
        }
        webView = WebView(this)
        FireWebViewSupport.configureBrowserLikeWebView(webView)
        webView.webViewClient = object : WebViewClientCompat() {
            override fun shouldOverrideUrlLoading(view: WebView, request: WebResourceRequest): Boolean {
                val target = request.url.toString()
                if (!isWebUrl(target)) {
                    runCatching {
                        startActivity(Intent(Intent.ACTION_VIEW, request.url))
                    }
                    return true
                }
                return false
            }

            override fun onPageStarted(view: WebView?, url: String?, favicon: Bitmap?) {
                super.onPageStarted(view, url, favicon)
                toolbar.title = url?.let { Uri.parse(it).host } ?: getString(R.string.in_app_web_title)
                progressBar.visibility = View.VISIBLE
            }

            override fun onPageFinished(view: WebView?, url: String?) {
                super.onPageFinished(view, url)
                progressBar.visibility = View.GONE
            }
        }
        webView.webChromeClient = object : WebChromeClient() {
            override fun onProgressChanged(view: WebView?, newProgress: Int) {
                progressBar.progress = newProgress
                progressBar.visibility = if (newProgress >= 100) View.GONE else View.VISIBLE
            }
        }

        root.addView(
            toolbar,
            android.widget.LinearLayout.LayoutParams(
                android.widget.LinearLayout.LayoutParams.MATCH_PARENT,
                dp(56),
            ),
        )
        root.addView(
            progressBar,
            android.widget.LinearLayout.LayoutParams(
                android.widget.LinearLayout.LayoutParams.MATCH_PARENT,
                dp(2),
            ),
        )
        root.addView(
            webView,
            android.widget.LinearLayout.LayoutParams(
                FrameLayout.LayoutParams.MATCH_PARENT,
                0,
                1f,
            ),
        )
        setContentView(root)
        webView.loadUrl(url)
    }

    private fun dp(value: Int): Int =
        (value * resources.displayMetrics.density).toInt()

    override fun onBackPressed() {
        if (::webView.isInitialized && webView.canGoBack()) {
            webView.goBack()
        } else {
            super.onBackPressed()
        }
    }

    override fun onDestroy() {
        if (::webView.isInitialized) {
            webView.destroy()
        }
        super.onDestroy()
    }

    companion object {
        private const val EXTRA_URL = "com.fire.app.extra.IN_APP_WEB_URL"

        fun start(context: Context, url: String) {
            context.startActivity(
                Intent(context, FireInAppWebViewActivity::class.java)
                    .putExtra(EXTRA_URL, url),
            )
        }

        private fun isWebUrl(value: String): Boolean =
            value.startsWith("http://") || value.startsWith("https://")
    }
}
