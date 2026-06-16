import Combine
import UIKit
import WebKit

/// Pure-native login page. No WebView is embedded in this controller; hCaptcha
/// and JS login requests run in `FireCaptchaLoginDialogController`.
@MainActor
final class FireLoginViewController: UIViewController {
    private let viewModel: FireAppViewModel
    private var cancellables = Set<AnyCancellable>()

    private let scrollView = UIScrollView()
    private let contentView = UIView()
    private let logoImageView = UIImageView()
    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()
    private let identifierField = UITextField()
    private let passwordField = UITextField()
    private let rememberSwitch = UISwitch()
    private let rememberLabel = UILabel()
    private let loginButton = UIButton(type: .system)
    private let forgotPasswordButton = UIButton(type: .system)
    private let dividerLabel = UILabel()
    private let otherMethodsButton = UIButton(type: .system)
    private let errorBannerContainer = UIView()
    private let errorBannerImageView = UIImageView()
    private let errorBannerLabel = UILabel()
    private let activityIndicator = UIActivityIndicatorView(style: .large)

    private var captchaDialog: FireCaptchaLoginDialogController?
    private var cfRetryUsed = false
    private var pendingIdentifier = ""
    private var pendingPassword = ""
    private var pendingRememberCredential = false
    private var hasShownSecondFactor = false
    private var errorBannerDismissWorkItem: DispatchWorkItem?

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
        view.backgroundColor = .systemBackground
        setupNavigation()
        setupScrollView()
        setupLogo()
        setupCredentialFields()
        setupRememberPassword()
        setupLoginButton()
        setupForgotPassword()
        setupOtherMethods()
        setupErrorBanner()
        setupActivityIndicator()
        observeViewModelState()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        viewModel.setAPMRoute("auth.login")
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        if isBeingDismissed || navigationController?.isBeingDismissed == true {
            viewModel.restoreTopLevelAPMRoute()
        }
    }

    private func observeViewModelState() {
        viewModel.$savedLoginCredential
            .receive(on: RunLoop.main)
            .sink { [weak self] credential in
                guard let self else { return }
                guard let credential else {
                    self.identifierField.text = nil
                    self.passwordField.text = nil
                    self.rememberSwitch.isOn = false
                    self.updateLoginButtonState()
                    return
                }
                self.identifierField.text = credential.username
                self.passwordField.text = credential.password
                self.rememberSwitch.isOn = true
                self.updateLoginButtonState()
            }
            .store(in: &cancellables)

        viewModel.$errorMessage
            .receive(on: RunLoop.main)
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .sink { [weak self] message in
                guard let self, self.captchaDialog != nil else { return }
                self.setLoginLoading(false)
                self.dismissCaptchaDialog()
                self.showErrorBanner(message)
            }
            .store(in: &cancellables)

        viewModel.$isSyncingLoginSession
            .receive(on: RunLoop.main)
            .sink { [weak self] isSyncing in
                guard let self, !isSyncing, self.viewModel.authPresentationState != nil else {
                    return
                }
                self.setLoginLoading(false)
            }
            .store(in: &cancellables)
    }

    private func setupNavigation() {
        title = "登录 LinuxDo"
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            title: "关闭",
            style: .plain,
            target: self,
            action: #selector(closeTapped)
        )
    }

    private func setupScrollView() {
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.keyboardDismissMode = .interactive
        view.addSubview(scrollView)

        contentView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(contentView)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),

            contentView.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            contentView.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            contentView.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            contentView.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            contentView.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor),
        ])
    }

    private func setupLogo() {
        logoImageView.translatesAutoresizingMaskIntoConstraints = false
        logoImageView.image = UIImage(systemName: "flame.fill")
        logoImageView.tintColor = .systemOrange
        logoImageView.contentMode = .scaleAspectFit

        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.text = "Fire"
        titleLabel.font = .systemFont(ofSize: 32, weight: .bold)
        titleLabel.textAlignment = .center

        subtitleLabel.translatesAutoresizingMaskIntoConstraints = false
        subtitleLabel.text = "LinuxDo 社区客户端"
        subtitleLabel.font = .systemFont(ofSize: 15)
        subtitleLabel.textColor = .secondaryLabel
        subtitleLabel.textAlignment = .center

        contentView.addSubview(logoImageView)
        contentView.addSubview(titleLabel)
        contentView.addSubview(subtitleLabel)

        NSLayoutConstraint.activate([
            logoImageView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 48),
            logoImageView.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            logoImageView.widthAnchor.constraint(equalToConstant: 72),
            logoImageView.heightAnchor.constraint(equalToConstant: 72),

            titleLabel.topAnchor.constraint(equalTo: logoImageView.bottomAnchor, constant: 16),
            titleLabel.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),

            subtitleLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 4),
            subtitleLabel.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
        ])
    }

    private func setupCredentialFields() {
        configureTextField(identifierField, placeholder: "用户名或邮箱", secure: false)
        identifierField.returnKeyType = .next
        identifierField.addTarget(self, action: #selector(textFieldsChanged), for: .editingChanged)

        configureTextField(passwordField, placeholder: "密码", secure: true)
        passwordField.returnKeyType = .go
        passwordField.addTarget(self, action: #selector(textFieldsChanged), for: .editingChanged)

        contentView.addSubview(identifierField)
        contentView.addSubview(passwordField)

        NSLayoutConstraint.activate([
            identifierField.topAnchor.constraint(equalTo: subtitleLabel.bottomAnchor, constant: 32),
            identifierField.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 24),
            identifierField.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -24),
            identifierField.heightAnchor.constraint(equalToConstant: 48),

            passwordField.topAnchor.constraint(equalTo: identifierField.bottomAnchor, constant: 12),
            passwordField.leadingAnchor.constraint(equalTo: identifierField.leadingAnchor),
            passwordField.trailingAnchor.constraint(equalTo: identifierField.trailingAnchor),
            passwordField.heightAnchor.constraint(equalToConstant: 48),
        ])
    }

    private func configureTextField(_ field: UITextField, placeholder: String, secure: Bool) {
        field.translatesAutoresizingMaskIntoConstraints = false
        field.placeholder = placeholder
        field.borderStyle = .roundedRect
        field.autocapitalizationType = .none
        field.autocorrectionType = .no
        field.clearButtonMode = .whileEditing
        field.isSecureTextEntry = secure
        field.textContentType = secure ? .password : .username
    }

    private func setupRememberPassword() {
        rememberSwitch.translatesAutoresizingMaskIntoConstraints = false
        rememberSwitch.onTintColor = .systemOrange

        rememberLabel.translatesAutoresizingMaskIntoConstraints = false
        rememberLabel.text = "记住账号密码"
        rememberLabel.font = .systemFont(ofSize: 15)
        rememberLabel.textColor = .secondaryLabel
        rememberLabel.isUserInteractionEnabled = true
        rememberLabel.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(rememberLabelTapped)))

        contentView.addSubview(rememberSwitch)
        contentView.addSubview(rememberLabel)

        NSLayoutConstraint.activate([
            rememberSwitch.topAnchor.constraint(equalTo: passwordField.bottomAnchor, constant: 12),
            rememberSwitch.leadingAnchor.constraint(equalTo: identifierField.leadingAnchor),

            rememberLabel.centerYAnchor.constraint(equalTo: rememberSwitch.centerYAnchor),
            rememberLabel.leadingAnchor.constraint(equalTo: rememberSwitch.trailingAnchor, constant: 8),
        ])
    }

    private func setupLoginButton() {
        loginButton.translatesAutoresizingMaskIntoConstraints = false
        var configuration = UIButton.Configuration.filled()
        configuration.title = "登录"
        configuration.baseBackgroundColor = .systemOrange
        configuration.baseForegroundColor = .white
        configuration.cornerStyle = .medium
        loginButton.configuration = configuration
        loginButton.addTarget(self, action: #selector(loginTapped), for: .touchUpInside)
        loginButton.isEnabled = false

        contentView.addSubview(loginButton)

        NSLayoutConstraint.activate([
            loginButton.topAnchor.constraint(equalTo: rememberSwitch.bottomAnchor, constant: 20),
            loginButton.leadingAnchor.constraint(equalTo: identifierField.leadingAnchor),
            loginButton.trailingAnchor.constraint(equalTo: identifierField.trailingAnchor),
            loginButton.heightAnchor.constraint(equalToConstant: 50),
        ])
    }

    private func setupForgotPassword() {
        forgotPasswordButton.translatesAutoresizingMaskIntoConstraints = false
        forgotPasswordButton.setTitle("忘记密码?", for: .normal)
        forgotPasswordButton.titleLabel?.font = .systemFont(ofSize: 14)
        forgotPasswordButton.setTitleColor(.secondaryLabel, for: .normal)
        forgotPasswordButton.addTarget(self, action: #selector(forgotPasswordTapped), for: .touchUpInside)

        contentView.addSubview(forgotPasswordButton)

        NSLayoutConstraint.activate([
            forgotPasswordButton.topAnchor.constraint(equalTo: loginButton.bottomAnchor, constant: 12),
            forgotPasswordButton.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
        ])
    }

    private func setupOtherMethods() {
        dividerLabel.translatesAutoresizingMaskIntoConstraints = false
        dividerLabel.text = "- 其他方式 -"
        dividerLabel.font = .systemFont(ofSize: 13)
        dividerLabel.textColor = .tertiaryLabel
        dividerLabel.textAlignment = .center

        otherMethodsButton.translatesAutoresizingMaskIntoConstraints = false
        var configuration = UIButton.Configuration.bordered()
        configuration.title = "其他方式登录 (OAuth / Passkey)"
        configuration.image = UIImage(systemName: "globe")
        configuration.imagePadding = 8
        configuration.cornerStyle = .medium
        otherMethodsButton.configuration = configuration
        otherMethodsButton.addTarget(self, action: #selector(otherMethodsTapped), for: .touchUpInside)

        contentView.addSubview(dividerLabel)
        contentView.addSubview(otherMethodsButton)

        NSLayoutConstraint.activate([
            dividerLabel.topAnchor.constraint(equalTo: forgotPasswordButton.bottomAnchor, constant: 20),
            dividerLabel.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),

            otherMethodsButton.topAnchor.constraint(equalTo: dividerLabel.bottomAnchor, constant: 12),
            otherMethodsButton.leadingAnchor.constraint(equalTo: identifierField.leadingAnchor),
            otherMethodsButton.trailingAnchor.constraint(equalTo: identifierField.trailingAnchor),
            otherMethodsButton.heightAnchor.constraint(greaterThanOrEqualToConstant: 44),
            otherMethodsButton.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -32),
        ])
    }

    private func setupErrorBanner() {
        errorBannerContainer.translatesAutoresizingMaskIntoConstraints = false
        errorBannerContainer.backgroundColor = UIColor.systemRed.withAlphaComponent(0.1)
        errorBannerContainer.layer.cornerRadius = 8
        errorBannerContainer.isHidden = true
        errorBannerContainer.alpha = 0

        errorBannerImageView.translatesAutoresizingMaskIntoConstraints = false
        errorBannerImageView.image = UIImage(systemName: "exclamationmark.triangle.fill")
        errorBannerImageView.tintColor = .systemRed

        errorBannerLabel.translatesAutoresizingMaskIntoConstraints = false
        errorBannerLabel.font = .systemFont(ofSize: 14)
        errorBannerLabel.textColor = .systemRed
        errorBannerLabel.numberOfLines = 0

        errorBannerContainer.addSubview(errorBannerImageView)
        errorBannerContainer.addSubview(errorBannerLabel)
        view.addSubview(errorBannerContainer)

        NSLayoutConstraint.activate([
            errorBannerContainer.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8),
            errorBannerContainer.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            errorBannerContainer.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),

            errorBannerImageView.topAnchor.constraint(equalTo: errorBannerContainer.topAnchor, constant: 12),
            errorBannerImageView.leadingAnchor.constraint(equalTo: errorBannerContainer.leadingAnchor, constant: 12),
            errorBannerImageView.widthAnchor.constraint(equalToConstant: 20),
            errorBannerImageView.heightAnchor.constraint(equalToConstant: 20),
            errorBannerImageView.bottomAnchor.constraint(lessThanOrEqualTo: errorBannerContainer.bottomAnchor, constant: -12),

            errorBannerLabel.topAnchor.constraint(equalTo: errorBannerContainer.topAnchor, constant: 12),
            errorBannerLabel.leadingAnchor.constraint(equalTo: errorBannerImageView.trailingAnchor, constant: 8),
            errorBannerLabel.trailingAnchor.constraint(equalTo: errorBannerContainer.trailingAnchor, constant: -12),
            errorBannerLabel.bottomAnchor.constraint(equalTo: errorBannerContainer.bottomAnchor, constant: -12),
        ])
    }

    private func setupActivityIndicator() {
        activityIndicator.translatesAutoresizingMaskIntoConstraints = false
        activityIndicator.hidesWhenStopped = true
        view.addSubview(activityIndicator)

        NSLayoutConstraint.activate([
            activityIndicator.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            activityIndicator.centerYAnchor.constraint(equalTo: view.centerYAnchor),
        ])
    }

    @objc private func closeTapped() {
        viewModel.dismissAuthPresentation()
    }

    @objc private func textFieldsChanged() {
        updateLoginButtonState()
        hideErrorBanner()
    }

    @objc private func rememberLabelTapped() {
        rememberSwitch.setOn(!rememberSwitch.isOn, animated: true)
    }

    @objc private func loginTapped() {
        guard let identifier = identifierField.text?.trimmingCharacters(in: .whitespacesAndNewlines),
              let password = passwordField.text,
              !identifier.isEmpty,
              !password.isEmpty
        else {
            return
        }

        pendingIdentifier = identifier
        pendingPassword = password
        pendingRememberCredential = rememberSwitch.isOn
        cfRetryUsed = false
        hasShownSecondFactor = false
        hideErrorBanner()
        setLoginLoading(true)

        Task { await performLogin() }
    }

    @objc private func forgotPasswordTapped() {
        presentWebViewBrowser(url: URL(string: "https://linux.do/password-reset")!)
    }

    @objc private func otherMethodsTapped() {
        presentWebViewBrowser(url: URL(string: "https://linux.do/login")!)
    }

    private func performLogin() async {
        let hasCloudflareClearance = await viewModel.ensureCloudflareClearance()
        guard hasCloudflareClearance else {
            setLoginLoading(false)
            showErrorBanner("网络验证失败，请重试")
            return
        }

        let loginCoordinator: FireWebViewLoginCoordinator
        do {
            loginCoordinator = try await viewModel.loginCoordinatorForDialog()
        } catch {
            setLoginLoading(false)
            showErrorBanner("网络准备失败，请重试")
            return
        }

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
                self?.setLoginLoading(false)
                self?.captchaDialog = nil
            }
        )

        dialog.classifyResult = { [weak self, weak dialog] phase, status, body in
            guard let self, let dialog else { return }
            Task {
                do {
                    let decision = try await self.viewModel.classifyLoginResult(
                        phase: phase,
                        status: status,
                        body: body
                    )
                    dialog.dispatchResult(self.dialogResult(from: decision))
                } catch {
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
        switch result {
        case .success:
            completeLoginFromDialog()
        case let .needSecondFactor(requirement):
            showSecondFactorPrompt(requirement: requirement)
        case .retryCloudflare:
            recoverCloudflare()
        case let .failure(failure):
            setLoginLoading(false)
            dismissCaptchaDialog()
            showErrorBanner(failure.message ?? "登录失败")
            if failure.kind == .invalidCredentials {
                passwordField.text = nil
                updateLoginButtonState()
            }
        }
    }

    private func completeLoginFromDialog() {
        guard let dialog = captchaDialog else { return }
        viewModel.completeMinimalLogin(
            from: dialog.webView,
            identifier: pendingIdentifier,
            password: pendingPassword,
            rememberCredential: pendingRememberCredential
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
            self?.setLoginLoading(false)
            self?.dismissCaptchaDialog()
        })
        (captchaDialog ?? self).present(alert, animated: true)
    }

    private func recoverCloudflare() {
        guard !cfRetryUsed else {
            setLoginLoading(false)
            dismissCaptchaDialog()
            showErrorBanner("网络验证失败，请稍后重试")
            return
        }
        cfRetryUsed = true

        Task {
            guard let dialog = captchaDialog else { return }
            do {
                try await viewModel.recoverLoginCloudflareChallenge(in: dialog.webView)
            } catch {
                setLoginLoading(false)
                dismissCaptchaDialog()
                showErrorBanner("网络验证失败，请重试")
                return
            }
            dialog.retryAfterCloudflareRecovery()
        }
    }

    private func presentWebViewBrowser(url: URL) {
        let browser = FireWebViewBrowserViewController(url: url, viewModel: viewModel)
        browser.modalPresentationStyle = .fullScreen
        present(browser, animated: true)
    }

    private func updateLoginButtonState() {
        let hasIdentifier = !(identifierField.text?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
        let hasPassword = !(passwordField.text?.isEmpty ?? true)
        loginButton.isEnabled = hasIdentifier && hasPassword
    }

    private func setLoginLoading(_ loading: Bool) {
        if loading {
            activityIndicator.startAnimating()
            loginButton.isEnabled = false
            view.isUserInteractionEnabled = false
        } else {
            activityIndicator.stopAnimating()
            view.isUserInteractionEnabled = true
            updateLoginButtonState()
        }
    }

    private func showErrorBanner(_ message: String) {
        errorBannerDismissWorkItem?.cancel()
        errorBannerLabel.text = message
        errorBannerContainer.isHidden = false
        UIView.animate(withDuration: 0.25) {
            self.errorBannerContainer.alpha = 1
        }

        let workItem = DispatchWorkItem { [weak self] in
            self?.hideErrorBanner()
        }
        errorBannerDismissWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 4, execute: workItem)
    }

    private func hideErrorBanner() {
        errorBannerDismissWorkItem?.cancel()
        guard !errorBannerContainer.isHidden else { return }
        UIView.animate(withDuration: 0.25, animations: {
            self.errorBannerContainer.alpha = 0
        }) { [weak self] _ in
            self?.errorBannerContainer.isHidden = true
        }
    }

    private func dismissCaptchaDialog() {
        captchaDialog?.dismiss(animated: true) { [weak self] in
            self?.captchaDialog = nil
        }
    }
}
