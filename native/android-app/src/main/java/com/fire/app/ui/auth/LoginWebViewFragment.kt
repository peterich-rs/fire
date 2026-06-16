package com.fire.app.ui.auth

import android.graphics.Bitmap
import android.os.Bundle
import android.os.Message
import android.text.Editable
import android.text.TextWatcher
import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import android.webkit.JavascriptInterface
import android.webkit.WebChromeClient
import android.webkit.WebResourceRequest
import android.webkit.WebView
import android.widget.EditText
import android.widget.ImageView
import android.widget.ProgressBar
import android.widget.TextView
import android.widget.Toast
import androidx.appcompat.app.AlertDialog
import androidx.core.view.isVisible
import androidx.fragment.app.Fragment
import androidx.lifecycle.lifecycleScope
import androidx.navigation.fragment.findNavController
import androidx.webkit.SafeBrowsingResponseCompat
import androidx.webkit.WebResourceErrorCompat
import androidx.webkit.WebViewClientCompat
import androidx.webkit.WebViewFeature
import com.fire.app.R
import com.fire.app.core.error.launchWithFireErrorHandling
import com.fire.app.session.FireAppStateRefreshRepository
import com.fire.app.session.FireCredentialStore
import com.fire.app.session.FireCloudflareChallengeCoordinator
import com.fire.app.session.FireLoginScripts
import com.fire.app.session.FireSavedCredential
import com.fire.app.session.FireSessionStore
import com.fire.app.session.FireSessionStoreRepository
import com.fire.app.session.FireWebViewLoginCoordinator
import com.fire.app.ui.webview.FireWebViewSupport
import com.google.android.material.button.MaterialButton
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import org.json.JSONObject
import uniffi.fire_uniffi_session.CloudflareChallengeRequestState
import uniffi.fire_uniffi_session.RefreshTriggerState
import uniffi.fire_uniffi_session.WebViewLoginDecisionState
import uniffi.fire_uniffi_session.WebViewLoginJsResultState
import uniffi.fire_uniffi_session.WebViewLoginPhaseState

class LoginWebViewFragment : Fragment() {

    private var sessionStore: FireSessionStore? = null
    private var loginCoordinator: FireWebViewLoginCoordinator? = null
    private var isCompletingLogin = false
    private var credential: FireSavedCredential? = null
    private var lastHcaptchaToken: String? = null
    private var lastLoginHcaptchaToken: String? = null
    private var lastLoginSecondFactorToken: String? = null
    private var cfRetryUsed = false

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
            val identifierInput: EditText = view.findViewById(R.id.login_identifier_input)
            val passwordInput: EditText = view.findViewById(R.id.login_password_input)

            configureLoginWebView(webView)
            webView.addJavascriptInterface(FireLoginJsInterface(this@LoginWebViewFragment), "Android")

            identifierInput.setText(credential?.username.orEmpty())
            passwordInput.setText(credential?.password.orEmpty())
            syncButton.isEnabled = hasEnteredCredentials(identifierInput, passwordInput)
            val inputWatcher = object : TextWatcher {
                override fun beforeTextChanged(s: CharSequence?, start: Int, count: Int, after: Int) = Unit
                override fun onTextChanged(s: CharSequence?, start: Int, before: Int, count: Int) {
                    syncButton.isEnabled = hasEnteredCredentials(identifierInput, passwordInput) && !isCompletingLogin
                }
                override fun afterTextChanged(s: Editable?) = Unit
            }
            identifierInput.addTextChangedListener(inputWatcher)
            passwordInput.addTextChangedListener(inputWatcher)

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

            override fun doUpdateVisitedHistory(view: WebView?, url: String?, isReload: Boolean) {
                super.doUpdateVisitedHistory(view, url, isReload)
            }

