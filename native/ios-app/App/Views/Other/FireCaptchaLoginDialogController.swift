import UIKit
import WebKit

enum FireCaptchaDialogResult {
    case success
    case needSecondFactor(SecondFactorRequirementState)
    case retryCloudflare
    case failure(LoginFailureState)
}

/// Form-sheet dialog that renders hCaptcha in a WKWebView and executes
/// `window.__fireLogin`. The WKWebView stays alive until the presenter extracts
/// cookies via `completeJsLogin(from:)`.
@MainActor
final class FireCaptchaLoginDialogController: UIViewController {
    private(set) var webView: WKWebView!

    private let identifier: String
    private let password: String
    private let loginCoordinator: FireWebViewLoginCoordinator
    private let onResult: (FireCaptchaDialogResult) -> Void
    private let onCancel: () -> Void

    private var lastLoginHcaptchaToken: String?
    private var lastLoginSecondFactorToken: String?
    private var hasReportedResult = false
    private var didTearDownWebView = false
    private var loginResultTimeoutWorkItem: DispatchWorkItem?
    private var statusLabel: UILabel!
    private var activityIndicator: UIActivityIndicatorView!
    private var navigationBar: UINavigationBar!

    private static let loginResultTimeoutSeconds: TimeInterval = 30

    var classifyResult: ((WebViewLoginPhaseState, UInt16, String) -> Void)?

    init(
        identifier: String,
        password: String,
        loginCoordinator: FireWebViewLoginCoordinator,
        onResult: @escaping (FireCaptchaDialogResult) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.identifier = identifier
        self.password = password
        self.loginCoordinator = loginCoordinator
        self.onResult = onResult
        self.onCancel = onCancel
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .pageSheet
        if let sheet = sheetPresentationController {
            // Challenges need vertical room; start large so the widget is not clipped.
            sheet.detents = [.medium(), .large()]
            sheet.selectedDetentIdentifier = .large
            sheet.prefersGrabberVisible = true
            sheet.prefersScrollingExpandsWhenScrolledToEdge = true
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = FireTheme.uiCanvas
        setupNavigationBar()
        setupWebView()
        setupStatusLabel()
        loadMinimalLoginPage()
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        if isBeingDismissed || navigationController?.isBeingDismissed == true {
            tearDownWebViewIfNeeded()
        }
    }

    private func setupNavigationBar() {
        navigationBar = UINavigationBar()
        navigationBar.translatesAutoresizingMaskIntoConstraints = false

        let navigationItem = UINavigationItem(title: "安全验证")
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .close,
            target: self,
            action: #selector(closeTapped)
        )
        navigationBar.items = [navigationItem]
        view.addSubview(navigationBar)

        NSLayoutConstraint.activate([
            navigationBar.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            navigationBar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            navigationBar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])
    }

    private func setupWebView() {
        let configuration = FireWebViewBrowserProfile.makeMinimalLoginConfiguration(
            messageHandler: FireCaptchaScriptMessageProxy(delegate: self)
        )
        webView = WKWebView(frame: .zero, configuration: configuration)
        webView.translatesAutoresizingMaskIntoConstraints = false
        // Challenge UI can be taller than the sheet; allow scrolling instead of clipping.
        webView.scrollView.isScrollEnabled = true
        webView.scrollView.alwaysBounceVertical = true
        webView.isOpaque = false
        webView.backgroundColor = .clear
        FireWebViewBrowserProfile.configure(webView)
        view.addSubview(webView)

        NSLayoutConstraint.activate([
            webView.topAnchor.constraint(equalTo: navigationBar.bottomAnchor, constant: 8),
            webView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])
    }

    private func setupStatusLabel() {
        statusLabel = UILabel()
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        statusLabel.font = .systemFont(ofSize: 14)
        statusLabel.textColor = .secondaryLabel
        statusLabel.textAlignment = .center
        statusLabel.numberOfLines = 0
        statusLabel.text = "正在加载验证..."
        view.addSubview(statusLabel)

        activityIndicator = UIActivityIndicatorView(style: .medium)
        activityIndicator.translatesAutoresizingMaskIntoConstraints = false
        activityIndicator.hidesWhenStopped = true
        activityIndicator.startAnimating()
        // Keep the spinner below the status line — never overlay the captcha WebView.
        view.addSubview(activityIndicator)

        NSLayoutConstraint.activate([
            webView.bottomAnchor.constraint(equalTo: statusLabel.topAnchor, constant: -10),
            statusLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            statusLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            activityIndicator.topAnchor.constraint(equalTo: statusLabel.bottomAnchor, constant: 8),
            activityIndicator.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            activityIndicator.bottomAnchor.constraint(
                equalTo: view.safeAreaLayoutGuide.bottomAnchor,
                constant: -12
            ),
        ])
    }

