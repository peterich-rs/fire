import UIKit
import WebKit

/// Headless (logic-only) external OAuth login driven by a hidden WKWebView.
///
/// Default UX keeps the WebView off-screen while native loading is shown.
/// If the IdP requires interaction, the host can `promote(from:)` the same WebView.
@MainActor
final class FireHeadlessExternalLoginEngine: NSObject {
    enum Outcome: Equatable {
        case authenticated
        case needsUserInteraction
        case failed(String)
        case cancelled
    }

    let method: FireExternalLoginMethod

    private let viewModel: FireAppViewModel
    private let scriptMessageProxy = FireHeadlessScriptMessageProxy()
    private var webView: WKWebView?
    private var hostConstraints: [NSLayoutConstraint] = []
    private var cookiePollTimer: Timer?
    private var softTimeoutWorkItem: DispatchWorkItem?
    private var hardTimeoutWorkItem: DispatchWorkItem?
    private var interactionWatchWorkItem: DispatchWorkItem?
    private var didAutoStart = false
    private var hasFinished = false
    private var hasAuthCandidate = false
    private var isPromoted = false
    private weak var promotedController: FirePromotedExternalLoginViewController?
    private weak var hostView: UIView?

    private let loginURL = URL(string: "https://linux.do/login")!
    /// Quiet headless window before we consider promoting for user interaction.
    private let softTimeoutSeconds: TimeInterval = 12
    /// Absolute ceiling for a headless/promoted attempt.
    private let hardTimeoutSeconds: TimeInterval = 50
    /// How long we may sit on an IdP host before asking the user to take over.
    private let interactionGraceSeconds: TimeInterval = 2.5

    var onOutcome: ((Outcome) -> Void)?

    init(method: FireExternalLoginMethod, viewModel: FireAppViewModel) {
        self.method = method
        self.viewModel = viewModel
        super.init()
    }

    var currentWebView: WKWebView? { webView }

    func start(in hostView: UIView) {
        precondition(webView == nil, "engine already started")
        self.hostView = hostView

        scriptMessageProxy.onMessage = { [weak self] message in
            self?.handleScriptMessage(message)
        }

        let configuration = FireWebViewBrowserProfile.makeLoginConfiguration(
            credential: viewModel.savedLoginCredential,
            messageHandler: scriptMessageProxy
        )
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.allowsBackForwardNavigationGestures = false
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.isUserInteractionEnabled = false
        webView.alpha = 0.01
        FireWebViewBrowserProfile.configure(
            webView,
            preferredUserAgent: viewModel.session.browserUserAgent
        )
        self.webView = webView

        // Keep the view in the hierarchy with a real size so WebKit does not throttle JS,
        // but park it far off-screen so the user only sees native loading.
        webView.translatesAutoresizingMaskIntoConstraints = false
        hostView.insertSubview(webView, at: 0)
        let constraints = [
            webView.widthAnchor.constraint(equalToConstant: 390),
            webView.heightAnchor.constraint(equalToConstant: 844),
            webView.leadingAnchor.constraint(equalTo: hostView.leadingAnchor, constant: -5000),
            webView.topAnchor.constraint(equalTo: hostView.topAnchor),
        ]
        NSLayoutConstraint.activate(constraints)
        hostConstraints = constraints

        scheduleTimeouts()
        startCookiePolling()

        Task { [weak self] in
            guard let self else { return }
            await self.primeAndLoad()
        }
    }

    func cancel() {
        finish(.cancelled)
    }

    /// Move the same WebView into a visible full-screen host so the user can finish OAuth.
    func promote(from presenter: UIViewController) {
        guard !hasFinished, !isPromoted, let webView else { return }
        isPromoted = true
        softTimeoutWorkItem?.cancel()
        interactionWatchWorkItem?.cancel()

        NSLayoutConstraint.deactivate(hostConstraints)
        hostConstraints = []
        webView.removeFromSuperview()
        webView.alpha = 1
        webView.isUserInteractionEnabled = true

        let controller = FirePromotedExternalLoginViewController(
            webView: webView,
            title: Self.promotedTitle(for: method)
        )
        controller.onClose = { [weak self] in
            self?.cancel()
        }
        promotedController = controller
        presenter.present(controller, animated: true)

        FireAPMManager.shared.recordBreadcrumb(
            level: "info",
            target: "auth.login",
            message: "headless external login promoted method=\(method.rawValue)"
        )
    }

    func teardown() {
        softTimeoutWorkItem?.cancel()
        hardTimeoutWorkItem?.cancel()
        interactionWatchWorkItem?.cancel()
        cookiePollTimer?.invalidate()
        cookiePollTimer = nil

        if let promotedController, promotedController.presentingViewController != nil {
            promotedController.dismiss(animated: false)
        }
        promotedController = nil

        if let webView {
            [
                FireLoginScripts.loginCredentialsMessageName,
                FireLoginScripts.fingerprintDoneMessageName,
            ].forEach { name in
                webView.configuration.userContentController.removeScriptMessageHandler(forName: name)
            }
            webView.navigationDelegate = nil
            webView.uiDelegate = nil
            webView.stopLoading()
            webView.removeFromSuperview()
        }
        webView = nil
        hostConstraints = []
        hostView = nil
        onOutcome = nil
    }

