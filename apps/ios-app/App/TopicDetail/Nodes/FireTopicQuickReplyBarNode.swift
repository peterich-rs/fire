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

    let backgroundFill = UIView()
    let topBorderView = UIView()
    let contentStack = UIStackView()
    let topStack = UIStackView()
    let typingLabel = UILabel()
    let targetRow = UIStackView()
    let targetLabel = UILabel()
    let clearTargetButton = UIButton(type: .system)
    let inputBar = FireBottomInputBar(kind: .topicQuickReply)
    let messageLabel = UILabel()

    var applyingState = false
    var contentStackBottomConstraint: NSLayoutConstraint?
    var bottomInset: CGFloat = 0
    var currentState = FireTopicDetailQuickReplyState(
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

        let previous = currentState
        currentState = state
        var heightChanged = previous.isVisible != state.isVisible

        if previous.isVisible != state.isVisible {
            isHidden = !state.isVisible
        }
        if previous.typingSummary != state.typingSummary {
            typingLabel.text = state.typingSummary
            typingLabel.isHidden = (state.typingSummary?.isEmpty ?? true)
            heightChanged = true
        }
        if previous.targetSummary != state.targetSummary {
            targetLabel.text = state.targetSummary
            targetRow.isHidden = (state.targetSummary?.isEmpty ?? true)
            heightChanged = true
        }
        if previous.draft != state.draft
            || previous.placeholder != state.placeholder
            || previous.isSubmitting != state.isSubmitting {
            inputBar.apply(
                text: state.draft,
                placeholder: state.placeholder,
                isSending: state.isSubmitting,
                isEnabled: !state.isSubmitting
            )
            clearTargetButton.isEnabled = !state.isSubmitting
            heightChanged = true
        }
        if previous.validationMessage != state.validationMessage {
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
            heightChanged = true
        }

        if heightChanged {
            invalidateIntrinsicContentSize()
            setNeedsLayout()
        }
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
}


// MARK: - Compatibility alias for older call sites / docs

typealias FireTopicQuickReplyBarNode = FireTopicQuickReplyBarView
