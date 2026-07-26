import UIKit

/// WeChat-style bottom input chrome for topic detail.
///
/// Pure UIKit (not a Texture node). The view controller pins this view to the
/// bottom of the page above the feed so feed cells can never composite through
/// the bar. Keyboard lift is a bottom-constraint constant, not Texture layout.
///
/// ```
/// ┌─────────────────────────────┐
/// │  feed                       │
/// ├─────────────────────────────┤  ← this view (opaque, full width)
/// │  [✎]  快速回复…        [↑]  │
/// └─────────────────────────────┘
/// │ keyboard                    │
/// └─────────────────────────────┘
/// ```
@MainActor
final class FireTopicQuickReplyBarView: UIView, UITextFieldDelegate {
    struct Callbacks {
        let onDraftChanged: (String) -> Void
        let onSubmit: () -> Void
        let onOpenAdvancedComposer: () -> Void
        let onClearTarget: () -> Void
        let onFocusChanged: (Bool) -> Void
    }

    var callbacks: Callbacks?

    var isInputFocused: Bool {
        textField.isFirstResponder
    }

    /// Current laid-out height including bottom padding. 0 when hidden.
    var barHeight: CGFloat {
        isHidden ? 0 : bounds.height
    }

    /// Preferred height for Auto Layout height constraint (includes bottom padding).
    func preferredHeight(forWidth width: CGFloat) -> CGFloat {
        guard !isHidden else { return 0 }
        return Self.estimatedHeight(
            state: currentState,
            width: max(width, 1),
            bottomInset: bottomInset
        )
    }

    private let backgroundFill = UIView()
    private let topBorderView = UIView()
    private let contentStack = UIStackView()
    private let topStack = UIStackView()
    private let typingLabel = UILabel()
    private let targetRow = UIStackView()
    private let targetLabel = UILabel()
    private let clearTargetButton = UIButton(type: .system)
    private let inputRow = UIStackView()
    private let composerButton = UIButton(type: .system)
    private let fieldContainer = UIView()
    private let textField = UITextField()
    private let sendButton = UIButton(type: .system)
    private let messageLabel = UILabel()

    private var applyingState = false
    private var contentStackBottomConstraint: NSLayoutConstraint?
    private var bottomInset: CGFloat = 0
    private var currentState = FireTopicDetailQuickReplyState(
        isVisible: false,
        typingSummary: nil,
        targetSummary: nil,
        placeholder: "快速回复…",
        draft: "",
        isSubmitting: false,
        validationMessage: nil
    )

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupView()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override var intrinsicContentSize: CGSize {
        let height = isHidden
            ? 0
            : Self.estimatedHeight(state: currentState, width: bounds.width > 1 ? bounds.width : UIScreen.main.bounds.width, bottomInset: bottomInset)
        return CGSize(width: UIView.noIntrinsicMetric, height: height)
    }

    func apply(state: FireTopicDetailQuickReplyState) {
        applyingState = true
        defer { applyingState = false }

        currentState = state
        isHidden = !state.isVisible

        typingLabel.text = state.typingSummary
        typingLabel.isHidden = (state.typingSummary?.isEmpty ?? true)

        targetLabel.text = state.targetSummary
        targetRow.isHidden = (state.targetSummary?.isEmpty ?? true)

        textField.attributedPlaceholder = NSAttributedString(
            string: state.placeholder,
            attributes: [
                .foregroundColor: FireTheme.uiTertiaryInk,
                .font: UIFont.preferredFont(forTextStyle: .subheadline),
            ]
        )
        if textField.text != state.draft {
            textField.text = state.draft
        }
        sendButton.isEnabled = !state.isSubmitting
        composerButton.isEnabled = !state.isSubmitting
        clearTargetButton.isEnabled = !state.isSubmitting

        applySendButton(isSubmitting: state.isSubmitting)

        if let message = state.validationMessage, message.isEmpty == false {
            messageLabel.text = message
            messageLabel.textColor = message.contains("至少需要")
                ? FireTheme.uiSubtleInk
                : FireTheme.uiError
            messageLabel.isHidden = false
        } else {
            messageLabel.text = nil
            messageLabel.isHidden = true
        }

        invalidateIntrinsicContentSize()
        setNeedsLayout()
    }

