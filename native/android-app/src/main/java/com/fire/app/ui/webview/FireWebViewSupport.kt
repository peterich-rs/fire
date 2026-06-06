package com.fire.app.ui.webview

import android.annotation.SuppressLint
import android.graphics.Bitmap
import android.os.Message
import android.webkit.CookieManager
import android.webkit.WebResourceRequest
import android.webkit.WebSettings
import android.webkit.WebView
import androidx.webkit.WebSettingsCompat
import androidx.webkit.WebViewClientCompat
import androidx.webkit.WebViewFeature

object FireWebViewSupport {
    private val versionTokenPattern = Regex("\\sVersion/\\d+(?:\\.\\d+)*")
    private val whitespacePattern = Regex("\\s+")

    internal fun browserCompatibleUserAgent(defaultUserAgent: String): String {
        return defaultUserAgent
            .replace("; wv", "")
            .replace(versionTokenPattern, "")
            .replace(whitespacePattern, " ")
            .trim()
    }

    @Suppress("DEPRECATION")
    @SuppressLint("SetJavaScriptEnabled")
    fun configureBrowserLikeWebView(webView: WebView) {
        CookieManager.getInstance().setAcceptCookie(true)
        CookieManager.getInstance().setAcceptThirdPartyCookies(webView, true)

        webView.settings.apply {
            javaScriptEnabled = true
            domStorageEnabled = true
            databaseEnabled = true
            userAgentString = browserCompatibleUserAgent(WebSettings.getDefaultUserAgent(webView.context))
            javaScriptCanOpenWindowsAutomatically = true
            setSupportMultipleWindows(true)
            setSupportZoom(true)
            builtInZoomControls = true
            displayZoomControls = false
            useWideViewPort = true
            loadWithOverviewMode = true
            loadsImagesAutomatically = true
            blockNetworkImage = false
            cacheMode = WebSettings.LOAD_DEFAULT
            allowFileAccess = false
            allowContentAccess = false
            allowFileAccessFromFileURLs = false
            allowUniversalAccessFromFileURLs = false
            mixedContentMode = WebSettings.MIXED_CONTENT_NEVER_ALLOW
            mediaPlaybackRequiresUserGesture = false
            setGeolocationEnabled(false)
        }

        if (WebViewFeature.isFeatureSupported(WebViewFeature.SAFE_BROWSING_ENABLE)) {
            WebSettingsCompat.setSafeBrowsingEnabled(webView.settings, true)
        }
    }

    fun routePopupIntoParent(parent: WebView, resultMsg: Message): Boolean {
        val transport = resultMsg.obj as? WebView.WebViewTransport ?: return false
        val popup = WebView(parent.context)
        configureBrowserLikeWebView(popup)
        popup.webViewClient = object : WebViewClientCompat() {
            override fun shouldOverrideUrlLoading(view: WebView, request: WebResourceRequest): Boolean {
                return routeToParent(parent, view, request.url.toString())
            }

            override fun onPageStarted(view: WebView?, url: String?, favicon: Bitmap?) {
                super.onPageStarted(view, url, favicon)
                val child = view ?: return
                routeToParent(parent, child, url)
            }
        }
        transport.webView = popup
        resultMsg.sendToTarget()
        return true
    }

    private fun routeToParent(parent: WebView, popup: WebView, url: String?): Boolean {
        val target = url?.takeIf { it.startsWith("http://") || it.startsWith("https://") } ?: return false
        parent.loadUrl(target)
        popup.destroy()
        return true
    }
}
