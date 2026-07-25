import UIKit
import WebKit

enum FireLoginScripts {
    static let linuxDoHcaptchaSiteKey = "a776b4ac-8c4c-441e-986a-c6ee9ed8cf08"

    static let loginCredentialsMessageName = "loginCredentials"
    static let fingerprintDoneMessageName = "fingerprintDone"
    static let hcaptchaPassMessageName = "hcaptcha_pass"
    static let hcaptchaErrorMessageName = "hcaptcha_error"
    static let hcaptchaExpiredMessageName = "hcaptcha_expired"
    static let hcaptchaReadyMessageName = "hcaptcha_ready"
    /// Reports measured captcha/challenge content height so the native sheet can resize.
    static let hcaptchaContentHeightMessageName = "hcaptcha_content_height"
    static let loginResultMessageName = "login_result"

    static var preloadedDataCapture: WKUserScript {
        WKUserScript(
            source: """
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
              window.__rawPreloaded = parts.join('\\n');
            }).observe(document.documentElement, {childList: true, subtree: true});
            """,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: true
        )
    }

    static func credentialAutoFillUserScript(
        credential: FireSavedCredential?
    ) -> WKUserScript {
        WKUserScript(
            source: credentialAutoFillSource(credential: credential),
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: true
        )
    }

    static func credentialAutoFillSource(credential: FireSavedCredential?) -> String {
        let username = jsStringLiteral(credential?.username)
        let password = jsStringLiteral(credential?.password)
        return """
        (function() {
          if (window.__fireLoginHookTimer) {
            clearInterval(window.__fireLoginHookTimer);
          }
          var savedUser = \(username);
          var savedPass = \(password);
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
                userInput.dispatchEvent(new Event('input', { bubbles: true }));
                passInput.dispatchEvent(new Event('input', { bubbles: true }));
              }
              if (!hooked) {
                hooked = true;
                window.__fireLoginHooked = true;
                var loginBtn = document.getElementById('login-button');
                if (loginBtn) {
                  loginBtn.addEventListener('click', function() {
                    var u = document.getElementById('login-account-name');
                    var p = document.getElementById('login-account-password');
                    if (
                      u && p && u.value && p.value
                      && window.webkit
                      && window.webkit.messageHandlers
                      && window.webkit.messageHandlers.\(loginCredentialsMessageName)
                    ) {
                      window.webkit.messageHandlers.\(loginCredentialsMessageName).postMessage({
                        username: u.value,
                        password: p.value
                      });
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
        """
    }

    static var fingerprintIntercept: WKUserScript {
        WKUserScript(
            source: """
            (function() {
              if (window.__fpHooked) return;
              window.__fpHooked = true;
              function notify() {
                try {
                  if (
                    window.webkit
                    && window.webkit.messageHandlers
                    && window.webkit.messageHandlers.\(fingerprintDoneMessageName)
                  ) {
                    window.webkit.messageHandlers.\(fingerprintDoneMessageName).postMessage("done");
                  }
                } catch (error) {}
              }

              var originalFetch = window.fetch;
              if (originalFetch) {
                window.fetch = function(input, init) {
                  var result = originalFetch.apply(this, arguments);
                  if (
                    init && init.method && init.method.toUpperCase() === 'POST'
                    && typeof init.body === 'string'
                    && init.body.indexOf('visitor_id=') !== -1
                  ) {
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
                if (
                  this.__fireMethod === 'POST'
                  && typeof body === 'string'
                  && body.indexOf('visitor_id=') !== -1
                ) {
                  this.addEventListener('loadend', notify);
                }
                return originalSend.apply(this, arguments);
              };
            })();
            """,
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: true
        )
    }

    static var readCurrentUsername: String {
        """
        (function() {
          try {
            var meta = document.querySelector('meta[name="current-username"]');
            if (meta && meta.content) return meta.content;
            if (
              typeof Discourse !== 'undefined'
              && Discourse.User
              && typeof Discourse.User.current === 'function'
            ) {
              var currentUser = Discourse.User.current();
              if (currentUser && currentUser.username) return currentUser.username;
            }
          } catch (error) {}
          return null;
        })();
        """
    }

