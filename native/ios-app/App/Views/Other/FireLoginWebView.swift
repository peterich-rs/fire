import Combine
import UIKit
import WebKit

@MainActor
final class FireLoginWebViewController: UIViewController, WKNavigationDelegate, WKUIDelegate,
    WKScriptMessageHandler
{
    private let viewModel: FireAppViewModel
    private let progressView = UIProgressView(progressViewStyle: .bar)
    private let addressBar = FireLoginAddressBarView()
    private let errorBanner = FireLoginErrorBannerView()
    private let credentialStack = UIStackView()
    private let identifierField = UITextField()
    private let passwordField = UITextField()
    private let bottomBar = FireAuthBottomToolbarView()
    private let webView: WKWebView
    private let scriptMessageProxy: FireLoginScriptMessageProxy
    private var cancellables: Set<AnyCancellable> = []
    private var observations: [NSKeyValueObservation] = []
    private var errorBannerHiddenHeightConstraint: NSLayoutConstraint?
    private var lastInjectedCredential: FireSavedCredential?
    private var didTearDownWebView = false
    private var lastHcaptchaToken: String?
    private var isRunningMinimalLogin = false

    init(
        viewModel: FireAppViewModel,
        presentationState _: FireAuthPresentationState
    ) {
        self.viewModel = viewModel
        let scriptMessageProxy = FireLoginScriptMessageProxy()
        self.scriptMessageProxy = scriptMessageProxy
        self.webView = WKWebView(
            frame: .zero,
            configuration: FireWebViewBrowserProfile.makeMinimalLoginConfiguration(
                messageHandler: scriptMessageProxy
            )
        )

        super.init(nibName: nil, bundle: nil)
        scriptMessageProxy.delegate = self
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        observations.removeAll()
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        title = "登录 LinuxDo"
        view.backgroundColor = .systemBackground
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            title: "关闭",
            style: .plain,
            target: self,
            action: #selector(closeButtonTapped)
        )
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            image: UIImage(systemName: "arrow.clockwise"),
            style: .plain,
            target: self,
            action: #selector(reloadButtonTapped)
        )

        configureWebView()
        installSubviews()
        bindState()
        observeWebView()
        syncBrowserState()
        viewModel.prepareMinimalAuthWebView(webView)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        viewModel.setAPMRoute("auth.login")
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        if isBeingDismissed || navigationController?.isBeingDismissed == true {
            tearDownWebViewIfNeeded()
            viewModel.restoreTopLevelAPMRoute()
        }
    }

    private func tearDownWebViewIfNeeded() {
        guard !didTearDownWebView else { return }
        didTearDownWebView = true
        observations.removeAll()
        webView.navigationDelegate = nil
        webView.uiDelegate = nil
        [
            FireLoginScripts.hcaptchaPassMessageName,
            FireLoginScripts.hcaptchaErrorMessageName,
            FireLoginScripts.hcaptchaExpiredMessageName,
            FireLoginScripts.loginResultMessageName,
        ].forEach { name in
            webView.configuration.userContentController.removeScriptMessageHandler(forName: name)
        }
    }

    private func configureWebView() {
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.allowsBackForwardNavigationGestures = true
        FireWebViewBrowserProfile.configure(
            webView,
            preferredUserAgent: viewModel.session.browserUserAgent
        )
    }

    private func installSubviews() {
        progressView.translatesAutoresizingMaskIntoConstraints = false
        progressView.progressTintColor = .systemOrange
        progressView.trackTintColor = .clear
        progressView.isHidden = true

        addressBar.translatesAutoresizingMaskIntoConstraints = false
        errorBanner.translatesAutoresizingMaskIntoConstraints = false
        errorBanner.isHidden = true
        credentialStack.translatesAutoresizingMaskIntoConstraints = false
        credentialStack.axis = .vertical
        credentialStack.spacing = 10
        credentialStack.layoutMargins = UIEdgeInsets(top: 12, left: 16, bottom: 10, right: 16)
        credentialStack.isLayoutMarginsRelativeArrangement = true
        configureCredentialField(identifierField, placeholder: "用户名或邮箱", secure: false)
        configureCredentialField(passwordField, placeholder: "密码", secure: true)
        credentialStack.addArrangedSubview(identifierField)
        credentialStack.addArrangedSubview(passwordField)
        webView.translatesAutoresizingMaskIntoConstraints = false
        bottomBar.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(progressView)
        view.addSubview(addressBar)
        view.addSubview(errorBanner)
        view.addSubview(credentialStack)
        view.addSubview(webView)
        view.addSubview(bottomBar)

        let hiddenErrorBannerHeight = errorBanner.heightAnchor.constraint(equalToConstant: 0)
        hiddenErrorBannerHeight.isActive = true
        errorBannerHiddenHeightConstraint = hiddenErrorBannerHeight

        NSLayoutConstraint.activate([
            progressView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            progressView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            progressView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            progressView.heightAnchor.constraint(equalToConstant: 2),

            addressBar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            addressBar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            addressBar.topAnchor.constraint(equalTo: progressView.bottomAnchor),

            errorBanner.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            errorBanner.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            errorBanner.topAnchor.constraint(equalTo: addressBar.bottomAnchor),

            webView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            credentialStack.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            credentialStack.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            credentialStack.topAnchor.constraint(equalTo: errorBanner.bottomAnchor),

            webView.topAnchor.constraint(equalTo: credentialStack.bottomAnchor),
            webView.bottomAnchor.constraint(equalTo: bottomBar.topAnchor),

            bottomBar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            bottomBar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            bottomBar.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
        ])

        errorBanner.onDismiss = { [weak self] in
            self?.viewModel.dismissError()
        }
        bottomBar.onBack = { [weak self] in
            self?.webView.goBack()
        }
        bottomBar.onForward = { [weak self] in
            self?.webView.goForward()
        }
        bottomBar.onPrimaryAction = { [weak self] in
            self?.performPrimaryAction()
        }
    }

    private func bindState() {
        viewModel.$errorMessage
            .receive(on: RunLoop.main)
            .sink { [weak self] message in
                self?.updateErrorBanner(message)
            }
            .store(in: &cancellables)

        viewModel.$isSyncingLoginSession
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.syncBrowserState()
            }
            .store(in: &cancellables)

        viewModel.$savedLoginCredential
            .receive(on: RunLoop.main)
            .sink { [weak self] credential in
                self?.applyCredential(credential)
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.syncBrowserState()
            }
            .store(in: &cancellables)
    }

    private func observeWebView() {
        observations = [
            webView.observe(\.canGoBack, options: [.initial, .new]) { [weak self] _, _ in
                Task { @MainActor in
                    self?.syncBrowserState()
                }
            },
            webView.observe(\.canGoForward, options: [.initial, .new]) { [weak self] _, _ in
                Task { @MainActor in
                    self?.syncBrowserState()
                }
            },
            webView.observe(\.isLoading, options: [.initial, .new]) { [weak self] webView, _ in
                Task { @MainActor in
                    self?.handleLoadingStateChange(isLoading: webView.isLoading)
                }
            },
            webView.observe(\.estimatedProgress, options: [.initial, .new]) { [weak self] webView, _ in
                Task { @MainActor in
                    self?.progressView.progress = Float(webView.estimatedProgress)
                }
            },
            webView.observe(\.title, options: [.initial, .new]) { [weak self] _, _ in
                Task { @MainActor in
                    self?.syncBrowserState()
                }
            },
            webView.observe(\.url, options: [.initial, .new]) { [weak self] _, _ in
                Task { @MainActor in
                    self?.syncBrowserState()
                }
            },
        ]
    }

    private func applyCredential(_ credential: FireSavedCredential?) {
        guard credential != lastInjectedCredential else {
            return
        }
        lastInjectedCredential = credential
        identifierField.text = credential?.username
        passwordField.text = credential?.password
        syncBrowserState()
    }

    private func configureCredentialField(
        _ field: UITextField,
        placeholder: String,
        secure: Bool
    ) {
        field.borderStyle = .roundedRect
        field.placeholder = placeholder
        field.autocapitalizationType = .none
        field.autocorrectionType = .no
        field.clearButtonMode = .whileEditing
        field.isSecureTextEntry = secure
        field.returnKeyType = secure ? .done : .next
        field.textContentType = secure ? .password : .username
        field.addTarget(self, action: #selector(credentialFieldChanged), for: .editingChanged)
    }

    @objc private func credentialFieldChanged() {
        syncBrowserState()
    }

    private func handleLoadingStateChange(isLoading: Bool) {
        syncBrowserState()
    }

    private func syncBrowserState() {
        addressBar.configure(currentURL: webView.url?.absoluteString ?? webView.url?.host)
        progressView.isHidden = !webView.isLoading
        progressView.setProgress(Float(webView.estimatedProgress), animated: true)
        bottomBar.configure(
            canGoBack: webView.canGoBack,
            canGoForward: webView.canGoForward,
            isLoading: webView.isLoading || isRunningMinimalLogin,
            isRunningAction: viewModel.isSyncingLoginSession || isRunningMinimalLogin,
            canPerformPrimaryAction: hasEnteredCredentials(),
            primaryTitle: (viewModel.isSyncingLoginSession || isRunningMinimalLogin) ? "登录中..." : "登录"
        )
    }

    private func hasEnteredCredentials() -> Bool {
        !(identifierField.text?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
            && !(passwordField.text?.isEmpty ?? true)
    }

    private func updateErrorBanner(_ message: String?) {
        guard let message, !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            errorBannerHiddenHeightConstraint?.isActive = true
            errorBanner.isHidden = true
            return
        }
        errorBanner.configure(message: message)
        errorBannerHiddenHeightConstraint?.isActive = false
        errorBanner.isHidden = false
    }

    private func performPrimaryAction() {
        guard let token = lastHcaptchaToken, !token.isEmpty else {
            viewModel.errorMessage = "请先完成人机验证。"
            return
        }
        runMinimalLogin(hcaptchaToken: token, secondFactorToken: nil)
    }

    private func runMinimalLogin(hcaptchaToken: String?, secondFactorToken: String?) {
        let identifier = identifierField.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let password = passwordField.text ?? ""
        guard !identifier.isEmpty, !password.isEmpty else {
            viewModel.errorMessage = "请先填写账号和密码。"
            return
        }

        isRunningMinimalLogin = true
        syncBrowserState()
        let script = FireLoginScripts.fireLoginInvocation(
            identifier: identifier,
            password: password,
            hcaptchaToken: hcaptchaToken,
            secondFactorToken: secondFactorToken
        )
        webView.evaluateJavaScript(script) { [weak self] _, error in
            guard let self, let error else { return }
            Task { @MainActor in
                self.isRunningMinimalLogin = false
                self.viewModel.errorMessage = error.localizedDescription
                self.syncBrowserState()
            }
        }
    }

    private func openInCurrentWebViewIfNeeded(
        _ navigationAction: WKNavigationAction,
        in webView: WKWebView
    ) -> Bool {
        guard navigationAction.targetFrame == nil else {
            return false
        }
        webView.load(navigationAction.request)
        syncBrowserState()
        return true
    }

    @objc private func closeButtonTapped() {
        viewModel.dismissAuthPresentation()
    }

    @objc private func reloadButtonTapped() {
        webView.reload()
    }

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        syncBrowserState()
    }

    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        syncBrowserState()
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        syncBrowserState()
    }

    func webView(
        _ webView: WKWebView,
        didFail navigation: WKNavigation!,
        withError error: Error
    ) {
        syncBrowserState()
    }

    func webView(
        _ webView: WKWebView,
        didFailProvisionalNavigation navigation: WKNavigation!,
        withError error: Error
    ) {
        syncBrowserState()
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        syncBrowserState()
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

    func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        switch message.name {
        case FireLoginScripts.hcaptchaPassMessageName:
            guard let token = message.body as? String else { return }
            lastHcaptchaToken = token
            runMinimalLogin(hcaptchaToken: token, secondFactorToken: nil)
        case FireLoginScripts.hcaptchaErrorMessageName:
            isRunningMinimalLogin = false
            viewModel.errorMessage = (message.body as? String) ?? "hCaptcha 验证失败，请重试。"
            syncBrowserState()
        case FireLoginScripts.hcaptchaExpiredMessageName:
            lastHcaptchaToken = nil
            isRunningMinimalLogin = false
            viewModel.errorMessage = "hCaptcha 已过期，请重新验证。"
            syncBrowserState()
        case FireLoginScripts.loginResultMessageName:
            handleLoginResult(message.body)
        default:
            break
        }
    }

    private func handleLoginResult(_ body: Any) {
        guard let result = makeLoginJsResult(from: body) else {
            isRunningMinimalLogin = false
            viewModel.errorMessage = "登录结果格式无效。"
            syncBrowserState()
            return
        }

        Task { @MainActor in
            do {
                let decision = try await viewModel.classifyWebViewLoginResult(result)
                handleLoginDecision(decision)
            } catch {
                isRunningMinimalLogin = false
                viewModel.errorMessage = error.localizedDescription
                syncBrowserState()
            }
        }
    }

    private func makeLoginJsResult(from body: Any) -> WebViewLoginJsResultState? {
        guard let payload = body as? [String: Any] else {
            return nil
        }
        let phase: WebViewLoginPhaseState
        switch (payload["phase"] as? String)?.lowercased() {
        case "csrf":
            phase = .csrf
        case "hcaptcha":
            phase = .hcaptcha
        case "session":
            phase = .session
        default:
            phase = .exception
        }
        let status = UInt16(clamping: (payload["status"] as? NSNumber)?.intValue ?? 0)
        return WebViewLoginJsResultState(
            phase: phase,
            status: status,
            body: (payload["body"] as? String) ?? ""
        )
    }

    private func handleLoginDecision(_ decision: WebViewLoginDecisionState) {
        switch decision {
        case .success:
            completeMinimalLogin()
        case .needSecondFactor:
            isRunningMinimalLogin = false
            syncBrowserState()
            showSecondFactorPrompt()
        case .retryCloudflare:
            isRunningMinimalLogin = false
            viewModel.errorMessage = "需要先完成 Cloudflare 验证后再登录。"
            syncBrowserState()
        case let .failure(failure):
            isRunningMinimalLogin = false
            viewModel.errorMessage = failure.message ?? "登录失败，请重试。"
            syncBrowserState()
        }
    }

    private func completeMinimalLogin() {
        isRunningMinimalLogin = false
        syncBrowserState()
        viewModel.completeMinimalLogin(
            from: webView,
            identifier: identifierField.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
            password: passwordField.text ?? ""
        )
    }

    private func showSecondFactorPrompt() {
        let alert = UIAlertController(title: "二步验证码", message: nil, preferredStyle: .alert)
        alert.addTextField { field in
            field.placeholder = "身份验证器验证码"
            field.keyboardType = .numberPad
            field.textContentType = .oneTimeCode
        }
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        alert.addAction(UIAlertAction(title: "验证", style: .default) { [weak self, weak alert] _ in
            guard let self else { return }
            let code = alert?.textFields?.first?.text?.trimmingCharacters(in: .whitespacesAndNewlines)
            self.runMinimalLogin(hcaptchaToken: nil, secondFactorToken: code)
        })
        present(alert, animated: true)
    }
}

