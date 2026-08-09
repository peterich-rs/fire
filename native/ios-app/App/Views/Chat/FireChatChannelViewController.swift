import PhotosUI
import UIKit
import UniformTypeIdentifiers

@MainActor
final class FireChatChannelViewController: UIViewController, UITableViewDataSource, UITableViewDelegate, UITextViewDelegate {
    private let viewModel: FireAppViewModel
    private let onRead: (UInt64) -> Void
    private let ownerToken: String
    private var channel: ChatChannelState
    private let threadID: UInt64?
    private var messages: [ChatMessageState] = []
    private var pins: [ChatMessageState] = []
    private var canLoadMorePast = false
    private var isLoading = false
    private var isSending = false
    private var busObserver: NSObjectProtocol?

    private lazy var tableView: UITableView = {
        let table = UITableView(frame: .zero, style: .plain)
        table.translatesAutoresizingMaskIntoConstraints = false
        table.dataSource = self
        table.delegate = self
        table.separatorStyle = .none
        table.keyboardDismissMode = .interactive
        table.register(FireChatMessageCell.self, forCellReuseIdentifier: FireChatMessageCell.reuseID)
        table.transform = CGAffineTransform(scaleX: 1, y: -1)
        return table
    }()

    private lazy var pinBanner: UIButton = {
        let button = UIButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.backgroundColor = FireTheme.uiSurfaceSecondary
        button.contentHorizontalAlignment = .left
        button.titleLabel?.font = .preferredFont(forTextStyle: .footnote)
        button.contentEdgeInsets = UIEdgeInsets(top: 8, left: 12, bottom: 8, right: 12)
        button.addTarget(self, action: #selector(pinBannerTapped), for: .touchUpInside)
        button.isHidden = true
        return button
    }()

    private lazy var composerContainer: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.backgroundColor = FireTheme.uiSurface
        return view
    }()

    private lazy var textView: UITextView = {
        let view = UITextView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.font = .preferredFont(forTextStyle: .body)
        view.layer.cornerRadius = FireTheme.smallCornerRadius
        view.backgroundColor = FireTheme.uiSurfaceSecondary
        view.textContainerInset = UIEdgeInsets(top: 8, left: 8, bottom: 8, right: 8)
        view.delegate = self
        view.isScrollEnabled = false
        return view
    }()