    static var readCsrfToken: String {
        """
        (function() {
          var meta = document.querySelector('meta[name="csrf-token"]');
          return meta && meta.content ? meta.content : null;
        })();
        """
    }

    static var readPreloadedData: String {
        "(function(){return window.__rawPreloaded||null;})()"
    }

    /// Active Cloudflare interstitial markers (aligned with challenge completion).
    static var hasActiveCloudflareChallenge: String {
        """
        (function() {
          try {
            var title = (document.title || '').toLowerCase();
            var html = ((document.documentElement && document.documentElement.outerHTML) || '')
              .slice(0, 12000)
              .toLowerCase();
            var active = html.indexOf('cf_chl_opt') !== -1 ||
              html.indexOf('cf-turnstile') !== -1 ||
              html.indexOf('challenge-running') !== -1 ||
              html.indexOf('challenge-stage') !== -1 ||
              (html.indexOf('challenge-platform') !== -1 && html.indexOf('cloudflare') !== -1) ||
              title.indexOf('just a moment') !== -1 ||
              (html.indexOf('just a moment') !== -1 &&
                (html.indexOf('cloudflare') !== -1 || html.indexOf('cf-challenge') !== -1));
            var originNotFound =
              html.indexOf('page-not-found') !== -1 ||
              html.indexOf('discourse-no-results') !== -1 ||
              html.indexOf('"errortype":"notfound"') !== -1 ||
              html.indexOf('404-body') !== -1;
            if (originNotFound) return false;
            return active;
          } catch (error) {
            return false;
          }
        })();
        """
    }

