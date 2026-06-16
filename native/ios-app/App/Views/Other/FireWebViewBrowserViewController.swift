import Combine
import UIKit
import WebKit

/// Full-screen WebView browser for login fallback paths such as OAuth,
/// Passkey, and forgot password.
@MainActor
final class FireWebViewBrowserViewController: UIViewController, WKNavigationDelegate, WKUIDelegate {
    private let initialURL: URL
    private let viewModel: FireAppViewModel
    private let scriptMessageProxy = FireBrowserScriptMessageProxy()
    private var webView: WKWebView!
    private var navigationBar: UINavigationBar!
    private var progressView: UIProgressView!
    private var observations: [NSKeyValueObservation] = []
    private var cookiePollTimer: Timer?
    private var hasFinalizedLogin = false
    private var cancellables = Set<AnyCancellable>()

    init(url: URL, viewModel: FireAppViewModel) {
        self.initialURL = url
        self.viewModel = viewModel
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        cookiePollTimer?.invalidate()
        observations.removeAll()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        setupNavigationBar()
        setupWebView()
        setupProgressView()
        observeWebView()
        observeViewModelErrors()
        loadURL()
        startCookiePolling()
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        if isBeingDismissed || navigationController?.isBeingDismissed == true {
            tearDownWebView()
        }
    }

    private func setupNavigationBar() {
        navigationBar = UINavigationBar()
        navigationBar.translatesAutoresizingMaskIntoConstraints = false

        let navigationItem = UINavigationItem(title: initialURL.host ?? "linux.do")
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .close,
            target: self,
            action: #selector(closeTapped)
        )
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .refresh,
            target: self,
            action: #selector(reloadTapped)
        )
        navigationBar.items = [navigationItem]
        view.addSubview(navigationBar)

        NSLayoutConstraint.activate([
            navigationBar.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            navigationBar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            navigationBar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])
    }

    private func tearDownWebView() {
        cookiePollTimer?.invalidate()
        observations.removeAll()
        [
            FireLoginScripts.loginCredentialsMessageName,
            FireLoginScripts.fingerprintDoneMessageName,
        ].forEach { name in
            webView?.configuration.userContentController.removeScriptMessageHandler(forName: name)
        }
        webView?.navigationDelegate = nil
        webView?.uiDelegate = nil
        webView?.stopLoading()
    }

    private func setupWebView() {
        scriptMessageProxy.onMessage = { [weak self] message in
            Task { @MainActor in
                self?.handleScriptMessage(message)
            }
        }

        let configuration = FireWebViewBrowserProfile.makeLoginConfiguration(
            credential: viewModel.savedLoginCredential,
            messageHandler: scriptMessageProxy
        )
        webView = WKWebView(frame: .zero, configuration: configuration)
        webView.translatesAutoresizingMaskIntoConstraints = false
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.allowsBackForwardNavigationGestures = true
        FireWebViewBrowserProfile.configure(
            webView,
            preferredUserAgent: viewModel.session.browserUserAgent
        )
        view.addSubview(webView)

        NSLayoutConstraint.activate([
            webView.topAnchor.constraint(equalTo: navigationBar.bottomAnchor),
            webView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            webView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }

    private func setupProgressView() {
        progressView = UIProgressView(progressViewStyle: .bar)
        progressView.translatesAutoresizingMaskIntoConstraints = false
        progressView.progressTintColor = .systemOrange
        progressView.trackTintColor = .clear
        progressView.isHidden = true
        view.addSubview(progressView)

        NSLayoutConstraint.activate([
            progressView.topAnchor.constraint(equalTo: webView.topAnchor),
            progressView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            progressView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            progressView.heightAnchor.constraint(equalToConstant: 2),
        ])
    }

    private func observeWebView() {
        observations = [
            webView.observe(\.estimatedProgress, options: [.initial, .new]) { [weak self] webView, _ in
                Task { @MainActor in
                    self?.progressView.progress = Float(webView.estimatedProgress)
                    self?.progressView.isHidden = webView.estimatedProgress >= 1.0
                }
            },
            webView.observe(\.title, options: [.initial, .new]) { [weak self] webView, _ in
                Task { @MainActor in
                    self?.navigationBar.topItem?.title = webView.title ?? self?.initialURL.host ?? "linux.do"
                }
            },
        ]
    }

    private func observeViewModelErrors() {
        viewModel.$errorMessage
            .receive(on: RunLoop.main)
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .sink { [weak self] message in
                guard let self, self.hasFinalizedLogin else { return }
                self.hasFinalizedLogin = false
                self.startCookiePolling()
                self.showErrorAlert(message)
            }
            .store(in: &cancellables)
    }

    private func loadURL() {
        Task { [weak self] in
            guard let self else { return }
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
                    message: "browser fallback cookie priming failed: \(error.localizedDescription)"
                )
            }

            webView.load(URLRequest(url: initialURL))
        }
    }

    private func startCookiePolling() {
        cookiePollTimer?.invalidate()
        cookiePollTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.checkForAuthToken()
            }
        }
    }

    private func checkForAuthToken() {
        webView.configuration.websiteDataStore.httpCookieStore.getAllCookies { [weak self] cookies in
            Task { @MainActor in
                guard let self, !self.hasFinalizedLogin else { return }
                let hasAuth = cookies.contains { $0.name == "_t" && !$0.value.isEmpty }
                guard hasAuth else { return }

                do {
                    let readiness = try await self.viewModel.probeLoginSyncReadiness(from: self.webView)
                    guard readiness.isReady else { return }
                } catch {
                    return
                }

                self.hasFinalizedLogin = true
                self.cookiePollTimer?.invalidate()
                self.viewModel.completeLogin(from: self.webView)
            }
        }
    }

    private func handleScriptMessage(_ message: WKScriptMessage) {
        switch message.name {
        case FireLoginScripts.fingerprintDoneMessageName:
            viewModel.recordLoginFingerprintDone()
        case FireLoginScripts.loginCredentialsMessageName:
            break
        default:
            break
        }
    }

    private func showErrorAlert(_ message: String) {
        let alert = UIAlertController(
            title: "登录同步失败",
            message: message,
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "重试", style: .default))
        present(alert, animated: true)
    }

    @objc private func closeTapped() {
        dismiss(animated: true)
    }

    @objc private func reloadTapped() {
        webView.reload()
    }

    private func openInCurrentWebViewIfNeeded(
        _ navigationAction: WKNavigationAction,
        in webView: WKWebView
    ) -> Bool {
        guard navigationAction.targetFrame == nil else {
            return false
        }
        webView.load(navigationAction.request)
        return true
    }

    func webView(
        _ webView: WKWebView,
        createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction,
        windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        _ = openInCurrentWebViewIfNeeded(navigationAction, in: webView)
        return nil
    }
}

private final class FireBrowserScriptMessageProxy: NSObject, WKScriptMessageHandler {
    var onMessage: ((WKScriptMessage) -> Void)?

    func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        onMessage?(message)
    }
}