    private lazy var attachButton: UIButton = {
        let button = UIButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.setImage(UIImage(systemName: "photo"), for: .normal)
        button.accessibilityLabel = "发送图片"
        button.addTarget(self, action: #selector(attachTapped), for: .touchUpInside)
        return button
    }()

    private lazy var sendButton: UIButton = {
        let button = UIButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.setImage(UIImage(systemName: "arrow.up.circle.fill"), for: .normal)
        button.tintColor = FireTheme.uiAccent
        button.addTarget(self, action: #selector(sendTapped), for: .touchUpInside)
        button.accessibilityLabel = "发送"
        return button
    }()

    private var textViewHeightConstraint: NSLayoutConstraint?
    private var composerBottomConstraint: NSLayoutConstraint?
    private let isThread: Bool

    init(
        channel: ChatChannelState,
        viewModel: FireAppViewModel,
        threadID: UInt64? = nil,
        onRead: @escaping (UInt64) -> Void
    ) {
        self.channel = channel
        self.viewModel = viewModel
        self.threadID = threadID
        self.isThread = threadID != nil
        self.onRead = onRead
        self.ownerToken = "chat-channel-\(channel.id)-\(threadID.map(String.init) ?? "main")"
        super.init(nibName: nil, bundle: nil)
        title = isThread ? "消息串" : channel.displayTitle
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = FireTheme.uiCanvas
        setupLayout()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(keyboardWillChange(_:)),
            name: UIResponder.keyboardWillChangeFrameNotification,
            object: nil
        )
        busObserver = NotificationCenter.default.addObserver(
            forName: .fireChatMessageBusEvent,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let event = notification.userInfo?["event"] as? MessageBusEventState else { return }
            Task { @MainActor in
                self?.handleBusEvent(event)
            }
        }
        Task { await loadInitial() }
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
        if let busObserver {
            NotificationCenter.default.removeObserver(busObserver)
        }
        let viewModel = viewModel
        let ownerToken = ownerToken
        let channelID = channel.id
        let threadID = threadID
        Task {
            let channelName = threadID.map { "/chat/\(channelID)/thread/\($0)" } ?? "/chat/\(channelID)"
            try? await viewModel.unsubscribeMessageBusChannel(channel: channelName, ownerToken: ownerToken)
        }
    }

    private func setupLayout() {
        view.addSubview(pinBanner)
        view.addSubview(tableView)
        view.addSubview(composerContainer)
        composerContainer.addSubview(attachButton)
        composerContainer.addSubview(textView)
        composerContainer.addSubview(sendButton)

        let height = textView.heightAnchor.constraint(equalToConstant: 36)
        textViewHeightConstraint = height
        let bottom = composerContainer.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor)
        composerBottomConstraint = bottom

        NSLayoutConstraint.activate([
            pinBanner.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            pinBanner.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            pinBanner.trailingAnchor.constraint(equalTo: view.trailingAnchor),

            composerContainer.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            composerContainer.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            bottom,

            attachButton.leadingAnchor.constraint(equalTo: composerContainer.leadingAnchor, constant: 8),
            attachButton.centerYAnchor.constraint(equalTo: textView.centerYAnchor),
            attachButton.widthAnchor.constraint(equalToConstant: 32),
            attachButton.heightAnchor.constraint(equalToConstant: 32),

            textView.leadingAnchor.constraint(equalTo: attachButton.trailingAnchor, constant: 4),
            textView.topAnchor.constraint(equalTo: composerContainer.topAnchor, constant: 8),
            textView.bottomAnchor.constraint(equalTo: composerContainer.bottomAnchor, constant: -8),
            textView.trailingAnchor.constraint(equalTo: sendButton.leadingAnchor, constant: -8),
            height,

            sendButton.trailingAnchor.constraint(equalTo: composerContainer.trailingAnchor, constant: -12),
            sendButton.centerYAnchor.constraint(equalTo: textView.centerYAnchor),
            sendButton.widthAnchor.constraint(equalToConstant: 36),
            sendButton.heightAnchor.constraint(equalToConstant: 36),

            tableView.topAnchor.constraint(equalTo: pinBanner.bottomAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: composerContainer.topAnchor),
        ])
    }

