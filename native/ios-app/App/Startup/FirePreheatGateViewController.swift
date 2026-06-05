import UIKit

final class FirePreheatGateViewController: UIViewController {
    private let loadingIndicator = UIActivityIndicatorView(style: .large)
    private let statusLabel = UILabel()
    private let errorContainer = UIView()
    private let errorLabel = UILabel()
    private let retryButton = UIButton(type: .system)
    private let logoutButton = UIButton(type: .system)

    private let sessionStore: FireSessionStore
    private var isLoaded = false

    init(sessionStore: FireSessionStore) {
        self.sessionStore = sessionStore
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        awaitPreloadedData()
    }

    private func setupUI() {
        view.backgroundColor = .systemBackground

        loadingIndicator.translatesAutoresizingMaskIntoConstraints = false
        loadingIndicator.startAnimating()
        view.addSubview(loadingIndicator)

        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        statusLabel.text = "正在加载..."
        statusLabel.textColor = .secondaryLabel
        statusLabel.font = .systemFont(ofSize: 14)
        statusLabel.textAlignment = .center
        view.addSubview(statusLabel)

        errorContainer.translatesAutoresizingMaskIntoConstraints = false
        errorContainer.isHidden = true
        view.addSubview(errorContainer)

        errorLabel.translatesAutoresizingMaskIntoConstraints = false
        errorLabel.textColor = .label
        errorLabel.font = .systemFont(ofSize: 16)
        errorLabel.textAlignment = .center
        errorLabel.numberOfLines = 0
        errorContainer.addSubview(errorLabel)

        retryButton.translatesAutoresizingMaskIntoConstraints = false
        retryButton.setTitle("重试", for: .normal)
        retryButton.addTarget(self, action: #selector(retryTapped), for: .touchUpInside)
        errorContainer.addSubview(retryButton)

        logoutButton.translatesAutoresizingMaskIntoConstraints = false
        logoutButton.setTitle("退出登录", for: .normal)
        logoutButton.addTarget(self, action: #selector(logoutTapped), for: .touchUpInside)
        errorContainer.addSubview(logoutButton)

        NSLayoutConstraint.activate([
            loadingIndicator.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            loadingIndicator.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            statusLabel.topAnchor.constraint(equalTo: loadingIndicator.bottomAnchor, constant: 12),
            statusLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),

            errorContainer.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            errorContainer.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            errorContainer.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 40),
            errorContainer.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -40),

            errorLabel.topAnchor.constraint(equalTo: errorContainer.topAnchor),
            errorLabel.leadingAnchor.constraint(equalTo: errorContainer.leadingAnchor),
            errorLabel.trailingAnchor.constraint(equalTo: errorContainer.trailingAnchor),

            retryButton.topAnchor.constraint(equalTo: errorLabel.bottomAnchor, constant: 20),
            retryButton.centerXAnchor.constraint(equalTo: errorContainer.centerXAnchor),

            logoutButton.topAnchor.constraint(equalTo: retryButton.bottomAnchor, constant: 12),
            logoutButton.centerXAnchor.constraint(equalTo: errorContainer.centerXAnchor),
            logoutButton.bottomAnchor.constraint(equalTo: errorContainer.bottomAnchor),
        ])
    }

    private func awaitPreloadedData() {
        Task { @MainActor in
            loadingIndicator.startAnimating()
            loadingIndicator.isHidden = false
            statusLabel.isHidden = false
            errorContainer.isHidden = true

            do {
                _ = try await sessionStore.prepareStartupSession()
                let _ = try await sessionStore.awaitPreloadedData()
                onPreloadedDataReady()
            } catch {
                showErrorPage(error.localizedDescription)
            }
        }
    }

    private func onPreloadedDataReady() {
        isLoaded = true
        loadingIndicator.stopAnimating()
        NotificationCenter.default.post(name: .firePreheatGateDidComplete, object: nil)
    }

    private func showErrorPage(_ message: String) {
        loadingIndicator.stopAnimating()
        loadingIndicator.isHidden = true
        statusLabel.isHidden = true
        errorContainer.isHidden = false
        errorLabel.text = message
    }

    @objc private func retryTapped() {
        awaitPreloadedData()
    }

    @objc private func logoutTapped() {
        NotificationCenter.default.post(name: .firePreheatGateRequestsLogout, object: nil)
    }
}

extension Notification.Name {
    static let firePreheatGateDidComplete = Notification.Name("firePreheatGateDidComplete")
    static let firePreheatGateRequestsLogout = Notification.Name("firePreheatGateRequestsLogout")
}
