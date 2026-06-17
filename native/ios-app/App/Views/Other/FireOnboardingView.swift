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
    private lazy var validatingView = FireOnboardingValidatingView()
    private lazy var credentialFormView = FireOnboardingCredentialFormView()
    private lazy var loggingInView = FireOnboardingLoggingInView()
    private var phase: FireOnboardingPhase = .validating
    private var errorDismissWorkItem: DispatchWorkItem?
    private var cancellables: Set<AnyCancellable> = []

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
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            image: UIImage(systemName: "ant"),
            style: .plain,
            target: self,
            action: #selector(developerToolsButtonTapped)
        )
        navigationItem.rightBarButtonItem?.accessibilityLabel = "开发者工具"

        configureBrand()
        configureBottomControls()
        bindState()
        installValidatingPhaseInitial()
        Task { await viewModel.performStartupValidation() }
    }

    private func configureBrand() {
        let imageView = UIImageView(image: UIImage(systemName: "flame.fill"))
        imageView.tintColor = .systemOrange
        imageView.contentMode = .scaleAspectFit

        let titleLabel = UILabel()
        titleLabel.text = "Fire"
        titleLabel.font = UIFont.preferredFont(forTextStyle: .largeTitle).withOnboardingWeight(.bold)
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
        textStack.spacing = 8

        brandStack.axis = .vertical
        brandStack.alignment = .center
        brandStack.spacing = 20
        brandStack.translatesAutoresizingMaskIntoConstraints = false
        brandStack.addArrangedSubview(imageView)
        brandStack.addArrangedSubview(textStack)

        view.addSubview(brandStack)
        NSLayoutConstraint.activate([
            imageView.widthAnchor.constraint(equalToConstant: 58),
            imageView.heightAnchor.constraint(equalToConstant: 58),
            brandStack.centerXAnchor.constraint(equalTo: view.safeAreaLayoutGuide.centerXAnchor),
            brandStack.centerYAnchor.constraint(equalTo: view.safeAreaLayoutGuide.centerYAnchor, constant: -96),
            brandStack.leadingAnchor.constraint(greaterThanOrEqualTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 24),
            brandStack.trailingAnchor.constraint(lessThanOrEqualTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -24),
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
        NSLayoutConstraint.activate([
            bottomStack.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 24),
            bottomStack.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -24),
            bottomStack.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -40),
            phaseContainerView.leadingAnchor.constraint(equalTo: bottomStack.leadingAnchor),
            phaseContainerView.trailingAnchor.constraint(equalTo: bottomStack.trailingAnchor),
            phaseContainerView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -40),
            phaseContainerView.heightAnchor.constraint(greaterThanOrEqualToConstant: 240),
        ])
    }

    private func bindState() {
        viewModel.$errorMessage
            .receive(on: RunLoop.main)
            .sink { [weak self] errorMessage in
                guard let self else { return }
                if let errorMessage,
                   !errorMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    self.showErrorBanner(errorMessage)
                } else {
                    self.hideErrorBanner()
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
                nextPhase = .credential
            } else {
                return
            }
            self.applyPhase(nextPhase)
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
        // Step 3 wires onLoginTapped / onForgotPassword / onOtherMethods to the
        // migrated login orchestration methods. Kept nil for now.
    }

    private func applyPhase(_ next: FireOnboardingPhase) {
        guard phase != next else { return }

        if next == .credential, phase != .credential {
            Task { await viewModel.prepareLoginForm() }
        }

        let previous = phase
        phase = next

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

    @objc private func developerToolsButtonTapped() {
        let controller = UIHostingController(rootView: FireDeveloperToolsView(viewModel: viewModel))
        controller.title = "开发者工具"
        navigationController?.pushViewController(controller, animated: true)
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
