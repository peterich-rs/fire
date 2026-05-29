package com.fire.app.ui.auth

import android.graphics.Bitmap
import android.os.Bundle
import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import android.webkit.CookieManager
import android.webkit.WebSettings
import android.webkit.WebChromeClient
import android.webkit.WebResourceRequest
import android.webkit.WebView
import android.widget.Toast
import android.widget.ImageView
import android.widget.ProgressBar
import android.widget.TextView
import androidx.core.view.isVisible
import androidx.fragment.app.Fragment
import androidx.lifecycle.lifecycleScope
import androidx.navigation.fragment.findNavController
import androidx.webkit.SafeBrowsingResponseCompat
import androidx.webkit.WebResourceErrorCompat
import androidx.webkit.WebSettingsCompat
import androidx.webkit.WebViewClientCompat
import androidx.webkit.WebViewFeature
import com.fire.app.R
import com.fire.app.session.FireSessionStoreRepository
import com.fire.app.session.FireWebViewLoginCoordinator
import com.google.android.material.button.MaterialButton
import kotlinx.coroutines.launch

class LoginWebViewFragment : Fragment() {

    private var loginCoordinator: FireWebViewLoginCoordinator? = null
    private val loginBaseUrl = "https://linux.do"

    override fun onCreateView(
        inflater: LayoutInflater,
        container: ViewGroup?,
        savedInstanceState: Bundle?,
    ): View? {
        return inflater.inflate(R.layout.fragment_login_webview, container, false)
    }

    override fun onViewCreated(view: View, savedInstanceState: Bundle?) {
        super.onViewCreated(view, savedInstanceState)

        val sessionStore = FireSessionStoreRepository.get(requireContext())
        loginCoordinator = FireWebViewLoginCoordinator(sessionStore)

        val webView: WebView = view.findViewById(R.id.login_webview)
        val loadingIndicator: ProgressBar = view.findViewById(R.id.loading_indicator)
        val closeButton: ImageView = view.findViewById(R.id.close_button)
        val syncButton: MaterialButton = view.findViewById(R.id.sync_button)
        val pageTitleText: TextView = view.findViewById(R.id.page_title_text)
        val pageUrlText: TextView = view.findViewById(R.id.page_url_text)

        configureLoginWebView(webView)

        webView.webViewClient = object : WebViewClientCompat() {
            override fun onPageStarted(view: WebView?, url: String?, favicon: Bitmap?) {
                super.onPageStarted(view, url, favicon)
                loadingIndicator.isVisible = true
                updateChrome(webView, pageTitleText, pageUrlText)
            }

            override fun onPageFinished(view: WebView?, url: String?) {
                super.onPageFinished(view, url)
                loadingIndicator.isVisible = false
                updateChrome(webView, pageTitleText, pageUrlText)
            }

            override fun onReceivedError(
                view: WebView,
                request: WebResourceRequest,
                error: WebResourceErrorCompat,
            ) {
                super.onReceivedError(view, request, error)
                if (request.isForMainFrame) {
                    loadingIndicator.isVisible = false
                    updateChrome(webView, pageTitleText, pageUrlText)
                }
            }

            override fun shouldOverrideUrlLoading(view: WebView, request: WebResourceRequest): Boolean {
                val scheme = request.url.scheme?.lowercase()
                if (scheme == "http" || scheme == "https") {
                    return false
                }
                Toast.makeText(
                    requireContext(),
                    R.string.login_blocked_external_navigation,
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
                    requireContext(),
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
                updateChrome(webView, pageTitleText, pageUrlText)
            }

            override fun onProgressChanged(view: WebView?, newProgress: Int) {
                super.onProgressChanged(view, newProgress)
                loadingIndicator.isVisible = newProgress < 100
                loadingIndicator.progress = newProgress
                updateChrome(webView, pageTitleText, pageUrlText)
            }
        }

        webView.loadUrl(loginBaseUrl)

        closeButton.setOnClickListener {
            findNavController().popBackStack()
        }

        syncButton.setOnClickListener {
            lifecycleScope.launch {
                loginCoordinator?.completeLogin(webView)
                findNavController().navigate(R.id.action_loginWebView_to_home)
            }
        }

        updateChrome(webView, pageTitleText, pageUrlText)
    }

    override fun onDestroyView() {
        val webView = view?.findViewById<WebView>(R.id.login_webview)
        webView?.destroy()
        super.onDestroyView()
    }

    @Suppress("DEPRECATION")
    private fun configureLoginWebView(webView: WebView) {
        CookieManager.getInstance().setAcceptCookie(true)
        CookieManager.getInstance().setAcceptThirdPartyCookies(webView, true)

        webView.settings.apply {
            javaScriptEnabled = true
            domStorageEnabled = true
            javaScriptCanOpenWindowsAutomatically = false
            setSupportMultipleWindows(false)
            allowFileAccess = false
            allowContentAccess = false
            allowFileAccessFromFileURLs = false
            allowUniversalAccessFromFileURLs = false
            mixedContentMode = WebSettings.MIXED_CONTENT_NEVER_ALLOW
            mediaPlaybackRequiresUserGesture = true
            setGeolocationEnabled(false)
        }

        if (WebViewFeature.isFeatureSupported(WebViewFeature.SAFE_BROWSING_ENABLE)) {
            WebSettingsCompat.setSafeBrowsingEnabled(webView.settings, true)
        }
    }

    private fun updateChrome(
        webView: WebView,
        pageTitleText: TextView,
        pageUrlText: TextView,
    ) {
        pageTitleText.text = webView.title ?: getString(R.string.login_title)
        pageUrlText.text = webView.url ?: loginBaseUrl
    }
}