    private func loadInitial() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            if !isThread {
                channel = try await viewModel.fetchChatChannel(channelID: channel.id)
                title = channel.displayTitle
                pins = try await viewModel.fetchChatChannelPins(channelID: channel.id)
                updatePinBanner()
                if !pins.isEmpty {
                    try? await viewModel.markChatChannelPinsRead(channelID: channel.id)
                }
            }
            let query = ChatMessagesQueryState(
                channelId: channel.id,
                direction: nil,
                targetMessageId: nil,
                fetchFromLastRead: true,
                pageSize: 50
            )
            let page: ChatMessagesState
            if let threadID {
                page = try await viewModel.fetchChatThreadMessages(
                    channelID: channel.id,
                    threadID: threadID,
                    query: query
                )
                try? await viewModel.markChatThreadRead(channelID: channel.id, threadID: threadID)
            } else {
                page = try await viewModel.fetchChatMessages(query: query)
            }
            messages = page.messages.reversed()
            canLoadMorePast = page.canLoadMorePast
            tableView.reloadData()
            if let latest = page.messages.last?.id, !isThread {
                try? await viewModel.markChatChannelRead(channelID: channel.id, messageID: latest)
                onRead(channel.id)
            }
            let busName = threadID.map { "/chat/\(channel.id)/thread/\($0)" } ?? "/chat/\(channel.id)"
            let lastID = isThread ? nil : channel.busLastIds.channelMessageBusLastId
            try? await viewModel.subscribeMessageBusChannel(
                channel: busName,
                ownerToken: ownerToken,
                lastMessageId: lastID
            )
        } catch {
            presentError(error)
        }
    }

    private func loadMorePast() async {
        guard canLoadMorePast, !isLoading, let oldest = messages.last else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let query = ChatMessagesQueryState(
                channelId: channel.id,
                direction: "past",
                targetMessageId: oldest.id,
                fetchFromLastRead: false,
                pageSize: 50
            )
            let page: ChatMessagesState
            if let threadID {
                page = try await viewModel.fetchChatThreadMessages(
                    channelID: channel.id,
                    threadID: threadID,
                    query: query
                )
            } else {
                page = try await viewModel.fetchChatMessages(query: query)
            }
            messages.append(contentsOf: page.messages.reversed())
            canLoadMorePast = page.canLoadMorePast
            tableView.reloadData()
        } catch {
            presentError(error)
        }
    }

    private func handleBusEvent(_ event: MessageBusEventState) {
        let expected = threadID.map { "/chat/\(channel.id)/thread/\($0)" } ?? "/chat/\(channel.id)"
        guard event.channel == expected else { return }
        let type = event.detailEventType ?? event.messageType
        switch type {
        case "sent":
            if let message = FireChatBusPayload.chatMessage(from: event, fallbackChannelID: channel.id) {
                upsertMessage(message, preferAppend: true)
            }
        case "edit", "processed", "refresh", "restore", "thread_created", "update_thread_original_message":
            if let message = FireChatBusPayload.chatMessage(from: event, fallbackChannelID: channel.id) {
                upsertMessage(message, preferAppend: false)
            }
        case "delete":
            if let object = FireChatBusPayload.jsonObject(from: event),
               let deletedID = (object["deleted_id"] as? NSNumber)?.uint64Value
                ?? object["deleted_id"] as? UInt64,
               let index = messages.firstIndex(where: { $0.id == deletedID })
            {
                messages.remove(at: index)
                tableView.reloadData()
            }
        case "reaction":
            applyReaction(event)
        case "pin":
            if let message = FireChatBusPayload.chatMessage(from: event, fallbackChannelID: channel.id) {
                pins = [message] + pins.filter { $0.id != message.id }
                updatePinBanner()
            }
        case "unpin":
            if let message = FireChatBusPayload.chatMessage(from: event, fallbackChannelID: channel.id) {
                pins.removeAll { $0.id == message.id }
                updatePinBanner()
            }
        default:
            break
        }
    }

    private func applyReaction(_ event: MessageBusEventState) {
        guard let object = FireChatBusPayload.jsonObject(from: event),
              let messageID = (object["chat_message_id"] as? NSNumber)?.uint64Value
                ?? object["chat_message_id"] as? UInt64,
              let emoji = object["emoji"] as? String,
              let action = object["action"] as? String,
              let index = messages.firstIndex(where: { $0.id == messageID })
        else {
            return
        }
        var message = messages[index]
        var reactions = message.reactions
        if let existing = reactions.firstIndex(where: { $0.emoji == emoji }) {
            let current = reactions[existing]
            let nextCount: UInt32
            let reacted: Bool
            if action == "add" {
                nextCount = current.count &+ 1
                reacted = current.reacted || (object["user"] as? [String: Any]).flatMap { ($0["id"] as? NSNumber)?.uint64Value } == viewModel.currentUserID
            } else {
                nextCount = current.count > 0 ? current.count - 1 : 0
                reacted = false
            }
            if nextCount == 0 {
                reactions.remove(at: existing)
            } else {
                reactions[existing] = ChatMessageReactionState(
                    emoji: emoji,
                    count: nextCount,
                    reacted: reacted,
                    users: current.users
                )
            }
        } else if action == "add" {
            reactions.append(
                ChatMessageReactionState(emoji: emoji, count: 1, reacted: true, users: [])
            )
        }
        message = withReactions(message, reactions)
        messages[index] = message
        tableView.reloadRows(at: [IndexPath(row: index, section: 0)], with: .none)
    }

    private func upsertMessage(_ message: ChatMessageState, preferAppend: Bool) {
        if let index = messages.firstIndex(where: { $0.id == message.id }) {
            messages[index] = message
            tableView.reloadRows(at: [IndexPath(row: index, section: 0)], with: .none)
            return
        }
        guard preferAppend else { return }
        messages.insert(message, at: 0)
        tableView.insertRows(at: [IndexPath(row: 0, section: 0)], with: .fade)
    }

    private func updatePinBanner() {
        guard !isThread, let pin = pins.first else {
            pinBanner.isHidden = true
            return
        }
        pinBanner.isHidden = false
        let text = pin.previewText.isEmpty ? "置顶消息" : "置顶：\(pin.previewText)"
        pinBanner.setTitle(text, for: .normal)
    }

    @objc private func pinBannerTapped() {
        guard let pin = pins.first else { return }
        if let index = messages.firstIndex(where: { $0.id == pin.id }) {
            tableView.scrollToRow(at: IndexPath(row: index, section: 0), at: .middle, animated: true)
        }
    }

    @objc private func sendTapped() {
        let text = textView.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isSending else { return }
        Task { await send(message: text, uploadIDs: []) }
    }

    @objc private func attachTapped() {
        var configuration = PHPickerConfiguration(photoLibrary: .shared())
        configuration.filter = .images
        configuration.selectionLimit = 1
        let picker = PHPickerViewController(configuration: configuration)
        picker.delegate = self
        present(picker, animated: true)
    }

    private func send(message: String, uploadIDs: [UInt64]) async {
        isSending = true
        sendButton.isEnabled = false
        defer {
            isSending = false
            sendButton.isEnabled = true
        }
        do {
            _ = try await viewModel.sendChatMessage(
                request: SendChatMessageRequestState(
                    channelId: channel.id,
                    message: message,
                    stagedId: UUID().uuidString,
                    inReplyToId: nil,
                    threadId: threadID,
                    uploadIds: uploadIDs
                )
            )
            if message == textView.text.trimmingCharacters(in: .whitespacesAndNewlines) {
                textView.text = ""
                textViewDidChange(textView)
            }
            // Bus will deliver the authoritative message; also soft refresh for reliability.
            await softRefreshLatest()
        } catch {
            presentError(error)
        }
    }

    private func softRefreshLatest() async {
        do {
            let query = ChatMessagesQueryState(
                channelId: channel.id,
                direction: nil,
                targetMessageId: nil,
                fetchFromLastRead: false,
                pageSize: 50
            )
            let page: ChatMessagesState
            if let threadID {
                page = try await viewModel.fetchChatThreadMessages(
                    channelID: channel.id,
                    threadID: threadID,
                    query: query
                )
            } else {
                page = try await viewModel.fetchChatMessages(query: query)
            }
            messages = page.messages.reversed()
            canLoadMorePast = page.canLoadMorePast
            tableView.reloadData()
            if let latest = page.messages.last?.id, !isThread {
                try? await viewModel.markChatChannelRead(channelID: channel.id, messageID: latest)
                onRead(channel.id)
            }
        } catch {
            // Keep bus path as primary; soft refresh failures are non-fatal.
        }
    }

    func textViewDidChange(_ textView: UITextView) {
        let size = textView.sizeThatFits(CGSize(width: textView.bounds.width, height: .greatestFiniteMagnitude))
        textViewHeightConstraint?.constant = min(max(size.height, 36), 120)
        textView.isScrollEnabled = size.height > 120
    }

    @objc private func keyboardWillChange(_ notification: Notification) {
        guard
            let frame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect,
            let duration = notification.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? Double
        else {
            return
        }
        let converted = view.convert(frame, from: nil)
        let overlap = max(0, view.bounds.maxY - converted.minY - view.safeAreaInsets.bottom)
        composerBottomConstraint?.constant = -overlap
        UIView.animate(withDuration: duration) {
            self.view.layoutIfNeeded()
        }
    }

    private func presentError(_ error: Error) {
        let alert = UIAlertController(
            title: "操作失败",
            message: error.localizedDescription,
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "好", style: .default))
        present(alert, animated: true)
    }

    private func presentMessageActions(for message: ChatMessageState) {
        let sheet = UIAlertController(title: nil, message: nil, preferredStyle: .actionSheet)
        for emoji in ["heart", "tada", "laughing", "+1", "eyes"] {
            let title = message.reactions.first(where: { $0.emoji == emoji })?.reacted == true
                ? "取消 :\(emoji):"
                : ":\(emoji):"
            sheet.addAction(UIAlertAction(title: title, style: .default) { [weak self] _ in
                Task { await self?.toggleReaction(message: message, emoji: emoji) }
            })
        }
        if channel.threadingEnabled, !isThread {
            sheet.addAction(UIAlertAction(title: "打开消息串", style: .default) { [weak self] _ in
                Task { await self?.openThread(for: message) }
            })
        }
        if channel.canManagePins || channel.canModerate {
            if message.pinned {
                sheet.addAction(UIAlertAction(title: "取消置顶", style: .default) { [weak self] _ in
                    Task {
                        try? await self?.viewModel.unpinChatMessage(
                            channelID: message.channelId,
                            messageID: message.id
                        )
                    }
                })
            } else {
                sheet.addAction(UIAlertAction(title: "置顶", style: .default) { [weak self] _ in
                    Task {
                        try? await self?.viewModel.pinChatMessage(
                            channelID: message.channelId,
                            messageID: message.id
                        )
                    }
                })
            }
        }
        if message.user?.id == viewModel.currentUserID || channel.canDeleteOthers || channel.canDeleteSelf {
            sheet.addAction(UIAlertAction(title: "删除", style: .destructive) { [weak self] _ in
                Task {
                    try? await self?.viewModel.deleteChatMessage(
                        channelID: message.channelId,
                        messageID: message.id
                    )
                }
            })
        }
        sheet.addAction(UIAlertAction(title: "取消", style: .cancel))
        if let popover = sheet.popoverPresentationController {
            popover.sourceView = view
            popover.sourceRect = CGRect(x: view.bounds.midX, y: view.bounds.midY, width: 1, height: 1)
        }
        present(sheet, animated: true)
    }

    private func toggleReaction(message: ChatMessageState, emoji: String) async {
        let reacted = message.reactions.first(where: { $0.emoji == emoji })?.reacted == true
        do {
            try await viewModel.reactChatMessage(
                channelID: message.channelId,
                messageID: message.id,
                emoji: emoji,
                reactAction: reacted ? "remove" : "add"
            )
        } catch {
            presentError(error)
        }
    }

    private func openThread(for message: ChatMessageState) async {
        do {
            let threadID: UInt64
            if let existing = message.threadId ?? message.thread?.id {
                threadID = existing
            } else {
                threadID = try await viewModel.createChatThread(
                    channelID: channel.id,
                    originalMessageID: message.id
                )
            }
            let controller = FireChatChannelViewController(
                channel: channel,
                viewModel: viewModel,
                threadID: threadID,
                onRead: onRead
            )
            navigationController?.pushViewController(controller, animated: true)
        } catch {
            presentError(error)
        }
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        messages.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(
            withIdentifier: FireChatMessageCell.reuseID,
            for: indexPath
        ) as! FireChatMessageCell
        let message = messages[indexPath.row]
        cell.configure(message: message)
        cell.transform = CGAffineTransform(scaleX: 1, y: -1)
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        presentMessageActions(for: messages[indexPath.row])
    }

    func tableView(
        _ tableView: UITableView,
        willDisplay cell: UITableViewCell,
        forRowAt indexPath: IndexPath
    ) {
        if indexPath.row >= messages.count - 3 {
            Task { await loadMorePast() }
        }
    }

    private func withReactions(
        _ message: ChatMessageState,
        _ reactions: [ChatMessageReactionState]
    ) -> ChatMessageState {
        ChatMessageState(
            id: message.id,
            channelId: message.channelId,
            message: message.message,
            cooked: message.cooked,
            excerpt: message.excerpt,
            previewText: message.previewText,
            createdAt: message.createdAt,
            deletedAt: message.deletedAt,
            deletedById: message.deletedById,
            edited: message.edited,
            threadId: message.threadId,
            thread: message.thread,
            user: message.user,
            mentionedUsers: message.mentionedUsers,
            reactions: reactions,
            uploads: message.uploads,
            inReplyTo: message.inReplyTo,
            streaming: message.streaming,
            availableFlags: message.availableFlags,
            userFlagStatus: message.userFlagStatus,
            bookmark: message.bookmark,
            pinned: message.pinned,
            isDeleted: message.isDeleted
        )
    }
}

