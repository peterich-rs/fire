import UIKit

final class FirePreheatGateViewController: UIViewController {
    private static let startupLoginErrorMessage = "网络异常，请重新登录"

    private let statusView = FireStartupOnboardingStatusView()

    private let sessionStore: FireSessionStore
    private let onComplete: () -> Void
    private let onRequestLogin: (String?) -> Void
    private var isLoaded = false

    init(
        sessionStore: FireSessionStore,
        onComplete: @escaping () -> Void,
        onRequestLogin: @escaping (String?) -> Void
    ) {
        self.sessionStore = sessionStore
        self.onComplete = onComplete
        self.onRequestLogin = onRequestLogin
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        awaitPreloadedData()
    }

    private func setupUI() {
        view.backgroundColor = FireStartupOnboardingPalette.background
        statusView.translatesAutoresizingMaskIntoConstraints = false
        statusView.showLoading("正在校验登录态…")
        view.addSubview(statusView)

        NSLayoutConstraint.activate([
            statusView.topAnchor.constraint(equalTo: view.topAnchor),
            statusView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            statusView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            statusView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])
    }

    private func awaitPreloadedData() {
        Task { @MainActor in
            statusView.showLoading("正在校验登录态…")

            do {
                _ = try await sessionStore.prepareStartupSession()
                let _ = try await sessionStore.awaitPreloadedData()
                onPreloadedDataReady()
            } catch {
                showErrorPage(Self.startupLoginErrorMessage)
            }
        }
    }

    private func onPreloadedDataReady() {
        isLoaded = true
        onComplete()
    }

    private func showErrorPage(_ message: String) {
        statusView.showLoginError(message, onLogin: {
            self.onRequestLogin(message)
        })
    }
}

enum FireStartupOnboardingPalette {
    static let accent = UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.961, green: 0.451, blue: 0.212, alpha: 1)
            : UIColor(red: 0.91, green: 0.388, blue: 0.18, alpha: 1)
    }

    static let background = UIColor.systemBackground
}

final class FireStartupOnboardingStatusView: UIView {
    private let heroStack = UIStackView()
    private let logoView = UIImageView()
    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()
    private let actionStack = UIStackView()
    private let errorBanner = UIView()
    private let errorLabel = UILabel()
    private let actionButton = UIButton(type: .system)
    private var onAction: (() -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupUI()
    }

    required init?(coder: NSCoder) { fatalError() }

    func showLoading(_ message: String) {
        onAction = nil
        errorBanner.isHidden = true
        actionButton.isEnabled = false
        actionButton.removeTarget(self, action: #selector(actionTapped), for: .touchUpInside)

        var configuration = UIButton.Configuration.filled()
        configuration.title = message
        configuration.showsActivityIndicator = true
        configuration.baseBackgroundColor = FireStartupOnboardingPalette.accent
        configuration.baseForegroundColor = .white
        configuration.cornerStyle = .fixed
        configuration.background.cornerRadius = 12
        configuration.contentInsets = NSDirectionalEdgeInsets(
            top: 14,
            leading: 16,
            bottom: 14,
            trailing: 16
        )
        actionButton.configuration = configuration
    }

    func showLoginError(_ message: String, onLogin: @escaping () -> Void) {
        self.onAction = onLogin
        errorLabel.text = message
        errorBanner.isHidden = false
        actionButton.isEnabled = true
        actionButton.removeTarget(self, action: #selector(actionTapped), for: .touchUpInside)
        actionButton.addTarget(self, action: #selector(actionTapped), for: .touchUpInside)

        var configuration = UIButton.Configuration.filled()
        configuration.title = "登录 LinuxDo"
        configuration.image = UIImage(systemName: "person.badge.key")
        configuration.imagePadding = 8
        configuration.baseBackgroundColor = FireStartupOnboardingPalette.accent
        configuration.baseForegroundColor = .white
        configuration.cornerStyle = .fixed
        configuration.background.cornerRadius = 12
        configuration.contentInsets = NSDirectionalEdgeInsets(
            top: 14,
            leading: 16,
            bottom: 14,
            trailing: 16
        )
        actionButton.configuration = configuration
    }

    private func setupUI() {
        backgroundColor = FireStartupOnboardingPalette.background

        heroStack.translatesAutoresizingMaskIntoConstraints = false
        heroStack.axis = .vertical
        heroStack.alignment = .center
        heroStack.spacing = 20
        addSubview(heroStack)

        let logoConfiguration = UIImage.SymbolConfiguration(pointSize: 56, weight: .regular)
        logoView.image = UIImage(systemName: "flame.fill", withConfiguration: logoConfiguration)
        logoView.tintColor = FireStartupOnboardingPalette.accent
        logoView.contentMode = .scaleAspectFit
        logoView.setContentHuggingPriority(.required, for: .vertical)
        heroStack.addArrangedSubview(logoView)

        let titleStack = UIStackView()
        titleStack.axis = .vertical
        titleStack.alignment = .center
        titleStack.spacing = 8
        heroStack.addArrangedSubview(titleStack)

        titleLabel.text = "Fire"
        titleLabel.font = .systemFont(ofSize: 34, weight: .bold)
        titleLabel.textColor = .label
        titleStack.addArrangedSubview(titleLabel)

        subtitleLabel.text = "LinuxDo 原生客户端"
        subtitleLabel.font = .preferredFont(forTextStyle: .subheadline)
        subtitleLabel.textColor = .secondaryLabel
        titleStack.addArrangedSubview(subtitleLabel)

        actionStack.translatesAutoresizingMaskIntoConstraints = false
        actionStack.axis = .vertical
        actionStack.spacing = 12
        addSubview(actionStack)

        errorBanner.isHidden = true
        errorBanner.backgroundColor = .tertiarySystemFill
        errorBanner.layer.cornerRadius = 10
        errorBanner.layer.cornerCurve = .continuous
        actionStack.addArrangedSubview(errorBanner)

        errorLabel.translatesAutoresizingMaskIntoConstraints = false
        errorLabel.font = .preferredFont(forTextStyle: .caption1)
        errorLabel.textColor = .secondaryLabel
        errorLabel.numberOfLines = 3
        errorBanner.addSubview(errorLabel)

        actionButton.titleLabel?.font = .preferredFont(forTextStyle: .headline)
        actionStack.addArrangedSubview(actionButton)

        NSLayoutConstraint.activate([
            heroStack.centerXAnchor.constraint(equalTo: centerXAnchor),
            heroStack.centerYAnchor.constraint(equalTo: centerYAnchor, constant: -52),
            heroStack.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 24),
            heroStack.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -24),

            actionStack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 24),
            actionStack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -24),
            actionStack.bottomAnchor.constraint(equalTo: safeAreaLayoutGuide.bottomAnchor, constant: -40),

            errorLabel.topAnchor.constraint(equalTo: errorBanner.topAnchor, constant: 12),
            errorLabel.bottomAnchor.constraint(equalTo: errorBanner.bottomAnchor, constant: -12),
            errorLabel.leadingAnchor.constraint(equalTo: errorBanner.leadingAnchor, constant: 12),
            errorLabel.trailingAnchor.constraint(equalTo: errorBanner.trailingAnchor, constant: -12),

            actionButton.heightAnchor.constraint(greaterThanOrEqualToConstant: 46),
        ])
    }

    @objc private func actionTapped() {
        onAction?()
    }
}
