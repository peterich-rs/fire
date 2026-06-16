package com.fire.app.session

import org.json.JSONObject

object FireLoginScripts {
    const val linuxDoHcaptchaSiteKey = "a776b4ac-8c4c-441e-986a-c6ee9ed8cf08"

    private const val hcaptchaScriptUrl = "https://js.hcaptcha.com/1/api.js"

    const val preloadedDataCapture = """
        new MutationObserver(function(_, obs) {
          var el = document.querySelector('[data-preloaded]');
          if (!el) return;
          obs.disconnect();
          var parts = [el.outerHTML];
          document.querySelectorAll('meta[name]').forEach(function(m) {
            parts.push(m.outerHTML);
          });
          var setup = document.getElementById('data-discourse-setup');
          if (setup) parts.push(setup.outerHTML);
          window.__rawPreloaded = parts.join('\n');
        }).observe(document.documentElement, {childList: true, subtree: true});
    """

    fun credentialAutoFill(username: String?, password: String?): String {
        val escapedUser = username?.let { JSONObject.quote(it) } ?: "null"
        val escapedPass = password?.let { JSONObject.quote(it) } ?: "null"
        return """
            (function() {
              if (window.__fireLoginHookTimer) {
                clearInterval(window.__fireLoginHookTimer);
              }
              var savedUser = $escapedUser;
              var savedPass = $escapedPass;
              var filled = !!window.__fireLoginFilled;
              var hooked = !!window.__fireLoginHooked;
              var attempts = 0;
              window.__fireLoginHookTimer = setInterval(function() {
                var userInput = document.getElementById('login-account-name');
                var passInput = document.getElementById('login-account-password');
                if (userInput && passInput) {
                  if (!filled && savedUser && savedPass) {
                    filled = true;
                    window.__fireLoginFilled = true;
                    userInput.value = savedUser;
                    passInput.value = savedPass;
                    userInput.dispatchEvent(new Event('input', {bubbles: true}));
                    passInput.dispatchEvent(new Event('input', {bubbles: true}));
                  }
                  if (!hooked) {
                    hooked = true;
                    window.__fireLoginHooked = true;
                    var loginBtn = document.getElementById('login-button');
                    if (loginBtn) {
                      loginBtn.addEventListener('click', function() {
                        var u = document.getElementById('login-account-name');
                        var p = document.getElementById('login-account-password');
                        if (u && p && u.value && p.value) {
                          Android.onLoginCredentials(u.value, p.value);
                        }
                      }, true);
                    }
                  }
                  clearInterval(window.__fireLoginHookTimer);
                  window.__fireLoginHookTimer = null;
                }
                if (++attempts > 30) {
                  clearInterval(window.__fireLoginHookTimer);
                  window.__fireLoginHookTimer = null;
                }
              }, 300);
            })();
        """.trimIndent()
    }

    const val fingerprintIntercept = """
        (function() {
          if (window.__fpHooked) return;
          window.__fpHooked = true;
          function notify() {
            try { Android.onFingerprintDone(); } catch (error) {}
          }
          var originalFetch = window.fetch;
          if (originalFetch) {
            window.fetch = function(input, init) {
              var result = originalFetch.apply(this, arguments);
              if (init && init.method && init.method.toUpperCase() === 'POST' &&
                  typeof init.body === 'string' && init.body.indexOf('visitor_id=') !== -1) {
                result.then(notify, notify);
              }
              return result;
            };
          }
          var originalOpen = XMLHttpRequest.prototype.open;
          var originalSend = XMLHttpRequest.prototype.send;
          XMLHttpRequest.prototype.open = function(method) {
            this.__fireMethod = method;
            return originalOpen.apply(this, arguments);
          };
          XMLHttpRequest.prototype.send = function(body) {
            if (this.__fireMethod === 'POST' &&
                typeof body === 'string' &&
                body.indexOf('visitor_id=') !== -1) {
              this.addEventListener('loadend', notify);
            }
            return originalSend.apply(this, arguments);
          };
        })();
    """

    const val readCurrentUsername = """
        (function() {
          try {
            var meta = document.querySelector('meta[name="current-username"]');
            if (meta && meta.content) return meta.content;
            if (typeof Discourse !== 'undefined' && Discourse.User &&
                typeof Discourse.User.current === 'function') {
              var currentUser = Discourse.User.current();
              if (currentUser && currentUser.username) return currentUser.username;
            }
          } catch (error) {}
          return null;
        })();
    """

    const val readCsrfToken = """
        (function() {
          var meta = document.querySelector('meta[name="csrf-token"]');
          return meta && meta.content ? meta.content : null;
        })();
    """

    const val readPreloadedData = "(function(){return window.__rawPreloaded||null;})()"

