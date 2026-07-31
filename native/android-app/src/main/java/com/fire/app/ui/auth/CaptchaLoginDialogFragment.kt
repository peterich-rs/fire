package com.fire.app.ui.auth

import android.app.Dialog
import android.graphics.Bitmap
import android.os.Bundle
import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import android.view.WindowManager
import android.webkit.JavascriptInterface
import android.webkit.WebChromeClient
import android.webkit.WebResourceRequest
import android.webkit.WebView
import android.widget.EditText
import android.widget.ImageView
import android.widget.ProgressBar
import android.widget.Toast
import androidx.appcompat.app.AlertDialog
import androidx.core.os.bundleOf
import androidx.core.view.isVisible
import androidx.fragment.app.DialogFragment
import androidx.fragment.app.setFragmentResult
import androidx.lifecycle.lifecycleScope
import androidx.webkit.WebResourceErrorCompat
import androidx.webkit.WebViewClientCompat
import com.fire.app.FireApplication
import com.fire.app.R
import com.fire.app.core.error.launchWithFireErrorHandling
import com.fire.app.session.FireAppStateRefreshRepository
import com.fire.app.session.FireCloudflareChallengeCoordinator
import com.fire.app.session.FireCredentialStore
import com.fire.app.session.FireLastLoginStore
import com.fire.app.session.FireLoginScripts
import com.fire.app.session.FireSessionStore
import com.fire.app.session.FireSessionStoreRepository
import com.fire.app.session.FireWebViewLoginCoordinator
import com.fire.app.ui.webview.FireWebViewSupport
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

/**
 * Password + hCaptcha surface presented as a light sheet over onboarding,
 * mirroring iOS `FireCaptchaLoginDialogController`.
 */
class CaptchaLoginDialogFragment : DialogFragment() {

    private var sessionStore: FireSessionStore? = null
    private var loginCoordinator: FireWebViewLoginCoordinator? = null
    private var isCompletingLogin = false
    private var lastLoginHcaptchaToken: String? = null
    private var lastLoginSecondFactorToken: String? = null
    private var cfRetryUsed = false
    private var resultDelivered = false

    private var loginIdentifier: String = ""
    private var loginPassword: String = ""
    private var loginRemember: Boolean = false
    private var isAutoLogin: Boolean = false

