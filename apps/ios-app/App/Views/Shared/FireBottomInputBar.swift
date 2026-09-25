import InputBarAccessoryView
import UIKit

/// Mention suggestion returned by a host search.
struct FireBottomInputMention: Equatable {
    let handle: String
    let displayName: String
}

/// Payload the host sends after the user taps send.
struct FireBottomInputPayload: Equatable {
    let text: String
    let images: [UIImage]
}

/// Shared WeChat-style bottom composer built on InputBarAccessoryView.
///
/// The library owns wrapping, grow-to-max-lines, placeholder, image paste,
/// attachment strip, and @ autocomplete. Fire owns chrome, theme, and keyboard
/// pinning — this view is always a subview, never `inputAccessoryView`.
@MainActor
final class FireBottomInputBar: UIView {
    enum Kind {
        /// Left: advanced composer. Image paste still feeds the attachment strip.
        case topicQuickReply
        /// Left: photo picker. Images stage in the attachment strip until send.
        case chat
    }

    struct Callbacks {
        var onTextChanged: (String) -> Void = { _ in }
        var onSend: (FireBottomInputPayload) -> Void = { _ in }
        var onLeadingAction: () -> Void = {}
        var onFocusChanged: (Bool) -> Void = { _ in }
        var onHeightChanged: (CGFloat) -> Void = { _ in }
        var onSearchMentions: ((String) async -> [FireBottomInputMention])?
        var onPickImage: (() -> Void)?
    }

    var callbacks = Callbacks()

    var isInputFocused: Bool {
        inputBar.inputTextView.isFirstResponder
    }

    var currentText: String {
        inputBar.inputTextView.text ?? ""
    }

    var currentImages: [UIImage] {
        attachmentManager.attachments.compactMap { attachment in
            if case let .image(image) = attachment {
                return image
            }
            return nil
        }
    }

    /// Single-line capsule height (text insets + subheadline).
    static let minimumInputHeight: CGFloat = 36

    /// Caps grow at five lines, matching Android `maxLines=5`.
    static let maximumLineCount: CGFloat = 5

    static func maximumInputHeight(for font: UIFont = UIFont.preferredFont(forTextStyle: .subheadline)) -> CGFloat {
        ceil(font.lineHeight * maximumLineCount) + 16
    }

    static func estimatedWrappedHeight(
        text: String,
        width: CGFloat,
        font: UIFont = UIFont.preferredFont(forTextStyle: .subheadline)
    ) -> CGFloat {
        let textWidth = max(width - 36 - 36 - 16 - 24, 80)
        let minHeight = minimumInputHeight
        let maxHeight = maximumInputHeight(for: font)
        guard !text.isEmpty else { return minHeight }
        let bounds = (text as NSString).boundingRect(
            with: CGSize(width: textWidth, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: font],
            context: nil
        )
        return min(max(ceil(bounds.height) + 16, minHeight), maxHeight)
    }

    private let kind: Kind
    private let inputBar = InputBarAccessoryView()
    private let leadingButton = InputBarButtonItem()
    private let attachmentManager = AttachmentManager()
    private lazy var autocompleteManager = AutocompleteManager(for: inputBar.inputTextView)

    private var mentionCompletions: [AutocompleteCompletion] = []
    private var mentionSearchTask: Task<Void, Never>?
    private var applyingState = false
    private var isSending = false
    private var lastNotifiedHeight: CGFloat = 0

