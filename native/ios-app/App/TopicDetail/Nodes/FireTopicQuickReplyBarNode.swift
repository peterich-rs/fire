import AsyncDisplayKit
import UIKit

@MainActor
final class FireTopicQuickReplyBarNode: ASDisplayNode {
    struct Callbacks {
        let onDraftChanged: (String) -> Void
        let onSubmit: () -> Void
        let onOpenAdvancedComposer: () -> Void
        let onClearTarget: () -> Void
        let onFocusChanged: (Bool) -> Void
    }

    private let contentNode = ASDisplayNode(viewBlock: {
        FireTopicQuickReplyBarView()
    })
    private var measuredWidth: CGFloat = max(UIScreen.main.bounds.width, 1)
    private var measuredHeight: CGFloat = 0
    private var bottomInset: CGFloat = 0

    var callbacks: Callbacks? {
        didSet {
            contentView.callbacks = callbacks
        }
    }

    var isInputFocused: Bool {
        contentView.isInputFocused
    }

    private var currentState = FireTopicDetailQuickReplyState(
        isVisible: false,
        typingSummary: nil,
        targetSummary: nil,
        placeholder: "快速回复…",
        draft: "",
        isSubmitting: false,
        validationMessage: nil
    )

    override init() {
        super.init()
        automaticallyManagesSubnodes = true
        backgroundColor = .clear
        updateMeasuredSize(forWidth: measuredWidth)
    }

    func apply(state: FireTopicDetailQuickReplyState) {
        currentState = state
        isHidden = !state.isVisible
        contentView.apply(state: state)
        updateMeasuredSize(forWidth: measuredWidth)
        invalidateCalculatedLayout()
        setNeedsLayout()
    }

    func focusInput() {
        contentView.focusInput()
    }

    func resignInputFocus() {
        contentView.resignInputFocus()
    }

    func updateBottomInset(_ inset: CGFloat) {
        bottomInset = inset
        contentView.updateBottomInset(inset)
        updateMeasuredSize(forWidth: measuredWidth)
        invalidateCalculatedLayout()
        setNeedsLayout()
    }

    func updateLayoutWidth(_ width: CGFloat) {
        updateMeasuredSize(forWidth: width)
        invalidateCalculatedLayout()
        setNeedsLayout()
    }

    override func layoutSpecThatFits(_ constrainedSize: ASSizeRange) -> ASLayoutSpec {
        guard currentState.isVisible else {
            return ASInsetLayoutSpec(insets: .zero, child: ASLayoutSpec())
        }
        let constrainedWidth = max(constrainedSize.max.width, 1)
        contentNode.style.minWidth = ASDimensionMake(constrainedWidth)
        contentNode.style.maxWidth = ASDimensionMake(constrainedWidth)
        contentNode.style.minHeight = ASDimensionMake(max(measuredHeight, 1))
        contentNode.style.maxHeight = ASDimensionMake(max(measuredHeight, 1))
        return ASWrapperLayoutSpec(layoutElement: contentNode)
    }

    private var contentView: FireTopicQuickReplyBarView {
        guard let view = contentNode.view as? FireTopicQuickReplyBarView else {
            fatalError("Expected FireTopicQuickReplyBarView backing view")
        }
        return view
    }

    private func updateMeasuredSize(forWidth width: CGFloat) {
        let targetWidth = max(width, 1)
        measuredWidth = targetWidth
        measuredHeight = currentState.isVisible
            ? max(estimatedHeight(forWidth: targetWidth), 1)
            : 0
        contentNode.style.preferredSize = CGSize(
            width: targetWidth,
            height: measuredHeight
        )
    }