    func focusInput() {
        textField.becomeFirstResponder()
    }

    func resignInputFocus() {
        textField.resignFirstResponder()
    }

    /// Home-indicator / keyboard-adjacent padding under the input row.
    func updateBottomInset(_ inset: CGFloat) {
        let target = max(inset, 0)
        guard abs(bottomInset - target) > 0.5 else { return }
        bottomInset = target
        contentStackBottomConstraint?.constant = -(10 + bottomInset)
        invalidateIntrinsicContentSize()
        setNeedsLayout()
    }

    /// Deterministic height used by tests and intrinsic content size.
    static func estimatedHeight(
        state: FireTopicDetailQuickReplyState,
        width: CGFloat,
        bottomInset: CGFloat
    ) -> CGFloat {
        guard state.isVisible else { return 0 }
        let contentWidth = max(width - 24, 1)
        // top pad 10 + input row 36 + bottom content pad 10 + home/keyboard pad
        var height: CGFloat = 10 + 36 + 10 + max(bottomInset, 0)

        let caption1LineHeight = ceil(UIFont.preferredFont(forTextStyle: .caption1).lineHeight)
        var topStackHeight: CGFloat = 0
        if !(state.typingSummary?.isEmpty ?? true) {
            topStackHeight += caption1LineHeight
        }
        if !(state.targetSummary?.isEmpty ?? true) {
            if topStackHeight > 0 {
                topStackHeight += 8
            }
            topStackHeight += max(caption1LineHeight, 18)
        }
        if topStackHeight > 0 {
            height += topStackHeight + 8
        }

        if let message = state.validationMessage, !message.isEmpty {
            let font = UIFont.preferredFont(forTextStyle: .caption2)
            let messageBounds = (message as NSString).boundingRect(
                with: CGSize(width: contentWidth, height: .greatestFiniteMagnitude),
                options: [.usesLineFragmentOrigin, .usesFontLeading],
                attributes: [.font: font],
                context: nil
            )
            height += 8 + ceil(messageBounds.height)
        }

        return ceil(height)
    }

