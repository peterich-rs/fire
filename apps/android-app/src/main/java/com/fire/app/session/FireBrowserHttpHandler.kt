package com.fire.app.session

import android.content.Context
import android.os.Handler
import android.os.Looper
import android.webkit.CookieManager
import android.webkit.WebView
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import org.json.JSONObject
import uniffi.fire_uniffi_session.BrowserHttpHandler
import uniffi.fire_uniffi_session.BrowserHttpHeaderState
import uniffi.fire_uniffi_session.BrowserHttpRequestState
import uniffi.fire_uniffi_session.BrowserHttpResponseState
import uniffi.fire_uniffi_types.FireUniFfiException

class FireBrowserHttpHandler(
    context: Context,
) : BrowserHttpHandler {
    private val appContext = context.applicationContext

    override fun executeBrowserHttp(request: BrowserHttpRequestState): BrowserHttpResponseState {
        val latch = CountDownLatch(1)
        var result: BrowserHttpResponseState? = null
        var error: String? = null
        Handler(Looper.getMainLooper()).post {
            val webView = WebView(appContext)
            CookieManager.getInstance().setAcceptCookie(true)
            val headerObject = request.headers.joinToString(",") { header ->
                "\"${header.name.jsonEscape()}\":\"${header.value.jsonEscape()}\""
            }
            val script = """
                (async () => {
                  try {
                    const res = await fetch("${request.url.jsonEscape()}", {
                      method: "${request.method.jsonEscape()}",
                      headers: {$headerObject},
                      body: ${requestBodyLiteral(request)},
                      credentials: "include"
                    });
                    const buffer = await res.arrayBuffer();
                    const body = Array.from(new Uint8Array(buffer));
                    const headers = [];
                    res.headers.forEach((value, name) => headers.push({name, value}));
                    return JSON.stringify({status: res.status, headers, body});
                  } catch (error) {
                    return JSON.stringify({error: String(error)});
                  }
                })()
            """.trimIndent()
            webView.evaluateJavascript(script) { raw ->
                try {
                    val json = JSONObject(raw.trim('"').replace("\\\"", "\""))
                    if (json.has("error")) {
                        error = json.optString("error")
                    } else {
                        val headers = mutableListOf<BrowserHttpHeaderState>()
                        val headerArray = json.optJSONArray("headers")
                        if (headerArray != null) {
                            for (index in 0 until headerArray.length()) {
                                val item = headerArray.optJSONObject(index) ?: continue
                                headers += BrowserHttpHeaderState(
                                    name = item.optString("name"),
                                    value = item.optString("value"),
                                )
                            }
                        }
                        val bodyArray = json.optJSONArray("body")
                        val body = if (bodyArray == null) {
                            byteArrayOf()
                        } else {
                            ByteArray(bodyArray.length()) { bodyArray.optInt(it).toByte() }
                        }
                        result = BrowserHttpResponseState(
                            status = json.optInt("status", 502).toUShort(),
                            headers = headers,
                            body = body,
                        )
                    }
                } catch (thrown: Exception) {
                    error = thrown.message
                } finally {
                    latch.countDown()
                }
            }
        }
        latch.await((request.timeoutMs + 2_000u).toLong(), TimeUnit.MILLISECONDS)
        return result ?: throw FireUniFfiException.Validation(
            details = error ?: "browser fetch failed",
        )
    }
}

private fun requestBodyLiteral(request: BrowserHttpRequestState): String {
    val body = request.body ?: return "undefined"
    if (body.isEmpty()) return "undefined"
    val encoded = android.util.Base64.encodeToString(
        body.map { it.toByte() }.toByteArray(),
        android.util.Base64.NO_WRAP,
    )
    return "Uint8Array.from(atob(\"${encoded.jsonEscape()}\"), c => c.charCodeAt(0))"
}

private fun String.jsonEscape(): String {
    return replace("\\", "\\\\").replace("\"", "\\\"")
}