    init(kind: Kind) {
        self.kind = kind
        super.init(frame: .zero)
        setupView()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override var intrinsicContentSize: CGSize {
        inputBar.intrinsicContentSize
    }

    func apply(
        text: String,
        placeholder: String,
        isSending: Bool,
        isEnabled: Bool
    ) {
        applyingState = true
        defer { applyingState = false }

        self.isSending = isSending
        if inputBar.inputTextView.text != text {
            inputBar.inputTextView.text = text
        }
        inputBar.inputTextView.placeholder = placeholder
        inputBar.inputTextView.isEditable = isEnabled && !isSending
        leadingButton.isEnabled = isEnabled && !isSending
        inputBar.sendButton.isEnabled = shouldEnableSend(text: text)
        inputBar.inputTextViewDidChange()
        invalidateIntrinsicContentSize()
    }

    func focusInput() {
        inputBar.inputTextView.becomeFirstResponder()
    }

    func resignInputFocus() {
        inputBar.inputTextView.resignFirstResponder()
    }

    func insertImage(_ image: UIImage) {
        attachmentManager.handleInput(of: image)
        updateSendEnabled()
        notifyHeightIfNeeded()
    }

    func resetAfterSend() {
        inputBar.inputTextView.text = ""
        attachmentManager.invalidate()
        autocompleteManager.invalidate()
        mentionCompletions = []
        setPluginView(attachmentManager.attachmentView, active: false)
        setPluginView(autocompleteManager.tableView, active: false)
        inputBar.inputTextViewDidChange()
        invalidateIntrinsicContentSize()
        notifyHeightIfNeeded()
    }

    func applyThemeColorsIfNeeded() {
        let canvas = FireTheme.uiCanvas.resolvedColor(with: traitCollection)
        backgroundColor = canvas
        isOpaque = true
        inputBar.backgroundColor = canvas
        inputBar.backgroundView.backgroundColor = canvas
        inputBar.separatorLine.backgroundColor = FireTheme.uiDivider
        inputBar.inputTextView.backgroundColor = FireTheme.uiSurface
        inputBar.inputTextView.textColor = FireTheme.uiInk
        inputBar.inputTextView.tintColor = FireTheme.uiAccent
        inputBar.inputTextView.placeholderTextColor = FireTheme.uiTertiaryInk
        inputBar.sendButton.tintColor = FireTheme.uiAccent
        leadingButton.tintColor = FireTheme.uiSubtleInk
        autocompleteManager.tableView.backgroundColor = canvas
        autocompleteManager.defaultTextAttributes = typingAttributes()
    }

    // MARK: - Setup

    private func setupView() {
        translatesAutoresizingMaskIntoConstraints = false
        isOpaque = true
        clipsToBounds = true
        backgroundColor = FireTheme.uiCanvas

        configureInputBar()
        configureLeadingButton()
        configureSendButton()
        configureTextView()
        configureAttachmentManager()
        configureAutocompleteManager()

        addSubview(inputBar)
        inputBar.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            inputBar.leadingAnchor.constraint(equalTo: leadingAnchor),
            inputBar.trailingAnchor.constraint(equalTo: trailingAnchor),
            inputBar.topAnchor.constraint(equalTo: topAnchor),
            inputBar.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])

