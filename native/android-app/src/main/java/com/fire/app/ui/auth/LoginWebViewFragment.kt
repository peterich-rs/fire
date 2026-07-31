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
import android.widget.EditText
import android.widget.ImageView
import android.widget.ProgressBar
import android.widget.TextView
import android.widget.Toast
import androidx.appcompat.app.AlertDialog
import androidx.core.os.bundleOf
import androidx.core.view.isVisible
import androidx.fragment.app.Fragment
import androidx.fragment.app.setFragmentResult
import androidx.lifecycle.lifecycleScope
import androidx.navigation.fragment.findNavController
import androidx.webkit.SafeBrowsingResponseCompat
import androidx.webkit.WebResourceErrorCompat
import androidx.webkit.WebViewClientCompat
import androidx.webkit.WebViewFeature
import com.fire.app.FireApplication
import com.fire.app.R
import com.fire.app.core.error.launchWithFireErrorHandling
import com.fire.app.session.FireAppStateRefreshRepository
import com.fire.app.session.FireCloudflareChallengeCoordinator
import com.fire.app.session.FireCredentialStore
import com.fire.app.session.FireExternalLoginScripts
import com.fire.app.session.FireLastLoginStore
import com.fire.app.session.FireLoginScripts
import com.fire.app.session.FireSessionStore
import com.fire.app.session.FireSessionStoreRepository
import com.fire.app.session.FireWebViewLoginCoordinator
import com.fire.app.ui.webview.FireWebViewSupport
import kotlin.coroutines.resume
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import kotlinx.coroutines.suspendCancellableCoroutine
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
    private var lastHcaptchaToken: String? = null
    private var lastLoginHcaptchaToken: String? = null
    private var lastLoginSecondFactorToken: String? = null
    private var cfRetryUsed = false
    private var oauthPollJob: Job? = null
    private var didAutoStartExternalLogin = false
    private var resultDelivered = false

    private var loginMode: String = MODE_PASSWORD_CAPTCHA
    private var loginIdentifier: String = ""
    private var loginPassword: String = ""
    private var loginProvider: String = ""
    private var loginRemember: Boolean = false

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

        val args = LoginWebViewFragmentArgs.fromBundle(requireArguments())
        loginMode = args.loginMode
        loginIdentifier = args.loginIdentifier
        loginPassword = args.loginPassword
        loginProvider = args.loginProvider
        loginRemember = args.loginRemember

        viewLifecycleOwner.lifecycleScope.launch {
            sessionStore = FireSessionStoreRepository.get(requireContext())
            loginCoordinator = FireWebViewLoginCoordinator(requireNotNull(sessionStore))

            val webView: WebView = view.findViewById(R.id.login_webview)
            val loadingIndicator: ProgressBar = view.findViewById(R.id.loading_indicator)
            val closeButton: ImageView = view.findViewById(R.id.close_button)
            val pageTitleText: TextView = view.findViewById(R.id.page_title_text)
            val pageUrlText: TextView = view.findViewById(R.id.page_url_text)

            configureLoginWebView(webView)
            webView.addJavascriptInterface(FireLoginJsInterface(this@LoginWebViewFragment), "Android")
            startLoginSurfacePolling(webView)

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
                attemptAutoStartExternalLogin(webView, url)
                maybeRecoverActiveCloudflareOrFinalizeExternalLogin(webView)
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

            loadLoginSurface(webView)

            closeButton.setOnClickListener {
                deliverResult(RESULT_CANCELLED, null)
                findNavController().popBackStack()
            }

            updateChrome(webView, pageTitleText, pageUrlText)
        }
    }

    override fun onDestroyView() {
        oauthPollJob?.cancel()
        oauthPollJob = null
        // If the user backed out without an explicit result, treat as cancel once.
        if (!resultDelivered && isRemoving) {
            deliverResult(RESULT_CANCELLED, null)
        }
        val webView = view?.findViewById<WebView>(R.id.login_webview)
        webView?.destroy()
        super.onDestroyView()
    }

    private fun deliverResult(status: String, message: String?) {
        if (resultDelivered) return
        resultDelivered = true
        setFragmentResult(
            REQUEST_KEY,
            bundleOf(
                KEY_STATUS to status,
                KEY_MESSAGE to message,
            ),
        )
    }

    private fun attemptAutoStartExternalLogin(webView: WebView, url: String?) {
        if (didAutoStartExternalLogin) return
        if (loginMode != MODE_OAUTH && loginMode != MODE_PASSKEY) return
        if (!FireExternalLoginScripts.isLinuxDoLoginPage(url)) return

        val method = resolveExternalMethodForAutoStart() ?: return
        didAutoStartExternalLogin = true
        webView.evaluateJavascript(FireExternalLoginScripts.autoStart(method), null)
    }

    private fun resolveExternalMethodForAutoStart(): FireExternalLoginMethod? {
        if (loginMode == MODE_PASSKEY) {
            return FireExternalLoginMethod.Passkey
        }
        val provider = loginProvider.trim().lowercase()
        return FireExternalLoginMethod.entries.firstOrNull {
            it.discourseProviderName?.lowercase() == provider ||
                it.name.lowercase() == provider ||
                it.lastLoginMethod.storageKey == provider
        }
    }

    private fun loadLoginSurface(webView: WebView) {
        when (loginMode) {
            MODE_OAUTH, MODE_PASSKEY -> {
                replayCookiesAndLoadLoginPage(webView)
            }
            else -> {
                replayCookiesAndLoadMinimalLogin(webView)
            }
        }
    }

    private fun replayCookiesAndLoadLoginPage(webView: WebView) {
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
                webView.loadUrl("$loginBaseUrl/login")
            } catch (_: Exception) {
                Toast.makeText(
                    requireContext(),
                    R.string.login_cloudflare_retry_failed,
                    Toast.LENGTH_LONG,
                ).show()
            }
        }
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
        if (sessionStore.cloudflareClearanceIsTrusted()) {
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

    private fun runMinimalLogin(
        webView: WebView,
        hcaptchaToken: String?,
        secondFactorToken: String?,
        isCloudflareRetry: Boolean = false,
    ) {
        val identifier = loginIdentifier.trim()
        val password = loginPassword
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
        val webView = view?.findViewById<WebView>(R.id.login_webview) ?: return
        runMinimalLogin(webView, token, null)
    }

    fun onHcaptchaError(message: String?) {
        isCompletingLogin = false
        Toast.makeText(
            requireContext(),
            message?.takeIf { it.isNotBlank() } ?: getString(R.string.login_hcaptcha_error),
            Toast.LENGTH_SHORT,
        ).show()
    }

    fun onHcaptchaExpired() {
        lastHcaptchaToken = null
        isCompletingLogin = false
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
                    val message = decision.failure.message ?: getString(R.string.login_failed)
                    Toast.makeText(requireContext(), message, Toast.LENGTH_LONG).show()
                    deliverResult(RESULT_FAILED, message)
                    findNavController().popBackStack()
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
            }
            .setPositiveButton(R.string.login_two_factor_submit) { _, _ ->
                val code = input.text?.toString()?.trim().orEmpty()
                val webView = view?.findViewById<WebView>(R.id.login_webview) ?: return@setPositiveButton
                runMinimalLogin(
                    webView = webView,
                    hcaptchaToken = null,
                    secondFactorToken = code,
                )
            }
            .show()
    }

    private fun handleCloudflareRetry() {
        val sessionStore = requireNotNull(sessionStore)
        val coordinator = loginCoordinator ?: return
        val webView = view?.findViewById<WebView>(R.id.login_webview) ?: return
        if (cfRetryUsed) {
            isCompletingLogin = false
            Toast.makeText(
                requireContext(),
                loginCloudflareFailureMessage(null),
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
                val reason = when {
                    result.userCancelled -> "cancelled"
                    else -> "failed"
                }
                Toast.makeText(
                    requireContext(),
                    loginCloudflareFailureMessage(reason),
                    Toast.LENGTH_LONG,
                ).show()
                return@launchWithFireErrorHandling
            }
            val freshCfClearance = result.freshCfClearance?.trim().orEmpty()
            if (freshCfClearance.isBlank()) {
                isCompletingLogin = false
                Toast.makeText(
                    requireContext(),
                    loginCloudflareFailureMessage("failed"),
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
                hcaptchaToken = lastLoginHcaptchaToken,
                secondFactorToken = lastLoginSecondFactorToken,
                isCloudflareRetry = true,
            )
        }
    }

    private fun startLoginSurfacePolling(webView: WebView) {
        oauthPollJob?.cancel()
        oauthPollJob = viewLifecycleOwner.lifecycleScope.launch {
            while (isActive) {
                delay(1_000)
                if (!isCompletingLogin) {
                    maybeRecoverActiveCloudflareOrFinalizeExternalLogin(webView)
                }
            }
        }
    }

    private fun maybeRecoverActiveCloudflareOrFinalizeExternalLogin(webView: WebView) {
        if (isCompletingLogin || !isAdded) return
        val coordinator = loginCoordinator ?: return
        val sessionStore = sessionStore ?: return
        viewLifecycleOwner.lifecycleScope.launch {
            if (isCompletingLogin) return@launch
            val activeCf = runCatching {
                withContext(Dispatchers.Main) {
                    webView.evaluateJavascriptSuspend(FireLoginScripts.hasActiveCloudflareChallenge)
                }
            }.getOrNull()
            if (activeCf == "true") {
                runCatching {
                    ensureCloudflareClearanceForLogin(sessionStore)
                    withContext(Dispatchers.Main) {
                        webView.loadUrl("$loginBaseUrl/")
                    }
                }
                return@launch
            }
            val readiness = runCatching {
                coordinator.probeLoginSyncReadiness(webView)
            }.getOrNull() ?: return@launch
            if (!readiness.isReady) return@launch
            completeExternalLoginAndNavigate(webView, readiness.username)
        }
    }

    private fun completeExternalLoginAndNavigate(webView: WebView, username: String?) {
        if (isCompletingLogin) return
        val sessionStore = requireNotNull(sessionStore)
        val coordinator = loginCoordinator ?: return
        isCompletingLogin = true
        viewLifecycleOwner.lifecycleScope.launchWithFireErrorHandling(
            operation = "login_webview.complete_external_login",
            sessionStore = sessionStore,
            fallbackMessage = getString(R.string.login_sync_error),
            onError = { error ->
                isCompletingLogin = false
                Toast.makeText(requireContext(), error.displayMessage, Toast.LENGTH_SHORT).show()
            },
        ) {
            if (!username.isNullOrBlank()) {
                coordinator.completeJsLogin(webView, username)
            } else {
                coordinator.completeLogin(webView)
            }
            saveLastLoginMethodForExternal()
            val snapshot = sessionStore.snapshot()
            val refresh = com.fire.app.session.FireCfClearanceRefreshService.get(requireContext())
            refresh.bind(sessionStore)
            refresh.updateSession(snapshot)
            refresh.setLoginStateConfirmed(true)
            refresh.setSceneActive(true)
            FireApplication.applicationScope().launch {
                runCatching {
                    sessionStore.triggerAppStateRefresh(
                        RefreshTriggerState.LOGIN_COMPLETED,
                        FireAppStateRefreshRepository,
                    )
                }
            }
            navigateHome()
        }
    }

    private fun completeMinimalLoginAndNavigate() {
        val sessionStore = requireNotNull(sessionStore)
        val coordinator = loginCoordinator ?: return
        val webView = view?.findViewById<WebView>(R.id.login_webview) ?: return
        val identifier = loginIdentifier.trim()
        val password = loginPassword
        viewLifecycleOwner.lifecycleScope.launchWithFireErrorHandling(
            operation = "login_webview.complete_js_login",
            sessionStore = sessionStore,
            fallbackMessage = getString(R.string.login_sync_error),
            onError = { error ->
                isCompletingLogin = false
                Toast.makeText(requireContext(), error.displayMessage, Toast.LENGTH_SHORT).show()
            },
        ) {
            coordinator.completeJsLogin(webView, identifier)
            if (loginRemember) {
                FireCredentialStore.save(requireContext(), identifier, password)
            } else {
                FireCredentialStore.clear(requireContext())
            }
            FireLastLoginStore.save(requireContext(), FireLastLoginMethod.Password)
            val snapshot = sessionStore.snapshot()
            val refresh = com.fire.app.session.FireCfClearanceRefreshService.get(requireContext())
            refresh.bind(sessionStore)
            refresh.updateSession(snapshot)
            refresh.setLoginStateConfirmed(true)
            refresh.setSceneActive(true)
            FireApplication.applicationScope().launch {
                runCatching {
                    sessionStore.triggerAppStateRefresh(
                        RefreshTriggerState.LOGIN_COMPLETED,
                        FireAppStateRefreshRepository,
                    )
                }
            }
            navigateHome()
        }
    }

    private fun saveLastLoginMethodForExternal() {
        val provider = loginProvider.trim()
        val method = when (provider.lowercase()) {
            "google_oauth2" -> FireLastLoginMethod.Google
            "github" -> FireLastLoginMethod.GitHub
            "twitter" -> FireLastLoginMethod.X
            "discord" -> FireLastLoginMethod.Discord
            "apple" -> FireLastLoginMethod.Apple
            "passkey" -> FireLastLoginMethod.Passkey
            else -> FireLastLoginMethod.entries.firstOrNull { it.storageKey == provider.lowercase() }
        }
        if (method != null) {
            FireLastLoginStore.save(requireContext(), method)
        }
    }

    private fun navigateHome() {
        if (!isAdded) {
            return
        }
        isCompletingLogin = false
        deliverResult(RESULT_SUCCESS, null)
        findNavController().navigate(R.id.action_loginWebView_to_home)
    }

    private fun loginCloudflareFailureMessage(reason: String?): String {
        return when (reason?.trim()?.lowercase()) {
            "cooldown" -> getString(R.string.login_cloudflare_cooldown)
            "cancelled" -> getString(R.string.login_cloudflare_cancelled)
            "in_progress" -> getString(R.string.login_cloudflare_in_progress)
            else -> getString(R.string.login_cloudflare_retry_failed)
        }
    }

    private suspend fun WebView.evaluateJavascriptSuspend(script: String): String =
        suspendCancellableCoroutine { continuation ->
            evaluateJavascript(script) { value ->
                continuation.resume(value ?: "null")
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

    companion object {
        const val MODE_PASSWORD_CAPTCHA = "password_captcha"
        const val MODE_OAUTH = "oauth"
        const val MODE_PASSKEY = "passkey"

        const val REQUEST_KEY = "login_webview_result"
        const val KEY_STATUS = "status"
        const val KEY_MESSAGE = "message"
        const val RESULT_SUCCESS = "success"
        const val RESULT_CANCELLED = "cancelled"
        const val RESULT_FAILED = "failed"
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
