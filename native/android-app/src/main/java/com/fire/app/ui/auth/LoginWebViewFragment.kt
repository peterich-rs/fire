package com.fire.app.ui.auth

import android.graphics.Bitmap
import android.os.Bundle
import android.os.Message
import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import android.webkit.JavascriptInterface
import android.webkit.WebChromeClient
import android.webkit.WebResourceRequest
import android.webkit.WebView
import android.widget.ImageView
import android.widget.ProgressBar
import android.widget.TextView
import android.widget.Toast
import androidx.core.view.isVisible
import androidx.fragment.app.Fragment
import androidx.lifecycle.lifecycleScope
import androidx.navigation.fragment.findNavController
import androidx.webkit.SafeBrowsingResponseCompat
import androidx.webkit.WebResourceErrorCompat
import androidx.webkit.WebViewClientCompat
import androidx.webkit.WebViewCompat
import androidx.webkit.WebViewFeature
import com.fire.app.R
import com.fire.app.core.error.launchWithFireErrorHandling
import com.fire.app.session.FireAppStateRefreshRepository
import com.fire.app.session.FireCredentialStore
import com.fire.app.session.FireLoginScripts
import com.fire.app.session.FireSavedCredential
import com.fire.app.session.FireSessionStore
import com.fire.app.session.FireSessionStoreRepository
import com.fire.app.session.FireWebViewLoginCoordinator
import com.fire.app.ui.webview.FireWebViewSupport
import com.google.android.material.button.MaterialButton
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import uniffi.fire_uniffi_session.RefreshTriggerState

class LoginWebViewFragment : Fragment() {

    private var sessionStore: FireSessionStore? = null
    private var loginCoordinator: FireWebViewLoginCoordinator? = null
    private var readinessRetryJob: Job? = null
    private var fingerprintTimeoutJob: Job? = null
    private var readinessRetryCount = 0
    private var isCompletingLogin = false
    private var fingerprintDone = false
    private var waitingForFingerprint = false
    private var credential: FireSavedCredential? = null
    private var documentStartScriptInstalled = false

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

        viewLifecycleOwner.lifecycleScope.launch {
            sessionStore = FireSessionStoreRepository.get(requireContext())
            loginCoordinator = FireWebViewLoginCoordinator(requireNotNull(sessionStore))
            credential = FireCredentialStore.load(requireContext())

            val webView: WebView = view.findViewById(R.id.login_webview)
            val loadingIndicator: ProgressBar = view.findViewById(R.id.loading_indicator)
            val closeButton: ImageView = view.findViewById(R.id.close_button)
            val syncButton: MaterialButton = view.findViewById(R.id.sync_button)
            val pageTitleText: TextView = view.findViewById(R.id.page_title_text)
            val pageUrlText: TextView = view.findViewById(R.id.page_url_text)

            configureLoginWebView(webView)
            installDocumentStartScript(webView)
            webView.addJavascriptInterface(FireLoginJsInterface(this@LoginWebViewFragment), "Android")

            syncButton.isEnabled = false

            webView.webViewClient = object : WebViewClientCompat() {
            override fun onPageStarted(view: WebView?, url: String?, favicon: Bitmap?) {
                super.onPageStarted(view, url, favicon)
                loadingIndicator.isVisible = true
                updateChrome(webView, pageTitleText, pageUrlText)
                if (!documentStartScriptInstalled) {
                    injectPreloadedCaptureScript(webView)
                }
            }

            override fun onPageFinished(view: WebView?, url: String?) {
                super.onPageFinished(view, url)
                loadingIndicator.isVisible = false
                injectPageScripts(webView)
                updateChrome(webView, pageTitleText, pageUrlText)
                requestLoginStateCheck(webView, syncButton)
            }

            override fun doUpdateVisitedHistory(view: WebView?, url: String?, isReload: Boolean) {
                super.doUpdateVisitedHistory(view, url, isReload)
                requestLoginStateCheck(webView, syncButton)
            }

            override fun onLoadResource(view: WebView?, url: String?) {
                super.onLoadResource(view, url)
                if (url == loginBaseUrl || url == "$loginBaseUrl/") {
                    requestLoginStateCheck(webView, syncButton)
                }
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

            override fun onCreateWindow(
                view: WebView,
                isDialog: Boolean,
                isUserGesture: Boolean,
                resultMsg: Message,
            ): Boolean {
                return FireWebViewSupport.routePopupIntoParent(webView, resultMsg)
            }
            }

            replayCookiesAndLoadLogin(webView)

            closeButton.setOnClickListener {
                findNavController().popBackStack()
            }

            syncButton.setOnClickListener {
                completeLoginAndNavigate(webView, syncButton)
            }

            updateChrome(webView, pageTitleText, pageUrlText)
        }
    }

    override fun onDestroyView() {
        readinessRetryJob?.cancel()
        fingerprintTimeoutJob?.cancel()
        val webView = view?.findViewById<WebView>(R.id.login_webview)
        webView?.destroy()
        super.onDestroyView()
    }

    private fun replayCookiesAndLoadLogin(webView: WebView) {
        val sessionStore = requireNotNull(sessionStore)
        viewLifecycleOwner.lifecycleScope.launch {
            try {
                val cookieManager = android.webkit.CookieManager.getInstance()
                val replayEntries = sessionStore.cookieReplayQueue()
                for (entry in replayEntries) {
                    cookieManager.setCookie(entry.url, entry.rawSetCookie)
                }
                cookieManager.flush()
                if (replayEntries.isNotEmpty()) {
                    sessionStore.clearCookieReplayQueue()
                }
            } catch (_: Exception) {
                // Best-effort only: the authoritative session is still in Rust.
            } finally {
                webView.loadUrl("$loginBaseUrl/login")
            }
        }
    }

