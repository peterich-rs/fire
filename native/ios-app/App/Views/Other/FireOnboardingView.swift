import Combine
import SwiftUI
import UIKit

@MainActor
final class FireOnboardingViewController: UIViewController {
    private enum FireOnboardingPhase: Equatable {
        case validating
        case credential
        case loggingIn
    }

    private let viewModel: FireAppViewModel
    private let brandStack = UIStackView()
    private let bottomStack = UIStackView()
    private let errorBanner = FireOnboardingErrorBannerView()
    private let phaseContainerView = UIView()
    private let developerToolsButton = UIButton(type: .system)
    private var bottomStackBottomConstraint: NSLayoutConstraint?
    private lazy var validatingView = FireOnboardingValidatingView()
    private lazy var credentialFormView = FireOnboardingCredentialFormView()
    private lazy var loggingInView = FireOnboardingLoggingInView()
    private var phase: FireOnboardingPhase = .validating
    private var errorDismissWorkItem: DispatchWorkItem?
    private var cancellables: Set<AnyCancellable> = []

    private var captchaDialog: FireCaptchaLoginDialogController?
    private var cfRetryUsed = false
    private var pendingIdentifier = ""
    private var pendingPassword = ""
    private var pendingRememberCredential = false
    private var hasShownSecondFactor = false

    init(viewModel: FireAppViewModel) {
        self.viewModel = viewModel
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        // Single full-bleed canvas — no system navigation chrome strip on the login page.
        view.backgroundColor = FireTheme.uiCanvas
        navigationItem.largeTitleDisplayMode = .never

        configureBrand()
        configureDeveloperToolsButton()
        configureBottomControls()
        installKeyboardDismissGesture()
        observeKeyboardNotifications()
        bindState()
        installValidatingPhaseInitial()
        Task { await viewModel.performStartupValidation() }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        // Hide the hosting UINavigationController bar so login is one continuous page.
        navigationController?.setNavigationBarHidden(true, animated: animated)
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    private func configureBrand() {
        let imageView = UIImageView(image: UIImage(systemName: "flame.fill"))
        imageView.tintColor = .systemOrange
        imageView.contentMode = .scaleAspectFit

        let titleLabel = UILabel()
        titleLabel.text = "Fire"
        titleLabel.font = UIFont.preferredFont(forTextStyle: .title1).withOnboardingWeight(.bold)
        titleLabel.adjustsFontForContentSizeCategory = true
        titleLabel.textColor = .label
        titleLabel.textAlignment = .center

        let subtitleLabel = UILabel()
        subtitleLabel.text = "LinuxDo 原生客户端"
        subtitleLabel.font = UIFont.preferredFont(forTextStyle: .subheadline)
        subtitleLabel.adjustsFontForContentSizeCategory = true
        subtitleLabel.textColor = .secondaryLabel
        subtitleLabel.textAlignment = .center

        let textStack = UIStackView(arrangedSubviews: [titleLabel, subtitleLabel])
        textStack.axis = .vertical
        textStack.alignment = .center
        textStack.spacing = 4

        brandStack.axis = .vertical
        brandStack.alignment = .center
        brandStack.spacing = 10
        brandStack.translatesAutoresizingMaskIntoConstraints = false
        brandStack.addArrangedSubview(imageView)
        brandStack.addArrangedSubview(textStack)

        view.addSubview(brandStack)
        NSLayoutConstraint.activate([
            imageView.widthAnchor.constraint(equalToConstant: 44),
            imageView.heightAnchor.constraint(equalToConstant: 44),
            brandStack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 28),
            brandStack.centerXAnchor.constraint(equalTo: view.safeAreaLayoutGuide.centerXAnchor),
            brandStack.leadingAnchor.constraint(greaterThanOrEqualTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 24),
            brandStack.trailingAnchor.constraint(lessThanOrEqualTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -24),
        ])
    }