    fileprivate func markCaptchaReady(detail: String?) {
        activityIndicator.stopAnimating()
        switch detail {
        case "open":
            statusLabel.text = "请完成安全验证"
        case "close":
            statusLabel.text = "请点击验证框重试"
        default:
            statusLabel.text = "请完成下方验证"
        }
        statusLabel.textColor = .secondaryLabel
    }

    private func tearDownWebViewIfNeeded() {
        guard !didTearDownWebView else { return }
        didTearDownWebView = true
        [
            FireLoginScripts.hcaptchaPassMessageName,
            FireLoginScripts.hcaptchaErrorMessageName,
            FireLoginScripts.hcaptchaExpiredMessageName,
            FireLoginScripts.hcaptchaReadyMessageName,
            FireLoginScripts.loginResultMessageName,
        ].forEach { name in
            webView?.configuration.userContentController.removeScriptMessageHandler(forName: name)
        }
        webView?.stopLoading()
    }

    private func loadMinimalLoginPage() {
        Task { [weak self] in
            guard let self else { return }
            do {
                try await loginCoordinator.primeCookies(
                    into: webView,
                    targetURL: URL(string: "https://linux.do/")
                )
            } catch {
                FireAPMManager.shared.recordBreadcrumb(
                    level: "warn",
                    target: "auth.login",
                    message: "captcha dialog cookie priming failed: \(error.localizedDescription)"
                )
            }

            let html = FireLoginScripts.minimalLoginHTML(
                hcaptchaSiteKey: FireLoginScripts.linuxDoHcaptchaSiteKey,
                hcaptchaCreateEndpoint: "/captcha/hcaptcha/create.json"
            )
            webView.loadHTMLString(html, baseURL: URL(string: "https://linux.do/"))
        }
    }

    func dispatchResult(_ result: FireCaptchaDialogResult) {
        reportResult(result)
    }

    func retryWithSecondFactor(_ token: String) {
        hasReportedResult = false
        lastLoginHcaptchaToken = nil
        lastLoginSecondFactorToken = token
        statusLabel.text = "正在验证..."
        statusLabel.textColor = .secondaryLabel
        activityIndicator.startAnimating()

        scheduleLoginResultTimeout(reason: "after second_factor")
        evaluateFireLogin(
            hcaptchaToken: nil,
            secondFactorToken: token,
            context: "second_factor"
        )
    }

    func retryAfterCloudflareRecovery() {
        guard lastLoginHcaptchaToken != nil || lastLoginSecondFactorToken != nil else {
            statusLabel.text = "请重新尝试登录"
            statusLabel.textColor = .secondaryLabel
            hasReportedResult = false
            return
        }

        hasReportedResult = false
        statusLabel.text = "正在重试登录..."
        statusLabel.textColor = .secondaryLabel
        activityIndicator.startAnimating()
        scheduleLoginResultTimeout(reason: "after cloudflare recovery")
        evaluateFireLogin(
            hcaptchaToken: lastLoginHcaptchaToken,
            secondFactorToken: lastLoginSecondFactorToken,
            context: "cloudflare_retry"
        )
    }

    fileprivate func runLogin(hcaptchaToken: String) {
        lastLoginHcaptchaToken = hcaptchaToken
        lastLoginSecondFactorToken = nil
        hasReportedResult = false
        statusLabel.text = "正在登录..."
        statusLabel.textColor = .secondaryLabel
        activityIndicator.startAnimating()
        FireAPMManager.shared.recordBreadcrumb(
            level: "info",
            target: "auth.login",
            message: "hcaptcha_pass received; invoking __fireLogin token_len=\(hcaptchaToken.count)"
        )
        scheduleLoginResultTimeout(reason: "after hcaptcha_pass")
        evaluateFireLogin(
            hcaptchaToken: hcaptchaToken,
            secondFactorToken: nil,
            context: "hcaptcha_pass"
        )
    }

    private func evaluateFireLogin(
        hcaptchaToken: String?,
        secondFactorToken: String?,
        context: String
    ) {
        let invocation = FireLoginScripts.fireLoginInvocation(
            identifier: identifier,
            password: password,
            hcaptchaToken: hcaptchaToken,
            secondFactorToken: secondFactorToken
        )
        webView.evaluateJavaScript(invocation) { [weak self] _, error in
            guard let self else { return }
            if let error, !FireLoginScripts.isBenignEvaluateJavaScriptError(error) {
                FireAPMManager.shared.recordBreadcrumb(
                    level: "error",
                    target: "auth.login",
                    message: "__fireLogin evaluateJavaScript failed (\(context)): \(error.localizedDescription)"
                )
                self.reportResult(.failure(Self.unknownFailure(message: error.localizedDescription)))
                return
            }
            if let error {
                FireAPMManager.shared.recordBreadcrumb(
                    level: "info",
                    target: "auth.login",
                    message: "__fireLogin evaluateJavaScript benign (\(context)): \(error.localizedDescription); awaiting login_result"
                )
            } else {
                FireAPMManager.shared.recordBreadcrumb(
                    level: "info",
                    target: "auth.login",
                    message: "__fireLogin evaluateJavaScript accepted (\(context)); awaiting login_result bridge"
                )
            }
        }
    }