    static func minimalLoginHTML(
        hcaptchaSiteKey: String,
        hcaptchaCreateEndpoint: String? = nil
    ) -> String {
        let siteKey = jsStringLiteral(hcaptchaSiteKey)
        let hcaptchaCreateEndpoints = jsStringArrayLiteral(
            resolvedHcaptchaCreateEndpoints(preferred: hcaptchaCreateEndpoint)
        )
        return """
        <!doctype html>
        <html>
        <head>
          <meta charset="utf-8">
          <meta name="viewport" content="width=device-width, initial-scale=1">
          <style>
            html, body {
              margin: 0;
              /* Do NOT use min-height:100% — it makes scrollHeight track the WebView
                 and creates a feedback loop that keeps growing the native sheet. */
              height: auto;
              background: #ffffff;
              color-scheme: light;
              font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
            }
            #hcaptcha {
              display: flex;
              min-height: 78px;
              width: 100%;
              align-items: flex-start;
              justify-content: center;
              padding: 8px 0 12px;
              box-sizing: border-box;
            }
            /* Phase-2 challenge: hide the checkbox widget so it cannot peek above the card. */
            body.fire-hcaptcha-expanded #hcaptcha {
              position: fixed;
              left: -10000px;
              top: 0;
              width: 1px;
              height: 1px;
              min-height: 0;
              margin: 0;
              padding: 0;
              overflow: hidden;
              opacity: 0;
              pointer-events: none;
            }
            body.fire-hcaptcha-expanded {
              overflow: hidden;
              background: #ffffff;
            }
            iframe {
              max-width: 100%;
            }
          </style>
          <script>
            (function() {
              var hcaptchaSiteKey = \(siteKey);
              var lastReportedHeight = 0;
              var heightReportTimer = null;
              window.__fireHcaptchaExpanded = false;

              function postNative(name, payload) {
                try {
                  if (
                    !window.webkit
                    || !window.webkit.messageHandlers
                    || !window.webkit.messageHandlers[name]
                  ) {
                    return;
                  }
                  window.webkit.messageHandlers[name].postMessage(payload);
                } catch (error) {}
              }

              function setExpanded(expanded) {
                window.__fireHcaptchaExpanded = !!expanded;
                if (document.body) {
                  document.body.classList.toggle('fire-hcaptcha-expanded', !!expanded);
                }
                try { window.scrollTo(0, 0); } catch (error) {}
              }

              function measureChallengeFrameHeight() {
                var best = 0;
                document.querySelectorAll('iframe').forEach(function(iframe) {
                  try {
                    var rect = iframe.getBoundingClientRect();
                    // Checkbox widget ~300x75; challenge card is much taller.
                    if (rect.width < 180 || rect.height < 180) return;
                    if (rect.bottom < 0 || rect.top > (window.innerHeight + 80)) return;
                    // Prefer the largest challenge-like frame.
                    best = Math.max(best, rect.height);
                  } catch (error) {}
                });
                return best;
              }

              function measureContentHeight() {
                if (window.__fireHcaptchaExpanded) {
                  var challenge = measureChallengeFrameHeight();
                  if (challenge > 0) {
                    // Card height + small vertical breathing room under the challenge UI.
                    return Math.ceil(Math.max(420, Math.min(challenge + 28, 600)));
                  }
                  return 540;
                }

                var host = document.getElementById('hcaptcha');
                if (host) {
                  try {
                    var rect = host.getBoundingClientRect();
                    if (rect.height > 0) {
                      return Math.ceil(Math.max(130, Math.min(rect.height + 20, 200)));
                    }
                  } catch (error) {}
                }
                return 150;
              }

              function reportContentHeight(reason) {
                var height = measureContentHeight();
                var threshold = window.__fireHcaptchaExpanded ? 28 : 10;
                // While expanded, ignore observer noise entirely after the first solid report
                // unless height grows meaningfully (native also locks).
                if (Math.abs(height - lastReportedHeight) < threshold) {
                  if (reason === 'observe' || reason === 'resize' || reason === 'mutate' || reason === 'window') {
                    return;
                  }
                }
                lastReportedHeight = height;
                postNative('\(hcaptchaContentHeightMessageName)', {
                  height: height,
                  reason: reason || 'measure',
                  expanded: !!window.__fireHcaptchaExpanded
                });
              }

              function scheduleHeightReport(reason) {
                if (heightReportTimer) clearTimeout(heightReportTimer);
                // Longer debounce during challenge mount to avoid sheet bounce.
                var delay = window.__fireHcaptchaExpanded ? 280 : 80;
                heightReportTimer = setTimeout(function() {
                  heightReportTimer = null;
                  reportContentHeight(reason || 'observe');
                }, delay);
              }

              function installHeightObservers() {
                if (window.__fireHcaptchaHeightObserversInstalled) return;
                window.__fireHcaptchaHeightObserversInstalled = true;
                try {
                  if (window.ResizeObserver) {
                    var ro = new ResizeObserver(function() { scheduleHeightReport('resize'); });
                    if (document.body) ro.observe(document.body);
                    var host = document.getElementById('hcaptcha');
                    if (host) ro.observe(host);
                  }
                } catch (error) {}
                try {
                  if (window.MutationObserver && document.documentElement) {
                    new MutationObserver(function() { scheduleHeightReport('mutate'); })
                      .observe(document.documentElement, {
                        childList: true,
                        subtree: true,
                        attributes: true
                      });
                  }
                } catch (error) {}
                window.addEventListener('resize', function() { scheduleHeightReport('window'); }, { passive: true });
              }

              function report(phase, status, body) {
                postNative('\(loginResultMessageName)', {
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
                var endpoints = \(hcaptchaCreateEndpoints);
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
                if (
                  secondFactorToken !== null
                  && secondFactorToken !== undefined
                  && secondFactorToken !== ''
                ) {
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
                  if (!window.hcaptcha || !hcaptchaSiteKey) {
                    postNative('\(hcaptchaErrorMessageName)', 'hcaptcha_api_unavailable');
                    return;
                  }
                  window.__fireHcaptchaWidgetId = hcaptcha.render('hcaptcha', {
                    sitekey: hcaptchaSiteKey,
                    size: 'normal',
                    callback: function(token) {
                      setExpanded(false);
                      reportContentHeight('pass');
                      postNative('\(hcaptchaPassMessageName)', token);
                    },
                    'error-callback': function(message) {
                      postNative('\(hcaptchaErrorMessageName)', message || 'hcaptcha_error');
                    },
                    'expired-callback': function() {
                      postNative('\(hcaptchaExpiredMessageName)', 'expired');
                    },
                    'open-callback': function() {
                      // Hide checkbox phase immediately so it cannot peek above the challenge card.
                      setExpanded(true);
                      postNative('\(hcaptchaReadyMessageName)', 'open');
                      lastReportedHeight = 0;
                      postNative('\(hcaptchaContentHeightMessageName)', {
                        height: 540,
                        reason: 'open-seed',
                        expanded: true
                      });
                      // Single settled measurement after the challenge iframe mounts.
                      setTimeout(function() { reportContentHeight('open-delayed'); }, 360);
                    },
                    'close-callback': function() {
                      setExpanded(false);
                      postNative('\(hcaptchaReadyMessageName)', 'close');
                      reportContentHeight('close');
                    }
                  });
                  // Widget chrome is on screen — native loading spinner must not stay on top.
                  postNative('\(hcaptchaReadyMessageName)', 'rendered');
                  installHeightObservers();
                  reportContentHeight('rendered');
                } catch (error) {
                  postNative(
                    '\(hcaptchaErrorMessageName)',
                    String(error && error.message ? error.message : error)
                  );
                }
              };
            })();
          </script>
          <script
            src="https://js.hcaptcha.com/1/api.js"
            async
            defer
            onload="window.__fireHcaptchaReady && window.__fireHcaptchaReady()"
          ></script>
        </head>
        <body>
          <div id="hcaptcha"></div>
        </body>
        </html>
        """
    }