private final class FireLoginAddressBarView: UIView {
    private let label = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        configureSubviews()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(currentURL: String?) {
        label.text = currentURL ?? "linux.do"
    }

    private func configureSubviews() {
        backgroundColor = .secondarySystemBackground
        directionalLayoutMargins = NSDirectionalEdgeInsets(
            top: 6,
            leading: 16,
            bottom: 6,
            trailing: 16
        )

        let imageView = UIImageView(image: UIImage(systemName: "lock.fill"))
        imageView.tintColor = .tertiaryLabel
        imageView.contentMode = .scaleAspectFit
        imageView.setContentHuggingPriority(.required, for: .horizontal)

        label.font = UIFont.preferredFont(forTextStyle: .caption1)
        label.adjustsFontForContentSizeCategory = true
        label.textColor = .secondaryLabel
        label.lineBreakMode = .byTruncatingMiddle
        label.numberOfLines = 1

        let stackView = UIStackView(arrangedSubviews: [imageView, label])
        stackView.axis = .horizontal
        stackView.alignment = .center
        stackView.spacing = 6
        stackView.translatesAutoresizingMaskIntoConstraints = false

        addSubview(stackView)
        NSLayoutConstraint.activate([
            imageView.widthAnchor.constraint(equalToConstant: 12),
            imageView.heightAnchor.constraint(equalToConstant: 12),
            stackView.leadingAnchor.constraint(equalTo: layoutMarginsGuide.leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: layoutMarginsGuide.trailingAnchor),
            stackView.topAnchor.constraint(equalTo: layoutMarginsGuide.topAnchor),
            stackView.bottomAnchor.constraint(equalTo: layoutMarginsGuide.bottomAnchor),
        ])
    }
}

