import UIKit

extension FireOnboardingCredentialFormView {
    func setupLastLoginHint() {
        lastLoginHintLabel.translatesAutoresizingMaskIntoConstraints = false
        lastLoginHintLabel.font = .systemFont(ofSize: 12, weight: .regular)
        lastLoginHintLabel.textColor = .secondaryLabel
        lastLoginHintLabel.textAlignment = .center
        lastLoginHintLabel.numberOfLines = 1
        lastLoginHintLabel.isHidden = true

        contentView.addSubview(lastLoginHintLabel)

        NSLayoutConstraint.activate([
            lastLoginHintLabel.topAnchor.constraint(equalTo: loginButton.bottomAnchor, constant: 10),
            lastLoginHintLabel.leadingAnchor.constraint(equalTo: identifierField.leadingAnchor),
            lastLoginHintLabel.trailingAnchor.constraint(equalTo: identifierField.trailingAnchor),
        ])
    }
    func updateLastLoginAppearance() {
        let highlightedExternal = lastLoginMethod.flatMap(FireExternalLoginMethod.externalIcon(for:))

        if let method = lastLoginMethod {
            lastLoginHintLabel.isHidden = false
            lastLoginHintLabel.text = "上次使用：\(method.displayName)"
        } else {
            lastLoginHintLabel.isHidden = true
            lastLoginHintLabel.text = nil
        }

        // Password is a first-class last-login method; emphasize the primary login button.
        let passwordWasLast = lastLoginMethod == .password
        var loginConfiguration = loginButton.configuration ?? .filled()
        loginConfiguration.baseBackgroundColor = .systemOrange
        loginConfiguration.baseForegroundColor = .white
        if passwordWasLast {
            loginConfiguration.background.strokeColor = FireTheme.uiAccent
            loginConfiguration.background.strokeWidth = 1.5
            loginButton.accessibilityValue = "上次使用"
        } else {
            loginConfiguration.background.strokeColor = nil
            loginConfiguration.background.strokeWidth = 0
            loginButton.accessibilityValue = nil
        }
        loginButton.configuration = loginConfiguration

        for (index, button) in externalLoginButtons.enumerated() {
            guard FireExternalLoginMethod.allCases.indices.contains(index) else { continue }
            let method = FireExternalLoginMethod.allCases[index]
            let isLastUsed = method == highlightedExternal
            button.configuration = externalLoginConfiguration(for: method, highlighted: isLastUsed)
            button.accessibilityValue = isLastUsed ? "上次使用" : nil
        }
    }
}
