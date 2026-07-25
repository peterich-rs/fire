import UIKit

@MainActor
final class FireOnboardingCredentialFormView: UIView, UITextFieldDelegate {
    var onLoginTapped: ((String, String, Bool) -> Void)?
    var onForgotPassword: (() -> Void)?
    var onExternalLogin: ((FireExternalLoginMethod) -> Void)?

    private let scrollView = UIScrollView()
    private let contentView = UIView()
    private let identifierField = UITextField()
    private let passwordField = UITextField()
    private let passwordVisibilityButton = UIButton(type: .system)
    private let rememberCheckboxButton = UIButton(type: .system)
    private let rememberLabel = UILabel()
    private let rememberRow = UIControl()
    private let optionsRow = UIView()
    private let loginButton = UIButton(type: .system)
    private let lastLoginHintLabel = UILabel()
    private let forgotPasswordButton = UIButton(type: .system)
    private let dividerLabel = UILabel()
    private let externalLoginStack = UIStackView()
    private var externalLoginButtons: [UIButton] = []
    private var isLoggingIn = false
    private var isPasswordVisible = false
    private var isRememberChecked = false
    private var lastLoginMethod: FireLastLoginMethod?
    private lazy var keyboardToolbar: UIToolbar = {
        let toolbar = UIToolbar()
        toolbar.items = [
            UIBarButtonItem(systemItem: .flexibleSpace),
            UIBarButtonItem(title: "完成", style: .done, target: self, action: #selector(doneEditingTapped)),
        ]
        toolbar.sizeToFit()
        return toolbar
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupScrollView()
        setupCredentialFields()
        setupOptionsRow()
        setupLoginButton()
        setupLastLoginHint()
        setupExternalLoginMethods()
        observeKeyboardNotifications()
        updateLoginButtonState()
        updateRememberCheckboxAppearance()
        updatePasswordVisibilityAppearance()
        updateLastLoginAppearance()
        setContentHuggingPriority(.required, for: .vertical)
        setContentCompressionResistancePriority(.required, for: .vertical)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    /// Report content height so onboarding can vertically center brand+form without
    /// expanding the phase container into a tall empty well on large phones.
    override var intrinsicContentSize: CGSize {
        let width: CGFloat
        if bounds.width > 1 {
            width = bounds.width
        } else if let superviewWidth = superview?.bounds.width, superviewWidth > 1 {
            width = superviewWidth
        } else {
            width = 320
        }
        let target = CGSize(width: width, height: UIView.layoutFittingCompressedSize.height)
        let height = contentView.systemLayoutSizeFitting(
            target,
            withHorizontalFittingPriority: .required,
            verticalFittingPriority: .fittingSizeLevel
        ).height
        return CGSize(width: UIView.noIntrinsicMetric, height: ceil(height))
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let fitted = intrinsicContentSize.height
        if abs(fitted - bounds.height) > 0.5 {
            invalidateIntrinsicContentSize()
        }
        // Only scroll when keyboard or tiny screens make content taller than the well.
        scrollView.isScrollEnabled = scrollView.contentSize.height > scrollView.bounds.height + 1
    }

    /// Prefill from Keychain. Never wipes in-progress user edits when credential is nil
    /// (failed captcha / wrong password must keep the last typed account & password).
    func applySavedCredential(_ credential: FireSavedCredential?) {
        guard let credential else { return }

        let identifierEmpty = identifierField.text?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .isEmpty ?? true
        let passwordEmpty = passwordField.text?.isEmpty ?? true

        // Only fill blanks so a failed attempt's typed values are not overwritten.
        if identifierEmpty {
            identifierField.text = credential.username
        }
        if passwordEmpty {
            passwordField.text = credential.password
        }
        isRememberChecked = true
        updateRememberCheckboxAppearance()
        updateLoginButtonState()
    }

    func applyLastLoginMethod(_ method: FireLastLoginMethod?) {
        lastLoginMethod = method
        updateLastLoginAppearance()
    }

    func setLoggingIn(_ loading: Bool) {
        isLoggingIn = loading
        identifierField.isEnabled = !loading
        passwordField.isEnabled = !loading
        passwordVisibilityButton.isEnabled = !loading
        rememberRow.isEnabled = !loading
        rememberCheckboxButton.isEnabled = !loading
        forgotPasswordButton.isEnabled = !loading
        externalLoginButtons.forEach { $0.isEnabled = !loading }

        var configuration = loginButton.configuration ?? .filled()
        if loading {
            loginButton.isEnabled = false
            configuration.showsActivityIndicator = true
            configuration.title = "登录中…"
            loginButton.configuration = configuration
        } else {
            configuration.showsActivityIndicator = false
            configuration.title = "登录"
            loginButton.configuration = configuration
            updateLoginButtonState()
        }
    }

    private func setupScrollView() {
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.keyboardDismissMode = .interactive
        scrollView.alwaysBounceVertical = true
        addSubview(scrollView)

        contentView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(contentView)

        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(backgroundTapped))
        tapGesture.cancelsTouchesInView = false
        scrollView.addGestureRecognizer(tapGesture)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),

            contentView.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            contentView.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            contentView.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            contentView.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            contentView.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor),
        ])
    }

    private func setupCredentialFields() {
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

    private func configureTextField(_ field: UITextField, placeholder: String, secure: Bool) {
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

    private func applyCredentialFieldChrome(to field: UITextField) {
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

    private func restyleCredentialFieldsForCurrentAppearance() {
        applyCredentialFieldChrome(to: identifierField)
        applyCredentialFieldChrome(to: passwordField)
        updatePasswordVisibilityAppearance()
    }

    private func makePasswordVisibilityAccessory() -> UIView {
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

    private static var passwordVisibilitySymbolConfiguration: UIImage.SymbolConfiguration {
        let pointSize = UIImage.SymbolConfiguration(pointSize: 15, weight: .medium, scale: .medium)
        // Hierarchical rendering gives the eyelid/pupil softer depth than flat template monochrome.
        return pointSize.applying(UIImage.SymbolConfiguration(hierarchicalColor: .tertiaryLabel))
    }

    private func setupOptionsRow() {
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

    private func setupLoginButton() {
        loginButton.translatesAutoresizingMaskIntoConstraints = false
        var configuration = UIButton.Configuration.filled()
        configuration.title = "登录"
        configuration.baseBackgroundColor = .systemOrange
        configuration.baseForegroundColor = .white
        configuration.cornerStyle = .medium
        loginButton.configuration = configuration
        loginButton.addTarget(self, action: #selector(loginTapped), for: .touchUpInside)
        loginButton.fireBindPressBounce(.button)
        loginButton.isEnabled = false

        contentView.addSubview(loginButton)

        NSLayoutConstraint.activate([
            loginButton.topAnchor.constraint(equalTo: optionsRow.bottomAnchor, constant: 16),
            loginButton.leadingAnchor.constraint(equalTo: identifierField.leadingAnchor),
            loginButton.trailingAnchor.constraint(equalTo: identifierField.trailingAnchor),
            loginButton.heightAnchor.constraint(equalToConstant: 50),
        ])
    }

    private func setupLastLoginHint() {
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

    private func setupExternalLoginMethods() {
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

    private func makeExternalLoginButton(for method: FireExternalLoginMethod) -> UIButton {
        let button = UIButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.accessibilityLabel = method.accessibilityLabel
        button.tag = FireExternalLoginMethod.allCases.firstIndex(of: method) ?? 0
        button.configuration = externalLoginConfiguration(for: method, highlighted: false)
        button.addTarget(self, action: #selector(externalLoginTapped(_:)), for: .touchUpInside)
        button.fireBindPressBounce(.compact)
        return button
    }

    private func externalLoginConfiguration(
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

    private func observeKeyboardNotifications() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(keyboardWillChangeFrame(_:)),
            name: UIResponder.keyboardWillChangeFrameNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(keyboardWillHide(_:)),
            name: UIResponder.keyboardWillHideNotification,
            object: nil
        )
    }

    private func updateLoginButtonState() {
        guard !isLoggingIn else { return }
        let hasIdentifier = !(identifierField.text?
            .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
        let hasPassword = !(passwordField.text?.isEmpty ?? true)
        loginButton.isEnabled = hasIdentifier && hasPassword
    }

    private func updateRememberCheckboxAppearance() {
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

    private func updatePasswordVisibilityAppearance() {
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

    private func updateLastLoginAppearance() {
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

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        guard traitCollection.hasDifferentColorAppearance(comparedTo: previousTraitCollection) else {
            return
        }
        // Rebuild original-rendered light/dark provider glyphs after appearance flips.
        updateLastLoginAppearance()
        updateRememberCheckboxAppearance()
        restyleCredentialFieldsForCurrentAppearance()
    }

    @objc private func keyboardWillChangeFrame(_ notification: Notification) {
        guard let frameEnd = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect else {
            return
        }
        let convertedFrame = convert(frameEnd, from: nil)
        let overlap = max(0, bounds.maxY - convertedFrame.minY)
        scrollView.contentInset.bottom = overlap
        scrollView.verticalScrollIndicatorInsets.bottom = overlap
    }

    @objc private func keyboardWillHide(_ notification: Notification) {
        scrollView.contentInset.bottom = 0
        scrollView.verticalScrollIndicatorInsets.bottom = 0
    }

    @objc private func textFieldsChanged() {
        updateLoginButtonState()
    }

    @objc private func backgroundTapped() {
        endEditing(true)
    }

    @objc private func doneEditingTapped() {
        endEditing(true)
    }

    @objc private func rememberTapped() {
        isRememberChecked.toggle()
        updateRememberCheckboxAppearance()
        FireMotionHaptics.selection()
    }

    @objc private func passwordVisibilityTapped() {
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

    @objc private func loginTapped() {
        guard let identifier = identifierField.text?
                .trimmingCharacters(in: .whitespacesAndNewlines),
              let password = passwordField.text,
              !identifier.isEmpty,
              !password.isEmpty
        else {
            return
        }
        endEditing(true)
        onLoginTapped?(identifier, password, isRememberChecked)
    }

    @objc private func forgotPasswordTapped() {
        onForgotPassword?()
    }

    @objc private func externalLoginTapped(_ sender: UIButton) {
        let methods = FireExternalLoginMethod.allCases
        guard methods.indices.contains(sender.tag) else { return }
        onExternalLogin?(methods[sender.tag])
    }

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        if textField === identifierField {
            passwordField.becomeFirstResponder()
        } else if loginButton.isEnabled {
            loginTapped()
        } else {
            textField.resignFirstResponder()
        }
        return true
    }
}
