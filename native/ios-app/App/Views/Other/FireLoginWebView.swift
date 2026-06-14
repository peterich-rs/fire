import Combine
import UIKit
import WebKit

public final class FireLoginWebViewProbeBridge: NSObject, WKHTTPCookieStoreObserver {
    private static let cookieProbeDebounceDelay: TimeInterval = 0.35

    private weak var observedWebView: WKWebView?
    private weak var observedCookieStore: WKHTTPCookieStore?
    private var pendingProbeWorkItem: DispatchWorkItem?
    private let onProbeRequested: (WKWebView) -> Void

    public init(onProbeRequested: @escaping (WKWebView) -> Void) {
        self.onProbeRequested = onProbeRequested
    }

    deinit {
        pendingProbeWorkItem?.cancel()
        observedCookieStore?.remove(self)
    }

    public func attach(to webView: WKWebView) {
        let cookieStore = webView.configuration.websiteDataStore.httpCookieStore
        if observedCookieStore !== cookieStore {
            observedCookieStore?.remove(self)
            cookieStore.add(self)
            observedCookieStore = cookieStore
        }
        observedWebView = webView
    }

    public func detach() {
        pendingProbeWorkItem?.cancel()
        pendingProbeWorkItem = nil
        observedCookieStore?.remove(self)
        observedCookieStore = nil
        observedWebView = nil
    }

    public func requestProbe() {
        requestProbe(after: 0)
    }

    private func requestProbe(after delay: TimeInterval) {
        pendingProbeWorkItem?.cancel()
        guard let observedWebView else {
            return
        }

        let workItem = DispatchWorkItem { [weak self, weak observedWebView] in
            guard self != nil, let observedWebView else {
                return
            }
            self?.pendingProbeWorkItem = nil
            self?.onProbeRequested(observedWebView)
        }
        pendingProbeWorkItem = workItem

        if delay <= 0 {
            DispatchQueue.main.async(execute: workItem)
        } else {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
        }
    }

    public func cookiesDidChange(in cookieStore: WKHTTPCookieStore) {
        requestProbe(after: Self.cookieProbeDebounceDelay)
    }
}

@MainActor
final class FireLoginWebViewController: UIViewController, WKNavigationDelegate, WKUIDelegate,
    WKScriptMessageHandler
{
    private let viewModel: FireAppViewModel
    private let presentationState: FireAuthPresentationState
    private let progressView = UIProgressView(progressViewStyle: .bar)
    private let addressBar = FireLoginAddressBarView()
    private let errorBanner = FireLoginErrorBannerView()
    private let bottomBar = FireAuthBottomToolbarView()
    private let webView: WKWebView
    private let probeBridge: FireLoginWebViewProbeBridge
    private let scriptMessageProxy: FireLoginScriptMessageProxy
    private var cancellables: Set<AnyCancellable> = []
    private var observations: [NSKeyValueObservation] = []
    private var errorBannerHiddenHeightConstraint: NSLayoutConstraint?
    private var lastInjectedCredential: FireSavedCredential?
    private var didTearDownWebView = false

    init(
        viewModel: FireAppViewModel,
        presentationState: FireAuthPresentationState
    ) {
        self.viewModel = viewModel
        self.presentationState = presentationState
        self.probeBridge = FireLoginWebViewProbeBridge { webView in
            Task { @MainActor in
                viewModel.refreshLoginSyncReadiness(from: webView)
            }
        }
        let scriptMessageProxy = FireLoginScriptMessageProxy()
        self.scriptMessageProxy = scriptMessageProxy
        self.webView = WKWebView(
            frame: .zero,
            configuration: FireWebViewBrowserProfile.makeLoginConfiguration(
                credential: viewModel.savedLoginCredential,
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
        viewModel.prepareAuthWebView(webView)
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
        probeBridge.detach()
        webView.navigationDelegate = nil
        webView.uiDelegate = nil
        webView.configuration.userContentController.removeScriptMessageHandler(
            forName: FireLoginScripts.loginCredentialsMessageName
        )
        webView.configuration.userContentController.removeScriptMessageHandler(
            forName: FireLoginScripts.fingerprintDoneMessageName
        )
    }

    private func configureWebView() {
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.allowsBackForwardNavigationGestures = true
        FireWebViewBrowserProfile.configure(
            webView,
            preferredUserAgent: viewModel.session.browserUserAgent
        )
        probeBridge.attach(to: webView)
    }

    private func installSubviews() {
        progressView.translatesAutoresizingMaskIntoConstraints = false
        progressView.progressTintColor = .systemOrange
        progressView.trackTintColor = .clear
        progressView.isHidden = true

        addressBar.translatesAutoresizingMaskIntoConstraints = false
        errorBanner.translatesAutoresizingMaskIntoConstraints = false
        errorBanner.isHidden = true
        webView.translatesAutoresizingMaskIntoConstraints = false
        bottomBar.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(progressView)
        view.addSubview(addressBar)
        view.addSubview(errorBanner)
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
            webView.topAnchor.constraint(equalTo: errorBanner.bottomAnchor),
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
            .combineLatest(viewModel.$canSyncLoginSession)
            .receive(on: RunLoop.main)
            .sink { [weak self] _, _ in
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
                self?.refreshReadinessForActiveScene()
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
        webView.evaluateJavaScript(FireLoginScripts.credentialAutoFillSource(credential: credential))
    }

    private func handleLoadingStateChange(isLoading: Bool) {
        syncBrowserState()
        if !isLoading {
            viewModel.refreshLoginSyncReadiness(from: webView)
        }
    }

    private func refreshReadinessForActiveScene() {
        switch presentationState {
        case .login:
            viewModel.refreshLoginSyncReadiness(from: webView)
        }
    }

    private func syncBrowserState() {
        addressBar.configure(currentURL: webView.url?.absoluteString ?? webView.url?.host)
        progressView.isHidden = !webView.isLoading
        progressView.setProgress(Float(webView.estimatedProgress), animated: true)
        bottomBar.configure(
            canGoBack: webView.canGoBack,
            canGoForward: webView.canGoForward,
            isLoading: webView.isLoading,
            isRunningAction: viewModel.isSyncingLoginSession,
            canPerformPrimaryAction: viewModel.canSyncLoginSession,
            primaryTitle: viewModel.isSyncingLoginSession ? "同步中..." : "完成登录"
        )
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
        switch presentationState {
        case .login:
            viewModel.completeLogin(from: webView)
        }
    }

    private func syncBrowserStateAndProbe(_ webView: WKWebView) {
        syncBrowserState()
        probeBridge.attach(to: webView)
        probeBridge.requestProbe()
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
        syncBrowserStateAndProbe(webView)
    }

    func webView(
        _ webView: WKWebView,
        didFail navigation: WKNavigation!,
        withError error: Error
    ) {
        syncBrowserStateAndProbe(webView)
    }

    func webView(
        _ webView: WKWebView,
        didFailProvisionalNavigation navigation: WKNavigation!,
        withError error: Error
    ) {
        syncBrowserStateAndProbe(webView)
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        syncBrowserStateAndProbe(webView)
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
        case FireLoginScripts.loginCredentialsMessageName:
            guard
                let body = message.body as? [String: Any],
                let username = body["username"] as? String,
                let password = body["password"] as? String
            else {
                return
            }
            viewModel.saveLoginCredential(username: username, password: password)
        case FireLoginScripts.fingerprintDoneMessageName:
            viewModel.recordLoginFingerprintDone()
        default:
            break
        }
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
            title: "完成登录",
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
