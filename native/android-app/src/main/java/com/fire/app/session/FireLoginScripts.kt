package com.fire.app.session

import org.json.JSONObject

object FireLoginScripts {
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
}
