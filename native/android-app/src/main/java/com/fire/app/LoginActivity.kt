package com.fire.app

import android.graphics.Bitmap
import android.os.Bundle
import android.webkit.CookieManager
import android.webkit.WebChromeClient
import android.webkit.WebResourceError
import android.webkit.WebResourceRequest
import android.webkit.WebViewClient
import androidx.activity.addCallback
import androidx.appcompat.app.AppCompatActivity
import androidx.core.view.isVisible
import androidx.lifecycle.lifecycleScope
import com.fire.app.databinding.ActivityLoginBinding
import com.fire.app.session.FireSessionStore
import com.fire.app.session.FireWebViewLoginCoordinator
import kotlinx.coroutines.launch

class LoginActivity : AppCompatActivity() {
    private lateinit var binding: ActivityLoginBinding
    private lateinit var loginCoordinator: FireWebViewLoginCoordinator
    private val loginBaseUrl = "https://linux.do"

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        binding = ActivityLoginBinding.inflate(layoutInflater)
        setContentView(binding.root)

        loginCoordinator = FireWebViewLoginCoordinator(
            sessionStore = FireSessionStore(applicationContext),
        )

        onBackPressedDispatcher.addCallback(this) {
            if (binding.loginWebView.canGoBack()) {
                binding.loginWebView.goBack()
                updateBrowserChrome()
            } else {
                finish()
            }
        }

        CookieManager.getInstance().setAcceptCookie(true)
        CookieManager.getInstance().setAcceptThirdPartyCookies(binding.loginWebView, true)

        binding.loginWebView.settings.javaScriptEnabled = true
        binding.loginWebView.settings.domStorageEnabled = true
        binding.loginWebView.settings.javaScriptCanOpenWindowsAutomatically = true
        binding.loginWebView.webViewClient = object : WebViewClient() {
            override fun onPageStarted(view: android.webkit.WebView?, url: String?, favicon: Bitmap?) {
                super.onPageStarted(view, url, favicon)
                binding.loadingIndicator.isVisible = true
                updateBrowserChrome()
            }

            override fun onPageFinished(view: android.webkit.WebView?, url: String?) {
                super.onPageFinished(view, url)
                binding.loadingIndicator.isVisible = false
                updateBrowserChrome()
            }

            override fun onReceivedError(
                view: android.webkit.WebView?,
                request: WebResourceRequest?,
                error: WebResourceError?,
            ) {
                super.onReceivedError(view, request, error)
                binding.loadingIndicator.isVisible = false
                updateBrowserChrome()
            }
        }
        binding.loginWebView.webChromeClient = object : WebChromeClient() {
            override fun onReceivedTitle(view: android.webkit.WebView?, title: String?) {
                super.onReceivedTitle(view, title)
                updateBrowserChrome()
            }

            override fun onProgressChanged(view: android.webkit.WebView?, newProgress: Int) {
                super.onProgressChanged(view, newProgress)
                binding.loadingIndicator.isVisible = newProgress < 100
                binding.loadingIndicator.progress = newProgress
                updateBrowserChrome()
            }
        }
        binding.loginWebView.loadUrl(loginBaseUrl)

        binding.closeButton.setOnClickListener {
            finish()
        }
        binding.syncButton.setOnClickListener {
            lifecycleScope.launch {
                loginCoordinator.completeLogin(binding.loginWebView)
                setResult(RESULT_OK)
                finish()
            }
        }
        binding.backButton.setOnClickListener {
            if (binding.loginWebView.canGoBack()) {
                binding.loginWebView.goBack()
                updateBrowserChrome()
            }
        }
        binding.forwardButton.setOnClickListener {
            if (binding.loginWebView.canGoForward()) {
                binding.loginWebView.goForward()
                updateBrowserChrome()
            }
        }
        binding.homeButton.setOnClickListener {
            binding.loginWebView.loadUrl(loginBaseUrl)
        }
        binding.reloadButton.setOnClickListener {
            binding.loginWebView.reload()
        }

        updateBrowserChrome()
    }

    override fun onDestroy() {
        binding.loginWebView.destroy()
        super.onDestroy()
    }

    private fun updateBrowserChrome() {
        binding.backButton.isEnabled = binding.loginWebView.canGoBack()
        binding.forwardButton.isEnabled = binding.loginWebView.canGoForward()
        binding.pageTitleText.text = binding.loginWebView.title ?: getString(R.string.login_title)
        binding.pageUrlText.text = binding.loginWebView.url ?: loginBaseUrl
    }
}
