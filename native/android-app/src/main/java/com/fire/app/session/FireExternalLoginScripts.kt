package com.fire.app.session

import com.fire.app.ui.auth.FireExternalLoginMethod
import org.json.JSONObject

/**
 * JS snippets that auto-click Discourse login-page provider buttons after Ember hydrates.
 * Mirrors iOS `FireExternalLoginScripts`.
 */
object FireExternalLoginScripts {
    fun autoStart(method: FireExternalLoginMethod): String = when (method) {
        FireExternalLoginMethod.Passkey -> """
            (function() {
              function clickPasskey() {
                var root = document.getElementById('login-buttons') || document;
                var btn = root.querySelector('button.passkey-login-button, button.btn-social.passkey-login-button');
                if (!btn) return false;
                btn.click();
                return true;
              }
              if (clickPasskey()) return true;
              var attempts = 0;
              var timer = setInterval(function() {
                if (clickPasskey() || ++attempts >= 50) clearInterval(timer);
              }, 100);
              return false;
            })();
        """.trimIndent()
        else -> {
            val provider = method.discourseProviderName ?: method.name.lowercase()
            val providerLiteral = JSONObject.quote(provider)
            """
            (function() {
              var provider = $providerLiteral;
              function clickProvider() {
                var root = document.getElementById('login-buttons') || document;
                var btn = root.querySelector('button.btn-social.' + provider + ', button.' + provider);
                if (!btn) return false;
                btn.click();
                return true;
              }
              if (clickProvider()) return true;
              var attempts = 0;
              var timer = setInterval(function() {
                if (clickProvider() || ++attempts >= 50) clearInterval(timer);
              }, 100);
              return false;
            })();
            """.trimIndent()
        }
    }

    fun isLinuxDoLoginPage(url: String?): Boolean {
        if (url.isNullOrBlank()) return false
        val normalized = url.trim().lowercase()
        if (!normalized.contains("linux.do")) return false
        // Strip scheme/host; path starts after the host segment.
        val withoutScheme = normalized
            .removePrefix("https://")
            .removePrefix("http://")
        val pathStart = withoutScheme.indexOf('/')
        val path = if (pathStart >= 0) {
            withoutScheme.substring(pathStart).substringBefore('?').substringBefore('#')
        } else {
            "/"
        }
        return path == "/login" || path.startsWith("/login/")
    }
}