private final class FireLoginErrorBannerView: UIView {
    private let messageLabel = UILabel()
    var onDismiss: (() -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        configureSubviews()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(message: String) {
        messageLabel.text = message
    }

    private func configureSubviews() {
        backgroundColor = .secondarySystemBackground
        directionalLayoutMargins = NSDirectionalEdgeInsets(
            top: 8,
            leading: 12,
            bottom: 8,
            trailing: 12
        )

        let imageView = UIImageView(image: UIImage(systemName: "exclamationmark.triangle.fill"))
        imageView.tintColor = .systemOrange
        imageView.contentMode = .scaleAspectFit
        imageView.setContentHuggingPriority(.required, for: .horizontal)

        messageLabel.font = UIFont.preferredFont(forTextStyle: .caption1)
        messageLabel.adjustsFontForContentSizeCategory = true
        messageLabel.textColor = .secondaryLabel
        messageLabel.numberOfLines = 2

        let closeButton = UIButton(type: .system)
        closeButton.setImage(UIImage(systemName: "xmark"), for: .normal)
        closeButton.tintColor = .tertiaryLabel
        closeButton.accessibilityLabel = "关闭错误提示"
        closeButton.addAction(UIAction { [weak self] _ in
            self?.onDismiss?()
        }, for: .touchUpInside)

        let stackView = UIStackView(arrangedSubviews: [imageView, messageLabel, closeButton])
        stackView.axis = .horizontal
        stackView.alignment = .center
        stackView.spacing = 8
        stackView.translatesAutoresizingMaskIntoConstraints = false

        addSubview(stackView)
        NSLayoutConstraint.activate([
            imageView.widthAnchor.constraint(equalToConstant: 16),
            imageView.heightAnchor.constraint(equalToConstant: 16),
            closeButton.widthAnchor.constraint(equalToConstant: 28),
            closeButton.heightAnchor.constraint(equalToConstant: 28),
            stackView.leadingAnchor.constraint(equalTo: layoutMarginsGuide.leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: layoutMarginsGuide.trailingAnchor),
            stackView.topAnchor.constraint(equalTo: layoutMarginsGuide.topAnchor),
            stackView.bottomAnchor.constraint(equalTo: layoutMarginsGuide.bottomAnchor),
        ])
    }
}

private final class FireAuthBottomToolbarView: UIView {
    private let backButton = UIButton(type: .system)
    private let forwardButton = UIButton(type: .system)
    private let primaryButton = UIButton(type: .system)
    var onBack: (() -> Void)?
    var onForward: (() -> Void)?
    var onPrimaryAction: (() -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        configureSubviews()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(
        canGoBack: Bool,
        canGoForward: Bool,
        isLoading: Bool,
        isRunningAction: Bool,
        canPerformPrimaryAction: Bool,
        primaryTitle: String
    ) {
        backButton.isEnabled = canGoBack
        forwardButton.isEnabled = canGoForward
        primaryButton.isEnabled = !isLoading && !isRunningAction && canPerformPrimaryAction
        primaryButton.configuration = primaryConfiguration(
            title: primaryTitle,
            showsActivityIndicator: isRunningAction
        )
    }

    private func configureSubviews() {
        backgroundColor = .systemBackground
        directionalLayoutMargins = NSDirectionalEdgeInsets(
            top: 10,
            leading: 16,
            bottom: 10,
            trailing: 16
        )

        configureNavigationButton(backButton, systemImage: "chevron.backward")
        configureNavigationButton(forwardButton, systemImage: "chevron.forward")
        primaryButton.configuration = primaryConfiguration(
            title: "登录",
            showsActivityIndicator: false
        )

        backButton.addAction(UIAction { [weak self] _ in
            self?.onBack?()
        }, for: .touchUpInside)
        forwardButton.addAction(UIAction { [weak self] _ in
            self?.onForward?()
        }, for: .touchUpInside)
        primaryButton.addAction(UIAction { [weak self] _ in
            self?.onPrimaryAction?()
        }, for: .touchUpInside)

        let navigationStack = UIStackView(arrangedSubviews: [backButton, forwardButton])
        navigationStack.axis = .horizontal
        navigationStack.alignment = .center
        navigationStack.spacing = 16

        let rowStack = UIStackView(arrangedSubviews: [navigationStack, UIView(), primaryButton])
        rowStack.axis = .horizontal
        rowStack.alignment = .center
        rowStack.spacing = 16
        rowStack.translatesAutoresizingMaskIntoConstraints = false

        addSubview(rowStack)
        NSLayoutConstraint.activate([
            backButton.widthAnchor.constraint(equalToConstant: 34),
            backButton.heightAnchor.constraint(equalToConstant: 34),
            forwardButton.widthAnchor.constraint(equalToConstant: 34),
            forwardButton.heightAnchor.constraint(equalToConstant: 34),
            primaryButton.heightAnchor.constraint(greaterThanOrEqualToConstant: 42),
            rowStack.leadingAnchor.constraint(equalTo: layoutMarginsGuide.leadingAnchor),
            rowStack.trailingAnchor.constraint(equalTo: layoutMarginsGuide.trailingAnchor),
            rowStack.topAnchor.constraint(equalTo: layoutMarginsGuide.topAnchor),
            rowStack.bottomAnchor.constraint(equalTo: layoutMarginsGuide.bottomAnchor),
        ])
    }

    private func configureNavigationButton(_ button: UIButton, systemImage: String) {
        var configuration = UIButton.Configuration.plain()
        configuration.image = UIImage(systemName: systemImage)
        configuration.contentInsets = NSDirectionalEdgeInsets(
            top: 6,
            leading: 6,
            bottom: 6,
            trailing: 6
        )
        button.configuration = configuration
    }

    private func primaryConfiguration(
        title: String,
        showsActivityIndicator: Bool
    ) -> UIButton.Configuration {
        var configuration = UIButton.Configuration.filled()
        configuration.title = title
        configuration.baseBackgroundColor = .systemOrange
        configuration.baseForegroundColor = .white
        configuration.cornerStyle = .capsule
        configuration.showsActivityIndicator = showsActivityIndicator
        configuration.contentInsets = NSDirectionalEdgeInsets(
            top: 10,
            leading: 16,
            bottom: 10,
            trailing: 16
        )
        return configuration
    }
}

private final class FireLoginScriptMessageProxy: NSObject, WKScriptMessageHandler {
    weak var delegate: WKScriptMessageHandler?

    func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        delegate?.userContentController(userContentController, didReceive: message)
    }
}
