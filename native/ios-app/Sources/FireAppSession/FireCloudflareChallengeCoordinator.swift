import Foundation
import UIKit
import WebKit

final class FireCloudflareChallengeRuntimeHandler: CloudflareChallengeHandler, @unchecked Sendable {
    private let coordinator: FireCloudflareChallengeCoordinator

    init(sessionStore: FireSessionStore) {
        self.coordinator = FireCloudflareChallengeCoordinator(sessionStore: sessionStore)
    }

    func completeCloudflareChallenge(
        request: CloudflareChallengeRequestState
    ) -> CloudflareChallengeResultState {
        coordinator.completeSynchronously(request: request)
    }
}

final class FireCloudflareChallengeCoordinator: NSObject, @unchecked Sendable {
    private let sessionStore: FireSessionStore

    init(sessionStore: FireSessionStore) {
        self.sessionStore = sessionStore
    }

    nonisolated func completeSynchronously(
        request: CloudflareChallengeRequestState
    ) -> CloudflareChallengeResultState {
        if Thread.isMainThread {
            return CloudflareChallengeResultState(
                completed: false,
                userCancelled: false,
                freshCfClearance: nil,
                cookies: [],
                browserUserAgent: nil
            )
        }

        let semaphore = DispatchSemaphore(value: 0)
        let state = LockedChallengeResultState()
        DispatchQueue.main.async { [weak self] in
            guard let self else {
                state.set(
                    CloudflareChallengeResultState(
                        completed: false,
                        userCancelled: false,
                        freshCfClearance: nil,
                        cookies: [],
                        browserUserAgent: nil
                    )
                )
                semaphore.signal()
                return
            }

            Task { @MainActor in
                let result = await self.complete(request: request)
                state.set(result)
                semaphore.signal()
            }
        }
        semaphore.wait()
        return state.get()
    }

    @MainActor
    func completeManualVerification(originURL: String? = "https://linux.do/") async -> CloudflareChallengeResultState {
        let epoch = (try? await sessionStore.currentSessionEpoch()) ?? 0
        return await complete(
            request: CloudflareChallengeRequestState(
                operation: "login.csrf",
                requestUrl: "https://linux.do/session/csrf",
                originUrl: originURL,
                isForeground: true,
                sessionEpoch: epoch
            )
        )
    }

    @MainActor
    private func complete(
        request: CloudflareChallengeRequestState
    ) async -> CloudflareChallengeResultState {
        // Background/silent traffic must not steal focus. Rust only starts a new
        // challenge for foreground requests; this is a defensive host-side gate.
        guard request.isForeground else {
            return CloudflareChallengeResultState(
                completed: false,
                userCancelled: false,
                freshCfClearance: nil,
                cookies: [],
                browserUserAgent: nil
            )
        }

        guard let presenter = topPresenter() else {
            return CloudflareChallengeResultState(
                completed: false,
                userCancelled: false,
                freshCfClearance: nil,
                cookies: [],
                browserUserAgent: nil
            )
        }

        let snapshot = try? await sessionStore.snapshot()
        let challengeURL = challengeURL(
            request.originUrl,
            fallbackBaseURL: snapshot?.bootstrap.baseUrl
        )
        let cookieStore = WKWebsiteDataStore.default().httpCookieStore
        let existingCookies = await httpCookies(from: cookieStore)
        let baseline = challengeCookieSnapshot(from: existingCookies)
        let preservedClearanceCookies = existingCookies.filter {
            $0.name == "cf_clearance"
                && FireWebViewCookieActionSupport.matchesDeleteByName(
                    $0,
                    url: challengeURL,
                    name: "cf_clearance"
                )
        }
        FireCfClearanceRefreshService.shared.beginManualChallenge(reason: "manual_challenge_start")
        defer {
            FireCfClearanceRefreshService.shared.endManualChallenge(reason: "manual_challenge_end")
        }
        await deleteCloudflareClearanceCookies(from: cookieStore, targetURL: challengeURL)
        let controller = FireCloudflareChallengeViewController(
            url: challengeURL,
            preferredUserAgent: snapshot?.browserUserAgent,
            baselineSnapshot: baseline
        )
        let navigationController = UINavigationController(rootViewController: controller)
        navigationController.modalPresentationStyle = .fullScreen
        presenter.present(navigationController, animated: true)
        let outcome = await controller.awaitOutcome()
        switch outcome {
        case .cancelled:
            await restoreCookies(preservedClearanceCookies, in: cookieStore)
            return CloudflareChallengeResultState(
                completed: false,
                userCancelled: true,
                freshCfClearance: nil,
                cookies: [],
                browserUserAgent: nil
            )
        case let .completed(browserUserAgent, freshCfClearance):
            let loginCoordinator = FireWebViewLoginCoordinator(sessionStore: sessionStore)
            let cookies = Self.challengeResultCookies(
                (try? await loginCoordinator.platformCookiesForSessionResync()) ?? [],
                freshCfClearance: freshCfClearance
            )
            return CloudflareChallengeResultState(
                completed: true,
                userCancelled: false,
                freshCfClearance: freshCfClearance,
                cookies: cookies,
                browserUserAgent: browserUserAgent
            )
        }
    }

