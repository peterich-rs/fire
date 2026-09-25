import UIKit

extension FireOnboardingCredentialFormView {
    func setupCredentialFields() {
        configureTextField(identifierField, placeholder: "用户名或邮箱", secure: false)
        identifierField.returnKeyType = .next
        identifierField.delegate = self
        identifierField.addTarget(self, action: #selector(textFieldsChanged), for: .editingChanged)

        configureTextField(passwordField, placeholder: "密码", secure: true)
        passwordField.returnKeyType = .go
        passwordField.delegate = self
        passwordField.addTarget(self, action: #selector(textFieldsChanged), for: .editingChanged)
        // Eye toggle replaces clear button on the password field.
        passwordField.clearButtonMode = .never
        passwordField.rightView = makePasswordVisibilityAccessory()
        passwordField.rightViewMode = .always

        contentView.addSubview(identifierField)
        contentView.addSubview(passwordField)

        NSLayoutConstraint.activate([
            identifierField.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 8),
            identifierField.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            identifierField.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            identifierField.heightAnchor.constraint(equalToConstant: 48),

            passwordField.topAnchor.constraint(equalTo: identifierField.bottomAnchor, constant: 12),
            passwordField.leadingAnchor.constraint(equalTo: identifierField.leadingAnchor),
            passwordField.trailingAnchor.constraint(equalTo: identifierField.trailingAnchor),
            passwordField.heightAnchor.constraint(equalToConstant: 48),
        ])
    }
    func configureTextField(_ field: UITextField, placeholder: String, secure: Bool) {
        field.translatesAutoresizingMaskIntoConstraints = false
        field.placeholder = placeholder
        // Custom chrome instead of .roundedRect: system roundedRect sits too dark on
        // pure-black onboarding canvas and loses edge definition in dark mode.
        field.borderStyle = .none
        field.autocapitalizationType = .none
        field.autocorrectionType = .no
        field.clearButtonMode = .whileEditing
        field.isSecureTextEntry = secure
        field.textContentType = secure ? .password : .username
        field.inputAccessoryView = keyboardToolbar
        field.layer.cornerRadius = 10
        field.layer.masksToBounds = true
        field.leftView = UIView(frame: CGRect(x: 0, y: 0, width: 12, height: 1))
        field.leftViewMode = .always
        applyCredentialFieldChrome(to: field)
    }
    func applyCredentialFieldChrome(to field: UITextField) {
        let isDark = traitCollection.userInterfaceStyle == .dark
        field.backgroundColor = isDark
            ? UIColor.secondarySystemFill
            : UIColor.secondarySystemGroupedBackground
        field.textColor = .label
        field.tintColor = FireTheme.uiAccent
        field.layer.borderWidth = 1
        field.layer.borderColor = UIColor.separator.withAlphaComponent(isDark ? 0.7 : 0.45).cgColor
        field.attributedPlaceholder = NSAttributedString(
            string: field.placeholder ?? "",
            attributes: [
                .foregroundColor: UIColor.secondaryLabel.withAlphaComponent(0.85),
                .font: UIFont.systemFont(ofSize: 17),
            ]
        )
    }
    func restyleCredentialFieldsForCurrentAppearance() {
        applyCredentialFieldChrome(to: identifierField)
        applyCredentialFieldChrome(to: passwordField)
        updatePasswordVisibilityAppearance()
    }
    func makePasswordVisibilityAccessory() -> UIView {
        var configuration = UIButton.Configuration.plain()
        configuration.contentInsets = NSDirectionalEdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 10)
        configuration.preferredSymbolConfigurationForImage = Self.passwordVisibilitySymbolConfiguration
        passwordVisibilityButton.configuration = configuration
        passwordVisibilityButton.translatesAutoresizingMaskIntoConstraints = false
        passwordVisibilityButton.addTarget(self, action: #selector(passwordVisibilityTapped), for: .touchUpInside)
        passwordVisibilityButton.accessibilityLabel = "显示密码"
        passwordVisibilityButton.fireBindPressBounce(.compact)

        // Slightly wider trailing chrome so the glyph doesn't hug the field edge.
        let host = UIView(frame: CGRect(x: 0, y: 0, width: 44, height: 40))
        host.addSubview(passwordVisibilityButton)
        NSLayoutConstraint.activate([
            passwordVisibilityButton.leadingAnchor.constraint(equalTo: host.leadingAnchor),
            passwordVisibilityButton.trailingAnchor.constraint(equalTo: host.trailingAnchor),
            passwordVisibilityButton.topAnchor.constraint(equalTo: host.topAnchor),
            passwordVisibilityButton.bottomAnchor.constraint(equalTo: host.bottomAnchor),
            host.widthAnchor.constraint(equalToConstant: 44),
            host.heightAnchor.constraint(equalToConstant: 40),
        ])
        return host
    }
    func updatePasswordVisibilityAppearance() {
        // Prefer the filled pair — reads cleaner at small sizes than the outline glyphs.
        let symbol = isPasswordVisible ? "eye.slash.fill" : "eye.fill"
        let image = UIImage(systemName: symbol, withConfiguration: Self.passwordVisibilitySymbolConfiguration)?
            .withRenderingMode(.alwaysTemplate)

        var configuration = passwordVisibilityButton.configuration ?? .plain()
        configuration.image = image
        configuration.baseForegroundColor = UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor.tertiaryLabel
                : UIColor.secondaryLabel.withAlphaComponent(0.85)
        }
        configuration.preferredSymbolConfigurationForImage = Self.passwordVisibilitySymbolConfiguration
        configuration.contentInsets = NSDirectionalEdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 10)
        passwordVisibilityButton.configuration = configuration
        passwordVisibilityButton.accessibilityLabel = isPasswordVisible ? "隐藏密码" : "显示密码"
    }
    @objc func textFieldsChanged() {
        updateLoginButtonState()
    }
    @objc func passwordVisibilityTapped() {
        isPasswordVisible.toggle()
        // Preserve caret / text when flipping secure entry (UIKit quirk).
        let wasFirstResponder = passwordField.isFirstResponder
        let existing = passwordField.text
        passwordField.isSecureTextEntry = !isPasswordVisible
        passwordField.text = nil
        passwordField.text = existing
        if wasFirstResponder {
            passwordField.becomeFirstResponder()
        }
        updatePasswordVisibilityAppearance()
    }
}
