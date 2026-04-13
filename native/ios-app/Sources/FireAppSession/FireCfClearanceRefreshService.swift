import Foundation
import WebKit

@MainActor
final class FireCfClearanceRefreshService: NSObject, WKNavigationDelegate {
    static let shared = FireCfClearanceRefreshService()

    private static let refreshInterval: Duration = .seconds(240)
    private static let refreshURL = URL(string: "https://linux.do/")!

    private weak var loginCoordinator: FireWebViewLoginCoordinator?
    private var session: SessionState = .placeholder()
    private var sceneActive = false
    private var interactiveRecoveryActive = false
    private var refreshTask: Task<Void, Never>?
    private var webView: WKWebView?
    private var loadContinuation: CheckedContinuation<Void, Error>?

    func updateSession(
        _ session: SessionState,
        loginCoordinator: FireWebViewLoginCoordinator
    ) {
        self.session = session
        self.loginCoordinator = loginCoordinator
        reconfigureLoop(reason: "session_update")
    }

    func setSceneActive(_ active: Bool) {
        sceneActive = active
        reconfigureLoop(reason: active ? "scene_active" : "scene_inactive")
    }

    func setInteractiveRecoveryActive(_ active: Bool) {
        interactiveRecoveryActive = active
        reconfigureLoop(reason: active ? "interactive_recovery_started" : "interactive_recovery_ended")
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

    private var shouldRun: Bool {
        Self.shouldAutoRefresh(
            session: session,
            sceneActive: sceneActive,
            interactiveRecoveryActive: interactiveRecoveryActive
        )
    }

    private func reconfigureLoop(reason: String) {
        if shouldRun {
            guard refreshTask == nil else { return }
            FireAPMManager.shared.recordBreadcrumb(
                target: "cf.refresh",
                message: "cf clearance refresh started reason=\(reason)"
            )
            refreshTask = Task { [weak self] in
                await self?.runRefreshLoop()
            }
        } else {
            refreshTask?.cancel()
            refreshTask = nil
            tearDownWebView()
            FireAPMManager.shared.recordBreadcrumb(
                target: "cf.refresh",
                message: "cf clearance refresh stopped reason=\(reason)"
            )
        }
    }

    private func runRefreshLoop() async {
        defer {
            refreshTask = nil
            if !shouldRun {
                tearDownWebView()
            }
        }

        while !Task.isCancelled && shouldRun {
            await performRefreshCycle()
            do {
                try await Task.sleep(for: Self.refreshInterval)
            } catch {
                break
            }
        }
    }

    private func performRefreshCycle() async {
        guard shouldRun, let loginCoordinator else {
            return
        }

        do {
            try await loadRefreshPage()
            let refreshed = try await loginCoordinator.refreshPlatformCookies()
            session = refreshed
            FireAPMManager.shared.recordBreadcrumb(
                target: "cf.refresh",
                message: "cf clearance refresh cycle succeeded"
            )
        } catch {
            FireAPMManager.shared.recordBreadcrumb(
                level: "warning",
                target: "cf.refresh",
                message: "cf clearance refresh cycle failed: \(error.localizedDescription)"
            )
        }
    }

    private func ensureWebView() -> WKWebView {
        if let webView {
            return webView
        }

        let configuration = WKWebViewConfiguration()
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
        webView?.stopLoading()
        webView?.navigationDelegate = nil
        webView = nil
    }

    private func loadRefreshPage() async throws {
        let webView = ensureWebView()
        let request = URLRequest(
            url: Self.refreshURL,
            cachePolicy: .reloadIgnoringLocalCacheData,
            timeoutInterval: 30
        )
        try await withCheckedThrowingContinuation { continuation in
            if let loadContinuation {
                loadContinuation.resume(throwing: CancellationError())
            }
            loadContinuation = continuation
            webView.load(request)
        }
    }

    private func resumeLoad(_ result: Result<Void, Error>) {
        guard let loadContinuation else { return }
        loadContinuation.resume(with: result)
        self.loadContinuation = nil
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        resumeLoad(.success(()))
    }

    func webView(
        _ webView: WKWebView,
        didFail navigation: WKNavigation!,
        withError error: Error
    ) {
        resumeLoad(.failure(error))
    }

    func webView(
        _ webView: WKWebView,
        didFailProvisionalNavigation navigation: WKNavigation!,
        withError error: Error
    ) {
        resumeLoad(.failure(error))
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        resumeLoad(.failure(NSError(
            domain: "FireCfClearanceRefreshService",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "Cloudflare refresh WebView terminated"]
        )))
    }
}