    static func fireLoginInvocation(
        identifier: String,
        password: String,
        hcaptchaToken: String?,
        secondFactorToken: String?
    ) -> String {
        let identifier = jsStringLiteral(identifier)
        let password = jsStringLiteral(password)
        let hcaptchaToken = jsStringLiteral(hcaptchaToken)
        let secondFactorToken = jsStringLiteral(secondFactorToken)
        // `__fireLogin` is async and returns a Promise. WKWebView's evaluateJavaScript
        // reports Promise results as "unsupported type" and would abort login if we
        // treated that as a hard failure. Kick off the promise and return a plain value.
        return """
        (function(){
          try {
            var p = window.__fireLogin(\(identifier),\(password),\(hcaptchaToken),\(secondFactorToken));
            if (p && typeof p.then === 'function') {
              p.catch(function(error) {
                try {
                  if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers['\(loginResultMessageName)']) {
                    window.webkit.messageHandlers['\(loginResultMessageName)'].postMessage({
                      phase: 'exception',
                      status: 0,
                      body: String(error && error.message ? error.message : error)
                    });
                  }
                } catch (e) {}
              });
            }
          } catch (error) {
            try {
              if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers['\(loginResultMessageName)']) {
                window.webkit.messageHandlers['\(loginResultMessageName)'].postMessage({
                  phase: 'exception',
                  status: 0,
                  body: String(error && error.message ? error.message : error)
                });
              }
            } catch (e) {}
          }
          return true;
        })();
        """
    }

    /// WKWebView often surfaces Promise evaluation as this non-fatal error.
    static func isBenignEvaluateJavaScriptError(_ error: Error) -> Bool {
        let nsError = error as NSError
        let message = nsError.localizedDescription.lowercased()
        if message.contains("unsupported type") {
            return true
        }
        // WKErrorJavaScriptResultTypeIsUnsupported == 5
        if nsError.domain == WKError.errorDomain || nsError.domain == "WKErrorDomain",
           nsError.code == 5 {
            return true
        }
        return false
    }

