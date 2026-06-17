import UIKit

@MainActor
final class FireOnboardingCredentialFormView: UIView, UITextFieldDelegate {
    var onLoginTapped: ((String, String, Bool) -> Void)?
    var onForgotPassword: (() -> Void)?
    var onOtherMethods: (() -> Void)?

    private let scrollView = UIScrollView()
    private let contentView = UIView()
    private let identifierField = UITextField()
    private let passwordField = UITextField()
    private let rememberSwitch = UISwitch()
    private let rememberLabel = UILabel()
    private let loginButton = UIButton(type: .system)
    private let forgotPasswordButton = UIButton(type: .system)
    private let dividerLabel = UILabel()
    private let otherMethodsButton = UIButton(type: .system)
    private var isLoggingIn = false
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
        setupRememberPassword()
        setupLoginButton()
        setupForgotPassword()
        setupOtherMethods()
        observeKeyboardNotifications()
        updateLoginButtonState()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    func applySavedCredential(_ credential: FireSavedCredential?) {
        guard let credential else {
            identifierField.text = nil
            passwordField.text = nil
            rememberSwitch.isOn = false
            updateLoginButtonState()
            return
        }
        identifierField.text = credential.username
        passwordField.text = credential.password
        rememberSwitch.isOn = true
        updateLoginButtonState()
    }

    func clearPasswordField() {
        passwordField.text = nil
        updateLoginButtonState()
    }

    func setLoggingIn(_ loading: Bool) {
        isLoggingIn = loading
        identifierField.isEnabled = !loading
        passwordField.isEnabled = !loading
        rememberSwitch.isEnabled = !loading
        forgotPasswordButton.isEnabled = !loading
        otherMethodsButton.isEnabled = !loading

        if loading {
            loginButton.isEnabled = false
            loginButton.configuration?.showsActivityIndicator = true
        } else {
            loginButton.configuration?.showsActivityIndicator = false
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
        field.borderStyle = .roundedRect
        field.autocapitalizationType = .none
        field.autocorrectionType = .no
        field.clearButtonMode = .whileEditing
        field.isSecureTextEntry = secure
        field.textContentType = secure ? .password : .username
        field.inputAccessoryView = keyboardToolbar
    }

    private func setupRememberPassword() {
        rememberSwitch.translatesAutoresizingMaskIntoConstraints = false
        rememberSwitch.onTintColor = .systemOrange

        rememberLabel.translatesAutoresizingMaskIntoConstraints = false
        rememberLabel.text = "记住账号密码"
        rememberLabel.font = .systemFont(ofSize: 15)
        rememberLabel.textColor = .secondaryLabel
        rememberLabel.isUserInteractionEnabled = true
        rememberLabel.addGestureRecognizer(
            UITapGestureRecognizer(target: self, action: #selector(rememberLabelTapped))
        )

        contentView.addSubview(rememberSwitch)
        contentView.addSubview(rememberLabel)

        NSLayoutConstraint.activate([
            rememberSwitch.topAnchor.constraint(equalTo: passwordField.bottomAnchor, constant: 12),
            rememberSwitch.leadingAnchor.constraint(equalTo: identifierField.leadingAnchor),

            rememberLabel.centerYAnchor.constraint(equalTo: rememberSwitch.centerYAnchor),
            rememberLabel.leadingAnchor.constraint(equalTo: rememberSwitch.trailingAnchor, constant: 8),
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
        loginButton.isEnabled = false

        contentView.addSubview(loginButton)

        NSLayoutConstraint.activate([
            loginButton.topAnchor.constraint(equalTo: rememberSwitch.bottomAnchor, constant: 20),
            loginButton.leadingAnchor.constraint(equalTo: identifierField.leadingAnchor),
            loginButton.trailingAnchor.constraint(equalTo: identifierField.trailingAnchor),
            loginButton.heightAnchor.constraint(equalToConstant: 50),
        ])
    }

    private func setupForgotPassword() {
        forgotPasswordButton.translatesAutoresizingMaskIntoConstraints = false
        forgotPasswordButton.setTitle("忘记密码?", for: .normal)
        forgotPasswordButton.titleLabel?.font = .systemFont(ofSize: 14)
        forgotPasswordButton.setTitleColor(.secondaryLabel, for: .normal)
        forgotPasswordButton.addTarget(self, action: #selector(forgotPasswordTapped), for: .touchUpInside)

        contentView.addSubview(forgotPasswordButton)

        NSLayoutConstraint.activate([
            forgotPasswordButton.topAnchor.constraint(equalTo: loginButton.bottomAnchor, constant: 12),
            forgotPasswordButton.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
        ])
    }

    private func setupOtherMethods() {
        dividerLabel.translatesAutoresizingMaskIntoConstraints = false
        dividerLabel.text = "- 其他方式 -"
        dividerLabel.font = .systemFont(ofSize: 13)
        dividerLabel.textColor = .tertiaryLabel
        dividerLabel.textAlignment = .center

        otherMethodsButton.translatesAutoresizingMaskIntoConstraints = false
        var configuration = UIButton.Configuration.bordered()
        configuration.title = "其他方式登录"
        configuration.image = UIImage(systemName: "globe")
        configuration.imagePadding = 8
        configuration.cornerStyle = .medium
        otherMethodsButton.configuration = configuration
        otherMethodsButton.addTarget(self, action: #selector(otherMethodsTapped), for: .touchUpInside)

        contentView.addSubview(dividerLabel)
        contentView.addSubview(otherMethodsButton)

        NSLayoutConstraint.activate([
            dividerLabel.topAnchor.constraint(equalTo: forgotPasswordButton.bottomAnchor, constant: 20),
            dividerLabel.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),

            otherMethodsButton.topAnchor.constraint(equalTo: dividerLabel.bottomAnchor, constant: 12),
            otherMethodsButton.leadingAnchor.constraint(equalTo: identifierField.leadingAnchor),
            otherMethodsButton.trailingAnchor.constraint(equalTo: identifierField.trailingAnchor),
            otherMethodsButton.heightAnchor.constraint(greaterThanOrEqualToConstant: 44),
            otherMethodsButton.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -32),
        ])
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

    @objc private func rememberLabelTapped() {
        rememberSwitch.setOn(!rememberSwitch.isOn, animated: true)
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
        onLoginTapped?(identifier, password, rememberSwitch.isOn)
    }

    @objc private func forgotPasswordTapped() {
        onForgotPassword?()
    }

    @objc private func otherMethodsTapped() {
        onOtherMethods?()
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
