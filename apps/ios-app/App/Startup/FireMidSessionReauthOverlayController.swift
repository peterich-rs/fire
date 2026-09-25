import UIKit

/// Lightweight blocking overlay shown while mid-session Google/headless reauth runs
/// on top of the authenticated shell. Keeps the main UI mounted so the failed
/// request can retry in place after login succeeds.
@MainActor
final class FireMidSessionReauthOverlayController: UIViewController {
    var onCancel: (() -> Void)?

    private let dimView = UIView()
    private let cardView = UIView()
    private let spinner = UIActivityIndicatorView(style: .large)
    private let messageLabel = UILabel()
    private let cancelButton = UIButton(type: .system)

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear

        dimView.translatesAutoresizingMaskIntoConstraints = false
        dimView.backgroundColor = UIColor.black.withAlphaComponent(0.28)
        view.addSubview(dimView)

        cardView.translatesAutoresizingMaskIntoConstraints = false
        cardView.backgroundColor = FireTheme.uiPanelElevated
        cardView.layer.cornerRadius = 16
        cardView.layer.cornerCurve = .continuous
        view.addSubview(cardView)

        spinner.translatesAutoresizingMaskIntoConstraints = false
        spinner.color = FireTheme.uiAccent
        spinner.startAnimating()
        cardView.addSubview(spinner)

        messageLabel.translatesAutoresizingMaskIntoConstraints = false
        messageLabel.textAlignment = .center
        messageLabel.numberOfLines = 0
        messageLabel.font = .preferredFont(forTextStyle: .subheadline)
        messageLabel.adjustsFontForContentSizeCategory = true
        messageLabel.textColor = FireTheme.uiInk
        cardView.addSubview(messageLabel)

        cancelButton.translatesAutoresizingMaskIntoConstraints = false
        cancelButton.setTitle("取消", for: .normal)
        cancelButton.titleLabel?.font = .preferredFont(forTextStyle: .body)
        cancelButton.addTarget(self, action: #selector(cancelTapped), for: .touchUpInside)
        cardView.addSubview(cancelButton)

        NSLayoutConstraint.activate([
            dimView.topAnchor.constraint(equalTo: view.topAnchor),
            dimView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            dimView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            dimView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            cardView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            cardView.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            cardView.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 40),
            cardView.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -40),
            cardView.widthAnchor.constraint(greaterThanOrEqualToConstant: 240),

            spinner.topAnchor.constraint(equalTo: cardView.topAnchor, constant: 28),
            spinner.centerXAnchor.constraint(equalTo: cardView.centerXAnchor),

            messageLabel.topAnchor.constraint(equalTo: spinner.bottomAnchor, constant: 16),
            messageLabel.leadingAnchor.constraint(equalTo: cardView.leadingAnchor, constant: 20),
            messageLabel.trailingAnchor.constraint(equalTo: cardView.trailingAnchor, constant: -20),

            cancelButton.topAnchor.constraint(equalTo: messageLabel.bottomAnchor, constant: 18),
            cancelButton.centerXAnchor.constraint(equalTo: cardView.centerXAnchor),
            cancelButton.bottomAnchor.constraint(equalTo: cardView.bottomAnchor, constant: -18),
        ])
    }

    func updateMessage(_ message: String) {
        messageLabel.text = message
    }

    @objc private func cancelTapped() {
        onCancel?()
    }
}