    private func configureDeveloperToolsButton() {
        var configuration = UIButton.Configuration.plain()
        configuration.image = UIImage(systemName: "ant")
        configuration.baseForegroundColor = FireTheme.uiTertiaryInk
        configuration.contentInsets = NSDirectionalEdgeInsets(top: 10, leading: 10, bottom: 10, trailing: 10)
        developerToolsButton.configuration = configuration
        developerToolsButton.accessibilityLabel = "开发者工具"
        developerToolsButton.translatesAutoresizingMaskIntoConstraints = false
        developerToolsButton.addTarget(self, action: #selector(developerToolsButtonTapped), for: .touchUpInside)
        view.addSubview(developerToolsButton)
        NSLayoutConstraint.activate([
            developerToolsButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 4),
            developerToolsButton.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -8),
        ])
    }

    private func configureBottomControls() {
        errorBanner.onDismiss = { [weak self] in
            self?.viewModel.dismissError()
        }

        phaseContainerView.translatesAutoresizingMaskIntoConstraints = false

        bottomStack.axis = .vertical
        bottomStack.alignment = .fill
        bottomStack.spacing = 12
        bottomStack.translatesAutoresizingMaskIntoConstraints = false
        bottomStack.addArrangedSubview(errorBanner)
        bottomStack.addArrangedSubview(phaseContainerView)

        view.addSubview(bottomStack)
        let bottomConstraint = bottomStack.bottomAnchor.constraint(
            equalTo: view.safeAreaLayoutGuide.bottomAnchor,
            constant: -24
        )
        let topConstraint = bottomStack.topAnchor.constraint(equalTo: brandStack.bottomAnchor, constant: 24)
        topConstraint.priority = .defaultHigh
        let minimumTopConstraint = bottomStack.topAnchor.constraint(
            greaterThanOrEqualTo: brandStack.bottomAnchor,
            constant: 12
        )
        let phaseMinimumHeightConstraint = phaseContainerView.heightAnchor.constraint(
            greaterThanOrEqualToConstant: 180
        )
        phaseMinimumHeightConstraint.priority = .defaultHigh
        bottomStackBottomConstraint = bottomConstraint
        NSLayoutConstraint.activate([
            bottomStack.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 24),
            bottomStack.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -24),
            topConstraint,
            minimumTopConstraint,
            bottomConstraint,
            phaseMinimumHeightConstraint,
        ])
    }

    private func installKeyboardDismissGesture() {
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(backgroundTapped))
        tapGesture.cancelsTouchesInView = false
        view.addGestureRecognizer(tapGesture)
    }

    private func observeKeyboardNotifications() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(keyboardWillChangeFrame(_:)),
            name: UIResponder.keyboardWillChangeFrameNotification,
            object: nil
        )
    }

    private func bindState() {
        viewModel.$errorMessage
            .receive(on: RunLoop.main)
            .sink { [weak self] errorMessage in
                guard let self else { return }
                guard let errorMessage,
                      !errorMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                else {
                    self.hideErrorBanner()
                    return
                }
                // Always leave the logging-in chrome; setLoginLoading(false) alone leaves the overlay.
                if self.phase == .loggingIn {
                    self.abortLoginAttempt(message: errorMessage, source: "viewModel.errorMessage")
                } else {
                    self.showErrorBanner(errorMessage)
                }
            }
            .store(in: &cancellables)

        Publishers.CombineLatest3(
            viewModel.$isStartupValidationComplete,
            viewModel.$session,
            viewModel.$isSyncingLoginSession
        )
        .receive(on: RunLoop.main)
        .sink { [weak self] isStartupValidationComplete, session, isSyncingLoginSession in
            guard let self else { return }
            let nextPhase: FireOnboardingPhase
            if !isStartupValidationComplete {
                nextPhase = .validating
            } else if isSyncingLoginSession {
                nextPhase = .loggingIn
            } else if !session.readiness.canReadAuthenticatedApi {
                // Do not clobber an in-flight captcha attempt that is still waiting for
                // hCaptcha / session.json (isSyncingLoginSession is only true during cookie sync).
                if self.phase == .loggingIn, self.captchaDialog != nil {
                    return
                }
                nextPhase = .credential
            } else {
                // Authenticated: tear down captcha if it is still up.
                if self.captchaDialog != nil {
                    self.logAuth("authenticated session applied; dismissing captcha dialog")
                    self.dismissCaptchaDialog()
                }
                return
            }
            self.applyPhase(nextPhase)
        }
        .store(in: &cancellables)

        viewModel.$isSyncingLoginSession
            .receive(on: RunLoop.main)
            .sink { [weak self] isSyncing in
                guard let self else { return }
                if isSyncing {
                    self.logAuth("isSyncingLoginSession=true")
                    return
                }
                guard self.phase == .loggingIn else { return }
                // Cookie sync finished. If still unauthenticated, surface as a failed attempt.
                if self.viewModel.session.readiness.canReadAuthenticatedApi {
                    self.logAuth("cookie sync finished; session authenticated")
                    self.dismissCaptchaDialog()
                    return
                }
                if self.viewModel.errorMessage == nil {
                    self.abortLoginAttempt(
                        message: "登录未完成，请重试",
                        source: "isSyncingLoginSession→false unauthenticated"
                    )
                }
            }
            .store(in: &cancellables)

        viewModel.$savedLoginCredential
            .receive(on: RunLoop.main)
            .sink { [weak self] credential in
                self?.credentialFormView.applySavedCredential(credential)
            }
            .store(in: &cancellables)

        wireCredentialFormCallbacks()
    }

    private func wireCredentialFormCallbacks() {
        credentialFormView.onLoginTapped = { [weak self] identifier, password, remember in
            guard let self else { return }
            self.pendingIdentifier = identifier
            self.pendingPassword = password
            self.pendingRememberCredential = remember
            self.cfRetryUsed = false
            self.hasShownSecondFactor = false
            self.hideErrorBanner()
            self.logAuth("login tapped identifier_len=\(identifier.count) remember=\(remember)")
            self.applyPhase(.loggingIn)
            Task { await self.performLogin() }
        }
        credentialFormView.onForgotPassword = { [weak self] in
            self?.presentWebViewBrowser(url: URL(string: "https://linux.do/password-reset")!)
        }
        credentialFormView.onOtherMethods = { [weak self] in
            self?.presentWebViewBrowser(url: URL(string: "https://linux.do/login")!)
        }
    }

    private func applyPhase(_ next: FireOnboardingPhase) {
        guard phase != next else { return }

        if next == .credential, phase != .credential {
            Task { await viewModel.prepareLoginForm() }
        }

        let previous = phase
        phase = next

        if next == .loggingIn {
            setLoginLoading(true)
        } else if previous == .loggingIn {
            setLoginLoading(false)
        }

        UIView.transition(
            with: phaseContainerView,
            duration: 0.22,
            options: [.transitionCrossDissolve]
        ) {
            self.installPhaseSubviews(for: next, replacing: previous)
        }
    }

    private func installValidatingPhaseInitial() {
        phaseContainerView.addSubview(validatingView)
        validatingView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            validatingView.topAnchor.constraint(equalTo: phaseContainerView.topAnchor),
            validatingView.leadingAnchor.constraint(equalTo: phaseContainerView.leadingAnchor),
            validatingView.trailingAnchor.constraint(equalTo: phaseContainerView.trailingAnchor),
            validatingView.bottomAnchor.constraint(equalTo: phaseContainerView.bottomAnchor),
        ])
        validatingView.configure(isAnimating: true, message: "正在校验登录态…")
    }

    private func installPhaseSubviews(for next: FireOnboardingPhase, replacing previous: FireOnboardingPhase) {
        if previous == .loggingIn {
            credentialFormView.setLoggingIn(false)
            loggingInView.removeFromSuperview()
        }

        validatingView.removeFromSuperview()
        credentialFormView.removeFromSuperview()

        switch next {
        case .validating:
            phaseContainerView.addSubview(validatingView)
            validatingView.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                validatingView.topAnchor.constraint(equalTo: phaseContainerView.topAnchor),
                validatingView.leadingAnchor.constraint(equalTo: phaseContainerView.leadingAnchor),
                validatingView.trailingAnchor.constraint(equalTo: phaseContainerView.trailingAnchor),
                validatingView.bottomAnchor.constraint(equalTo: phaseContainerView.bottomAnchor),
            ])
            validatingView.configure(isAnimating: true, message: "正在校验登录态…")

        case .credential:
            phaseContainerView.addSubview(credentialFormView)
            credentialFormView.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                credentialFormView.topAnchor.constraint(equalTo: phaseContainerView.topAnchor),
                credentialFormView.leadingAnchor.constraint(equalTo: phaseContainerView.leadingAnchor),
                credentialFormView.trailingAnchor.constraint(equalTo: phaseContainerView.trailingAnchor),
                credentialFormView.bottomAnchor.constraint(equalTo: phaseContainerView.bottomAnchor),
            ])

        case .loggingIn:
            phaseContainerView.addSubview(credentialFormView)
            credentialFormView.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                credentialFormView.topAnchor.constraint(equalTo: phaseContainerView.topAnchor),
                credentialFormView.leadingAnchor.constraint(equalTo: phaseContainerView.leadingAnchor),
                credentialFormView.trailingAnchor.constraint(equalTo: phaseContainerView.trailingAnchor),
                credentialFormView.bottomAnchor.constraint(equalTo: phaseContainerView.bottomAnchor),
            ])
            credentialFormView.setLoggingIn(true)

            phaseContainerView.addSubview(loggingInView)
            loggingInView.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                loggingInView.topAnchor.constraint(equalTo: phaseContainerView.topAnchor),
                loggingInView.leadingAnchor.constraint(equalTo: phaseContainerView.leadingAnchor),
                loggingInView.trailingAnchor.constraint(equalTo: phaseContainerView.trailingAnchor),
                loggingInView.bottomAnchor.constraint(equalTo: phaseContainerView.bottomAnchor),
            ])
        }
    }

    private func showErrorBanner(_ message: String) {
        errorDismissWorkItem?.cancel()
        errorBanner.configure(message: message)
        errorBanner.isHidden = false

        let workItem = DispatchWorkItem { [weak self] in
            self?.hideErrorBanner()
        }
        errorDismissWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 4, execute: workItem)
    }

    private func hideErrorBanner() {
        errorDismissWorkItem?.cancel()
        errorDismissWorkItem = nil
        errorBanner.isHidden = true
    }

    private func performLogin() async {
        logAuth("performLogin begin; ensuring cloudflare clearance")
        let hasCloudflareClearance = await viewModel.ensureCloudflareClearance()
        guard hasCloudflareClearance else {
            abortLoginAttempt(message: "网络验证失败，请重试", source: "ensureCloudflareClearance")
            return
        }

        let loginCoordinator: FireWebViewLoginCoordinator
        do {
            loginCoordinator = try await viewModel.loginCoordinatorForDialog()
        } catch {
            abortLoginAttempt(
                message: "网络准备失败，请重试",
                source: "loginCoordinatorForDialog: \(error.localizedDescription)"
            )
            return
        }

        logAuth("presenting captcha dialog")
        presentCaptchaDialog(loginCoordinator: loginCoordinator)
    }

    private func presentCaptchaDialog(loginCoordinator: FireWebViewLoginCoordinator) {
        let dialog = FireCaptchaLoginDialogController(
            identifier: pendingIdentifier,
            password: pendingPassword,
            loginCoordinator: loginCoordinator,
            onResult: { [weak self] result in
                self?.handleDialogResult(result)
            },
            onCancel: { [weak self] in
                self?.abortLoginAttempt(message: nil, source: "captchaDialog.cancel")
            }
        )

        dialog.classifyResult = { [weak self, weak dialog] phase, status, body in
            guard let self, let dialog else { return }
            self.logAuth(
                "login_result bridge phase=\(String(describing: phase)) status=\(status) body_len=\(body.count)"
            )
            Task {
                do {
                    let decision = try await self.viewModel.classifyLoginResult(
                        phase: phase,
                        status: status,
                        body: body
                    )
                    self.logAuth("classifyLoginResult decision=\(String(describing: decision))")
                    dialog.dispatchResult(self.dialogResult(from: decision))
                } catch {
                    self.logAuth("classifyLoginResult failed: \(error.localizedDescription)")
                    dialog.dispatchResult(
                        .failure(
                            LoginFailureState(
                                kind: .unknown,
                                message: error.localizedDescription,
                                sentToEmail: nil,
                                currentEmail: nil
                            )
                        )
                    )
                }
            }
        }

        captchaDialog = dialog
        present(dialog, animated: true)
    }

    private func dialogResult(from decision: WebViewLoginDecisionState) -> FireCaptchaDialogResult {
        switch decision {
        case .success:
            return .success
        case let .needSecondFactor(requirement):
            return .needSecondFactor(requirement)
        case .retryCloudflare:
            return .retryCloudflare
        case let .failure(failure):
            return .failure(failure)
        }
    }

    private func handleDialogResult(_ result: FireCaptchaDialogResult) {
        logAuth("captcha dialog result=\(String(describing: result))")
        switch result {
        case .success:
            completeLoginFromDialog()
        case let .needSecondFactor(requirement):
            showSecondFactorPrompt(requirement: requirement)
        case .retryCloudflare:
            recoverCloudflare()
        case let .failure(failure):
            // Keep the typed account/password so the user can fix a typo and retry.
            abortLoginAttempt(
                message: failure.message ?? "登录失败",
                source: "captchaDialog.failure kind=\(String(describing: failure.kind))"
            )
        }
    }

    private func completeLoginFromDialog() {
        guard let dialog = captchaDialog else {
            abortLoginAttempt(message: "登录状态丢失，请重试", source: "completeLoginFromDialog missing dialog")
            return
        }
        logAuth("completeMinimalLogin begin; keeping captcha webView alive for cookie extraction")
        viewModel.completeMinimalLogin(
            from: dialog.webView,
            identifier: pendingIdentifier,
            password: pendingPassword,
            rememberCredential: pendingRememberCredential
        )
    }

    /// Tear down captcha + logging-in overlay and return to the credential form.
    private func abortLoginAttempt(message: String?, source: String) {
        logAuth("abortLoginAttempt source=\(source) message=\(message ?? "nil")")
        dismissCaptchaDialog()
        if viewModel.session.readiness.canReadAuthenticatedApi {
            setLoginLoading(false)
            return
        }
        applyPhase(.credential)
        if let message, !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            showErrorBanner(message)
        }
    }

    private func logAuth(_ message: String) {
        FireAPMManager.shared.recordBreadcrumb(
            level: "info",
            target: "auth.login",
            message: message
        )
    }

    private func showSecondFactorPrompt(requirement: SecondFactorRequirementState) {
        let isFirstAttempt = !hasShownSecondFactor
        hasShownSecondFactor = true

        let fallbackHint: String?
        if !requirement.totpEnabled && (requirement.backupEnabled || requirement.securityKeyEnabled) {
            fallbackHint = "备用码或安全密钥请通过其他方式登录。"
        } else {
            fallbackHint = nil
        }
        let baseMessage = requirement.message ?? "请输入验证器中的 6 位代码"
        let message = [baseMessage, fallbackHint].compactMap { $0 }.joined(separator: "\n")

        let alert = UIAlertController(
            title: isFirstAttempt ? "两步验证" : "验证码错误",
            message: message,
            preferredStyle: .alert
        )
        alert.addTextField { field in
            field.placeholder = "6 位验证码"
            field.keyboardType = .numberPad
            field.textContentType = .oneTimeCode
        }
        alert.addAction(UIAlertAction(title: "确定", style: .default) { [weak self, weak alert] _ in
            guard let self else { return }
            guard let code = alert?.textFields?.first?.text?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !code.isEmpty
            else {
                return
            }
            self.captchaDialog?.retryWithSecondFactor(code)
        })
        alert.addAction(UIAlertAction(title: "取消", style: .cancel) { [weak self] _ in
            self?.abortLoginAttempt(message: nil, source: "secondFactor.cancel")
        })
        (captchaDialog ?? self).present(alert, animated: true)
    }

    private func recoverCloudflare() {
        guard !cfRetryUsed else {
            abortLoginAttempt(message: "网络验证失败，请稍后重试", source: "recoverCloudflare already used")
            return
        }
        cfRetryUsed = true
        logAuth("recoverCloudflare begin")

        Task {
            guard let dialog = captchaDialog else {
                abortLoginAttempt(message: "网络验证失败，请重试", source: "recoverCloudflare missing dialog")
                return
            }
            do {
                try await viewModel.recoverLoginCloudflareChallenge(in: dialog.webView)
            } catch {
                abortLoginAttempt(
                    message: "网络验证失败，请重试",
                    source: "recoverCloudflare: \(error.localizedDescription)"
                )
                return
            }
            logAuth("recoverCloudflare done; retrying login in dialog")
            dialog.retryAfterCloudflareRecovery()
        }
    }

    private func presentWebViewBrowser(url: URL) {
        let browser = FireWebViewBrowserViewController(url: url, viewModel: viewModel)
        browser.modalPresentationStyle = .fullScreen
        present(browser, animated: true)
    }

    private func setLoginLoading(_ loading: Bool) {
        if loading {
            view.endEditing(true)
        }
        credentialFormView.setLoggingIn(loading)
        view.isUserInteractionEnabled = !loading
    }

    private func dismissCaptchaDialog() {
        captchaDialog?.dismiss(animated: true) { [weak self] in
            self?.captchaDialog = nil
        }
    }

    @objc private func developerToolsButtonTapped() {
        let controller = FireHosting.controller(
            rootView: FireDeveloperToolsView(viewModel: viewModel),
            title: "开发者工具"
        )
        // Show nav chrome only for the pushed diagnostics page; login itself stays bar-less.
        navigationController?.setNavigationBarHidden(false, animated: true)
        navigationController?.pushViewController(controller, animated: true)
    }

    @objc private func backgroundTapped() {
        view.endEditing(true)
    }

    @objc private func keyboardWillChangeFrame(_ notification: Notification) {
        guard let frameEnd = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect else {
            return
        }

        let convertedFrame = view.convert(frameEnd, from: nil)
        let overlap = max(0, view.bounds.maxY - convertedFrame.minY - view.safeAreaInsets.bottom)
        bottomStackBottomConstraint?.constant = overlap > 0 ? -(overlap + 12) : -24

        let duration = notification.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? TimeInterval
            ?? 0.25
        let curve = notification.userInfo?[UIResponder.keyboardAnimationCurveUserInfoKey] as? UInt
            ?? UIView.AnimationOptions.curveEaseInOut.rawValue
        UIView.animate(
            withDuration: duration,
            delay: 0,
            options: UIView.AnimationOptions(rawValue: curve << 16)
        ) {
            self.view.layoutIfNeeded()
        }
    }
}