    private fun configureLoginWebView(webView: WebView) {
        FireWebViewSupport.configureBrowserLikeWebView(webView)
    }

    private fun installDocumentStartScript(webView: WebView) {
        if (!WebViewFeature.isFeatureSupported(WebViewFeature.DOCUMENT_START_SCRIPT)) {
            documentStartScriptInstalled = false
            return
        }

        WebViewCompat.addDocumentStartJavaScript(
            webView,
            FireLoginScripts.preloadedDataCapture,
            setOf("https://linux.do"),
        )
        documentStartScriptInstalled = true
    }

    private fun injectPreloadedCaptureScript(webView: WebView) {
        webView.evaluateJavascript(FireLoginScripts.preloadedDataCapture, null)
    }

    private fun injectPageScripts(webView: WebView) {
        val savedCredential = credential
        webView.evaluateJavascript(
            FireLoginScripts.credentialAutoFill(savedCredential?.username, savedCredential?.password),
            null,
        )
        webView.evaluateJavascript(FireLoginScripts.fingerprintIntercept, null)
    }

    private fun requestLoginStateCheck(webView: WebView, syncButton: MaterialButton) {
        val coordinator = loginCoordinator ?: return
        viewLifecycleOwner.lifecycleScope.launch {
            val readiness = runCatching { coordinator.probeLoginSyncReadiness(webView) }.getOrNull()
            val isReady = readiness?.isReady == true
            syncButton.isEnabled = isReady && !isCompletingLogin

            if (isReady) {
                cancelReadinessRetry()
                completeLoginAndNavigate(webView, syncButton)
                return@launch
            }

            if (readiness?.username != null) {
                scheduleReadinessRetry(webView, syncButton)
            } else {
                cancelReadinessRetry()
            }
        }
    }

    private fun scheduleReadinessRetry(webView: WebView, syncButton: MaterialButton) {
        if (readinessRetryCount >= 15) {
            return
        }
        if (readinessRetryJob?.isActive == true) {
            return
        }
        readinessRetryCount += 1
        readinessRetryJob = viewLifecycleOwner.lifecycleScope.launch {
            delay(500)
            readinessRetryJob = null
            requestLoginStateCheck(webView, syncButton)
        }
    }

    private fun cancelReadinessRetry() {
        readinessRetryJob?.cancel()
        readinessRetryJob = null
        readinessRetryCount = 0
    }

    private fun completeLoginAndNavigate(webView: WebView, syncButton: MaterialButton) {
        val sessionStore = requireNotNull(sessionStore)
        val coordinator = loginCoordinator ?: return
        if (isCompletingLogin) {
            return
        }

        isCompletingLogin = true
        syncButton.isEnabled = false

        viewLifecycleOwner.lifecycleScope.launchWithFireErrorHandling(
            operation = "login_webview.complete_login",
            sessionStore = sessionStore,
            fallbackMessage = getString(R.string.login_sync_error),
            onError = { error ->
                isCompletingLogin = false
                syncButton.isEnabled = true
                Toast.makeText(requireContext(), error.displayMessage, Toast.LENGTH_SHORT).show()
            },
        ) {
            coordinator.completeLogin(webView)
            sessionStore.triggerAppStateRefresh(
                RefreshTriggerState.LOGIN_COMPLETED,
                FireAppStateRefreshRepository,
            )
            awaitFingerprintThenNavigate(sessionStore)
        }
    }

    private suspend fun awaitFingerprintThenNavigate(sessionStore: FireSessionStore) {
        if (fingerprintDone) {
            sessionStore.recordFingerprintDone()
            navigateHome()
            return
        }

        waitingForFingerprint = true
        fingerprintTimeoutJob?.cancel()
        fingerprintTimeoutJob = viewLifecycleOwner.lifecycleScope.launch {
            delay(15_000)
            if (!fingerprintDone) {
                fingerprintDone = true
            }
            sessionStore.recordFingerprintDone()
            waitingForFingerprint = false
            navigateHome()
        }
    }

    fun onLoginCredentials(username: String, password: String) {
        FireCredentialStore.save(requireContext(), username, password)
        credential = FireCredentialStore.load(requireContext())
    }

    fun onFingerprintDone() {
        if (fingerprintDone) {
            return
        }
        fingerprintDone = true
        val sessionStore = sessionStore ?: return
        if (!waitingForFingerprint) {
            return
        }

        fingerprintTimeoutJob?.cancel()
        viewLifecycleOwner.lifecycleScope.launch {
            sessionStore.recordFingerprintDone()
            waitingForFingerprint = false
            navigateHome()
        }
    }

    private fun navigateHome() {
        if (!isAdded) {
            return
        }
        isCompletingLogin = false
        cancelReadinessRetry()
        findNavController().navigate(R.id.action_loginWebView_to_home)
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

private class FireLoginJsInterface(
    private val fragment: LoginWebViewFragment,
) {
    @JavascriptInterface
    fun onLoginCredentials(username: String, password: String) {
        fragment.onLoginCredentials(username, password)
    }

    @JavascriptInterface
    fun onFingerprintDone() {
        fragment.onFingerprintDone()
    }
}
