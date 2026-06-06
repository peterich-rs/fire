import UIKit
import WebKit

enum FireLoginScripts {
    static let loginCredentialsMessageName = "loginCredentials"
    static let fingerprintDoneMessageName = "fingerprintDone"

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

    private static func jsStringLiteral(_ value: String?) -> String {
        guard let value else {
            return "null"
        }
        let data = try? JSONEncoder().encode(value)
        return String(data: data ?? Data("null".utf8), encoding: .utf8) ?? "null"
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
