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
    private var statusLabel: UILabel!
    private var activityIndicator: UIActivityIndicatorView!
    private var navigationBar: UINavigationBar!

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
            sheet.detents = [.medium(), .large()]
            sheet.prefersGrabberVisible = true
            sheet.prefersScrollingExpandsWhenScrolledToEdge = false
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
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
        webView.scrollView.isScrollEnabled = false
        FireWebViewBrowserProfile.configure(webView)
        view.addSubview(webView)

        NSLayoutConstraint.activate([
            webView.topAnchor.constraint(equalTo: navigationBar.bottomAnchor, constant: 12),
            webView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            webView.heightAnchor.constraint(greaterThanOrEqualToConstant: 150),
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
        activityIndicator.startAnimating()
        view.addSubview(activityIndicator)

        NSLayoutConstraint.activate([
            statusLabel.topAnchor.constraint(equalTo: webView.bottomAnchor, constant: 12),
            statusLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            statusLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            statusLabel.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -16),
            activityIndicator.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            activityIndicator.centerYAnchor.constraint(equalTo: webView.centerYAnchor),
        ])
    }

    private func tearDownWebViewIfNeeded() {
        guard !didTearDownWebView else { return }
        didTearDownWebView = true
        [
            FireLoginScripts.hcaptchaPassMessageName,
            FireLoginScripts.hcaptchaErrorMessageName,
            FireLoginScripts.hcaptchaExpiredMessageName,
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

        let invocation = FireLoginScripts.fireLoginInvocation(
            identifier: identifier,
            password: password,
            hcaptchaToken: nil,
            secondFactorToken: token
        )
        webView.evaluateJavaScript(invocation) { [weak self] _, error in
            guard let self, let error else { return }
            self.reportResult(.failure(Self.unknownFailure(message: error.localizedDescription)))
        }
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

        let invocation = FireLoginScripts.fireLoginInvocation(
            identifier: identifier,
            password: password,
            hcaptchaToken: lastLoginHcaptchaToken,
            secondFactorToken: lastLoginSecondFactorToken
        )
        webView.evaluateJavaScript(invocation) { [weak self] _, error in
            guard let self, let error else { return }
            self.reportResult(.failure(Self.unknownFailure(message: error.localizedDescription)))
        }
    }

    fileprivate func runLogin(hcaptchaToken: String) {
        lastLoginHcaptchaToken = hcaptchaToken
        lastLoginSecondFactorToken = nil
        hasReportedResult = false
        statusLabel.text = "正在登录..."
        statusLabel.textColor = .secondaryLabel
        activityIndicator.startAnimating()

        let invocation = FireLoginScripts.fireLoginInvocation(
            identifier: identifier,
            password: password,
            hcaptchaToken: hcaptchaToken,
            secondFactorToken: nil
        )
        webView.evaluateJavaScript(invocation) { [weak self] _, error in
            guard let self, let error else { return }
            self.reportResult(.failure(Self.unknownFailure(message: error.localizedDescription)))
        }
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
        activityIndicator.stopAnimating()

        switch result {
        case .success:
            statusLabel.text = "验证成功"
            statusLabel.textColor = .secondaryLabel
        case .needSecondFactor:
            statusLabel.text = ""
            statusLabel.textColor = .secondaryLabel
        case .retryCloudflare:
            statusLabel.text = "正在恢复网络..."
            statusLabel.textColor = .secondaryLabel
        case let .failure(failure):
            statusLabel.text = failure.message ?? "登录失败"
            statusLabel.textColor = .systemRed
            hasReportedResult = false
        }

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
