package com.fire.app.ui.auth

import android.graphics.Bitmap
import android.os.Bundle
import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import android.webkit.CookieManager
import android.webkit.WebChromeClient
import android.webkit.WebResourceError
import android.webkit.WebResourceRequest
import android.webkit.WebViewClient
import android.widget.ImageView
import android.widget.ProgressBar
import android.widget.TextView
import androidx.core.view.isVisible
import androidx.fragment.app.Fragment
import androidx.lifecycle.lifecycleScope
import androidx.navigation.fragment.findNavController
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

        val webView: android.webkit.WebView = view.findViewById(R.id.login_webview)
        val loadingIndicator: ProgressBar = view.findViewById(R.id.loading_indicator)
        val closeButton: ImageView = view.findViewById(R.id.close_button)
        val syncButton: MaterialButton = view.findViewById(R.id.sync_button)
        val pageTitleText: TextView = view.findViewById(R.id.page_title_text)
        val pageUrlText: TextView = view.findViewById(R.id.page_url_text)

        CookieManager.getInstance().setAcceptCookie(true)
        CookieManager.getInstance().setAcceptThirdPartyCookies(webView, true)

        webView.settings.javaScriptEnabled = true
        webView.settings.domStorageEnabled = true
        webView.settings.javaScriptCanOpenWindowsAutomatically = true

        webView.webViewClient = object : WebViewClient() {
            override fun onPageStarted(view: android.webkit.WebView?, url: String?, favicon: Bitmap?) {
                super.onPageStarted(view, url, favicon)
                loadingIndicator.isVisible = true
                updateChrome(webView, pageTitleText, pageUrlText)
            }

            override fun onPageFinished(view: android.webkit.WebView?, url: String?) {
                super.onPageFinished(view, url)
                loadingIndicator.isVisible = false
                updateChrome(webView, pageTitleText, pageUrlText)
            }

            override fun onReceivedError(
                view: android.webkit.WebView?,
                request: WebResourceRequest?,
                error: WebResourceError?,
            ) {
                super.onReceivedError(view, request, error)
                loadingIndicator.isVisible = false
                updateChrome(webView, pageTitleText, pageUrlText)
            }
        }

        webView.webChromeClient = object : WebChromeClient() {
            override fun onReceivedTitle(view: android.webkit.WebView?, title: String?) {
                super.onReceivedTitle(view, title)
                updateChrome(webView, pageTitleText, pageUrlText)
            }

            override fun onProgressChanged(view: android.webkit.WebView?, newProgress: Int) {
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
        val webView = view?.findViewById<android.webkit.WebView>(R.id.login_webview)
        webView?.destroy()
        super.onDestroyView()
    }

    private fun updateChrome(
        webView: android.webkit.WebView,
        pageTitleText: TextView,
        pageUrlText: TextView,
    ) {
        pageTitleText.text = webView.title ?: getString(R.string.login_title)
        pageUrlText.text = webView.url ?: loginBaseUrl
    }
}
