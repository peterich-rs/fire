import UIKit

@MainActor
final class FireOnboardingCredentialFormView: UIView, UITextFieldDelegate {
    var onLoginTapped: ((String, String, Bool) -> Void)?
    var onForgotPassword: (() -> Void)?
    var onExternalLogin: ((FireExternalLoginMethod) -> Void)?

    let scrollView = UIScrollView()
    let contentView = UIView()
    let identifierField = UITextField()
    let passwordField = UITextField()
    let passwordVisibilityButton = UIButton(type: .system)
    let rememberCheckboxButton = UIButton(type: .system)
    let rememberLabel = UILabel()
    let rememberRow = UIControl()
    let optionsRow = UIView()
    let loginButton = UIButton(type: .system)
    let lastLoginHintLabel = UILabel()
    let forgotPasswordButton = UIButton(type: .system)
    let dividerLabel = UILabel()
    let externalLoginStack = UIStackView()
    var externalLoginButtons: [UIButton] = []
    var isLoggingIn = false
    var isPasswordVisible = false
    var isRememberChecked = false
    var lastLoginMethod: FireLastLoginMethod?
    lazy var keyboardToolbar: UIToolbar = {
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

    static var passwordVisibilitySymbolConfiguration: UIImage.SymbolConfiguration {
        let pointSize = UIImage.SymbolConfiguration(pointSize: 15, weight: .medium, scale: .medium)
        // Hierarchical rendering gives the eyelid/pupil softer depth than flat template monochrome.
        return pointSize.applying(UIImage.SymbolConfiguration(hierarchicalColor: .tertiaryLabel))
    }

    func updateLoginButtonState() {
        guard !isLoggingIn else { return }
        let hasIdentifier = !(identifierField.text?
            .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
        let hasPassword = !(passwordField.text?.isEmpty ?? true)
        loginButton.isEnabled = hasIdentifier && hasPassword
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