    // MARK: - UITextFieldDelegate

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        callbacks?.onSubmit()
        return false
    }

    func textFieldDidBeginEditing(_ textField: UITextField) {
        callbacks?.onFocusChanged(true)
    }

    func textFieldDidEndEditing(_ textField: UITextField) {
        callbacks?.onFocusChanged(false)
    }

    // MARK: - Actions

    @objc private func draftDidChange() {
        guard !applyingState else { return }
        callbacks?.onDraftChanged(textField.text ?? "")
    }

    @objc private func handleSubmit() {
        callbacks?.onSubmit()
    }

    @objc private func handleOpenAdvancedComposer() {
        callbacks?.onOpenAdvancedComposer()
    }

    @objc private func handleClearTarget() {
        // Controller clears draft + target; resign after apply so the empty field
        // is committed before keyboard dismissal animations run.
        callbacks?.onClearTarget()
        textField.resignFirstResponder()
        callbacks?.onFocusChanged(false)
    }

    // MARK: - Private

    private func applySendButton(isSubmitting: Bool) {
        if isSubmitting {
            let indicator = UIActivityIndicatorView(style: .medium)
            indicator.color = FireTheme.uiAccent
            indicator.startAnimating()
            sendButton.configuration = nil
            sendButton.setTitle(nil, for: .normal)
            sendButton.setImage(nil, for: .normal)
            sendButton.subviews.forEach { $0.removeFromSuperview() }
            sendButton.addSubview(indicator)
            indicator.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                indicator.centerXAnchor.constraint(equalTo: sendButton.centerXAnchor),
                indicator.centerYAnchor.constraint(equalTo: sendButton.centerYAnchor),
            ])
        } else {
            sendButton.subviews.forEach {
                if $0 is UIActivityIndicatorView {
                    $0.removeFromSuperview()
                }
            }
            var sendConfig = UIButton.Configuration.plain()
            sendConfig.image = UIImage(systemName: "arrow.up.circle.fill")
            sendConfig.contentInsets = .zero
            sendConfig.preferredSymbolConfigurationForImage = UIImage.SymbolConfiguration(
                pointSize: 28,
                weight: .regular
            )
            sendButton.configuration = sendConfig
            sendButton.tintColor = FireTheme.uiAccent
        }
    }

    private func setupView() {
        // Fully opaque canvas — never translucent chrome over scrolling feed text.
        // Hard opaque resolved color (not dynamic with alpha) so UIKit never
        // composites underlying Texture cells through this layer.
        let canvas = FireTheme.uiCanvas.resolvedColor(with: traitCollection)
        isOpaque = true
        backgroundColor = canvas
        clipsToBounds = true
        tintColor = FireTheme.uiAccent

        backgroundFill.translatesAutoresizingMaskIntoConstraints = false
        backgroundFill.isOpaque = true
        backgroundFill.backgroundColor = canvas
        addSubview(backgroundFill)

        topBorderView.translatesAutoresizingMaskIntoConstraints = false
        topBorderView.backgroundColor = FireTheme.uiDivider
        backgroundFill.addSubview(topBorderView)

        contentStack.axis = .vertical
        contentStack.spacing = 8
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        backgroundFill.addSubview(contentStack)

        topStack.axis = .vertical
        topStack.spacing = 8

        typingLabel.font = UIFont.preferredFont(forTextStyle: .caption1)
        typingLabel.textColor = FireTheme.uiSubtleInk
        typingLabel.numberOfLines = 1

        targetRow.axis = .horizontal
        targetRow.spacing = 8
        targetRow.alignment = .center

        targetLabel.font = UIFont.preferredFont(forTextStyle: .caption1)
        targetLabel.textColor = FireTheme.uiAccent
        targetLabel.numberOfLines = 1

        // Fixed 28pt hit target — plain UIImage buttons stretch inside UIStackView.
        var clearConfig = UIButton.Configuration.plain()
        clearConfig.image = UIImage(systemName: "xmark.circle.fill")
        clearConfig.contentInsets = .zero
        clearConfig.preferredSymbolConfigurationForImage = UIImage.SymbolConfiguration(
            pointSize: 18,
            weight: .regular
        )
        clearTargetButton.configuration = clearConfig
        clearTargetButton.tintColor = FireTheme.uiTertiaryInk
        clearTargetButton.accessibilityLabel = "取消目标"
        clearTargetButton.addTarget(self, action: #selector(handleClearTarget), for: .touchUpInside)
        clearTargetButton.setContentHuggingPriority(.required, for: .horizontal)
        clearTargetButton.setContentCompressionResistancePriority(.required, for: .horizontal)
        clearTargetButton.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            clearTargetButton.widthAnchor.constraint(equalToConstant: 28),
            clearTargetButton.heightAnchor.constraint(equalToConstant: 28),
        ])

        let targetSpacer = UIView()
        targetSpacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        targetSpacer.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        targetRow.addArrangedSubview(targetLabel)
        targetRow.addArrangedSubview(targetSpacer)
        targetRow.addArrangedSubview(clearTargetButton)

        topStack.addArrangedSubview(typingLabel)
        topStack.addArrangedSubview(targetRow)
        contentStack.addArrangedSubview(topStack)

        inputRow.axis = .horizontal
        inputRow.spacing = 10
        inputRow.alignment = .center

        var composerConfig = UIButton.Configuration.plain()
        composerConfig.image = UIImage(systemName: "square.and.pencil")
        composerConfig.contentInsets = .zero
        composerConfig.preferredSymbolConfigurationForImage = UIImage.SymbolConfiguration(
            pointSize: 20,
            weight: .medium
        )
        composerButton.configuration = composerConfig
        composerButton.tintColor = FireTheme.uiSubtleInk
        composerButton.accessibilityLabel = "打开完整编辑器"
        composerButton.addTarget(self, action: #selector(handleOpenAdvancedComposer), for: .touchUpInside)

        fieldContainer.translatesAutoresizingMaskIntoConstraints = false
        fieldContainer.backgroundColor = FireTheme.uiSurface
        fieldContainer.layer.cornerRadius = 18
        fieldContainer.layer.cornerCurve = .continuous
        fieldContainer.clipsToBounds = true

        textField.borderStyle = .none
        textField.backgroundColor = .clear
        textField.font = UIFont.preferredFont(forTextStyle: .subheadline)
        textField.adjustsFontForContentSizeCategory = true
        textField.textColor = FireTheme.uiInk
        textField.tintColor = FireTheme.uiAccent
        textField.returnKeyType = .send
        textField.delegate = self
        textField.clearButtonMode = .whileEditing
        textField.autocorrectionType = .default
        textField.translatesAutoresizingMaskIntoConstraints = false
        textField.addTarget(self, action: #selector(draftDidChange), for: .editingChanged)
        textField.setContentHuggingPriority(.defaultLow, for: .horizontal)
        textField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        fieldContainer.addSubview(textField)

        applySendButton(isSubmitting: false)
        sendButton.accessibilityLabel = "发送"
        sendButton.addTarget(self, action: #selector(handleSubmit), for: .touchUpInside)
        sendButton.fireBindPressBounce(.compact)

        inputRow.addArrangedSubview(composerButton)
        inputRow.addArrangedSubview(fieldContainer)
        inputRow.addArrangedSubview(sendButton)
        contentStack.addArrangedSubview(inputRow)

        messageLabel.font = UIFont.preferredFont(forTextStyle: .caption2)
        messageLabel.numberOfLines = 0
        messageLabel.isHidden = true
        contentStack.addArrangedSubview(messageLabel)

        let bottomConstraint = contentStack.bottomAnchor.constraint(
            equalTo: backgroundFill.bottomAnchor,
            constant: -10
        )
        contentStackBottomConstraint = bottomConstraint

        NSLayoutConstraint.activate([
            backgroundFill.leadingAnchor.constraint(equalTo: leadingAnchor),
            backgroundFill.trailingAnchor.constraint(equalTo: trailingAnchor),
            backgroundFill.topAnchor.constraint(equalTo: topAnchor),
            backgroundFill.bottomAnchor.constraint(equalTo: bottomAnchor),

            topBorderView.leadingAnchor.constraint(equalTo: backgroundFill.leadingAnchor),
            topBorderView.trailingAnchor.constraint(equalTo: backgroundFill.trailingAnchor),
            topBorderView.topAnchor.constraint(equalTo: backgroundFill.topAnchor),
            topBorderView.heightAnchor.constraint(equalToConstant: 1.0 / UIScreen.main.scale),

            contentStack.leadingAnchor.constraint(equalTo: backgroundFill.leadingAnchor, constant: 12),
            contentStack.trailingAnchor.constraint(equalTo: backgroundFill.trailingAnchor, constant: -12),
            contentStack.topAnchor.constraint(equalTo: backgroundFill.topAnchor, constant: 10),
            bottomConstraint,

            composerButton.widthAnchor.constraint(equalToConstant: 36),
            composerButton.heightAnchor.constraint(equalToConstant: 36),

            fieldContainer.heightAnchor.constraint(equalToConstant: 36),
            textField.leadingAnchor.constraint(equalTo: fieldContainer.leadingAnchor, constant: 12),
            textField.trailingAnchor.constraint(equalTo: fieldContainer.trailingAnchor, constant: -8),
            textField.topAnchor.constraint(equalTo: fieldContainer.topAnchor),
            textField.bottomAnchor.constraint(equalTo: fieldContainer.bottomAnchor),

            sendButton.widthAnchor.constraint(equalToConstant: 36),
            sendButton.heightAnchor.constraint(equalToConstant: 36),
        ])

        isHidden = true
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        guard traitCollection.hasDifferentColorAppearance(comparedTo: previousTraitCollection) else {
            return
        }
        let canvas = FireTheme.uiCanvas.resolvedColor(with: traitCollection)
        backgroundColor = canvas
        backgroundFill.backgroundColor = canvas
    }
}

// MARK: - Compatibility alias for older call sites / docs

typealias FireTopicQuickReplyBarNode = FireTopicQuickReplyBarView