    static func challengeResultCookies(
        _ cookies: [PlatformCookieState],
        freshCfClearance: String
    ) -> [PlatformCookieState] {
        let acceptedClearance = freshCfClearance.trimmingCharacters(in: .whitespacesAndNewlines)
        return cookies.filter { cookie in
            guard cookie.name.caseInsensitiveCompare("cf_clearance") == .orderedSame else {
                return true
            }
            return !acceptedClearance.isEmpty
                && cookie.value.trimmingCharacters(in: .whitespacesAndNewlines) == acceptedClearance
        }
    }

    @MainActor
    private func challengeURL(_ originURL: String?, fallbackBaseURL: String?) -> URL {
        if let originURL, let url = URL(string: originURL) {
            return rootChallengeURL(from: url)
        }
        if let fallbackBaseURL, let baseURL = URL(string: fallbackBaseURL) {
            return rootChallengeURL(from: baseURL)
        }
        return URL(string: "https://linux.do/challenge")!
    }

    @MainActor
    private func rootChallengeURL(from url: URL) -> URL {
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        components?.path = "/challenge"
        components?.query = nil
        components?.fragment = nil
        return components?.url ?? url
    }

    @MainActor
    private func httpCookies(from store: WKHTTPCookieStore) async -> [HTTPCookie] {
        await withCheckedContinuation { continuation in
            store.getAllCookies { cookies in
                continuation.resume(returning: cookies)
            }
        }
    }

    @MainActor
    private func deleteCloudflareClearanceCookies(
        from store: WKHTTPCookieStore,
        targetURL: URL
    ) async {
        let cookies = await httpCookies(from: store)
        for cookie in cookies where FireWebViewCookieActionSupport.matchesDeleteByName(
            cookie,
            url: targetURL,
            name: "cf_clearance"
        ) {
            await deleteCookie(cookie, from: store)
        }
    }

    @MainActor
    private func restoreCookies(_ cookies: [HTTPCookie], in store: WKHTTPCookieStore) async {
        for cookie in cookies {
            await setCookie(cookie, in: store)
        }
    }

    @MainActor
    private func deleteCookie(_ cookie: HTTPCookie, from store: WKHTTPCookieStore) async {
        await withCheckedContinuation { continuation in
            store.delete(cookie) {
                continuation.resume()
            }
        }
    }

    @MainActor
    private func setCookie(_ cookie: HTTPCookie, in store: WKHTTPCookieStore) async {
        await withCheckedContinuation { continuation in
            store.setCookie(cookie) {
                continuation.resume()
            }
        }
    }

    @MainActor
    private func challengeCookieSnapshot(
        from cookies: [HTTPCookie]
    ) -> FireCloudflareRecoveryCookieSnapshot {
        let relevant = cookies.filter {
            $0.domain.range(of: "linux.do", options: .caseInsensitive) != nil
                && !$0.value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        let authValues = relevant
            .filter { $0.name == "_t" || $0.name == "_forum_session" }
            .sorted { $0.name < $1.name }
            .map { "\($0.name)=\($0.value)" }
        let cfValue = relevant.first(where: { $0.name == "cf_clearance" })?.value
        return FireCloudflareRecoveryCookieSnapshot(
            hasAuthCookies: authValues.contains(where: { $0.hasPrefix("_t=") })
                && authValues.contains(where: { $0.hasPrefix("_forum_session=") }),
            authFingerprint: authValues.joined(separator: ";"),
            cfClearanceFingerprint: cfValue
        )
    }

    @MainActor
    private func topPresenter() -> UIViewController? {
        let scenes = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .filter {
                $0.activationState == .foregroundActive
                    || $0.activationState == .foregroundInactive
            }
        let window = scenes
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)
            ?? scenes.flatMap(\.windows).first
        return topPresentedController(from: window?.rootViewController)
    }