            override fun onLoadResource(view: WebView?, url: String?) {
                super.onLoadResource(view, url)
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

            replayCookiesAndLoadMinimalLogin(webView)

            closeButton.setOnClickListener {
                findNavController().popBackStack()
            }

            syncButton.setOnClickListener {
                val token = lastHcaptchaToken
                if (token.isNullOrBlank()) {
                    Toast.makeText(requireContext(), R.string.login_hcaptcha_required, Toast.LENGTH_SHORT).show()
                    return@setOnClickListener
                }
                runMinimalLogin(webView, identifierInput, passwordInput, token, null, syncButton)
            }

            updateChrome(webView, pageTitleText, pageUrlText)
        }
    }

    override fun onDestroyView() {
        val webView = view?.findViewById<WebView>(R.id.login_webview)
        webView?.destroy()
        super.onDestroyView()
    }

    private fun replayCookiesAndLoadMinimalLogin(webView: WebView) {
        val sessionStore = requireNotNull(sessionStore)
        val coordinator = requireNotNull(loginCoordinator)
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
                ensureCloudflareClearanceForLogin(sessionStore)
                coordinator.primeCookies(webView, "$loginBaseUrl/")
                webView.loadDataWithBaseURL(
                    "$loginBaseUrl/",
                    FireLoginScripts.minimalLoginDocument(FireLoginScripts.linuxDoHcaptchaSiteKey),
                    "text/html",
                    "UTF-8",
                    null,
                )
            } catch (_: Exception) {
                Toast.makeText(
                    requireContext(),
                    R.string.login_cloudflare_retry_failed,
                    Toast.LENGTH_LONG,
                ).show()
            }
        }
    }

    private suspend fun ensureCloudflareClearanceForLogin(sessionStore: FireSessionStore) {
        if (sessionStore.snapshot().readiness.hasCloudflareClearance) {
            return
        }
        val result = withContext(Dispatchers.IO) {
            FireCloudflareChallengeCoordinator(requireContext().applicationContext)
                .completeSynchronously(
                    CloudflareChallengeRequestState(
                        operation = "login.preflight",
                        requestUrl = "$loginBaseUrl/session/csrf",
                        originUrl = "$loginBaseUrl/",
                        isForeground = true,
                        sessionEpoch = 0uL,
                    ),
                )
        }
        val freshCfClearance = result.freshCfClearance?.trim().orEmpty()
        if (!result.completed || freshCfClearance.isBlank()) {
            error(getString(R.string.login_cloudflare_retry_failed))
        }
        val session = sessionStore.completeCloudflareChallenge(
            cookies = result.cookies,
            freshCfClearance = freshCfClearance,
            browserUserAgent = result.browserUserAgent,
        )
        if (session.cookies.cfClearance != freshCfClearance) {
            error(getString(R.string.login_cloudflare_retry_failed))
        }
        delay(1_500)
    }

    private fun configureLoginWebView(webView: WebView) {
        FireWebViewSupport.configureBrowserLikeWebView(webView)
    }

    private fun hasEnteredCredentials(identifierInput: EditText, passwordInput: EditText): Boolean {
        return identifierInput.text?.toString()?.trim()?.isNotEmpty() == true &&
            passwordInput.text?.toString()?.isNotEmpty() == true
    }

    private fun runMinimalLogin(
        webView: WebView,
        identifierInput: EditText,
        passwordInput: EditText,
        hcaptchaToken: String?,
        secondFactorToken: String?,
        syncButton: MaterialButton,
        isCloudflareRetry: Boolean = false,
    ) {
        val identifier = identifierInput.text?.toString()?.trim().orEmpty()
        val password = passwordInput.text?.toString().orEmpty()
        if (identifier.isBlank() || password.isBlank()) {
            Toast.makeText(requireContext(), R.string.login_credentials_required, Toast.LENGTH_SHORT).show()
            return
        }
        if (!isCloudflareRetry) {
            cfRetryUsed = false
        }
        lastLoginHcaptchaToken = hcaptchaToken
        lastLoginSecondFactorToken = secondFactorToken
        isCompletingLogin = true
        syncButton.isEnabled = false
        webView.evaluateJavascript(
            FireLoginScripts.fireLoginInvocation(
                identifier = identifier,
                password = password,
                hcaptchaToken = hcaptchaToken,
                secondFactorToken = secondFactorToken,
            ),
            null,
        )
    }

    fun onHcaptchaPass(token: String) {
        lastHcaptchaToken = token
        val root = view ?: return
        val webView: WebView = root.findViewById(R.id.login_webview)
        val identifierInput: EditText = root.findViewById(R.id.login_identifier_input)
        val passwordInput: EditText = root.findViewById(R.id.login_password_input)
        val syncButton: MaterialButton = root.findViewById(R.id.sync_button)
        runMinimalLogin(webView, identifierInput, passwordInput, token, null, syncButton)
    }

    fun onHcaptchaError(message: String?) {
        isCompletingLogin = false
        view?.findViewById<MaterialButton>(R.id.sync_button)?.isEnabled = true
        Toast.makeText(
            requireContext(),
            message?.takeIf { it.isNotBlank() } ?: getString(R.string.login_hcaptcha_error),
            Toast.LENGTH_SHORT,
        ).show()
    }

    fun onHcaptchaExpired() {
        lastHcaptchaToken = null
        isCompletingLogin = false
        view?.findViewById<MaterialButton>(R.id.sync_button)?.isEnabled = true
        Toast.makeText(requireContext(), R.string.login_hcaptcha_expired, Toast.LENGTH_SHORT).show()
    }

    fun onLoginResult(payload: String) {
        val sessionStore = requireNotNull(sessionStore)
        viewLifecycleOwner.lifecycleScope.launchWithFireErrorHandling(
            operation = "login_webview.classify_js_result",
            sessionStore = sessionStore,
            fallbackMessage = getString(R.string.login_sync_error),
            onError = { error ->
                isCompletingLogin = false
                view?.findViewById<MaterialButton>(R.id.sync_button)?.isEnabled = true
                Toast.makeText(requireContext(), error.displayMessage, Toast.LENGTH_SHORT).show()
            },
        ) {
            val result = parseLoginResult(payload)
            when (val decision = sessionStore.classifyWebViewLoginResult(result)) {
                is WebViewLoginDecisionState.Success -> completeMinimalLoginAndNavigate()
                is WebViewLoginDecisionState.NeedSecondFactor -> showSecondFactorDialog()
                is WebViewLoginDecisionState.RetryCloudflare -> handleCloudflareRetry()
                is WebViewLoginDecisionState.Failure -> {
                    isCompletingLogin = false
                    view?.findViewById<MaterialButton>(R.id.sync_button)?.isEnabled = true
                    Toast.makeText(
                        requireContext(),
                        decision.failure.message ?: getString(R.string.login_sync_error),
                        Toast.LENGTH_LONG,
                    ).show()
                }
            }
        }
    }

    private fun parseLoginResult(payload: String): WebViewLoginJsResultState {
        val json = JSONObject(payload)
        val phase = when (json.optString("phase").lowercase()) {
            "csrf" -> WebViewLoginPhaseState.CSRF
            "hcaptcha" -> WebViewLoginPhaseState.HCAPTCHA
            "session" -> WebViewLoginPhaseState.SESSION
            else -> WebViewLoginPhaseState.EXCEPTION
        }
        val status = json.optInt("status", 0).coerceIn(0, UShort.MAX_VALUE.toInt()).toUShort()
        return WebViewLoginJsResultState(
            phase = phase,
            status = status,
            body = json.optString("body"),
        )
    }

    private fun showSecondFactorDialog() {
        val input = EditText(requireContext()).apply {
            hint = getString(R.string.login_two_factor_hint)
            setSingleLine(true)
        }
        AlertDialog.Builder(requireContext())
            .setTitle(R.string.login_two_factor_title)
            .setView(input)
            .setNegativeButton(R.string.action_cancel) { _, _ ->
                isCompletingLogin = false
                view?.findViewById<MaterialButton>(R.id.sync_button)?.isEnabled = true
            }
            .setPositiveButton(R.string.login_two_factor_submit) { _, _ ->
                val code = input.text?.toString()?.trim().orEmpty()
                val root = view ?: return@setPositiveButton
                runMinimalLogin(
                    webView = root.findViewById(R.id.login_webview),
                    identifierInput = root.findViewById(R.id.login_identifier_input),
                    passwordInput = root.findViewById(R.id.login_password_input),
                    hcaptchaToken = null,
                    secondFactorToken = code,
                    syncButton = root.findViewById(R.id.sync_button),
                )
            }
            .show()
    }

    private fun handleCloudflareRetry() {
        val sessionStore = requireNotNull(sessionStore)
        val coordinator = loginCoordinator ?: return
        val root = view ?: return
        val webView: WebView = root.findViewById(R.id.login_webview)
        val identifierInput: EditText = root.findViewById(R.id.login_identifier_input)
        val passwordInput: EditText = root.findViewById(R.id.login_password_input)
        val syncButton: MaterialButton = root.findViewById(R.id.sync_button)
        if (cfRetryUsed) {
            isCompletingLogin = false
            syncButton.isEnabled = true
            Toast.makeText(
                requireContext(),
                R.string.login_cloudflare_retry_failed,
                Toast.LENGTH_LONG,
            ).show()
            return
        }

        cfRetryUsed = true
        Toast.makeText(
            requireContext(),
            R.string.login_cloudflare_retry_running,
            Toast.LENGTH_LONG,
        ).show()
        viewLifecycleOwner.lifecycleScope.launchWithFireErrorHandling(
            operation = "login_webview.cloudflare_retry",
            sessionStore = sessionStore,
            fallbackMessage = getString(R.string.login_cloudflare_retry_failed),
            onError = { error ->
                isCompletingLogin = false
                syncButton.isEnabled = true
                Toast.makeText(requireContext(), error.displayMessage, Toast.LENGTH_SHORT).show()
            },
        ) {
            val result = withContext(Dispatchers.IO) {
                FireCloudflareChallengeCoordinator(requireContext().applicationContext)
                    .completeSynchronously(
                        CloudflareChallengeRequestState(
                            operation = "login.csrf",
                            requestUrl = "$loginBaseUrl/session/csrf",
                            originUrl = "$loginBaseUrl/",
                            isForeground = true,
                            sessionEpoch = 0uL,
                        ),
                    )
            }
            if (!result.completed) {
                isCompletingLogin = false
                syncButton.isEnabled = true
                Toast.makeText(
                    requireContext(),
                    R.string.login_cloudflare_retry_failed,
                    Toast.LENGTH_LONG,
                ).show()
                return@launchWithFireErrorHandling
            }
            val freshCfClearance = result.freshCfClearance?.trim().orEmpty()
            if (freshCfClearance.isBlank()) {
                isCompletingLogin = false
                syncButton.isEnabled = true
                Toast.makeText(
                    requireContext(),
                    R.string.login_cloudflare_retry_failed,
                    Toast.LENGTH_LONG,
                ).show()
                return@launchWithFireErrorHandling
            }
            sessionStore.completeCloudflareChallenge(
                cookies = result.cookies,
                freshCfClearance = freshCfClearance,
                browserUserAgent = result.browserUserAgent,
            )
            delay(1_500)
            coordinator.primeCookies(webView, "$loginBaseUrl/")
            runMinimalLogin(
                webView = webView,
                identifierInput = identifierInput,
                passwordInput = passwordInput,
                hcaptchaToken = lastLoginHcaptchaToken,
                secondFactorToken = lastLoginSecondFactorToken,
                syncButton = syncButton,
                isCloudflareRetry = true,
            )
        }
    }

    private fun completeMinimalLoginAndNavigate() {
        val sessionStore = requireNotNull(sessionStore)
        val coordinator = loginCoordinator ?: return
        val root = view ?: return
        val webView: WebView = root.findViewById(R.id.login_webview)
        val identifier = root.findViewById<EditText>(R.id.login_identifier_input).text?.toString()?.trim().orEmpty()
        val password = root.findViewById<EditText>(R.id.login_password_input).text?.toString().orEmpty()
        viewLifecycleOwner.lifecycleScope.launchWithFireErrorHandling(
            operation = "login_webview.complete_js_login",
            sessionStore = sessionStore,
            fallbackMessage = getString(R.string.login_sync_error),
            onError = { error ->
                isCompletingLogin = false
                root.findViewById<MaterialButton>(R.id.sync_button).isEnabled = true
                Toast.makeText(requireContext(), error.displayMessage, Toast.LENGTH_SHORT).show()
            },
        ) {
            coordinator.completeJsLogin(webView, identifier)
            FireCredentialStore.save(requireContext(), identifier, password)
            credential = FireCredentialStore.load(requireContext())
            sessionStore.triggerAppStateRefresh(
                RefreshTriggerState.LOGIN_COMPLETED,
                FireAppStateRefreshRepository,
            )
            navigateHome()
        }
    }

    private fun navigateHome() {
        if (!isAdded) {
            return
        }
        isCompletingLogin = false
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
    fun hcaptchaPass(token: String) {
        dispatch { fragment.onHcaptchaPass(token) }
    }

    @JavascriptInterface
    fun hcaptchaError(message: String?) {
        dispatch { fragment.onHcaptchaError(message) }
    }

    @JavascriptInterface
    fun hcaptchaExpired(@Suppress("UNUSED_PARAMETER") value: String?) {
        dispatch { fragment.onHcaptchaExpired() }
    }

    @JavascriptInterface
    fun loginResult(payload: String) {
        dispatch { fragment.onLoginResult(payload) }
    }

    private fun dispatch(block: () -> Unit) {
        fragment.view?.post(block)
    }
}