private final class FireOnboardingErrorBannerView: UIView {
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
        backgroundColor = .tertiarySystemFill
        layer.cornerRadius = FireTheme.smallCornerRadius
        layer.cornerCurve = .continuous
        directionalLayoutMargins = NSDirectionalEdgeInsets(
            top: 12,
            leading: 12,
            bottom: 12,
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
        closeButton.tintColor = .secondaryLabel
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
            imageView.widthAnchor.constraint(equalToConstant: 18),
            imageView.heightAnchor.constraint(equalToConstant: 18),
            closeButton.widthAnchor.constraint(equalToConstant: 30),
            closeButton.heightAnchor.constraint(equalToConstant: 30),
            stackView.leadingAnchor.constraint(equalTo: layoutMarginsGuide.leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: layoutMarginsGuide.trailingAnchor),
            stackView.topAnchor.constraint(equalTo: layoutMarginsGuide.topAnchor),
            stackView.bottomAnchor.constraint(equalTo: layoutMarginsGuide.bottomAnchor),
        ])
    }
}

private extension UIFont {
    func withOnboardingWeight(_ weight: Weight) -> UIFont {
        let descriptor = fontDescriptor.addingAttributes([
            .traits: [UIFontDescriptor.TraitKey.weight: weight],
        ])
        return UIFont(descriptor: descriptor, size: pointSize)
    }
}