    @MainActor
    private func topPresentedController(from root: UIViewController?) -> UIViewController? {
        if let navigation = root as? UINavigationController {
            return topPresentedController(from: navigation.visibleViewController)
        }
        if let tabBar = root as? UITabBarController {
            return topPresentedController(from: tabBar.selectedViewController)
        }
        if let presented = root?.presentedViewController {
            return topPresentedController(from: presented)
        }
        return root
    }
}

private final class LockedChallengeResultState: @unchecked Sendable {
    private let lock = NSLock()
    private var value = CloudflareChallengeResultState(
        completed: false,
        userCancelled: false,
        freshCfClearance: nil,
        cookies: [],
        browserUserAgent: nil
    )

    func set(_ value: CloudflareChallengeResultState) {
        lock.lock()
        defer { lock.unlock() }
        self.value = value
    }

    func get() -> CloudflareChallengeResultState {
        lock.lock()
        defer { lock.unlock() }
        return value
    }
}

private final class FireCloudflareChallengeViewController: UIViewController, WKNavigationDelegate,
    WKUIDelegate, WKHTTPCookieStoreObserver, WKScriptMessageHandler
{
    enum Outcome {
        case completed(browserUserAgent: String?, freshCfClearance: String)
        case cancelled
    }

    private static let challengeCompletionHandlerName = "fireChallengeComplete"
    private static let challengeNavigationHandlerName = "fireChallengeNavigation"
    private static let challengeMonitorScriptSource = #"""
    (function() {
      if (window.__fireCfChallengeMonitorInstalled) {
        return;
      }
      window.__fireCfChallengeMonitorInstalled = true;

      function post(name, payload) {
        try {
          if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers[name]) {
            window.webkit.messageHandlers[name].postMessage(payload || {});
          }
        } catch (error) {}
      }

      function signalNavigation(reason) {
        post('fireChallengeNavigation', { reason: reason || '' });
      }

      if (window.fetch) {
        var originalFetch = window.fetch.bind(window);
        window.fetch = function(input, init) {
          var result = originalFetch(input, init);
          try {
            var url = typeof input === 'string' ? input : ((input && input.url) || '');
            if (String(url).indexOf('/cdn-cgi/challenge-platform/') !== -1) {
              Promise.resolve(result).then(function() {
                post('fireChallengeComplete', { kind: 'fetch', url: String(url) });
              }, function() {
                post('fireChallengeComplete', { kind: 'fetch', url: String(url) });
              });
            }
          } catch (error) {}
          return result;
        };
      }

      if (window.XMLHttpRequest && window.XMLHttpRequest.prototype) {
        var originalOpen = window.XMLHttpRequest.prototype.open;
        var originalSend = window.XMLHttpRequest.prototype.send;
        window.XMLHttpRequest.prototype.open = function(method, url) {
          this.__fireCfChallengeUrl = url;
          return originalOpen.apply(this, arguments);
        };
        window.XMLHttpRequest.prototype.send = function() {
          try {
            var url = String(this.__fireCfChallengeUrl || '');
            if (url.indexOf('/cdn-cgi/challenge-platform/') !== -1) {
              this.addEventListener('loadend', function() {
                post('fireChallengeComplete', { kind: 'xhr', url: url });
              });
            }
          } catch (error) {}
          return originalSend.apply(this, arguments);
        };
      }

      window.addEventListener('beforeunload', function() {
        signalNavigation('beforeunload');
      });
      window.addEventListener('pagehide', function() {
        signalNavigation('pagehide');
      });
    })();
    """#

    private let url: URL
    private let preferredUserAgent: String?
    private let baselineSnapshot: FireCloudflareRecoveryCookieSnapshot
    private var webView: WKWebView?
    private var completionOverlay: UIView?
    private var continuation: CheckedContinuation<Outcome, Never>?
    private var completionPollingTask: Task<Void, Never>?
    private var finished = false
    /// Once CF UI was observed, bare `/challenge` navigation is treated as the
    /// post-pass origin fallback (Discourse 404) and must stay covered.
    private var hasSeenActiveChallenge = false
    private var observedFreshClearance = false

    init(
        url: URL,
        preferredUserAgent: String?,
        baselineSnapshot: FireCloudflareRecoveryCookieSnapshot
    ) {
        self.url = url
        self.preferredUserAgent = preferredUserAgent
        self.baselineSnapshot = baselineSnapshot
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .fullScreen
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = FireTheme.uiCanvas
        title = "Cloudflare 验证"

        navigationItem.leftBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .close,
            target: self,
            action: #selector(closeTapped)
        )

        let configuration = FireWebViewBrowserProfile.makeConfiguration()
        let monitorScript = WKUserScript(
            source: Self.challengeMonitorScriptSource,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: false
        )
        configuration.userContentController.addUserScript(monitorScript)
        configuration.userContentController.add(
            self,
            name: Self.challengeCompletionHandlerName
        )
        configuration.userContentController.add(
            self,
            name: Self.challengeNavigationHandlerName
        )
        let webView = WKWebView(frame: .zero, configuration: configuration)
        FireWebViewBrowserProfile.configure(webView, preferredUserAgent: preferredUserAgent)
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(webView)

        // Covers Discourse's post-pass `/challenge` 404 so users never see
        // "page does not exist" while clearance is finalized (fluxdo behavior).
        let overlay = UIView()
        overlay.translatesAutoresizingMaskIntoConstraints = false
        overlay.backgroundColor = FireTheme.uiCanvas
        overlay.isHidden = true
        let spinner = UIActivityIndicatorView(style: .large)
        spinner.translatesAutoresizingMaskIntoConstraints = false
        spinner.startAnimating()
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.text = "正在完成验证…"
        label.textAlignment = .center
        label.textColor = .secondaryLabel
        label.font = .preferredFont(forTextStyle: .body)
        overlay.addSubview(spinner)
        overlay.addSubview(label)
        view.addSubview(overlay)

        NSLayoutConstraint.activate([
            webView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            webView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            webView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            overlay.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            overlay.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            overlay.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            overlay.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            spinner.centerXAnchor.constraint(equalTo: overlay.centerXAnchor),
            spinner.centerYAnchor.constraint(equalTo: overlay.centerYAnchor, constant: -16),
            label.topAnchor.constraint(equalTo: spinner.bottomAnchor, constant: 12),
            label.leadingAnchor.constraint(equalTo: overlay.leadingAnchor, constant: 24),
            label.trailingAnchor.constraint(equalTo: overlay.trailingAnchor, constant: -24),
        ])
        configuration.websiteDataStore.httpCookieStore.add(self)
        self.webView = webView
        self.completionOverlay = overlay
        startCompletionPolling()
        webView.load(URLRequest(url: url))
    }

    func awaitOutcome() async -> Outcome {
        await withCheckedContinuation { continuation in
            self.continuation = continuation
        }
    }

    @objc
    private func closeTapped() {
        finish(.cancelled)
    }

    private func finish(_ outcome: Outcome) {
        guard !finished else { return }
        finished = true
        completionPollingTask?.cancel()
        completionPollingTask = nil
        webView?.configuration.websiteDataStore.httpCookieStore.remove(self)
        webView?.configuration.userContentController.removeScriptMessageHandler(
            forName: Self.challengeCompletionHandlerName
        )
        webView?.configuration.userContentController.removeScriptMessageHandler(
            forName: Self.challengeNavigationHandlerName
        )
        let completion = continuation
        continuation = nil
        (navigationController ?? self).dismiss(animated: true) {
            completion?.resume(returning: outcome)
        }
    }

    private func startCompletionPolling() {
        completionPollingTask?.cancel()
        completionPollingTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                guard !Task.isCancelled else { return }
                await self?.evaluateCompletion()
            }
        }
    }

    func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        Task { @MainActor in
            await evaluateCompletion()
        }
    }

    func cookiesDidChange(in cookieStore: WKHTTPCookieStore) {
        Task { @MainActor in
            await evaluateCompletion()
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        Task { @MainActor in
            await noteActiveChallengeIfPresent(in: webView)
            await evaluateCompletion()
        }
    }

    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        Task { @MainActor in
            // CF often reloads bare `/challenge` after pass; cover before 404 paints.
            if self.isBareChallengeURL(webView.url) && self.hasSeenActiveChallenge {
                self.showCompletionOverlay()
            }
            await self.evaluateCompletion()
        }
    }

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
    ) {
        if navigationAction.targetFrame?.isMainFrame != false,
           isBareChallengeURL(navigationAction.request.url),
           hasSeenActiveChallenge || observedFreshClearance
        {
            // fluxdo: post-pass navigation back to /challenge is origin fallback.
            showCompletionOverlay()
        }
        decisionHandler(.allow)
    }

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationResponse: WKNavigationResponse,
        decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void
    ) {
        let response = navigationResponse.response
        let http = response as? HTTPURLResponse
        let responseURL = http?.url ?? response.url
        if navigationResponse.isForMainFrame,
           isBareChallengeURL(responseURL),
           let status = http?.statusCode,
           status == 404,
           !Self.hasCloudflareMitigatedChallenge(http)
        {
            // Source-site 404 on /challenge == CF passed. Cancel so Discourse's
            // "page does not exist" body never becomes visible.
            showCompletionOverlay()
            decisionHandler(.cancel)
            Task { @MainActor in
                await self.finishIfFreshClearanceAvailable(
                    reason: "main frame /challenge returned source 404"
                )
            }
            return
        }
        decisionHandler(.allow)
    }

    func webView(
        _ webView: WKWebView,
        createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction,
        windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        guard navigationAction.targetFrame == nil else {
            return nil
        }
        webView.load(navigationAction.request)
        return nil
    }

    @MainActor
    private func evaluateCompletion() async {
        guard let webView, !finished else { return }

        let cookies = await withCheckedContinuation { continuation in
            webView.configuration.websiteDataStore.httpCookieStore.getAllCookies { cookies in
                continuation.resume(returning: cookies)
            }
        }
        let snapshot = challengeCookieSnapshot(from: cookies)
        guard
            snapshot.hasNewCloudflareClearance(comparedTo: baselineSnapshot),
            let freshCfClearance = freshCloudflareClearanceValue(
                from: cookies,
                comparedTo: baselineSnapshot
            )
        else {
            return
        }
        observedFreshClearance = true

        let pageState = (try? await challengePageState(in: webView)) ?? .activeChallenge
        switch pageState {
        case .activeChallenge:
            hasSeenActiveChallenge = true
            return
        case .originFallbackNotFound:
            // Post-pass Discourse 404 for /challenge — cover and finish.
            showCompletionOverlay()
        case .passedNonChallenge:
            // Non-challenge page (or already covered). Safe to finish.
            if isBareChallengeURL(webView.url) || hasSeenActiveChallenge {
                showCompletionOverlay()
            }
        }

        finish(.completed(browserUserAgent: webView.customUserAgent, freshCfClearance: freshCfClearance))
    }

    @MainActor
    private func finishIfFreshClearanceAvailable(reason: String) async {
        guard !finished else { return }
        guard let webView else { return }
        let cookies: [HTTPCookie] = await withCheckedContinuation { continuation in
            webView.configuration.websiteDataStore.httpCookieStore.getAllCookies { cookies in
                continuation.resume(returning: cookies)
            }
        }
        guard
            let freshCfClearance = freshCloudflareClearanceValue(
                from: cookies,
                comparedTo: baselineSnapshot
            )
        else {
            // Keep overlay up and let polling retry once Set-Cookie settles.
            return
        }
        observedFreshClearance = true
        FireAPMManager.shared.recordBreadcrumb(
            level: "info",
            target: "auth.cf",
            message: "challenge complete via \(reason)"
        )
        finish(.completed(browserUserAgent: webView.customUserAgent, freshCfClearance: freshCfClearance))
    }

    @MainActor
    private func noteActiveChallengeIfPresent(in webView: WKWebView) async {
        let state = (try? await challengePageState(in: webView)) ?? .passedNonChallenge
        if state == .activeChallenge {
            hasSeenActiveChallenge = true
        }
    }

    @MainActor
    private func showCompletionOverlay() {
        guard let completionOverlay else { return }
        completionOverlay.isHidden = false
        view.bringSubviewToFront(completionOverlay)
    }

    private func isBareChallengeURL(_ url: URL?) -> Bool {
        guard let url else { return false }
        guard let host = url.host?.lowercased(), host.contains("linux.do") else {
            return false
        }
        let path = url.path.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        // bare `/challenge` only — ignore query-bearing challenge platform URLs
        return path == "challenge" && (url.query?.isEmpty ?? true)
    }

    private static func hasCloudflareMitigatedChallenge(_ response: HTTPURLResponse?) -> Bool {
        guard let response else { return false }
        for (key, value) in response.allHeaderFields {
            guard String(describing: key).caseInsensitiveCompare("cf-mitigated") == .orderedSame else {
                continue
            }
            return String(describing: value).localizedCaseInsensitiveContains("challenge")
        }
        return false
    }

    private enum ChallengePageState {
        case activeChallenge
        case originFallbackNotFound
        case passedNonChallenge
    }

    private func freshCloudflareClearanceValue(
        from cookies: [HTTPCookie],
        comparedTo baseline: FireCloudflareRecoveryCookieSnapshot
    ) -> String? {
        let values = cookies
            .filter {
                $0.domain.range(of: "linux.do", options: .caseInsensitive) != nil
                    && $0.name == "cf_clearance"
            }
            .map { $0.value.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        if let oldValue = baseline.cfClearanceFingerprint {
            return values.first { $0 != oldValue }
        }
        return values.first
    }

    private func challengeCookieSnapshot(
        from cookies: [HTTPCookie]
    ) -> FireCloudflareRecoveryCookieSnapshot {
        let relevant = cookies.filter {
            $0.domain.range(of: "linux.do", options: .caseInsensitive) != nil
                && !$0.value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        let authValues = relevant
            .filter { $0.name == "_t" || $0.name == "_forum_session" }
            .sorted { $0.name < $1.name }
            .map { "\($0.name)=\($0.value)" }
        let cfValue = relevant.first(where: { $0.name == "cf_clearance" })?.value
        return FireCloudflareRecoveryCookieSnapshot(
            hasAuthCookies: authValues.contains(where: { $0.hasPrefix("_t=") })
                && authValues.contains(where: { $0.hasPrefix("_forum_session=") }),
            authFingerprint: authValues.joined(separator: ";"),
            cfClearanceFingerprint: cfValue
        )
    }

    private func challengePageState(in webView: WKWebView) async throws -> ChallengePageState {
        let value = try await webView.evaluateJavaScript(
            """
            (function() {
              try {
                var title = (document.title || '').toLowerCase();
                var html = (document.documentElement && document.documentElement.outerHTML || '')
                  .slice(0, 12000)
                  .toLowerCase();
                var originNotFound =
                  html.indexOf('page-not-found') !== -1 ||
                  html.indexOf('discourse-no-results') !== -1 ||
                  html.indexOf('"errortype":"notfound"') !== -1 ||
                  html.indexOf('404-body') !== -1 ||
                  html.indexOf('exist or is private') !== -1 ||
                  html.indexOf('page you requested') !== -1 ||
                  title.indexOf('page not found') !== -1 ||
                  title.indexOf('oops') !== -1;
                if (originNotFound) {
                  return 'origin_404';
                }
                var active = html.indexOf('cf_chl_opt') !== -1 ||
                  html.indexOf('cf-turnstile') !== -1 ||
                  html.indexOf('challenge-running') !== -1 ||
                  html.indexOf('challenge-stage') !== -1 ||
                  (html.indexOf('challenge-platform') !== -1 && html.indexOf('cloudflare') !== -1) ||
                  (title.indexOf('just a moment') !== -1) ||
                  (html.indexOf('just a moment') !== -1 &&
                    (html.indexOf('cloudflare') !== -1 || html.indexOf('cf-challenge') !== -1));
                return active ? 'active' : 'passed';
              } catch (error) {
                return 'active';
              }
            })();
            """
        )
        switch (value as? String)?.lowercased() {
        case "origin_404":
            return .originFallbackNotFound
        case "passed":
            return .passedNonChallenge
        default:
            return .activeChallenge
        }
    }
}
