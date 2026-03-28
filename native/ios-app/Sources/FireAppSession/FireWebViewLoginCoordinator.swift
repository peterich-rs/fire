import Foundation
import WebKit

@MainActor
public final class FireWebViewLoginCoordinator {
    private let sessionStore: FireSessionStore

    public init(sessionStore: FireSessionStore) {
        self.sessionStore = sessionStore
    }

    public func restorePersistedSessionIfAvailable() async throws -> SessionState? {
        try await sessionStore.restorePersistedSessionIfAvailable()
    }

    public func completeLogin(from webView: WKWebView) async throws -> SessionState {
        let captured = try await captureLoginState(from: webView)
        let state = try await sessionStore.syncLoginContext(captured)
        if state.bootstrap.hasPreloadedData {
            return state
        }
        return try await sessionStore.refreshBootstrapIfNeeded()
    }

    public func logout() async throws -> SessionState {
        try await sessionStore.logout()
    }

    public func captureLoginState(from webView: WKWebView) async throws -> FireCapturedLoginState {
        let currentURL = webView.url?.absoluteString
        async let username = readStringJavaScript(
            script: """
            (function() {
              var meta = document.querySelector('meta[name="current-username"]');
              if (meta && meta.content) return meta.content;
              return null;
            })();
            """,
            in: webView
        )
        async let csrfToken = readStringJavaScript(
            script: """
            (function() {
              var meta = document.querySelector('meta[name="csrf-token"]');
              if (meta && meta.content) return meta.content;
              return null;
            })();
            """,
            in: webView
        )
        async let html = readStringJavaScript(
            script: "document.documentElement.outerHTML",
            in: webView
        )
        async let cookies = relevantCookies(from: webView)

        let capturedUsername = try await username
        let capturedCsrfToken = try await csrfToken
        let capturedHTML = try await html
        let capturedCookies = try await cookies

        return FireCapturedLoginState(
            currentURL: currentURL,
            username: capturedUsername,
            csrfToken: capturedCsrfToken,
            homeHTML: capturedHTML,
            cookies: capturedCookies
        )
    }

    private func relevantCookies(from webView: WKWebView) async throws -> [PlatformCookieState] {
        let allCookies = try await httpCookies(from: webView.configuration.websiteDataStore.httpCookieStore)
        return allCookies.compactMap { cookie in
            guard ["_t", "_forum_session", "cf_clearance"].contains(cookie.name) else {
                return nil
            }

            return PlatformCookieState(
                name: cookie.name,
                value: cookie.value,
                domain: cookie.domain,
                path: cookie.path
            )
        }
    }

    private func httpCookies(from store: WKHTTPCookieStore) async throws -> [HTTPCookie] {
        try await withCheckedThrowingContinuation { continuation in
            store.getAllCookies { cookies in
                continuation.resume(returning: cookies)
            }
        }
    }

    private func readStringJavaScript(script: String, in webView: WKWebView) async throws -> String? {
        let value = try await withCheckedThrowingContinuation { continuation in
            webView.evaluateJavaScript(script) { result, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: result)
                }
            }
        }

        guard let string = value as? String, !string.isEmpty, string != "null" else {
            return nil
        }
        return string
    }
}
