import UIKit

extension FireOnboardingCredentialFormView {
    func setupExternalLoginMethods() {
        dividerLabel.translatesAutoresizingMaskIntoConstraints = false
        dividerLabel.text = "- 其他方式 -"
        dividerLabel.font = .systemFont(ofSize: 13)
        dividerLabel.textColor = .tertiaryLabel
        dividerLabel.textAlignment = .center

        externalLoginStack.translatesAutoresizingMaskIntoConstraints = false
        externalLoginStack.axis = .horizontal
        externalLoginStack.alignment = .fill
        externalLoginStack.distribution = .fillEqually
        externalLoginStack.spacing = 8

        for method in FireExternalLoginMethod.allCases {
            let button = makeExternalLoginButton(for: method)
            externalLoginButtons.append(button)
            externalLoginStack.addArrangedSubview(button)
        }

        contentView.addSubview(dividerLabel)
        contentView.addSubview(externalLoginStack)

        NSLayoutConstraint.activate([
            dividerLabel.topAnchor.constraint(equalTo: lastLoginHintLabel.bottomAnchor, constant: 18),
            dividerLabel.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),

            externalLoginStack.topAnchor.constraint(equalTo: dividerLabel.bottomAnchor, constant: 14),
            externalLoginStack.leadingAnchor.constraint(equalTo: identifierField.leadingAnchor),
            externalLoginStack.trailingAnchor.constraint(equalTo: identifierField.trailingAnchor),
            externalLoginStack.heightAnchor.constraint(equalToConstant: 52),
            externalLoginStack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -32),
        ])
    }
    func makeExternalLoginButton(for method: FireExternalLoginMethod) -> UIButton {
        let button = UIButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.accessibilityLabel = method.accessibilityLabel
        button.tag = FireExternalLoginMethod.allCases.firstIndex(of: method) ?? 0
        button.configuration = externalLoginConfiguration(for: method, highlighted: false)
        button.addTarget(self, action: #selector(externalLoginTapped(_:)), for: .touchUpInside)
        button.fireBindPressBounce(.compact)
        return button
    }
    func externalLoginConfiguration(
        for method: FireExternalLoginMethod,
        highlighted: Bool
    ) -> UIButton.Configuration {
        var configuration = UIButton.Configuration.plain()
        configuration.image = method.iconImage
        // Elevated chip that stays readable on both light canvas and pure black dark canvas.
        configuration.background.backgroundColor = UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor.secondarySystemFill
                : UIColor.secondarySystemGroupedBackground
        }
        configuration.background.cornerRadius = 14
        configuration.background.strokeColor = highlighted
            ? FireTheme.uiAccent
            : UIColor.separator.withAlphaComponent(0.55)
        configuration.background.strokeWidth = highlighted ? 1.5 : 1
        configuration.contentInsets = NSDirectionalEdgeInsets(top: 12, leading: 10, bottom: 12, trailing: 10)
        return configuration
    }
    @objc func externalLoginTapped(_ sender: UIButton) {
        let methods = FireExternalLoginMethod.allCases
        guard methods.indices.contains(sender.tag) else { return }
        onExternalLogin?(methods[sender.tag])
    }
}