extension FireChatChannelViewController: PHPickerViewControllerDelegate {
    func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
        picker.dismiss(animated: true)
        guard let result = results.first else { return }
        let provider = result.itemProvider
        guard provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) else { return }
        provider.loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) { [weak self] data, error in
            guard let self, let data, error == nil else { return }
            Task { @MainActor in
                await self.uploadAndSendImage(data)
            }
        }
    }

    private func uploadAndSendImage(_ data: Data) async {
        do {
            let upload = try await viewModel.uploadImage(
                fileName: "chat-\(UUID().uuidString).jpg",
                mimeType: "image/jpeg",
                bytes: data
            )
            await send(message: "", uploadIDs: [upload.id])
        } catch {
            presentError(error)
        }
    }
}

private final class FireChatMessageCell: UITableViewCell {
    static let reuseID = "FireChatMessageCell"

    private let bubble = UIView()
    private let authorLabel = UILabel()
    private let bodyLabel = UILabel()
    private let metaLabel = UILabel()
    private let threadLabel = UILabel()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        selectionStyle = .none
        backgroundColor = .clear
        contentView.backgroundColor = .clear

        bubble.translatesAutoresizingMaskIntoConstraints = false
        bubble.backgroundColor = FireTheme.uiSurface
        bubble.layer.cornerRadius = FireTheme.mediumCornerRadius

