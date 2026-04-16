import Foundation
import WebKit

@MainActor
final class FireCfClearanceRefreshService: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
    static let shared = FireCfClearanceRefreshService()

    nonisolated static let logTarget = "cf.refresh"
    nonisolated static let rcInterceptHandlerName = "onRcIntercepted"
    nonisolated static let turnstileErrorHandlerName = "onTurnstileError"
    nonisolated static let initialSolveTimeout: Duration = .seconds(30)
    nonisolated static let retryDelay: Duration = .seconds(2)
    nonisolated static let cookiePropagationDelay: Duration = .milliseconds(500)
    nonisolated static let maxConsecutiveFailures = 3
    nonisolated static let fetchInterceptionUserScriptSource = #"""
(function() {
  if (window.__fireCfFetchInstalled) {
    return;
  }
  window.__fireCfFetchInstalled = true;

  var originalFetch = window.fetch ? window.fetch.bind(window) : null;
  var pendingRc = Object.create(null);
  var rcId = 0;

  function postRcIntercept(payload) {
    if (!window.webkit ||
        !window.webkit.messageHandlers ||
        !window.webkit.messageHandlers.onRcIntercepted) {
      throw new Error('fire_cf_refresh_bridge_missing');
    }
    window.webkit.messageHandlers.onRcIntercepted.postMessage(payload);
  }

  function parseBody(body) {
    if (!body) {
      return {};
    }
    if (typeof body === 'string') {
      try {
        return JSON.parse(body);
      } catch (error) {
        return {};
      }
    }
    if (typeof URLSearchParams !== 'undefined' && body instanceof URLSearchParams) {
      var result = {};
      body.forEach(function(value, key) {
        result[key] = value;
      });
      return result;
    }
    return {};
  }

  window._resolveRc = function(id, status, body) {
    var resolve = pendingRc[id];
    if (!resolve) {
      return;
    }
    delete pendingRc[id];
    resolve(new Response(body || '{}', {
      status: status,
      headers: { 'Content-Type': 'application/json' }
    }));
  };

  if (!originalFetch) {
    return;
  }

  window.fetch = function(input, init) {
    var requestURL = typeof input === 'string' ? input : (input && input.url) || '';
    if (requestURL.indexOf('/cdn-cgi/challenge-platform/') !== -1 &&
        requestURL.indexOf('/rc/') !== -1) {
      var id = 'rc_' + (++rcId);
      var challengeID = '';
      var parts = requestURL.split('/rc/');
      if (parts.length > 1) {
        challengeID = parts[1].split(/[?#]/)[0];
      }
      var parsedBody = parseBody(init && init.body);
      postRcIntercept({
        id: id,
        chlId: challengeID,
        secondaryToken: parsedBody.secondaryToken || '',
        sitekey: parsedBody.sitekey || '',
        runtimeToken: window.__fireCfRuntimeToken || ''
      });
      return new Promise(function(resolve) {
        pendingRc[id] = resolve;
      });
    }

    return originalFetch(input, init);
  };
})();
"""#

    private weak var loginCoordinator: FireWebViewLoginCoordinator?
    private var onSessionRefreshed: ((SessionState) async -> Void)?
    private var session: SessionState = .placeholder()
    private var sceneActive = false
    private var interactiveRecoveryActive = false
    private var startupTask: Task<Void, Never>?
    private var retryTask: Task<Void, Never>?
    private var initialSolveTimeoutTask: Task<Void, Never>?
    private var webView: WKWebView?
    private var loadContinuation: CheckedContinuation<Void, Error>?
    private var generation: UInt64 = 0
    private var consecutiveFailureCount = 0
    private var hasInterceptedInitialRc = false
    private var isCallingRc = false
    private var activeSitekey: String?
    private var activeBaseURL: String?
    private var activeRuntimeToken: String?
    private lazy var urlSession: URLSession = {
        let configuration = URLSessionConfiguration.default
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.httpShouldSetCookies = true
        configuration.httpCookieAcceptPolicy = .always
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 30
        return URLSession(configuration: configuration)
    }()

    func updateSession(
        _ session: SessionState,
        loginCoordinator: FireWebViewLoginCoordinator,
        onSessionRefreshed: ((SessionState) async -> Void)? = nil
    ) {
        self.session = session
        self.loginCoordinator = loginCoordinator
        if let onSessionRefreshed {
            self.onSessionRefreshed = onSessionRefreshed
        }

        if needsRuntimeRebuild {
            restartRuntime(reason: "session_update")
        } else {
            reconfigureRuntime(reason: "session_update")
        }
    }

    func setSceneActive(_ active: Bool) {
        sceneActive = active
        reconfigureRuntime(reason: active ? "scene_active" : "scene_inactive")
    }

    func setInteractiveRecoveryActive(_ active: Bool) {
        interactiveRecoveryActive = active
        reconfigureRuntime(reason: active ? "interactive_recovery_started" : "interactive_recovery_ended")
    }

    nonisolated static func shouldAutoRefresh(
        session: SessionState,
        sceneActive: Bool,
        interactiveRecoveryActive: Bool = false
    ) -> Bool {
        sceneActive
            && !interactiveRecoveryActive
            && session.readiness.canReadAuthenticatedApi
            && session.readiness.hasCloudflareClearance
            && !(session.bootstrap.turnstileSitekey?.isEmpty ?? true)
    }

    nonisolated static func turnstileHTML(
        sitekey: String,
        runtimeToken: String = "runtime-token"
    ) -> String {
        let sitekeyLiteral = javaScriptStringLiteral(sitekey)
        let runtimeTokenLiteral = javaScriptStringLiteral(runtimeToken)

        return """
<!DOCTYPE html>
<html>
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <style>
    html, body {
      margin: 0;
      padding: 0;
      background: transparent;
      width: 1px;
      height: 1px;
      overflow: hidden;
    }

    #fire-turnstile {
      width: 1px;
      height: 1px;
      overflow: hidden;
    }
  </style>
  <script>
    window.__fireCfRuntimeToken = \(runtimeTokenLiteral);

    function fireReportTurnstileError(error) {
      var message = '';
      try {
        message = String(error || 'turnstile_error');
      } catch (stringifyError) {
        message = 'turnstile_error';
      }
      if (window.webkit &&
          window.webkit.messageHandlers &&
          window.webkit.messageHandlers.onTurnstileError) {
        window.webkit.messageHandlers.onTurnstileError.postMessage({
          runtimeToken: window.__fireCfRuntimeToken || '',
          message: message
        });
      }
    }
  </script>
  <script src="https://challenges.cloudflare.com/turnstile/v0/api.js?onload=fireTurnstileOnLoad" async defer></script>
</head>
<body>
  <div id="fire-turnstile"></div>
  <script>
    function fireTurnstileOnLoad() {
      try {
        turnstile.render('#fire-turnstile', {
          sitekey: \(sitekeyLiteral),
          appearance: 'interaction-only',
          'refresh-expired': 'auto',
          'error-callback': fireReportTurnstileError
        });
      } catch (error) {
        fireReportTurnstileError(error);
      }
    }
  </script>
</body>
</html>
"""
    }

    nonisolated static func rcEndpointURL(baseURL: URL, challengeID: String) -> URL? {
        let base = baseURL.absoluteString.hasSuffix("/")
            ? String(baseURL.absoluteString.dropLast())
            : baseURL.absoluteString
        return URL(string: "\(base)/cdn-cgi/challenge-platform/h/g/rc/\(challengeID)")
    }

    private var shouldRun: Bool {
        Self.shouldAutoRefresh(
            session: session,
            sceneActive: sceneActive,
            interactiveRecoveryActive: interactiveRecoveryActive
        )
    }

    private var normalizedTurnstileSitekey: String? {
        guard
            let sitekey = session.bootstrap.turnstileSitekey?
                .trimmingCharacters(in: .whitespacesAndNewlines),
            !sitekey.isEmpty
        else {
            return nil
        }
        return sitekey
    }

    private var needsRuntimeRebuild: Bool {
        guard webView != nil || startupTask != nil || retryTask != nil else {
            return false
        }

        return activeSitekey != normalizedTurnstileSitekey
            || activeBaseURL != session.bootstrap.baseUrl
    }

    private func reconfigureRuntime(reason: String) {
        if shouldRun {
            startRuntimeIfNeeded(reason: reason)
        } else {
            stopRuntime(reason: reason)
        }
    }

    private func startRuntimeIfNeeded(reason: String) {
        guard shouldRun else { return }
        guard startupTask == nil, retryTask == nil, webView == nil else { return }
        guard let sitekey = normalizedTurnstileSitekey else { return }

        activeSitekey = sitekey
        activeBaseURL = session.bootstrap.baseUrl
        activeRuntimeToken = UUID().uuidString

        let generation = advanceGeneration()
        let runtimeToken = activeRuntimeToken ?? UUID().uuidString

        FireAPMManager.shared.recordBreadcrumb(
            target: Self.logTarget,
            message: "cf clearance refresh starting reason=\(reason)"
        )

        startupTask = Task { [weak self] in
            await self?.bootstrapRuntime(
                sitekey: sitekey,
                runtimeToken: runtimeToken,
                generation: generation,
                reason: reason
            )
        }
    }

    private func restartRuntime(reason: String) {
        if shouldRun {
            _ = cancelRuntime(resetFailures: false)
            reconfigureRuntime(reason: reason)
            return
        }

        stopRuntime(reason: reason)
    }

    private func stopRuntime(reason: String) {
        guard hasRuntimeState else { return }

        _ = cancelRuntime(resetFailures: true)
        FireAPMManager.shared.recordBreadcrumb(
            target: Self.logTarget,
            message: "cf clearance refresh stopped reason=\(reason)"
        )
    }

    private var hasRuntimeState: Bool {
        webView != nil || startupTask != nil || retryTask != nil || loadContinuation != nil
    }

    @discardableResult
    private func cancelRuntime(resetFailures: Bool) -> UInt64 {
        let generation = advanceGeneration()
        startupTask?.cancel()
        startupTask = nil
        retryTask?.cancel()
        retryTask = nil
        cancelInitialSolveTimeout()
        tearDownWebView()

        if resetFailures {
            consecutiveFailureCount = 0
        }

        return generation
    }

    private func advanceGeneration() -> UInt64 {
        generation &+= 1
        return generation
    }

    private func bootstrapRuntime(
        sitekey: String,
        runtimeToken: String,
        generation: UInt64,
        reason: String
    ) async {
        defer {
            if self.generation == generation {
                self.startupTask = nil
            }
        }

        do {
            try await loadTurnstilePage(
                sitekey: sitekey,
                runtimeToken: runtimeToken,
                generation: generation
            )
            guard isCurrentRuntime(generation: generation, runtimeToken: runtimeToken) else {
                return
            }

            scheduleInitialSolveTimeout(generation: generation, runtimeToken: runtimeToken)
            FireAPMManager.shared.recordBreadcrumb(
                target: Self.logTarget,
                message: "cf clearance refresh runtime ready reason=\(reason)"
            )
        } catch is CancellationError {
            return
        } catch {
            await handleRuntimeFailure(
                message: "cf clearance refresh startup failed: \(error.localizedDescription)",
                generation: generation,
                runtimeToken: runtimeToken
            )
        }
    }

    private func ensureWebView() -> WKWebView {
        if let webView {
            return webView
        }

        let userContentController = WKUserContentController()
        userContentController.addUserScript(
            WKUserScript(
                source: Self.fetchInterceptionUserScriptSource,
                injectionTime: .atDocumentStart,
                forMainFrameOnly: true
            )
        )
        userContentController.add(self, name: Self.rcInterceptHandlerName)
        userContentController.add(self, name: Self.turnstileErrorHandlerName)

        let configuration = WKWebViewConfiguration()
        configuration.userContentController = userContentController
        configuration.websiteDataStore = .default()

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.isHidden = true
        webView.navigationDelegate = self
        self.webView = webView
        return webView
    }

    private func tearDownWebView() {
        loadContinuation?.resume(throwing: CancellationError())
        loadContinuation = nil

        guard let webView else {
            activeSitekey = nil
            activeBaseURL = nil
            activeRuntimeToken = nil
            hasInterceptedInitialRc = false
            isCallingRc = false
            return
        }

        webView.stopLoading()
        let userContentController = webView.configuration.userContentController
        userContentController.removeScriptMessageHandler(forName: Self.rcInterceptHandlerName)
        userContentController.removeScriptMessageHandler(forName: Self.turnstileErrorHandlerName)
        userContentController.removeAllUserScripts()
        webView.navigationDelegate = nil
        self.webView = nil
        activeSitekey = nil
        activeBaseURL = nil
        activeRuntimeToken = nil
        hasInterceptedInitialRc = false
        isCallingRc = false
    }

    private func loadTurnstilePage(
        sitekey: String,
        runtimeToken: String,
        generation: UInt64
    ) async throws {
        guard isCurrentRuntime(generation: generation, runtimeToken: runtimeToken) else {
            throw CancellationError()
        }

        let webView = ensureWebView()
        let html = Self.turnstileHTML(sitekey: sitekey, runtimeToken: runtimeToken)

        try await withCheckedThrowingContinuation { continuation in
            if let loadContinuation {
                loadContinuation.resume(throwing: CancellationError())
            }
            loadContinuation = continuation
            webView.loadHTMLString(html, baseURL: session.baseURL)
        }
    }

    private func resumeLoad(_ result: Result<Void, Error>) {
        guard let loadContinuation else { return }
        loadContinuation.resume(with: result)
        self.loadContinuation = nil
    }

    private func scheduleInitialSolveTimeout(generation: UInt64, runtimeToken: String) {
        cancelInitialSolveTimeout()
        hasInterceptedInitialRc = false

        initialSolveTimeoutTask = Task { [weak self] in
            do {
                try await Task.sleep(for: Self.initialSolveTimeout)
            } catch {
                return
            }

            await self?.handleInitialSolveTimeout(
                generation: generation,
                runtimeToken: runtimeToken
            )
        }
    }

    private func cancelInitialSolveTimeout() {
        initialSolveTimeoutTask?.cancel()
        initialSolveTimeoutTask = nil
    }

    private func handleInitialSolveTimeout(generation: UInt64, runtimeToken: String) async {
        guard isCurrentRuntime(generation: generation, runtimeToken: runtimeToken) else {
            return
        }
        guard !hasInterceptedInitialRc else {
            return
        }

        await handleRuntimeFailure(
            message: "cf clearance refresh timed out waiting for Turnstile rc intercept",
            generation: generation,
            runtimeToken: runtimeToken
        )
    }

    private func scheduleRetry(reason: String, expectedGeneration: UInt64) {
        retryTask?.cancel()
        retryTask = Task { [weak self] in
            do {
                try await Task.sleep(for: Self.retryDelay)
            } catch {
                return
            }

            guard let self else { return }
            guard self.generation == expectedGeneration else { return }
            self.retryTask = nil
            self.reconfigureRuntime(reason: reason)
        }
    }

    private func handleRuntimeFailure(
        message: String,
        generation: UInt64,
        runtimeToken: String
    ) async {
        guard isCurrentRuntime(generation: generation, runtimeToken: runtimeToken) else {
            return
        }

        consecutiveFailureCount += 1
        FireAPMManager.shared.recordBreadcrumb(
            level: "warning",
            target: Self.logTarget,
            message: "\(message) failures=\(consecutiveFailureCount)"
        )

        let invalidatedGeneration = cancelRuntime(resetFailures: false)
        guard shouldRun else { return }

        guard consecutiveFailureCount < Self.maxConsecutiveFailures else {
            FireAPMManager.shared.recordBreadcrumb(
                level: "warning",
                target: Self.logTarget,
                message: "cf clearance refresh stopped after \(consecutiveFailureCount) consecutive failures"
            )
            return
        }

        scheduleRetry(reason: "retry_after_failure", expectedGeneration: invalidatedGeneration)
    }

    private func isCurrentRuntime(generation: UInt64, runtimeToken: String) -> Bool {
        generation == self.generation && runtimeToken == activeRuntimeToken
    }

    private func normalizedNonEmpty(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
            return nil
        }
        return value
    }

    func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        switch message.name {
        case Self.rcInterceptHandlerName:
            guard let payload = message.body as? [String: Any] else { return }
            let id = payload["id"] as? String ?? UUID().uuidString
            let challengeID = payload["chlId"] as? String
            let secondaryToken = payload["secondaryToken"] as? String
            let sitekey = payload["sitekey"] as? String
            let runtimeToken = payload["runtimeToken"] as? String ?? ""
            let generation = self.generation

            hasInterceptedInitialRc = true
            cancelInitialSolveTimeout()

            Task { [weak self] in
                await self?.handleRcIntercepted(
                    id: id,
                    challengeID: challengeID,
                    secondaryToken: secondaryToken,
                    sitekey: sitekey,
                    generation: generation,
                    runtimeToken: runtimeToken
                )
            }

        case Self.turnstileErrorHandlerName:
            guard let payload = message.body as? [String: Any] else { return }
            let runtimeToken = payload["runtimeToken"] as? String ?? ""
            let errorMessage = normalizedNonEmpty(payload["message"] as? String)
                ?? "turnstile_error"
            let generation = self.generation

            Task { [weak self] in
                await self?.handleRuntimeFailure(
                    message: "cf clearance refresh turnstile error: \(errorMessage)",
                    generation: generation,
                    runtimeToken: runtimeToken
                )
            }

        default:
            return
        }
    }

    private func handleRcIntercepted(
        id: String,
        challengeID: String?,
        secondaryToken: String?,
        sitekey: String?,
        generation: UInt64,
        runtimeToken: String
    ) async {
        guard isCurrentRuntime(generation: generation, runtimeToken: runtimeToken) else {
            return
        }

        guard !isCallingRc else {
            try? await resolveRc(id: id, statusCode: 503, body: "{}")
            return
        }

        guard
            let challengeID = normalizedNonEmpty(challengeID),
            let rcURL = Self.rcEndpointURL(baseURL: session.baseURL, challengeID: challengeID)
        else {
            FireAPMManager.shared.recordBreadcrumb(
                level: "warning",
                target: Self.logTarget,
                message: "cf clearance refresh intercepted rc without challenge id"
            )
            try? await resolveRc(id: id, statusCode: 400, body: "{}")
            return
        }

        guard let effectiveSitekey = normalizedNonEmpty(sitekey) ?? normalizedTurnstileSitekey else {
            FireAPMManager.shared.recordBreadcrumb(
                level: "warning",
                target: Self.logTarget,
                message: "cf clearance refresh intercepted rc without sitekey"
            )
            try? await resolveRc(id: id, statusCode: 400, body: "{}")
            return
        }

        isCallingRc = true
        defer {
            if isCurrentRuntime(generation: generation, runtimeToken: runtimeToken) {
                isCallingRc = false
            }
        }

        do {
            let response = try await performRcRequest(
                url: rcURL,
                secondaryToken: secondaryToken,
                sitekey: effectiveSitekey
            )
            guard isCurrentRuntime(generation: generation, runtimeToken: runtimeToken) else {
                return
            }

            try await resolveRc(id: id, statusCode: response.statusCode, body: response.body)
            try await Task.sleep(for: Self.cookiePropagationDelay)

            guard
                isCurrentRuntime(generation: generation, runtimeToken: runtimeToken),
                let loginCoordinator
            else {
                return
            }

            let refreshed = try await loginCoordinator.refreshPlatformCookies()
            guard isCurrentRuntime(generation: generation, runtimeToken: runtimeToken) else {
                return
            }

            consecutiveFailureCount = 0
            session = refreshed
            FireAPMManager.shared.recordBreadcrumb(
                target: Self.logTarget,
                message: "cf clearance refresh succeeded status=\(response.statusCode)"
            )

            if let onSessionRefreshed {
                await onSessionRefreshed(refreshed)
            }
        } catch is CancellationError {
            return
        } catch {
            try? await resolveRc(id: id, statusCode: 500, body: "{}")
            await handleRuntimeFailure(
                message: "cf clearance refresh rc call failed: \(error.localizedDescription)",
                generation: generation,
                runtimeToken: runtimeToken
            )
        }
    }

    private func performRcRequest(
        url: URL,
        secondaryToken: String?,
        sitekey: String
    ) async throws -> (statusCode: Int, body: String) {
        var payload: [String: String] = ["sitekey": sitekey]
        if let secondaryToken = normalizedNonEmpty(secondaryToken) {
            payload["secondaryToken"] = secondaryToken
        }

        var request = URLRequest(
            url: url,
            cachePolicy: .reloadIgnoringLocalCacheData,
            timeoutInterval: 30
        )
        request.httpMethod = "POST"
        request.httpShouldHandleCookies = true
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(session.bootstrap.baseUrl, forHTTPHeaderField: "Origin")

        let referer = session.bootstrap.baseUrl.hasSuffix("/")
            ? session.bootstrap.baseUrl
            : "\(session.bootstrap.baseUrl)/"
        request.setValue(referer, forHTTPHeaderField: "Referer")
        request.httpBody = try JSONSerialization.data(withJSONObject: payload, options: [])

        let (data, response) = try await urlSession.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw NSError(
                domain: "FireCfClearanceRefreshService",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: "Cloudflare rc endpoint returned a non-HTTP response"]
            )
        }

        let body = String(data: data, encoding: .utf8) ?? "{}"
        return (httpResponse.statusCode, body)
    }

    private func resolveRc(id: String, statusCode: Int, body: String) async throws {
        guard let webView else { return }

        let script = "window._resolveRc(\(Self.javaScriptStringLiteral(id)), \(statusCode), \(Self.javaScriptStringLiteral(body)))"
        _ = try await evaluateJavaScript(script, in: webView)
    }

    private func evaluateJavaScript(_ script: String, in webView: WKWebView) async throws -> Any? {
        try await withCheckedThrowingContinuation { continuation in
            webView.evaluateJavaScript(script) { result, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: result)
                }
            }
        }
    }

    nonisolated private static func javaScriptStringLiteral(_ value: String) -> String {
        let payload = [value]
        guard
            let data = try? JSONSerialization.data(withJSONObject: payload, options: []),
            let json = String(data: data, encoding: .utf8),
            json.count >= 2
        else {
            let escaped = value
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "\"", with: "\\\"")
                .replacingOccurrences(of: "\n", with: "\\n")
                .replacingOccurrences(of: "\r", with: "\\r")
            return "\"\(escaped)\""
        }

        return String(json.dropFirst().dropLast())
    }

    private func handleNavigationFailure(_ error: Error) {
        let generation = self.generation
        let runtimeToken = activeRuntimeToken ?? ""
        let wasLoading = loadContinuation != nil
        resumeLoad(.failure(error))

        guard !wasLoading else { return }

        Task { [weak self] in
            await self?.handleRuntimeFailure(
                message: "cf clearance refresh navigation failed: \(error.localizedDescription)",
                generation: generation,
                runtimeToken: runtimeToken
            )
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        resumeLoad(.success(()))
    }

    func webView(
        _ webView: WKWebView,
        didFail navigation: WKNavigation!,
        withError error: Error
    ) {
        handleNavigationFailure(error)
    }

    func webView(
        _ webView: WKWebView,
        didFailProvisionalNavigation navigation: WKNavigation!,
        withError error: Error
    ) {
        handleNavigationFailure(error)
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        handleNavigationFailure(NSError(
            domain: "FireCfClearanceRefreshService",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "Cloudflare refresh WebView terminated"]
        ))
    }
}