    private func primeAndLoad() async {
        guard let webView, !hasFinished else { return }
        do {
            let loginCoordinator = try await viewModel.loginCoordinatorForDialog()
            try await loginCoordinator.primeCookies(
                into: webView,
                targetURL: URL(string: "https://linux.do/")
            )
        } catch {
            FireAPMManager.shared.recordBreadcrumb(
                level: "warn",
                target: "auth.login",
                message: "headless external primeCookies failed: \(error.localizedDescription)"
            )
        }
        guard !hasFinished else { return }
        webView.load(URLRequest(url: loginURL))
    }

    private func scheduleTimeouts() {
        let soft = DispatchWorkItem { [weak self] in
            guard let self, !self.hasFinished else { return }
            if self.hasAuthCandidate { return }
            if self.isPromoted { return }
            // Soft timeout: ask host to show the WebView rather than failing immediately.
            self.emitNeedsInteraction(reason: "soft_timeout")
        }
        softTimeoutWorkItem = soft
        DispatchQueue.main.asyncAfter(deadline: .now() + softTimeoutSeconds, execute: soft)

        let hard = DispatchWorkItem { [weak self] in
            guard let self, !self.hasFinished else { return }
            self.finish(.failed("自动登录超时，请手动登录"))
        }
        hardTimeoutWorkItem = hard
        DispatchQueue.main.asyncAfter(deadline: .now() + hardTimeoutSeconds, execute: hard)
    }

    private func startCookiePolling() {
        cookiePollTimer?.invalidate()
        cookiePollTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.checkForAuthToken()
            }
        }
    }

    private func checkForAuthToken() {
        guard let webView, !hasFinished else { return }
        webView.configuration.websiteDataStore.httpCookieStore.getAllCookies { [weak self] cookies in
            Task { @MainActor in
                guard let self, !self.hasFinished else { return }

                if await self.pageHasActiveCloudflareChallenge(in: webView) {
                    // Need a visible surface to complete interactive CF.
                    if !self.isPromoted {
                        self.emitNeedsInteraction(reason: "active_cf_page")
                    } else {
                        do {
                            try await self.viewModel.recoverLoginCloudflareChallenge(in: webView)
                            webView.load(URLRequest(url: URL(string: "https://linux.do/")!))
                        } catch {
                            FireAPMManager.shared.recordBreadcrumb(
                                level: "warn",
                                target: "auth.login",
                                message: "headless oauth CF recover failed: \(error.localizedDescription)"
                            )
                        }
                    }
                    return
                }

                let hasAuth = cookies.contains { $0.name == "_t" && !$0.value.isEmpty }
                    && cookies.contains { $0.name == "_forum_session" && !$0.value.isEmpty }
                guard hasAuth else {
                    self.hasAuthCandidate = false
                    self.watchForInteractionIfNeeded(url: webView.url)
                    return
                }
                self.hasAuthCandidate = true
                self.interactionWatchWorkItem?.cancel()

                do {
                    let readiness = try await self.viewModel.probeLoginSyncReadiness(from: webView)
                    guard readiness.isReady else {
                        FireAPMManager.shared.recordBreadcrumb(
                            level: "info",
                            target: "auth.login",
                            message: "headless oauth waiting username=\(readiness.username ?? "nil") auth=\(readiness.hasAuthCookies) bootstrap=\(readiness.hasBootstrapHTML)"
                        )
                        return
                    }
                } catch {
                    FireAPMManager.shared.recordBreadcrumb(
                        level: "warn",
                        target: "auth.login",
                        message: "headless oauth probe failed: \(error.localizedDescription)"
                    )
                    return
                }

                self.finish(.authenticated)
            }
        }
    }

    private func pageHasActiveCloudflareChallenge(in webView: WKWebView) async -> Bool {
        await withCheckedContinuation { continuation in
            webView.evaluateJavaScript(FireLoginScripts.hasActiveCloudflareChallenge) { result, _ in
                continuation.resume(returning: (result as? Bool) ?? false)
            }
        }
    }

    private func watchForInteractionIfNeeded(url: URL?) {
        guard !isPromoted, !hasFinished else { return }
        guard Self.looksLikeIdentityProvider(url, method: method) else {
            interactionWatchWorkItem?.cancel()
            interactionWatchWorkItem = nil
            return
        }
        guard interactionWatchWorkItem == nil else { return }

        let work = DispatchWorkItem { [weak self] in
            guard let self, !self.hasFinished, !self.isPromoted else { return }
            self.emitNeedsInteraction(reason: "idp_dwell")
        }
        interactionWatchWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + interactionGraceSeconds, execute: work)
    }

    private func emitNeedsInteraction(reason: String) {
        guard !hasFinished, !isPromoted else { return }
        FireAPMManager.shared.recordBreadcrumb(
            level: "info",
            target: "auth.login",
            message: "headless external login needs interaction method=\(method.rawValue) reason=\(reason) url=\(webView?.url?.absoluteString ?? "nil")"
        )
        onOutcome?(.needsUserInteraction)
    }

    private func finish(_ outcome: Outcome) {
        guard !hasFinished else { return }
        hasFinished = true
        softTimeoutWorkItem?.cancel()
        hardTimeoutWorkItem?.cancel()
        interactionWatchWorkItem?.cancel()
        cookiePollTimer?.invalidate()
        cookiePollTimer = nil
        onOutcome?(outcome)
    }

    private func attemptAutoStartIfNeeded(in webView: WKWebView) {
        guard !didAutoStart, !hasFinished else { return }
        guard Self.isLinuxDoLoginPage(webView.url) else { return }
        didAutoStart = true
        let script = FireExternalLoginScripts.autoStart(method)
        webView.evaluateJavaScript(script) { _, error in
            if let error, !FireLoginScripts.isBenignEvaluateJavaScriptError(error) {
                FireAPMManager.shared.recordBreadcrumb(
                    level: "warn",
                    target: "auth.login",
                    message: "headless auto-start failed method=\(self.method.rawValue) error=\(error.localizedDescription)"
                )
            }
        }
    }

    private func handleScriptMessage(_ message: WKScriptMessage) {
        if message.name == FireLoginScripts.fingerprintDoneMessageName {
            viewModel.recordLoginFingerprintDone()
        }
    }

    private static func promotedTitle(for method: FireExternalLoginMethod) -> String {
        switch method {
        case .google: return "请完成 Google 登录"
        case .github: return "请完成 GitHub 登录"
        case .x: return "请完成 X 登录"
        case .discord: return "请完成 Discord 登录"
        case .apple: return "请完成 Apple 登录"
        case .passkey: return "请完成通行密钥登录"
        }
    }

    private static func isLinuxDoLoginPage(_ url: URL?) -> Bool {
        guard let url else { return false }
        guard let host = url.host?.lowercased(), host == "linux.do" || host.hasSuffix(".linux.do") else {
            return false
        }
        let path = url.path.lowercased()
        return path == "/login" || path.hasPrefix("/login/")
    }

    private static func looksLikeIdentityProvider(_ url: URL?, method: FireExternalLoginMethod) -> Bool {
        guard let host = url?.host?.lowercased() else { return false }
        switch method {
        case .google:
            // Stay strict — generic google.com hosts (fonts/static) must not force promotion.
            return host == "accounts.google.com"
                || host.hasSuffix(".accounts.google.com")
                || host.contains("accounts.google.")
        case .github:
            return host == "github.com" || host.hasSuffix(".github.com")
        case .x:
            return host.contains("twitter.com") || host.contains("x.com")
        case .discord:
            return host.contains("discord.com")
        case .apple:
            return host.contains("apple.com")
        case .passkey:
            return false
        }
    }
}