        authorLabel.translatesAutoresizingMaskIntoConstraints = false
        authorLabel.font = .preferredFont(forTextStyle: .caption1)
        authorLabel.textColor = FireTheme.uiAccent

        bodyLabel.translatesAutoresizingMaskIntoConstraints = false
        bodyLabel.font = .preferredFont(forTextStyle: .body)
        bodyLabel.numberOfLines = 0

        metaLabel.translatesAutoresizingMaskIntoConstraints = false
        metaLabel.font = .preferredFont(forTextStyle: .caption2)
        metaLabel.textColor = .tertiaryLabel

        threadLabel.translatesAutoresizingMaskIntoConstraints = false
        threadLabel.font = .preferredFont(forTextStyle: .caption1)
        threadLabel.textColor = FireTheme.uiAccent

        contentView.addSubview(bubble)
        bubble.addSubview(authorLabel)
        bubble.addSubview(bodyLabel)
        bubble.addSubview(metaLabel)
        bubble.addSubview(threadLabel)

        NSLayoutConstraint.activate([
            bubble.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 6),
            bubble.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 12),
            bubble.trailingAnchor.constraint(lessThanOrEqualTo: contentView.trailingAnchor, constant: -48),
            bubble.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -6),

            authorLabel.topAnchor.constraint(equalTo: bubble.topAnchor, constant: 8),
            authorLabel.leadingAnchor.constraint(equalTo: bubble.leadingAnchor, constant: 12),
            authorLabel.trailingAnchor.constraint(equalTo: bubble.trailingAnchor, constant: -12),

            bodyLabel.topAnchor.constraint(equalTo: authorLabel.bottomAnchor, constant: 4),
            bodyLabel.leadingAnchor.constraint(equalTo: authorLabel.leadingAnchor),
            bodyLabel.trailingAnchor.constraint(equalTo: authorLabel.trailingAnchor),

            metaLabel.topAnchor.constraint(equalTo: bodyLabel.bottomAnchor, constant: 4),
            metaLabel.leadingAnchor.constraint(equalTo: authorLabel.leadingAnchor),
            metaLabel.trailingAnchor.constraint(equalTo: authorLabel.trailingAnchor),

            threadLabel.topAnchor.constraint(equalTo: metaLabel.bottomAnchor, constant: 4),
            threadLabel.leadingAnchor.constraint(equalTo: authorLabel.leadingAnchor),
            threadLabel.trailingAnchor.constraint(equalTo: authorLabel.trailingAnchor),
            threadLabel.bottomAnchor.constraint(equalTo: bubble.bottomAnchor, constant: -8),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    func configure(message: ChatMessageState) {
        if message.isDeleted {
            authorLabel.text = message.user?.username ?? "用户"
            bodyLabel.text = "消息已删除"
            bodyLabel.textColor = .secondaryLabel
        } else {
            authorLabel.text = message.user?.username ?? "用户"
            if message.message.isEmpty, !message.uploads.isEmpty {
                bodyLabel.text = "[图片/附件]"
            } else {
                bodyLabel.text = message.message.isEmpty ? message.previewText : message.message
            }
            bodyLabel.textColor = .label
        }
        var meta: [String] = []
        if let created = message.createdAt, let date = FireChatTime.parse(created) {
            let formatter = DateFormatter()
            formatter.dateStyle = .none
            formatter.timeStyle = .short
            meta.append(formatter.string(from: date))
        }
        if message.edited { meta.append("已编辑") }
        if message.pinned { meta.append("置顶") }
        if !message.reactions.isEmpty {
            meta.append(message.reactions.map { ":\($0.emoji): \($0.count)" }.joined(separator: " "))
        }
        metaLabel.text = meta.joined(separator: " · ")
        if let replyCount = message.thread?.replyCount, replyCount > 0 {
            threadLabel.text = "\(replyCount) 条回复"
            threadLabel.isHidden = false
        } else {
            threadLabel.text = nil
            threadLabel.isHidden = true
        }
    }
}