    private static func jsStringLiteral(_ value: String?) -> String {
        guard let value else {
            return "null"
        }
        let data = try? JSONEncoder().encode(value)
        return String(data: data ?? Data("null".utf8), encoding: .utf8) ?? "null"
    }

    private static func jsStringArrayLiteral(_ values: [String]) -> String {
        let data = try? JSONEncoder().encode(values)
        return String(data: data ?? Data("[]".utf8), encoding: .utf8) ?? "[]"
    }

    private static func resolvedHcaptchaCreateEndpoints(preferred: String?) -> [String] {
        var endpoints: [String] = []
        if let preferred = preferred?.trimmingCharacters(in: .whitespacesAndNewlines),
           !preferred.isEmpty {
            endpoints.append(preferred)
        }
        for endpoint in ["/captcha/hcaptcha/create.json", "/hcaptcha/create.json"]
            where !endpoints.contains(endpoint) {
            endpoints.append(endpoint)
        }
        return endpoints
    }
}

@MainActor
enum FireWebViewBrowserProfile {
    static var mobileSafariUserAgent: String {
        let osToken = currentOSVersionToken(separator: "_")
        let versionToken = currentOSVersionToken(separator: ".")
        let device = UIDevice.current.userInterfaceIdiom == .pad ? "iPad" : "iPhone"
        return "Mozilla/5.0 (\(device); CPU \(device) OS \(osToken) like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/\(versionToken) Mobile/15E148 Safari/604.1"
    }

    static func preferredUserAgent(_ capturedUserAgent: String? = nil) -> String {
        let trimmed = capturedUserAgent?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let trimmed, !trimmed.isEmpty else {
            return mobileSafariUserAgent
        }

        return safariCompatibleUserAgent(trimmed)
    }

    static func makeConfiguration() -> WKWebViewConfiguration {
        makeConfiguration(userContentController: WKUserContentController())
    }

    static func makeLoginConfiguration(
        credential: FireSavedCredential?,
        messageHandler: WKScriptMessageHandler
    ) -> WKWebViewConfiguration {
        let userContentController = WKUserContentController()
        userContentController.addUserScript(FireLoginScripts.preloadedDataCapture)
        userContentController.addUserScript(
            FireLoginScripts.credentialAutoFillUserScript(credential: credential)
        )
        userContentController.addUserScript(FireLoginScripts.fingerprintIntercept)
        userContentController.add(
            messageHandler,
            name: FireLoginScripts.loginCredentialsMessageName
        )
        userContentController.add(
            messageHandler,
            name: FireLoginScripts.fingerprintDoneMessageName
        )
        return makeConfiguration(userContentController: userContentController)
    }

    static func makeMinimalLoginConfiguration(
        messageHandler: WKScriptMessageHandler
    ) -> WKWebViewConfiguration {
        let userContentController = WKUserContentController()
        [
            FireLoginScripts.hcaptchaPassMessageName,
            FireLoginScripts.hcaptchaErrorMessageName,
            FireLoginScripts.hcaptchaExpiredMessageName,
            FireLoginScripts.hcaptchaReadyMessageName,
            FireLoginScripts.hcaptchaContentHeightMessageName,
            FireLoginScripts.loginResultMessageName,
        ].forEach { name in
            userContentController.add(messageHandler, name: name)
        }
        return makeConfiguration(userContentController: userContentController)
    }

    static func makeConfiguration(userContentController: WKUserContentController) -> WKWebViewConfiguration {
        addBrowserUserScripts(to: userContentController)

        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        configuration.userContentController = userContentController
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = true
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        configuration.allowsInlineMediaPlayback = true
        configuration.allowsAirPlayForMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = []
        return configuration
    }

