package com.fire.app

import android.os.Bundle
import android.webkit.WebChromeClient
import android.webkit.WebViewClient
import androidx.appcompat.app.AppCompatActivity
import androidx.lifecycle.lifecycleScope
import com.fire.app.databinding.ActivityLoginBinding
import com.fire.app.session.FireSessionStore
import com.fire.app.session.FireWebViewLoginCoordinator
import kotlinx.coroutines.launch

class LoginActivity : AppCompatActivity() {
    private lateinit var binding: ActivityLoginBinding
    private lateinit var loginCoordinator: FireWebViewLoginCoordinator

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        binding = ActivityLoginBinding.inflate(layoutInflater)
        setContentView(binding.root)

        loginCoordinator = FireWebViewLoginCoordinator(
            sessionStore = FireSessionStore(applicationContext),
        )

        binding.loginWebView.settings.javaScriptEnabled = true
        binding.loginWebView.webViewClient = WebViewClient()
        binding.loginWebView.webChromeClient = WebChromeClient()
        binding.loginWebView.loadUrl("https://linux.do")

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
    }
}