        applyThemeColorsIfNeeded()
        inputBar.inputTextViewDidChange()
    }

    private func configureInputBar() {
        // Never use this as UIViewController.inputAccessoryView or with
        // InputBarAccessoryView.KeyboardManager. Hosts pin the bar with Auto
        // Layout so topic-detail swipe-to-reply and Texture insets stay in sync.
        inputBar.delegate = self
        inputBar.isTranslucent = false
        inputBar.shouldAutoUpdateMaxTextViewHeight = false
        inputBar.maxTextViewHeight = Self.maximumInputHeight()
        inputBar.shouldManageSendButtonEnabledState = false
        inputBar.shouldAnimateTextDidChangeLayout = true
        inputBar.separatorLine.isHidden = kind == .topicQuickReply
        switch kind {
        case .topicQuickReply:
            // Outer topic chrome already pads the strip.
            inputBar.padding = .zero
        case .chat:
            inputBar.padding = UIEdgeInsets(top: 10, left: 10, bottom: 10, right: 10)
        }
        inputBar.middleContentViewPadding = UIEdgeInsets(top: 0, left: 8, bottom: 0, right: 8)
        inputBar.leftStackView.alignment = .bottom
        inputBar.rightStackView.alignment = .bottom
        inputBar.setLeftStackViewWidthConstant(to: 36, animated: false)
        inputBar.setRightStackViewWidthConstant(to: 36, animated: false)
        inputBar.setStackViewItems([leadingButton], forStack: .left, animated: false)
        inputBar.setStackViewItems([inputBar.sendButton], forStack: .right, animated: false)
    }

    private func configureLeadingButton() {
        let symbol: String
        let label: String
        switch kind {
        case .topicQuickReply:
            symbol = "square.and.pencil"
            label = "打开完整编辑器"
        case .chat:
            symbol = "plus.circle.fill"
            label = "发送图片"
        }
        leadingButton.image = UIImage(
            systemName: symbol,
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 22, weight: .medium)
        )
        leadingButton.setSize(CGSize(width: 36, height: 36), animated: false)
        leadingButton.tintColor = FireTheme.uiSubtleInk
        leadingButton.accessibilityLabel = label
        leadingButton.onTouchUpInside { [weak self] _ in
            self?.handleLeadingAction()
        }
        leadingButton.fireBindPressBounce(.compact)
    }

    private func configureSendButton() {
        let send = inputBar.sendButton
        send.setSize(CGSize(width: 36, height: 36), animated: false)
        send.title = nil
        send.setTitle(nil, for: .normal)
        send.image = UIImage(
            systemName: "arrow.up.circle.fill",
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 28, weight: .regular)
        )
        send.tintColor = FireTheme.uiAccent
        send.accessibilityLabel = "发送"
        send.onEnabled { $0.tintColor = FireTheme.uiAccent }
        send.onDisabled { $0.tintColor = FireTheme.uiTertiaryInk }
        send.fireBindPressBounce(.compact)
    }

    private func configureTextView() {
        let textView = inputBar.inputTextView
        textView.backgroundColor = FireTheme.uiSurface
        textView.layer.cornerRadius = 18
        textView.layer.cornerCurve = .continuous
        textView.clipsToBounds = true
        textView.font = UIFont.preferredFont(forTextStyle: .subheadline)
        textView.adjustsFontForContentSizeCategory = true
        textView.textColor = FireTheme.uiInk
        textView.tintColor = FireTheme.uiAccent
        textView.placeholder = kind == .chat ? "发消息…" : "快速回复…"
        textView.placeholderTextColor = FireTheme.uiTertiaryInk
        textView.textContainerInset = UIEdgeInsets(top: 8, left: 10, bottom: 8, right: 10)
        textView.textContainer.lineFragmentPadding = 0
        textView.returnKeyType = .default
        textView.keyboardType = .default
        textView.enablesReturnKeyAutomatically = false
        // Paste goes through AttachmentManager instead of NSTextAttachment in the body.
        textView.isImagePasteEnabled = false
        textView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(textViewBeganEditing),
            name: UITextView.textDidBeginEditingNotification,
            object: textView
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(textViewEndedEditing),
            name: UITextView.textDidEndEditingNotification,
            object: textView
        )
    }

    private func configureAttachmentManager() {
        attachmentManager.delegate = self
        attachmentManager.showAddAttachmentCell = kind == .topicQuickReply
        attachmentManager.isPersistent = false
        inputBar.inputPlugins.append(attachmentManager)
    }

    private func configureAutocompleteManager() {
        autocompleteManager.delegate = self
        autocompleteManager.dataSource = self
        autocompleteManager.appendSpaceOnCompletion = true
        autocompleteManager.keepPrefixOnCompletion = true
        autocompleteManager.filterBlock = { _, _ in true }
        autocompleteManager.defaultTextAttributes = typingAttributes()
        autocompleteManager.register(
            prefix: "@",
            with: [
                .font: UIFont.preferredFont(forTextStyle: .subheadline),
                .foregroundColor: FireTheme.uiAccent,
                .backgroundColor: FireTheme.uiAccent.withAlphaComponent(0.12),
            ]
        )
        autocompleteManager.tableView.rowHeight = 40
        autocompleteManager.tableView.separatorStyle = .none
        autocompleteManager.tableView.backgroundColor = FireTheme.uiCanvas
        inputBar.inputPlugins.append(autocompleteManager)
    }

    private func typingAttributes() -> [NSAttributedString.Key: Any] {
        [
            .font: UIFont.preferredFont(forTextStyle: .subheadline),
            .foregroundColor: FireTheme.uiInk,
        ]
    }

    // MARK: - Actions

    private func handleLeadingAction() {
        switch kind {
        case .topicQuickReply:
            callbacks.onLeadingAction()
        case .chat:
            if let onPickImage = callbacks.onPickImage {
                onPickImage()
            } else {
                callbacks.onLeadingAction()
            }
        }
    }

    private func updateSendEnabled() {
        inputBar.sendButton.isEnabled = shouldEnableSend(text: currentText)
    }

    private func shouldEnableSend(text: String) -> Bool {
        guard !isSending else { return false }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty || !currentImages.isEmpty
    }

    private func notifyHeightIfNeeded() {
        invalidateIntrinsicContentSize()
        inputBar.invalidateIntrinsicContentSize()
        let height = inputBar.intrinsicContentSize.height
        guard abs(height - lastNotifiedHeight) > 0.5 else { return }
        lastNotifiedHeight = height
        callbacks.onHeightChanged(height)
    }

    private func setPluginView(_ pluginView: UIView, active: Bool) {
        let stack = inputBar.topStackView
        let contains = stack.arrangedSubviews.contains(pluginView)
        if active, !contains {
            if pluginView === autocompleteManager.tableView {
                stack.insertArrangedSubview(pluginView, at: 0)
            } else {
                stack.addArrangedSubview(pluginView)
            }
        } else if !active, contains {
            stack.removeArrangedSubview(pluginView)
            pluginView.removeFromSuperview()
        }
        inputBar.invalidateIntrinsicContentSize()
        notifyHeightIfNeeded()
    }

    private func scheduleMentionSearch() {
        mentionSearchTask?.cancel()
        guard let session = autocompleteManager.currentSession, session.prefix == "@" else {
            mentionCompletions = []
            setPluginView(autocompleteManager.tableView, active: false)
            return
        }
        let term = session.filter.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !term.isEmpty, callbacks.onSearchMentions != nil else {
            mentionCompletions = []
            setPluginView(autocompleteManager.tableView, active: false)
            return
        }
        mentionSearchTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(200))
            guard let self, !Task.isCancelled else { return }
            let results = await self.callbacks.onSearchMentions?(term) ?? []
            guard !Task.isCancelled else { return }
            self.mentionCompletions = results.map { mention in
                AutocompleteCompletion(
                    text: mention.handle,
                    context: ["displayName": mention.displayName]
                )
            }
            self.autocompleteManager.tableView.reloadData()
            self.setPluginView(
                self.autocompleteManager.tableView,
                active: !self.mentionCompletions.isEmpty
            )
        }
    }

    @objc private func textViewBeganEditing() {
        callbacks.onFocusChanged(true)
    }

    @objc private func textViewEndedEditing() {
        callbacks.onFocusChanged(false)
    }

    deinit {
        mentionSearchTask?.cancel()
        NotificationCenter.default.removeObserver(self)
    }
}

