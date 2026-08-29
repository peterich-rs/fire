import UIKit

/// WeChat-style bottom input chrome for topic detail.
///
/// Pure UIKit (not a Texture node). The view controller pins this view to the
/// bottom of the page above the feed so feed cells can never composite through
/// the bar. Keyboard lift is a bottom-constraint constant, not Texture layout.
/// Growing / wrap / paste / @mention live in `FireBottomInputBar`.
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
final class FireTopicQuickReplyBarView: UIView {
    struct Callbacks {
        let onDraftChanged: (String) -> Void
        let onSubmit: (FireBottomInputPayload) -> Void
        let onOpenAdvancedComposer: () -> Void
        let onClearTarget: () -> Void
        let onFocusChanged: (Bool) -> Void
        let onHeightChanged: () -> Void
        let onSearchMentions: (String) async -> [FireBottomInputMention]
        let onPickImage: () -> Void
    }

    var callbacks: Callbacks? {
        didSet { bindInputBarCallbacks() }
    }

    var isInputFocused: Bool {
        inputBar.isInputFocused
    }

    /// Current laid-out height including bottom padding. 0 when hidden.
    var barHeight: CGFloat {
        isHidden ? 0 : bounds.height
    }

    /// Preferred height for Auto Layout height constraint (includes bottom padding).
    func preferredHeight(forWidth width: CGFloat) -> CGFloat {
        guard !isHidden else { return 0 }
        if bounds.width > 1 {
            layoutIfNeeded()
            let measured = backgroundFill.systemLayoutSizeFitting(
                CGSize(width: max(width, 1), height: UIView.layoutFittingCompressedSize.height),
                withHorizontalFittingPriority: .required,
                verticalFittingPriority: .fittingSizeLevel
            ).height
            if measured > 1 {
                return ceil(measured)
            }
        }
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
    private let inputBar = FireBottomInputBar(kind: .topicQuickReply)
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
        bindInputBarCallbacks()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override var intrinsicContentSize: CGSize {
        let height = isHidden
            ? 0
            : preferredHeight(forWidth: bounds.width > 1 ? bounds.width : UIScreen.main.bounds.width)
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

        inputBar.apply(
            text: state.draft,
            placeholder: state.placeholder,
            isSending: state.isSubmitting,
            isEnabled: !state.isSubmitting
        )
        clearTargetButton.isEnabled = !state.isSubmitting

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
        inputBar.focusInput()
    }

    func resignInputFocus() {
        inputBar.resignInputFocus()
    }

    func resetAfterSend() {
        inputBar.resetAfterSend()
    }

    func insertImage(_ image: UIImage) {
        inputBar.insertImage(image)
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

    /// Deterministic height used by tests and intrinsic content size fallback.
    static func estimatedHeight(
        state: FireTopicDetailQuickReplyState,
        width: CGFloat,
        bottomInset: CGFloat
    ) -> CGFloat {
        guard state.isVisible else { return 0 }
        let contentWidth = max(width - 24, 1)
        var height: CGFloat = 10 + 10 + max(bottomInset, 0)
        height += FireBottomInputBar.estimatedWrappedHeight(text: state.draft, width: contentWidth)

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

    // MARK: - Actions

    @objc private func handleClearTarget() {
        callbacks?.onClearTarget()
        inputBar.resignInputFocus()
        callbacks?.onFocusChanged(false)
    }

    // MARK: - Private

    private func bindInputBarCallbacks() {
        inputBar.callbacks = .init(
            onTextChanged: { [weak self] text in
                guard let self, !self.applyingState else { return }
                self.callbacks?.onDraftChanged(text)
            },
            onSend: { [weak self] payload in
                self?.callbacks?.onSubmit(payload)
            },
            onLeadingAction: { [weak self] in
                self?.callbacks?.onOpenAdvancedComposer()
            },
            onFocusChanged: { [weak self] focused in
                self?.callbacks?.onFocusChanged(focused)
            },
            onHeightChanged: { [weak self] _ in
                guard let self else { return }
                self.invalidateIntrinsicContentSize()
                self.callbacks?.onHeightChanged()
            },
            onSearchMentions: { [weak self] term in
                await self?.callbacks?.onSearchMentions(term) ?? []
            },
            onPickImage: { [weak self] in
                self?.callbacks?.onPickImage()
            }
        )
    }

    private func setupView() {
        // Fully opaque canvas — never translucent chrome over scrolling feed text.
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
        contentStack.addArrangedSubview(inputBar)

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
        ])

        isHidden = true
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        guard traitCollection.hasDifferentColorAppearance(comparedTo: previousTraitCollection) else {
            return
        }
        applyThemeColorsIfNeeded()
    }

    /// Re-resolve opaque canvas colors after appearance preference changes.
    func applyThemeColorsIfNeeded() {
        let canvas = FireTheme.uiCanvas.resolvedColor(with: traitCollection)
        backgroundColor = canvas
        backgroundFill.backgroundColor = canvas
        topBorderView.backgroundColor = FireTheme.uiDivider
        tintColor = FireTheme.uiAccent
        inputBar.applyThemeColorsIfNeeded()
    }
}

// MARK: - Compatibility alias for older call sites / docs

typealias FireTopicQuickReplyBarNode = FireTopicQuickReplyBarView