    fun minimalLoginDocument(
        hcaptchaSiteKey: String,
        hcaptchaCreateEndpoint: String? = null,
    ): String {
        val siteKey = JSONObject.quote(hcaptchaSiteKey)
        val hcaptchaCreateEndpoints = resolvedHcaptchaCreateEndpoints(hcaptchaCreateEndpoint)
            .joinToString(prefix = "[", postfix = "]") { JSONObject.quote(it) }
        return """
            <!doctype html>
            <html>
            <head>
              <meta charset="utf-8">
              <meta name="viewport" content="width=device-width, initial-scale=1">
              <style>
                html, body {
                  margin: 0;
                  min-height: 100%;
                  background: transparent;
                  color-scheme: light dark;
                  font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
                }
                #hcaptcha {
                  display: flex;
                  min-height: 92px;
                  align-items: center;
                  justify-content: center;
                }
              </style>
              <script>
                (function() {
                  var hcaptchaSiteKey = $siteKey;

                  function postAndroid(name, payload) {
                    try {
                      if (!window.Android || typeof window.Android[name] !== 'function') return;
                      window.Android[name](
                        typeof payload === 'string' ? payload : JSON.stringify(payload)
                      );
                    } catch (error) {}
                  }

                  function report(phase, status, body) {
                    postAndroid('loginResult', {
                      phase: phase,
                      status: status || 0,
                      body: body == null ? '' : String(body)
                    });
                  }

                  function formBody(fields) {
                    var body = new URLSearchParams();
                    Object.keys(fields).forEach(function(key) {
                      var value = fields[key];
                      if (value !== null && value !== undefined) {
                        body.append(key, value);
                      }
                    });
                    return body.toString();
                  }

                  async function responseText(response) {
                    try {
                      return await response.text();
                    } catch (error) {
                      return String(error && error.message ? error.message : error);
                    }
                  }

                  async function fetchCsrf() {
                    var response = await fetch('/session/csrf', {
                      method: 'GET',
                      credentials: 'include',
                      cache: 'no-store',
                      headers: {
                        'Accept': 'application/json',
                        'X-Requested-With': 'XMLHttpRequest'
                      }
                    });
                    var text = await responseText(response);
                    if (!response.ok) {
                      report('csrf', response.status, text);
                      return null;
                    }
                    try {
                      var parsed = JSON.parse(text);
                      if (parsed && parsed.csrf) return parsed.csrf;
                    } catch (error) {}
                    report('csrf', response.status, text);
                    return null;
                  }

                  async function createHcaptcha(csrf, token) {
                    if (token === null || token === undefined || token === '') return true;
                    var endpoints = $hcaptchaCreateEndpoints;
                    var lastStatus = 0;
                    var lastBody = '';
                    for (var i = 0; i < endpoints.length; i++) {
                      try {
                        var response = await fetch(endpoints[i], {
                          method: 'POST',
                          credentials: 'include',
                          headers: {
                            'Content-Type': 'application/x-www-form-urlencoded',
                            'X-CSRF-Token': csrf,
                            'X-Requested-With': 'XMLHttpRequest'
                          },
                          body: formBody({ token: token })
                        });
                        var text = await responseText(response);
                        if (response.ok) return true;
                        lastStatus = response.status;
                        lastBody = text;
                        if (response.status === 404) continue;
                        break;
                      } catch (error) {
                        lastStatus = 0;
                        lastBody = String(error && error.message ? error.message : error);
                      }
                    }
                    report('hcaptcha', lastStatus, lastBody);
                    return false;
                  }

                  async function submitSession(csrf, identifier, password, secondFactorToken) {
                    var fields = {
                      login: identifier,
                      password: password
                    };
                    if (secondFactorToken !== null && secondFactorToken !== undefined && secondFactorToken !== '') {
                      fields.second_factor_token = secondFactorToken;
                      fields.second_factor_method = '1';
                    }
                    var response = await fetch('/session.json', {
                      method: 'POST',
                      credentials: 'include',
                      headers: {
                        'Accept': 'application/json',
                        'Content-Type': 'application/x-www-form-urlencoded',
                        'X-CSRF-Token': csrf,
                        'X-Requested-With': 'XMLHttpRequest'
                      },
                      body: formBody(fields)
                    });
                    report('session', response.status, await responseText(response));
                  }

                  window.__fireLogin = async function(identifier, password, hcaptchaToken, secondFactorToken) {
                    try {
                      var csrf = await fetchCsrf();
                      if (!csrf) return;
                      if (!(await createHcaptcha(csrf, hcaptchaToken))) return;
                      await submitSession(csrf, identifier, password, secondFactorToken);
                    } catch (error) {
                      report('exception', 0, String(error && error.message ? error.message : error));
                    }
                  };

                  window.__fireHcaptchaReady = function() {
                    try {
                      if (!window.hcaptcha || !hcaptchaSiteKey) return;
                      window.__fireHcaptchaWidgetId = hcaptcha.render('hcaptcha', {
                        sitekey: hcaptchaSiteKey,
                        callback: function(token) {
                          postAndroid('hcaptchaPass', token);
                        },
                        'error-callback': function(message) {
                          postAndroid('hcaptchaError', message || 'hcaptcha_error');
                        },
                        'expired-callback': function() {
                          postAndroid('hcaptchaExpired', 'expired');
                        }
                      });
                    } catch (error) {
                      postAndroid('hcaptchaError', String(error && error.message ? error.message : error));
                    }
                  };
                })();
              </script>
              <script src="$hcaptchaScriptUrl" async defer onload="window.__fireHcaptchaReady && window.__fireHcaptchaReady()"></script>
            </head>
            <body>
              <div id="hcaptcha"></div>
            </body>
            </html>
        """.trimIndent()
    }

    fun fireLoginInvocation(
        identifier: String,
        password: String,
        hcaptchaToken: String?,
        secondFactorToken: String?,
    ): String {
        val escapedIdentifier = JSONObject.quote(identifier)
        val escapedPassword = JSONObject.quote(password)
        val escapedHcaptcha = hcaptchaToken?.let { JSONObject.quote(it) } ?: "null"
        val escapedSecondFactor = secondFactorToken?.let { JSONObject.quote(it) } ?: "null"
        return "window.__fireLogin($escapedIdentifier,$escapedPassword,$escapedHcaptcha,$escapedSecondFactor);"
    }

    private fun resolvedHcaptchaCreateEndpoints(preferred: String?): List<String> {
        val endpoints = linkedSetOf<String>()
        preferred?.trim()?.takeIf { it.isNotEmpty() }?.let(endpoints::add)
        endpoints.add("/captcha/hcaptcha/create.json")
        endpoints.add("/hcaptcha/create.json")
        return endpoints.toList()
    }
}