    // Avoid re-entering UIKit fitting while the topic-detail controller is laying out.
    // The bar UI is simple enough that a deterministic height estimate is safer here.
    private func estimatedHeight(forWidth width: CGFloat) -> CGFloat {
        let contentWidth = max(width - 32, 1)
        var height: CGFloat = 10 + 36 + 12 + bottomInset

        let caption1LineHeight = ceil(UIFont.preferredFont(forTextStyle: .caption1).lineHeight)
        var topStackHeight: CGFloat = 0
        if !(currentState.typingSummary?.isEmpty ?? true) {
            topStackHeight += caption1LineHeight
        }
        if !(currentState.targetSummary?.isEmpty ?? true) {
            if topStackHeight > 0 {
                topStackHeight += 8
            }
            topStackHeight += max(caption1LineHeight, 18)
        }
        if topStackHeight > 0 {
            height += topStackHeight + 10
        }

        if let message = currentState.validationMessage,
           !message.isEmpty {
            let font = UIFont.preferredFont(forTextStyle: .caption2)
            let messageBounds = (message as NSString).boundingRect(
                with: CGSize(width: contentWidth, height: .greatestFiniteMagnitude),
                options: [.usesLineFragmentOrigin, .usesFontLeading],
                attributes: [.font: font],
                context: nil
            )
            height += 10 + ceil(messageBounds.height)
        }

        return ceil(height)
    }
}

private final class FireTopicQuickReplyBarView: UIView, UITextFieldDelegate {
    private let backgroundView = UIView()
    private let topBorderView = UIView()
    private let topStack = UIStackView()
    private let typingLabel = UILabel()
    private let targetRow = UIStackView()
    private let targetLabel = UILabel()
    private let clearTargetButton = UIButton(type: .system)
    private let inputRow = UIStackView()
    private let composerButton = UIButton(type: .system)
    private let textField = UITextField()
    private let sendButton = UIButton(type: .system)
    private let messageLabel = UILabel()

    var callbacks: FireTopicQuickReplyBarNode.Callbacks?

    var isInputFocused: Bool {
        textField.isFirstResponder
    }

    private var applyingState = false
    private var contentStackBottomConstraint: NSLayoutConstraint?

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupView()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    func apply(state: FireTopicDetailQuickReplyState) {
        applyingState = true
        defer { applyingState = false }

        typingLabel.text = state.typingSummary
        typingLabel.isHidden = (state.typingSummary?.isEmpty ?? true)

        targetLabel.text = state.targetSummary
        targetRow.isHidden = (state.targetSummary?.isEmpty ?? true)

        textField.placeholder = state.placeholder
        if textField.text != state.draft {
            textField.text = state.draft
        }
        sendButton.isEnabled = !state.isSubmitting
        composerButton.isEnabled = !state.isSubmitting
        clearTargetButton.isEnabled = !state.isSubmitting

        if state.isSubmitting {
            let indicator = UIActivityIndicatorView(style: .medium)
            indicator.startAnimating()
            sendButton.configuration?.image = nil
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
            sendButton.setImage(UIImage(systemName: "arrow.up.circle.fill"), for: .normal)
        }

        if let message = state.validationMessage,
           message.isEmpty == false {
            messageLabel.text = message
            messageLabel.textColor = message.contains("至少需要") ? .secondaryLabel : .systemRed
            messageLabel.isHidden = false
        } else {
            messageLabel.text = nil
            messageLabel.isHidden = true
        }

        setNeedsLayout()
    }

    func focusInput() {
        textField.becomeFirstResponder()
    }

    func resignInputFocus() {
        textField.resignFirstResponder()
    }

    func updateBottomInset(_ inset: CGFloat) {
        contentStackBottomConstraint?.constant = -(12 + inset)
        setNeedsLayout()
    }

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

    @objc
    private func draftDidChange() {
        guard !applyingState else { return }
        callbacks?.onDraftChanged(textField.text ?? "")
    }

    @objc
    private func handleSubmit() {
        callbacks?.onSubmit()
    }

    @objc
    private func handleOpenAdvancedComposer() {
        callbacks?.onOpenAdvancedComposer()
    }

    @objc
    private func handleClearTarget() {
        let shouldRestoreFocus = textField.isFirstResponder
        callbacks?.onClearTarget()
        if shouldRestoreFocus {
            DispatchQueue.main.async { [weak self] in
                self?.textField.becomeFirstResponder()
            }
        }
    }