// MARK: - InputBarAccessoryViewDelegate

extension FireBottomInputBar: InputBarAccessoryViewDelegate {
    func inputBar(_ inputBar: InputBarAccessoryView, didPressSendButtonWith text: String) {
        guard shouldEnableSend(text: text) else { return }
        callbacks.onSend(FireBottomInputPayload(text: text, images: currentImages))
    }

    func inputBar(_ inputBar: InputBarAccessoryView, textViewTextDidChangeTo text: String) {
        guard !applyingState else { return }
        inputBar.reloadPlugins()
        callbacks.onTextChanged(text)
        updateSendEnabled()
        scheduleMentionSearch()
        notifyHeightIfNeeded()
    }

    func inputBar(_ inputBar: InputBarAccessoryView, didChangeIntrinsicContentTo size: CGSize) {
        lastNotifiedHeight = size.height
        invalidateIntrinsicContentSize()
        callbacks.onHeightChanged(size.height)
    }
}

// MARK: - AttachmentManager

extension FireBottomInputBar: AttachmentManagerDelegate {
    func attachmentManager(_ manager: AttachmentManager, shouldBecomeVisible: Bool) {
        setPluginView(manager.attachmentView, active: shouldBecomeVisible)
        updateSendEnabled()
    }

    func attachmentManager(
        _ manager: AttachmentManager,
        didInsert attachment: AttachmentManager.Attachment,
        at index: Int
    ) {
        updateSendEnabled()
        notifyHeightIfNeeded()
    }

    func attachmentManager(
        _ manager: AttachmentManager,
        didRemove attachment: AttachmentManager.Attachment,
        at index: Int
    ) {
        updateSendEnabled()
        notifyHeightIfNeeded()
    }

    func attachmentManager(_ manager: AttachmentManager, didSelectAddAttachmentAt index: Int) {
        callbacks.onPickImage?()
    }
}

// MARK: - AutocompleteManager

extension FireBottomInputBar: AutocompleteManagerDelegate, AutocompleteManagerDataSource {
    func autocompleteManager(_ manager: AutocompleteManager, shouldBecomeVisible: Bool) {
        let visible = shouldBecomeVisible && !mentionCompletions.isEmpty
        setPluginView(manager.tableView, active: visible)
        if shouldBecomeVisible {
            scheduleMentionSearch()
        }
    }

    func autocompleteManager(
        _ manager: AutocompleteManager,
        autocompleteSourceFor prefix: String
    ) -> [AutocompleteCompletion] {
        prefix == "@" ? mentionCompletions : []
    }

    func autocompleteManager(
        _ manager: AutocompleteManager,
        tableView: UITableView,
        cellForRowAt indexPath: IndexPath,
        for session: AutocompleteSession
    ) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(
            withIdentifier: AutocompleteCell.reuseIdentifier,
            for: indexPath
        )
        let completion = mentionCompletions[indexPath.row]
        cell.textLabel?.text = "@\(completion.text)"
        cell.detailTextLabel?.text = completion.context?["displayName"] as? String
        cell.textLabel?.font = UIFont.preferredFont(forTextStyle: .subheadline)
        cell.textLabel?.textColor = FireTheme.uiInk
        cell.detailTextLabel?.textColor = FireTheme.uiSubtleInk
        cell.backgroundColor = .clear
        cell.contentView.backgroundColor = .clear
        return cell
    }
}

extension UIImage {
    func fireJPEGDataForUpload() -> Data? {
        jpegData(compressionQuality: 0.85)
    }
}
