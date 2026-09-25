import UIKit

extension FireOnboardingViewController {
    func applyPhase(_ next: FireOnboardingPhase) {
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
    func installValidatingPhaseInitial() {
        phaseContainerView.addSubview(validatingView)
        validatingView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            validatingView.topAnchor.constraint(equalTo: phaseContainerView.topAnchor),
            validatingView.leadingAnchor.constraint(equalTo: phaseContainerView.leadingAnchor),
            validatingView.trailingAnchor.constraint(equalTo: phaseContainerView.trailingAnchor),
            validatingView.bottomAnchor.constraint(equalTo: phaseContainerView.bottomAnchor),
        ])
        validatingView.configure(
            isAnimating: true,
            message: "正在校验登录态…",
            showsCancel: false
        )
    }
    func installPhaseSubviews(for next: FireOnboardingPhase, replacing previous: FireOnboardingPhase) {
        if previous == .loggingIn {
            credentialFormView.setLoggingIn(false)
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
            validatingView.configure(
                isAnimating: true,
                message: "正在校验登录态…",
                showsCancel: false
            )

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
            // Host-owned loading for: auto-login prep, captcha underlying wait, and post-login sync.
            phaseContainerView.addSubview(validatingView)
            validatingView.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                validatingView.topAnchor.constraint(equalTo: phaseContainerView.topAnchor),
                validatingView.leadingAnchor.constraint(equalTo: phaseContainerView.leadingAnchor),
                validatingView.trailingAnchor.constraint(equalTo: phaseContainerView.trailingAnchor),
                validatingView.bottomAnchor.constraint(equalTo: phaseContainerView.bottomAnchor),
            ])
            refreshLoggingInChrome()
        }
    }
    func refreshLoggingInChrome() {
        let detail: String?
        if isAutoLoginInFlight {
            switch activeAutoLoginKind {
            case .password:
                detail = "将使用已保存的账号密码"
            case let .external(method):
                detail = method == .google
                    ? "正在安全连接 Google，通常只需几秒"
                    : "正在安全连接，通常只需几秒"
            case .none:
                detail = nil
            }
        } else {
            detail = nil
        }
        validatingView.configure(
            isAnimating: true,
            message: loggingInMessage,
            detail: detail,
            // Cancel only while auto-login is waiting (prep). Captcha has its own dismiss;
            // once cookie sync starts the session is already past the cancellable boundary.
            showsCancel: isAutoLoginInFlight
                && captchaDialog == nil
                && !viewModel.isSyncingLoginSession
        )
    }
    func updateLoggingInMessage(_ message: String) {
        loggingInMessage = message
        guard phase == .loggingIn else { return }
        refreshLoggingInChrome()
    }
}