    private func setupView() {
        backgroundColor = .clear
        tintColor = FireTopicDetailCellColors.accent

        backgroundView.translatesAutoresizingMaskIntoConstraints = false
        backgroundView.backgroundColor = .systemBackground
        addSubview(backgroundView)

        topBorderView.translatesAutoresizingMaskIntoConstraints = false
        topBorderView.backgroundColor = .separator
        backgroundView.addSubview(topBorderView)

        let contentStack = UIStackView()
        contentStack.axis = .vertical
        contentStack.spacing = 10
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        backgroundView.addSubview(contentStack)

        topStack.axis = .vertical
        topStack.spacing = 8
        topStack.translatesAutoresizingMaskIntoConstraints = false

        typingLabel.font = UIFont.preferredFont(forTextStyle: .caption1)
        typingLabel.textColor = .secondaryLabel
        typingLabel.numberOfLines = 1

        targetRow.axis = .horizontal
        targetRow.spacing = 8
        targetRow.alignment = .center

        targetLabel.font = UIFont.preferredFont(forTextStyle: .caption1)
        targetLabel.textColor = FireTopicDetailCellColors.accent
        targetLabel.numberOfLines = 1

        clearTargetButton.setImage(UIImage(systemName: "xmark.circle.fill"), for: .normal)
        clearTargetButton.tintColor = .tertiaryLabel
        clearTargetButton.addTarget(self, action: #selector(handleClearTarget), for: .touchUpInside)

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
        composerButton.configuration = composerConfig
        composerButton.tintColor = FireTopicDetailCellColors.accent
        composerButton.addTarget(self, action: #selector(handleOpenAdvancedComposer), for: .touchUpInside)

        textField.borderStyle = .roundedRect
        textField.font = UIFont.preferredFont(forTextStyle: .subheadline)
        textField.adjustsFontForContentSizeCategory = true
        textField.returnKeyType = .send
        textField.delegate = self
        textField.clearButtonMode = .whileEditing
        textField.addTarget(self, action: #selector(draftDidChange), for: .editingChanged)
        textField.setContentHuggingPriority(.defaultLow, for: .horizontal)
        textField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        var sendConfig = UIButton.Configuration.plain()
        sendConfig.image = UIImage(systemName: "arrow.up.circle.fill")
        sendButton.configuration = sendConfig
        sendButton.tintColor = FireTopicDetailCellColors.accent
        sendButton.addTarget(self, action: #selector(handleSubmit), for: .touchUpInside)

        inputRow.addArrangedSubview(composerButton)
        inputRow.addArrangedSubview(textField)
        inputRow.addArrangedSubview(sendButton)
        contentStack.addArrangedSubview(inputRow)

        messageLabel.font = UIFont.preferredFont(forTextStyle: .caption2)
        messageLabel.numberOfLines = 0
        messageLabel.isHidden = true
        contentStack.addArrangedSubview(messageLabel)

        let bottomConstraint = contentStack.bottomAnchor.constraint(equalTo: backgroundView.bottomAnchor, constant: -12)
        contentStackBottomConstraint = bottomConstraint

        NSLayoutConstraint.activate([
            backgroundView.leadingAnchor.constraint(equalTo: leadingAnchor),
            backgroundView.trailingAnchor.constraint(equalTo: trailingAnchor),
            backgroundView.topAnchor.constraint(equalTo: topAnchor),
            backgroundView.bottomAnchor.constraint(equalTo: bottomAnchor),

            topBorderView.leadingAnchor.constraint(equalTo: backgroundView.leadingAnchor),
            topBorderView.trailingAnchor.constraint(equalTo: backgroundView.trailingAnchor),
            topBorderView.topAnchor.constraint(equalTo: backgroundView.topAnchor),
            topBorderView.heightAnchor.constraint(equalToConstant: 0.5),

            contentStack.leadingAnchor.constraint(equalTo: backgroundView.leadingAnchor, constant: 16),
            contentStack.trailingAnchor.constraint(equalTo: backgroundView.trailingAnchor, constant: -16),
            contentStack.topAnchor.constraint(equalTo: backgroundView.topAnchor, constant: 10),
            bottomConstraint,

            composerButton.widthAnchor.constraint(equalToConstant: 34),
            composerButton.heightAnchor.constraint(equalToConstant: 34),
            textField.heightAnchor.constraint(equalToConstant: 36),
            sendButton.widthAnchor.constraint(equalToConstant: 34),
            sendButton.heightAnchor.constraint(equalToConstant: 34),
        ])
    }
}
