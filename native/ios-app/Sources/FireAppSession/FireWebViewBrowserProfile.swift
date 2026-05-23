import UIKit
import WebKit

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
