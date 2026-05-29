package com.fire.app.ui.auth

import android.annotation.SuppressLint
import android.app.Dialog
import android.os.Bundle
import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import android.webkit.CookieManager
import android.webkit.WebResourceRequest
import android.webkit.WebView
import android.webkit.WebViewClient
import com.fire.app.R
import com.fire.app.session.FireSessionStoreRepository
import com.google.android.material.bottomsheet.BottomSheetDialogFragment
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch

class CloudflareRecoverySheet : BottomSheetDialogFragment() {

    private var recoveryUrl: String = "https://linux.do"
    private var onRecoveryComplete: (() -> Unit)? = null

    @SuppressLint("SetJavaScriptEnabled")
    override fun onCreateView(
        inflater: LayoutInflater,
        container: ViewGroup?,
        savedInstanceState: Bundle?,
    ): View? {
        return inflater.inflate(R.layout.sheet_cloudflare_recovery, container, false)
    }

    override fun onViewCreated(view: View, savedInstanceState: Bundle?) {
        super.onViewCreated(view, savedInstanceState)

        val webView = view.findViewById<WebView>(R.id.cf_recovery_webview)
        webView.settings.javaScriptEnabled = true
        webView.settings.domStorageEnabled = true

        webView.webViewClient = object : WebViewClient() {
            override fun shouldOverrideUrlLoading(
                view: WebView?,
                request: WebResourceRequest?,
            ): Boolean {
                return false
            }

            override fun onPageFinished(view: WebView?, url: String?) {
                super.onPageFinished(view, url)
                // Check if CF challenge is resolved by attempting to sync cookies
                val cookies = CookieManager.getInstance().getCookie(url ?: return)
                if (cookies?.contains("cf_clearance") == true) {
                    onRecoveryComplete?.invoke()
                    dismiss()
                }
            }
        }

        webView.loadUrl(recoveryUrl)
    }

    companion object {
        fun newInstance(
            recoveryUrl: String = "https://linux.do",
            onRecoveryComplete: (() -> Unit)? = null,
        ): CloudflareRecoverySheet {
            return CloudflareRecoverySheet().apply {
                this.recoveryUrl = recoveryUrl
                this.onRecoveryComplete = onRecoveryComplete
            }
        }
    }
}