    private val loginBaseUrl = "https://linux.do"

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setStyle(STYLE_NORMAL, R.style.Theme_Fire_CaptchaDialog)
        arguments?.let { args ->
            loginIdentifier = args.getString(ARG_IDENTIFIER).orEmpty()
            loginPassword = args.getString(ARG_PASSWORD).orEmpty()
            loginRemember = args.getBoolean(ARG_REMEMBER, false)
            isAutoLogin = args.getBoolean(ARG_IS_AUTO_LOGIN, false)
        }
    }

    override fun onCreateDialog(savedInstanceState: Bundle?): Dialog {
        val dialog = super.onCreateDialog(savedInstanceState)
        dialog.window?.let { window ->
            window.setSoftInputMode(WindowManager.LayoutParams.SOFT_INPUT_ADJUST_RESIZE)
            // Light forced chrome for captcha readability (iOS overrideUserInterfaceStyle = .light).
            window.decorView.systemUiVisibility = View.SYSTEM_UI_FLAG_LIGHT_STATUS_BAR
        }
        dialog.setCanceledOnTouchOutside(false)
        return dialog
    }

    override fun onStart() {
        super.onStart()
        dialog?.window?.setLayout(
            ViewGroup.LayoutParams.MATCH_PARENT,
            (resources.displayMetrics.heightPixels * 0.72f).toInt(),
        )
        dialog?.window?.setGravity(android.view.Gravity.BOTTOM)
        dialog?.window?.setBackgroundDrawableResource(android.R.color.transparent)
        view?.setBackgroundResource(android.R.color.white)
        view?.clipToOutline = true
    }

    override fun onCreateView(
        inflater: LayoutInflater,
        container: ViewGroup?,
        savedInstanceState: Bundle?,
    ): View = inflater.inflate(R.layout.dialog_captcha_login, container, false)

    override fun onViewCreated(view: View, savedInstanceState: Bundle?) {
        super.onViewCreated(view, savedInstanceState)
        val webView: WebView = view.findViewById(R.id.captcha_webview)
        val loadingIndicator: ProgressBar = view.findViewById(R.id.captcha_loading_indicator)
        val closeButton: ImageView = view.findViewById(R.id.captcha_close_button)

        closeButton.setOnClickListener {
            deliverResult(RESULT_CANCELLED, null)
            dismissAllowingStateLoss()
        }

        viewLifecycleOwner.lifecycleScope.launch {
            sessionStore = FireSessionStoreRepository.get(requireContext())
            loginCoordinator = FireWebViewLoginCoordinator(requireNotNull(sessionStore))
            configureLoginWebView(webView)
            webView.addJavascriptInterface(CaptchaJsInterface(this@CaptchaLoginDialogFragment), "Android")

            webView.webViewClient = object : WebViewClientCompat() {
                override fun onPageStarted(view: WebView?, url: String?, favicon: Bitmap?) {
                    super.onPageStarted(view, url, favicon)
                    loadingIndicator.isVisible = true
                }

                override fun onPageFinished(view: WebView?, url: String?) {
                    super.onPageFinished(view, url)
                    loadingIndicator.isVisible = false
                }

                override fun onReceivedError(
                    view: WebView,
                    request: WebResourceRequest,
                    error: WebResourceErrorCompat,
                ) {
                    super.onReceivedError(view, request, error)
                    if (request.isForMainFrame) {
                        loadingIndicator.isVisible = false
                    }
                }
            }
            webView.webChromeClient = object : WebChromeClient() {
                override fun onProgressChanged(view: WebView?, newProgress: Int) {
                    super.onProgressChanged(view, newProgress)
                    loadingIndicator.isVisible = newProgress < 100
                    loadingIndicator.progress = newProgress
                }
            }

            replayCookiesAndLoadMinimalLogin(webView)
        }
    }

    override fun onCancel(dialog: android.content.DialogInterface) {
        super.onCancel(dialog)
        deliverResult(RESULT_CANCELLED, null)
    }

    override fun onDestroyView() {
        view?.findViewById<WebView>(R.id.captcha_webview)?.destroy()
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
                KEY_IS_AUTO_LOGIN to isAutoLogin,
            ),
        )
    }

    private fun configureLoginWebView(webView: WebView) {
        FireWebViewSupport.configureBrowserLikeWebView(webView)
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
                val message = getString(R.string.login_cloudflare_retry_failed)
                Toast.makeText(requireContext(), message, Toast.LENGTH_LONG).show()
                deliverResult(RESULT_FAILED, message)
                dismissAllowingStateLoss()
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
        val webView = view?.findViewById<WebView>(R.id.captcha_webview) ?: return
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
        isCompletingLogin = false
        Toast.makeText(requireContext(), R.string.login_hcaptcha_expired, Toast.LENGTH_SHORT).show()
    }

    fun onLoginResult(payload: String) {
        val sessionStore = requireNotNull(sessionStore)
        viewLifecycleOwner.lifecycleScope.launchWithFireErrorHandling(
            operation = "captcha_login.classify_js_result",
            sessionStore = sessionStore,
            fallbackMessage = getString(R.string.login_sync_error),
            onError = { error ->
                isCompletingLogin = false
                deliverResult(RESULT_FAILED, error.displayMessage)
                dismissAllowingStateLoss()
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
                    deliverResult(RESULT_FAILED, message)
                    dismissAllowingStateLoss()
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
            inputType = android.text.InputType.TYPE_CLASS_NUMBER
        }
        AlertDialog.Builder(requireContext())
            .setTitle(R.string.login_two_factor_title)
            .setView(input)
            .setNegativeButton(R.string.action_cancel) { _, _ ->
                isCompletingLogin = false
                deliverResult(RESULT_CANCELLED, null)
                dismissAllowingStateLoss()
            }
            .setPositiveButton(R.string.login_two_factor_submit) { _, _ ->
                val code = input.text?.toString()?.trim().orEmpty()
                val webView = view?.findViewById<WebView>(R.id.captcha_webview) ?: return@setPositiveButton
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
        val webView = view?.findViewById<WebView>(R.id.captcha_webview) ?: return
        if (cfRetryUsed) {
            isCompletingLogin = false
            val message = getString(R.string.login_cloudflare_retry_failed)
            deliverResult(RESULT_FAILED, message)
            dismissAllowingStateLoss()
            return
        }
        cfRetryUsed = true
        Toast.makeText(requireContext(), R.string.login_cloudflare_retry_running, Toast.LENGTH_LONG).show()
        viewLifecycleOwner.lifecycleScope.launchWithFireErrorHandling(
            operation = "captcha_login.cloudflare_retry",
            sessionStore = sessionStore,
            fallbackMessage = getString(R.string.login_cloudflare_retry_failed),
            onError = { error ->
                isCompletingLogin = false
                deliverResult(RESULT_FAILED, error.displayMessage)
                dismissAllowingStateLoss()
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
                val message = getString(R.string.login_cloudflare_retry_failed)
                deliverResult(RESULT_FAILED, message)
                dismissAllowingStateLoss()
                return@launchWithFireErrorHandling
            }
            val freshCfClearance = result.freshCfClearance?.trim().orEmpty()
            if (freshCfClearance.isBlank()) {
                isCompletingLogin = false
                val message = getString(R.string.login_cloudflare_retry_failed)
                deliverResult(RESULT_FAILED, message)
                dismissAllowingStateLoss()
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

    private fun completeMinimalLoginAndNavigate() {
        val sessionStore = requireNotNull(sessionStore)
        val coordinator = loginCoordinator ?: return
        val webView = view?.findViewById<WebView>(R.id.captcha_webview) ?: return
        val identifier = loginIdentifier.trim()
        val password = loginPassword
        viewLifecycleOwner.lifecycleScope.launchWithFireErrorHandling(
            operation = "captcha_login.complete_js_login",
            sessionStore = sessionStore,
            fallbackMessage = getString(R.string.login_sync_error),
            onError = { error ->
                isCompletingLogin = false
                deliverResult(RESULT_FAILED, error.displayMessage)
                dismissAllowingStateLoss()
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
            isCompletingLogin = false
            deliverResult(RESULT_SUCCESS, null)
            dismissAllowingStateLoss()
        }
    }

    companion object {
        const val TAG = "CaptchaLoginDialog"
        const val REQUEST_KEY = "captcha_login_result"
        const val KEY_STATUS = "status"
        const val KEY_MESSAGE = "message"
        const val KEY_IS_AUTO_LOGIN = "is_auto_login"
        const val RESULT_SUCCESS = "success"
        const val RESULT_CANCELLED = "cancelled"
        const val RESULT_FAILED = "failed"

        private const val ARG_IDENTIFIER = "identifier"
        private const val ARG_PASSWORD = "password"
        private const val ARG_REMEMBER = "remember"
        private const val ARG_IS_AUTO_LOGIN = "is_auto_login"

        fun newInstance(
            identifier: String,
            password: String,
            remember: Boolean,
            isAutoLogin: Boolean = false,
        ): CaptchaLoginDialogFragment = CaptchaLoginDialogFragment().apply {
            arguments = bundleOf(
                ARG_IDENTIFIER to identifier,
                ARG_PASSWORD to password,
                ARG_REMEMBER to remember,
                ARG_IS_AUTO_LOGIN to isAutoLogin,
            )
        }
    }
}

private class CaptchaJsInterface(
    private val fragment: CaptchaLoginDialogFragment,
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