extension FireHeadlessExternalLoginEngine: WKNavigationDelegate, WKUIDelegate {
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        attemptAutoStartIfNeeded(in: webView)
        watchForInteractionIfNeeded(url: webView.url)
        // After Google/OAuth returns to linux.do, probe auth immediately.
        checkForAuthToken()
    }

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
    ) {
        watchForInteractionIfNeeded(url: navigationAction.request.url)
        decisionHandler(.allow)
    }

    func webView(
        _ webView: WKWebView,
        createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction,
        windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        // Keep OAuth in the single headless/promoted WebView (same as manual browser path).
        if navigationAction.targetFrame == nil {
            webView.load(navigationAction.request)
        }
        return nil
    }
}

/// Minimal visible host used when headless OAuth needs the user.
@MainActor
final class FirePromotedExternalLoginViewController: UIViewController {
    var onClose: (() -> Void)?

    private let managedWebView: WKWebView
    private let chromeTitle: String
    private let navigationBar = UINavigationBar()

    init(webView: WKWebView, title: String) {
        self.managedWebView = webView
        self.chromeTitle = title
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

        navigationBar.translatesAutoresizingMaskIntoConstraints = false
        navigationBar.tintColor = FireTheme.uiAccent
        let item = UINavigationItem(title: chromeTitle)
        item.leftBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .close,
            target: self,
            action: #selector(closeTapped)
        )
        navigationBar.items = [item]

        managedWebView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(navigationBar)
        view.addSubview(managedWebView)

        NSLayoutConstraint.activate([
            navigationBar.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            navigationBar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            navigationBar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            managedWebView.topAnchor.constraint(equalTo: navigationBar.bottomAnchor),
            managedWebView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            managedWebView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            managedWebView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }

    @objc private func closeTapped() {
        onClose?()
    }
}

private final class FireHeadlessScriptMessageProxy: NSObject, WKScriptMessageHandler {
    var onMessage: ((WKScriptMessage) -> Void)?

    func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        onMessage?(message)
    }
}
