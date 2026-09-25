import UIKit

extension FireOnboardingCredentialFormView {
    func setupOptionsRow() {
        optionsRow.translatesAutoresizingMaskIntoConstraints = false

        rememberRow.translatesAutoresizingMaskIntoConstraints = false
        rememberRow.addTarget(self, action: #selector(rememberTapped), for: .touchUpInside)
        rememberRow.accessibilityTraits = .button

        rememberCheckboxButton.translatesAutoresizingMaskIntoConstraints = false
        rememberCheckboxButton.isUserInteractionEnabled = false
        rememberCheckboxButton.tintColor = FireTheme.uiAccent
        rememberCheckboxButton.setContentHuggingPriority(.required, for: .horizontal)

        rememberLabel.translatesAutoresizingMaskIntoConstraints = false
        rememberLabel.text = "记住密码"
        rememberLabel.font = .systemFont(ofSize: 13, weight: .regular)
        rememberLabel.textColor = .secondaryLabel
        rememberLabel.isUserInteractionEnabled = false

        forgotPasswordButton.translatesAutoresizingMaskIntoConstraints = false
        forgotPasswordButton.setTitle("忘记密码?", for: .normal)
        forgotPasswordButton.titleLabel?.font = .systemFont(ofSize: 13, weight: .medium)
        forgotPasswordButton.setTitleColor(.systemBlue, for: .normal)
        forgotPasswordButton.setTitleColor(.systemBlue.withAlphaComponent(0.55), for: .highlighted)
        forgotPasswordButton.contentHorizontalAlignment = .trailing
        forgotPasswordButton.addTarget(self, action: #selector(forgotPasswordTapped), for: .touchUpInside)
        forgotPasswordButton.fireBindPressBounce(.compact)
        forgotPasswordButton.setContentHuggingPriority(.required, for: .horizontal)
        forgotPasswordButton.setContentCompressionResistancePriority(.required, for: .horizontal)

        rememberRow.addSubview(rememberCheckboxButton)
        rememberRow.addSubview(rememberLabel)
        optionsRow.addSubview(rememberRow)
        optionsRow.addSubview(forgotPasswordButton)
        contentView.addSubview(optionsRow)

        NSLayoutConstraint.activate([
            optionsRow.topAnchor.constraint(equalTo: passwordField.bottomAnchor, constant: 12),
            optionsRow.leadingAnchor.constraint(equalTo: identifierField.leadingAnchor),
            optionsRow.trailingAnchor.constraint(equalTo: identifierField.trailingAnchor),
            optionsRow.heightAnchor.constraint(equalToConstant: 24),

            rememberRow.leadingAnchor.constraint(equalTo: optionsRow.leadingAnchor),
            rememberRow.centerYAnchor.constraint(equalTo: optionsRow.centerYAnchor),
            rememberRow.trailingAnchor.constraint(lessThanOrEqualTo: forgotPasswordButton.leadingAnchor, constant: -8),
            rememberRow.heightAnchor.constraint(equalTo: optionsRow.heightAnchor),

            rememberCheckboxButton.leadingAnchor.constraint(equalTo: rememberRow.leadingAnchor),
            rememberCheckboxButton.centerYAnchor.constraint(equalTo: rememberLabel.centerYAnchor),
            rememberCheckboxButton.widthAnchor.constraint(equalToConstant: 16),
            rememberCheckboxButton.heightAnchor.constraint(equalToConstant: 16),

            rememberLabel.leadingAnchor.constraint(equalTo: rememberCheckboxButton.trailingAnchor, constant: 5),
            rememberLabel.centerYAnchor.constraint(equalTo: rememberRow.centerYAnchor),
            rememberLabel.trailingAnchor.constraint(equalTo: rememberRow.trailingAnchor),

            forgotPasswordButton.trailingAnchor.constraint(equalTo: optionsRow.trailingAnchor),
            forgotPasswordButton.centerYAnchor.constraint(equalTo: optionsRow.centerYAnchor),
            forgotPasswordButton.heightAnchor.constraint(equalTo: optionsRow.heightAnchor),
        ])
    }
    func updateRememberCheckboxAppearance() {
        let symbol = isRememberChecked ? "checkmark.circle.fill" : "circle"
        // Match the 13pt label optically; previous 18pt mark dominated the row.
        let config = UIImage.SymbolConfiguration(pointSize: 14, weight: .regular)
        rememberCheckboxButton.setImage(UIImage(systemName: symbol, withConfiguration: config), for: .normal)
        rememberCheckboxButton.tintColor = isRememberChecked ? FireTheme.uiAccent : .tertiaryLabel
        rememberCheckboxButton.contentVerticalAlignment = .center
        rememberCheckboxButton.contentHorizontalAlignment = .center
        rememberRow.accessibilityLabel = isRememberChecked ? "已勾选记住密码" : "记住密码"
        rememberRow.accessibilityValue = isRememberChecked ? "已选中" : "未选中"
    }
    @objc func rememberTapped() {
        isRememberChecked.toggle()
        updateRememberCheckboxAppearance()
        FireMotionHaptics.selection()
    }
    @objc func forgotPasswordTapped() {
        onForgotPassword?()
    }
}
