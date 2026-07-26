import UIKit

/// Compact UIKit Boost composer. Avoids `UIAlertController` text fields, which
/// spam Auto Layout / keyboard session warnings and feel cramped for short replies.
@MainActor
final class FireBoostInputViewController: UIViewController, UITextViewDelegate {
    var onSubmit: ((String) -> Void)?
    var onCancel: (() -> Void)?

    private let cardView = UIView()
    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()
    private let textView = UITextView()
    private let placeholderLabel = UILabel()
    private let cancelButton = UIButton(type: .system)
    private let sendButton = UIButton(type: .system)
    private let buttonRow = UIStackView()
    private var keyboardBottomConstraint: NSLayoutConstraint?

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = FireTheme.uiCanvas
        configureHierarchy()
        configureActions()
        updateSendEnabled()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(keyboardWillChange(_:)),
            name: UIResponder.keyboardWillChangeFrameNotification,
            object: nil
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        textView.becomeFirstResponder()
    }

    private func configureHierarchy() {
        cardView.translatesAutoresizingMaskIntoConstraints = false
        cardView.backgroundColor = FireTheme.uiPanelElevated
        cardView.layer.cornerRadius = 16
        cardView.layer.cornerCurve = .continuous
        view.addSubview(cardView)

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

        buttonRow.translatesAutoresizingMaskIntoConstraints = false
        buttonRow.axis = .horizontal
        buttonRow.alignment = .center
        buttonRow.spacing = 12
        buttonRow.addArrangedSubview(cancelButton)
        buttonRow.addArrangedSubview(UIView())
        buttonRow.addArrangedSubview(sendButton)

        [titleLabel, subtitleLabel, textView, buttonRow].forEach { cardView.addSubview($0) }
        textView.addSubview(placeholderLabel)

        let bottom = cardView.bottomAnchor.constraint(lessThanOrEqualTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -16)
        keyboardBottomConstraint = bottom

        NSLayoutConstraint.activate([
            cardView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            cardView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            cardView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 12),
            bottom,

            titleLabel.topAnchor.constraint(equalTo: cardView.topAnchor, constant: 18),
            titleLabel.leadingAnchor.constraint(equalTo: cardView.leadingAnchor, constant: 18),
            titleLabel.trailingAnchor.constraint(equalTo: cardView.trailingAnchor, constant: -18),

            subtitleLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 6),
            subtitleLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            subtitleLabel.trailingAnchor.constraint(equalTo: titleLabel.trailingAnchor),

            textView.topAnchor.constraint(equalTo: subtitleLabel.bottomAnchor, constant: 14),
            textView.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            textView.trailingAnchor.constraint(equalTo: titleLabel.trailingAnchor),
            textView.heightAnchor.constraint(greaterThanOrEqualToConstant: 120),

            placeholderLabel.topAnchor.constraint(equalTo: textView.topAnchor, constant: 12),
            placeholderLabel.leadingAnchor.constraint(equalTo: textView.leadingAnchor, constant: 15),
            placeholderLabel.trailingAnchor.constraint(lessThanOrEqualTo: textView.trailingAnchor, constant: -12),

            buttonRow.topAnchor.constraint(equalTo: textView.bottomAnchor, constant: 14),
            buttonRow.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            buttonRow.trailingAnchor.constraint(equalTo: titleLabel.trailingAnchor),
            buttonRow.bottomAnchor.constraint(equalTo: cardView.bottomAnchor, constant: -16),
            sendButton.heightAnchor.constraint(equalToConstant: 40),
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

    @objc private func keyboardWillChange(_ notification: Notification) {
        guard
            let frame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect,
            let duration = notification.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? Double,
            let curveRaw = notification.userInfo?[UIResponder.keyboardAnimationCurveUserInfoKey] as? UInt
        else {
            return
        }

        let keyboardFrameInView = view.convert(frame, from: nil)
        let overlap = max(0, view.bounds.maxY - keyboardFrameInView.minY - view.safeAreaInsets.bottom)
        keyboardBottomConstraint?.constant = -(max(overlap, 0) + 16)

        let options = UIView.AnimationOptions(rawValue: curveRaw << 16)
        UIView.animate(withDuration: duration, delay: 0, options: options) {
            self.view.layoutIfNeeded()
        }
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
