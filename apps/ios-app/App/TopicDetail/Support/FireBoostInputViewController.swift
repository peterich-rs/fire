import UIKit

/// Compact UIKit Boost composer.
///
/// Presented as a page sheet. Content fills the sheet and the text view is the
/// flexible spacer, so keyboard/sheet resizing never fights a fixed card height.
@MainActor
final class FireBoostInputViewController: UIViewController, UITextViewDelegate {
    var onSubmit: ((String) -> Void)?
    var onCancel: (() -> Void)?

    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()
    private let textView = UITextView()
    private let placeholderLabel = UILabel()
    private let cancelButton = UIButton(type: .system)
    private let sendButton = UIButton(type: .system)
    private let buttonRow = UIStackView()
    private let contentStack = UIStackView()

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = FireTheme.uiCanvas
        configureHierarchy()
        configureActions()
        updateSendEnabled()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        textView.becomeFirstResponder()
    }

    private func configureHierarchy() {
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.text = "Boost"
        titleLabel.font = .preferredFont(forTextStyle: .headline)
        titleLabel.adjustsFontForContentSizeCategory = true
        titleLabel.textColor = FireTheme.uiInk

        subtitleLabel.translatesAutoresizingMaskIntoConstraints = false
        subtitleLabel.text = "用一句话回应这条帖子，也可以只发表情。"
        subtitleLabel.font = .preferredFont(forTextStyle: .subheadline)
        subtitleLabel.adjustsFontForContentSizeCategory = true
        subtitleLabel.textColor = FireTheme.uiSubtleInk
        subtitleLabel.numberOfLines = 0

        textView.translatesAutoresizingMaskIntoConstraints = false
        textView.backgroundColor = FireTheme.uiSoftSurface
        textView.textColor = FireTheme.uiInk
        textView.font = .preferredFont(forTextStyle: .body)
        textView.adjustsFontForContentSizeCategory = true
        textView.layer.cornerRadius = 12
        textView.layer.cornerCurve = .continuous
        textView.textContainerInset = UIEdgeInsets(top: 12, left: 10, bottom: 12, right: 10)
        textView.delegate = self
        textView.returnKeyType = .default
        textView.autocapitalizationType = .sentences
        textView.accessibilityLabel = "Boost 内容"
        // Let the text field shrink when the sheet is short instead of overflowing.
        textView.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        textView.setContentHuggingPriority(.defaultLow, for: .vertical)

        placeholderLabel.translatesAutoresizingMaskIntoConstraints = false
        placeholderLabel.text = "写点什么…"
        placeholderLabel.font = .preferredFont(forTextStyle: .body)
        placeholderLabel.adjustsFontForContentSizeCategory = true
        placeholderLabel.textColor = FireTheme.uiTertiaryInk
        placeholderLabel.isUserInteractionEnabled = false

        cancelButton.translatesAutoresizingMaskIntoConstraints = false
        cancelButton.setTitle("取消", for: .normal)
        cancelButton.titleLabel?.font = .preferredFont(forTextStyle: .body)
        cancelButton.setTitleColor(FireTheme.uiSubtleInk, for: .normal)
        cancelButton.setContentHuggingPriority(.required, for: .vertical)

        sendButton.translatesAutoresizingMaskIntoConstraints = false
        sendButton.setTitle("发送", for: .normal)
        sendButton.titleLabel?.font = .preferredFont(forTextStyle: .body).withTraits(.traitBold)
            ?? .boldSystemFont(ofSize: UIFont.preferredFont(forTextStyle: .body).pointSize)
        sendButton.setTitleColor(.white, for: .normal)
        sendButton.setTitleColor(UIColor.white.withAlphaComponent(0.55), for: .disabled)
        sendButton.backgroundColor = FireTheme.uiAccent
        sendButton.layer.cornerRadius = 12
        sendButton.layer.cornerCurve = .continuous
        sendButton.contentEdgeInsets = UIEdgeInsets(top: 10, left: 18, bottom: 10, right: 18)
        sendButton.setContentHuggingPriority(.required, for: .vertical)

        buttonRow.axis = .horizontal
        buttonRow.alignment = .center
        buttonRow.spacing = 12
        buttonRow.translatesAutoresizingMaskIntoConstraints = false
        buttonRow.addArrangedSubview(cancelButton)
        buttonRow.addArrangedSubview(UIView())
        buttonRow.addArrangedSubview(sendButton)

        let headerStack = UIStackView(arrangedSubviews: [titleLabel, subtitleLabel])
        headerStack.axis = .vertical
        headerStack.spacing = 6
        headerStack.translatesAutoresizingMaskIntoConstraints = false

        contentStack.axis = .vertical
        contentStack.spacing = 14
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        contentStack.addArrangedSubview(headerStack)
        contentStack.addArrangedSubview(textView)
        contentStack.addArrangedSubview(buttonRow)

        view.addSubview(contentStack)
        textView.addSubview(placeholderLabel)

        NSLayoutConstraint.activate([
            contentStack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 16),
            contentStack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 18),
            contentStack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -18),
            contentStack.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -16),

            // Soft minimum so empty sheets still look usable; can break if space is tight.
            textView.heightAnchor.constraint(greaterThanOrEqualToConstant: 96).withPriority(.defaultHigh),
            sendButton.heightAnchor.constraint(equalToConstant: 40),

            placeholderLabel.topAnchor.constraint(equalTo: textView.topAnchor, constant: 12),
            placeholderLabel.leadingAnchor.constraint(equalTo: textView.leadingAnchor, constant: 15),
            placeholderLabel.trailingAnchor.constraint(lessThanOrEqualTo: textView.trailingAnchor, constant: -12),
        ])
    }

    private func configureActions() {
        cancelButton.addAction(UIAction { [weak self] _ in
            self?.onCancel?()
            self?.dismiss(animated: true)
        }, for: .touchUpInside)

        sendButton.addAction(UIAction { [weak self] _ in
            guard let self else { return }
            let raw = self.textView.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !raw.isEmpty else { return }
            self.textView.resignFirstResponder()
            let submit = self.onSubmit
            self.dismiss(animated: true) {
                submit?(raw)
            }
        }, for: .touchUpInside)
    }

    private func updateSendEnabled() {
        let hasText = !(textView.text ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .isEmpty
        sendButton.isEnabled = hasText
        sendButton.alpha = hasText ? 1 : 0.55
        placeholderLabel.isHidden = !(textView.text ?? "").isEmpty
    }

    func textViewDidChange(_ textView: UITextView) {
        updateSendEnabled()
    }
}

private extension NSLayoutConstraint {
    func withPriority(_ priority: UILayoutPriority) -> NSLayoutConstraint {
        self.priority = priority
        return self
    }
}

private extension UIFont {
    func withTraits(_ traits: UIFontDescriptor.SymbolicTraits) -> UIFont? {
        guard let descriptor = fontDescriptor.withSymbolicTraits(traits) else {
            return nil
        }
        return UIFont(descriptor: descriptor, size: pointSize)
    }
}
