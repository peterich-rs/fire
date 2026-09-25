import Combine
import SwiftUI
import UIKit

@MainActor
final class FireOnboardingViewController: UIViewController {
    enum FireOnboardingPhase: Equatable {
        case validating
        case credential
        case loggingIn
    }

    let viewModel: FireAppViewModel
    let entry: FireOnboardingEntry
    let contentColumn = UIStackView()
    let brandStack = UIStackView()
    let bottomStack = UIStackView()
    let errorBanner = FireOnboardingErrorBannerView()
    let phaseContainerView = UIView()
    let developerToolsButton = UIButton(type: .system)
    let feedbackButton = UIButton(type: .system)
    var contentCenterYConstraint: NSLayoutConstraint?
    var contentTopConstraint: NSLayoutConstraint?
    var contentBottomConstraint: NSLayoutConstraint?
    lazy var validatingView = FireOnboardingValidatingView()
    lazy var credentialFormView = FireOnboardingCredentialFormView()
    var phase: FireOnboardingPhase = .validating
    var errorDismissWorkItem: DispatchWorkItem?
    var cancellables: Set<AnyCancellable> = []

    var captchaDialog: FireCaptchaLoginDialogController?
    var cfRetryUsed = false
    var pendingIdentifier = ""
    var pendingPassword = ""
    var pendingRememberCredential = false
    var hasShownSecondFactor = false
    var loggingInMessage = "正在登录…"
    /// Cold-start post-validation routing: pending → routing → finished.
    enum StartupRouteState {
        case pending
        case routing
        case finished
    }

    var startupRouteState: StartupRouteState = .pending
    var isAutoLoginInFlight = false
    var activeAutoLoginKind: FireAutoLoginKind?
    var headlessExternalEngine: FireHeadlessExternalLoginEngine?

    init(viewModel: FireAppViewModel, entry: FireOnboardingEntry = .coldStart) {
        self.viewModel = viewModel
        self.entry = entry
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
        configureFeedbackButton()
        configureBottomControls()
        configureRootLayout()
        installKeyboardDismissGesture()
        observeKeyboardNotifications()
        bindState()
        validatingView.onCancel = { [weak self] in
            self?.cancelAutoLogin(source: "loading.cancel")
        }
        switch entry {
        case .coldStart:
            installValidatingPhaseInitial()
            Task { await viewModel.performStartupValidation() }
        case .sessionExpired:
            // Mid-session invalidation fallback: skip startup probe, try headless auto-login.
            installValidatingPhaseInitial()
            Task { await self.routeAfterSessionExpired() }
        case .signedOut:
            // Explicit logout: skip splash validation + auto-login; show the login form.
            startupRouteState = .finished
            phase = .credential
            installPhaseSubviews(for: .credential, replacing: .validating)
            Task {
                await viewModel.prepareLoginForm()
                self.credentialFormView.applySavedCredential(viewModel.savedLoginCredential)
                self.credentialFormView.applyLastLoginMethod(viewModel.lastLoginMethod)
            }
        }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        // Hide the hosting UINavigationController bar so login is one continuous page.
        navigationController?.setNavigationBarHidden(true, animated: animated)
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    /// Center brand + form as one content block. Tall phones get balanced
    /// top/bottom breathing room without sinking the form into the lower half.
    private func configureRootLayout() {
        contentColumn.axis = .vertical
        contentColumn.alignment = .fill
        contentColumn.spacing = 32
        contentColumn.translatesAutoresizingMaskIntoConstraints = false
        contentColumn.addArrangedSubview(brandStack)
        contentColumn.addArrangedSubview(bottomStack)
        contentColumn.setContentHuggingPriority(.required, for: .vertical)
        contentColumn.setContentCompressionResistancePriority(.required, for: .vertical)

        view.addSubview(contentColumn)

        let centerY = contentColumn.centerYAnchor.constraint(
            equalTo: view.safeAreaLayoutGuide.centerYAnchor,
            constant: -24 // slight optical lift above true center
        )
        centerY.priority = UILayoutPriority(700)

        let top = contentColumn.topAnchor.constraint(
            greaterThanOrEqualTo: view.safeAreaLayoutGuide.topAnchor,
            constant: 16
        )
        let bottom = contentColumn.bottomAnchor.constraint(
            lessThanOrEqualTo: view.safeAreaLayoutGuide.bottomAnchor,
            constant: -20
        )

        contentCenterYConstraint = centerY
        contentTopConstraint = top
        contentBottomConstraint = bottom

        NSLayoutConstraint.activate([
            contentColumn.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 24),
            contentColumn.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -24),
            centerY,
            top,
            bottom,
        ])

        view.bringSubviewToFront(developerToolsButton)
        view.bringSubviewToFront(feedbackButton)
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
            if entry == .signedOut {
                // Logout entry never re-enters validating/auto-login via session publishers.
                if session.readiness.canReadAuthenticatedApi {
                    return
                }
                if isSyncingLoginSession {
                    nextPhase = .loggingIn
                } else if self.captchaDialog != nil {
                    return
                } else {
                    nextPhase = .credential
                }
                self.applyPhase(nextPhase)
                return
            }

            if entry == .sessionExpired {
                // Session-expired fallback owns its own one-shot auto-login route and must
                // not wait on cold-start startup validation completeness.
                if session.readiness.canReadAuthenticatedApi {
                    self.isAutoLoginInFlight = false
                    self.activeAutoLoginKind = nil
                    self.teardownHeadlessExternalEngine()
                    return
                }
                if isSyncingLoginSession || self.isAutoLoginInFlight {
                    nextPhase = .loggingIn
                } else if self.startupRouteState != .finished {
                    nextPhase = .validating
                } else if self.captchaDialog != nil {
                    return
                } else {
                    nextPhase = .credential
                }
                self.applyPhase(nextPhase)
                return
            }

            if !isStartupValidationComplete {
                nextPhase = .validating
            } else if session.readiness.canReadAuthenticatedApi {
                // Authenticated: tear down captcha / auto-login chrome if still up.
                self.isAutoLoginInFlight = false
                self.activeAutoLoginKind = nil
                self.teardownHeadlessExternalEngine()
                if self.captchaDialog != nil {
                    self.logAuth("authenticated session applied; dismissing captcha dialog")
                    self.dismissCaptchaDialog()
                }
                return
            } else if isSyncingLoginSession || self.isAutoLoginInFlight {
                // Password login dismisses captcha as soon as /session.json succeeds, then uses
                // this host-owned loading phase while cookies/bootstrap catch up.
                // Auto-login keeps the same loading host before/during captcha presentation.
                nextPhase = .loggingIn
            } else if self.startupRouteState != .finished {
                // Stay on validating chrome while we load credentials and decide auto-login.
                nextPhase = .validating
                self.scheduleRouteAfterStartupValidationIfNeeded()
            } else if self.captchaDialog != nil {
                // Keep an open captcha/2FA sheet mounted while the user is still solving it.
                return
            } else {
                nextPhase = .credential
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
                    // Root coordinator swaps to home once canReadAuthenticatedApi flips.
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

        viewModel.$lastLoginMethod
            .receive(on: RunLoop.main)
            .sink { [weak self] method in
                self?.credentialFormView.applyLastLoginMethod(method)
            }
            .store(in: &cancellables)

        wireCredentialFormCallbacks()
    }

}