    static func colorSchemeUserScript() -> WKUserScript {
        WKUserScript(
            source: "document.documentElement.style.colorScheme = 'light dark';",
            injectionTime: .atDocumentStart,
            forMainFrameOnly: true
        )
    }

    static func browserCompatibilityUserScript() -> WKUserScript {
        WKUserScript(
            source: """
            (function() {
              try {
                if (typeof globalThis.structuredClone === 'undefined') {
                  globalThis.structuredClone = function(value) {
                    return JSON.parse(JSON.stringify(value));
                  };
                }
                if (!Object.hasOwn) {
                  Object.hasOwn = function(object, property) {
                    return Object.prototype.hasOwnProperty.call(object, property);
                  };
                }
                if (!Array.prototype.at) {
                  Array.prototype.at = function(index) {
                    var offset = Math.trunc(index) || 0;
                    if (offset < 0) offset += this.length;
                    if (offset < 0 || offset >= this.length) return undefined;
                    return this[offset];
                  };
                }
                if (!String.prototype.at) {
                  String.prototype.at = function(index) {
                    var offset = Math.trunc(index) || 0;
                    if (offset < 0) offset += this.length;
                    if (offset < 0 || offset >= this.length) return undefined;
                    return this.charAt(offset);
                  };
                }
                if (
                  typeof crypto !== 'undefined'
                  && typeof crypto.getRandomValues === 'function'
                  && typeof crypto.randomUUID !== 'function'
                ) {
                  crypto.randomUUID = function() {
                    var bytes = new Uint8Array(16);
                    crypto.getRandomValues(bytes);
                    bytes[6] = (bytes[6] & 0x0f) | 0x40;
                    bytes[8] = (bytes[8] & 0x3f) | 0x80;
                    var hex = Array.prototype.map.call(bytes, function(byte) {
                      return byte.toString(16).padStart(2, '0');
                    }).join('');
                    return hex.slice(0, 8) + '-' + hex.slice(8, 12) + '-' + hex.slice(12, 16) + '-' + hex.slice(16, 20) + '-' + hex.slice(20);
                  };
                }
              } catch (error) {}
            })();
            """,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: false
        )
    }

    static func addBrowserUserScripts(to userContentController: WKUserContentController) {
        userContentController.addUserScript(colorSchemeUserScript())
        userContentController.addUserScript(browserCompatibilityUserScript())
    }

    static func configure(_ webView: WKWebView, preferredUserAgent capturedUserAgent: String? = nil) {
        webView.customUserAgent = preferredUserAgent(capturedUserAgent)
        webView.allowsLinkPreview = true
        webView.isOpaque = false
        webView.backgroundColor = .systemBackground
        webView.scrollView.keyboardDismissMode = .interactive
        #if DEBUG
        if #available(iOS 16.4, *) {
            webView.isInspectable = true
        }
        #endif
    }

    private static func safariCompatibleUserAgent(_ userAgent: String) -> String {
        guard userAgent.contains("AppleWebKit"),
              userAgent.contains("Mobile/") else {
            return userAgent
        }

        var result = userAgent.replacingOccurrences(
            of: #"\s+Version/[\d.]+"#,
            with: "",
            options: .regularExpression
        )
        result = result.replacingOccurrences(
            of: #"\s+Safari/[\d.]+"#,
            with: "",
            options: .regularExpression
        )

        let versionToken = currentOSVersionToken(separator: ".")
        if let mobileRange = result.range(of: "Mobile/") {
            result.insert(contentsOf: "Version/\(versionToken) ", at: mobileRange.lowerBound)
        }
        result += " Safari/604.1"
        return result
    }

    private static func currentOSVersionToken(separator: String) -> String {
        let version = UIDevice.current.systemVersion
        let parts = version.split(separator: ".")
        let major = parts.first.map(String.init) ?? "18"
        let minor = parts.count > 1 ? String(parts[1]) : "0"
        return "\(major)\(separator)\(minor)"
    }
}