    private func scheduleLoginResultTimeout(reason: String) {
        loginResultTimeoutWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, !self.hasReportedResult else { return }
            FireAPMManager.shared.recordBreadcrumb(
                level: "error",
                target: "auth.login",
                message: "login_result timeout after \(Self.loginResultTimeoutSeconds)s (\(reason))"
            )
            self.reportResult(
                .failure(
                    Self.unknownFailure(message: "登录请求超时，请重试")
                )
            )
        }
        loginResultTimeoutWorkItem = work
        DispatchQueue.main.asyncAfter(
            deadline: .now() + Self.loginResultTimeoutSeconds,
            execute: work
        )
    }

    fileprivate func showHcaptchaError(_ message: String) {
        statusLabel.text = message
        statusLabel.textColor = .systemRed
        activityIndicator.stopAnimating()
    }

    fileprivate func handleLoginResultJs(_ body: [String: Any]) {
        let phase: WebViewLoginPhaseState
        switch (body["phase"] as? String)?.lowercased() {
        case "csrf":
            phase = .csrf
        case "hcaptcha":
            phase = .hcaptcha
        case "session":
            phase = .session
        default:
            phase = .exception
        }

        let rawStatus = (body["status"] as? NSNumber)?.intValue
            ?? body["status"] as? Int
            ?? 0
        classifyResult?(phase, UInt16(clamping: rawStatus), (body["body"] as? String) ?? "")
    }

    private func reportResult(_ result: FireCaptchaDialogResult) {
        guard !hasReportedResult else { return }
        hasReportedResult = true
        loginResultTimeoutWorkItem?.cancel()
        loginResultTimeoutWorkItem = nil
        activityIndicator.stopAnimating()

        switch result {
        case .success:
            statusLabel.text = "验证成功，正在同步会话…"
            statusLabel.textColor = .secondaryLabel
            activityIndicator.startAnimating()
        case .needSecondFactor:
            statusLabel.text = ""
            statusLabel.textColor = .secondaryLabel
        case .retryCloudflare:
            statusLabel.text = "正在恢复网络..."
            statusLabel.textColor = .secondaryLabel
            activityIndicator.startAnimating()
        case let .failure(failure):
            statusLabel.text = failure.message ?? "登录失败"
            statusLabel.textColor = .systemRed
            // Allow a subsequent captcha/login attempt from the same dialog if needed.
            hasReportedResult = false
        }

        FireAPMManager.shared.recordBreadcrumb(
            level: "info",
            target: "auth.login",
            message: "captcha dialog reportResult \(String(describing: result))"
        )
        onResult(result)
    }

    private func handleCancel() {
        onCancel()
        dismiss(animated: true)
    }

    @objc private func closeTapped() {
        handleCancel()
    }

    private static func unknownFailure(message: String) -> LoginFailureState {
        LoginFailureState(
            kind: .unknown,
            message: message,
            sentToEmail: nil,
            currentEmail: nil
        )
    }
}

private final class FireCaptchaScriptMessageProxy: NSObject, WKScriptMessageHandler {
    weak var delegate: FireCaptchaLoginDialogController?

    init(delegate: FireCaptchaLoginDialogController) {
        self.delegate = delegate
    }

    func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        guard let delegate else { return }

        switch message.name {
        case FireLoginScripts.hcaptchaPassMessageName:
            if let token = message.body as? String {
                Task { @MainActor in
                    delegate.runLogin(hcaptchaToken: token)
                }
            }
        case FireLoginScripts.hcaptchaReadyMessageName:
            let detail = message.body as? String
            Task { @MainActor in
                delegate.markCaptchaReady(detail: detail)
            }
        case FireLoginScripts.hcaptchaErrorMessageName:
            let message = (message.body as? String) ?? "人机验证失败"
            Task { @MainActor in
                delegate.showHcaptchaError(message)
            }
        case FireLoginScripts.hcaptchaExpiredMessageName:
            Task { @MainActor in
                delegate.showHcaptchaError("人机验证已过期，请重试")
            }
        case FireLoginScripts.loginResultMessageName:
            if let body = message.body as? [String: Any] {
                Task { @MainActor in
                    delegate.handleLoginResultJs(body)
                }
            }
        default:
            break
        }
    }
}
