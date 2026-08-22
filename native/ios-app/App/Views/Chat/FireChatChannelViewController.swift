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
        table.backgroundColor = FireTheme.uiCanvas
        table.contentInsetAdjustmentBehavior = .never
        table.register(FireChatMessageCell.self, forCellReuseIdentifier: FireChatMessageCell.reuseID)
        // Discord-style chronological stream (oldest → newest, newest near input).
        return table
    }()

    private lazy var pinBanner: UIButton = {
        let button = UIButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.backgroundColor = FireTheme.uiSurfaceSecondary
        button.contentHorizontalAlignment = .left
        button.titleLabel?.font = .preferredFont(forTextStyle: .footnote)
        var config = UIButton.Configuration.plain()
        config.contentInsets = NSDirectionalEdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12)
        config.baseForegroundColor = FireTheme.uiInk
        button.configuration = config
        button.addTarget(self, action: #selector(pinBannerTapped), for: .touchUpInside)
        button.isHidden = true
        return button
    }()

    /// WeChat-style opaque full-width bottom strip (mirrors topic quick-reply bar).
    private lazy var composerContainer: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.isOpaque = true
        view.backgroundColor = FireTheme.uiCanvas
        view.clipsToBounds = true
        return view
    }()

    private lazy var composerTopBorder: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.backgroundColor = FireTheme.uiDivider
        return view
    }()

    private lazy var fieldContainer: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.backgroundColor = FireTheme.uiSurface
        view.layer.cornerRadius = 18
        view.layer.cornerCurve = .continuous
        view.clipsToBounds = true
        return view
    }()

    private lazy var textView: UITextView = {
        let view = UITextView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.font = .preferredFont(forTextStyle: .subheadline)
        view.backgroundColor = .clear
        view.textColor = FireTheme.uiInk
        view.tintColor = FireTheme.uiAccent
        view.textContainerInset = UIEdgeInsets(top: 8, left: 8, bottom: 8, right: 8)
        view.textContainer.lineFragmentPadding = 0
        view.delegate = self
        view.isScrollEnabled = false
        return view
    }()

    private lazy var attachButton: UIButton = {
        let button = UIButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false
        var config = UIButton.Configuration.plain()
        config.image = UIImage(systemName: "plus.circle.fill")
        config.preferredSymbolConfigurationForImage = UIImage.SymbolConfiguration(pointSize: 24, weight: .regular)
        config.contentInsets = .zero
        button.configuration = config
        button.tintColor = FireTheme.uiSubtleInk
        button.accessibilityLabel = "发送图片"
        button.addTarget(self, action: #selector(attachTapped), for: .touchUpInside)
        return button
    }()

    private lazy var sendButton: UIButton = {
        let button = UIButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false
        var config = UIButton.Configuration.plain()
        config.image = UIImage(systemName: "arrow.up.circle.fill")
        config.preferredSymbolConfigurationForImage = UIImage.SymbolConfiguration(pointSize: 28, weight: .regular)
        config.contentInsets = .zero
        button.configuration = config
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

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        updateDismissButtonIfNeeded()
    }

    private func updateDismissButtonIfNeeded() {
        let isRootPresentedChat =
            navigationController?.presentingViewController != nil
            && navigationController?.viewControllers.count == 1
        if isRootPresentedChat {
            let dismissAction = UIAction { [weak self] _ in
                self?.navigationController?.dismiss(animated: true)
            }
            let dismissItem = UIBarButtonItem(
                title: "返回",
                image: UIImage(systemName: "chevron.backward"),
                primaryAction: dismissAction
            )
            dismissItem.accessibilityLabel = "返回"
            navigationItem.leftBarButtonItem = dismissItem
        } else {
            navigationItem.leftBarButtonItem = nil
        }
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
        composerContainer.addSubview(composerTopBorder)
        composerContainer.addSubview(attachButton)
        composerContainer.addSubview(fieldContainer)
        fieldContainer.addSubview(textView)
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

            composerTopBorder.topAnchor.constraint(equalTo: composerContainer.topAnchor),
            composerTopBorder.leadingAnchor.constraint(equalTo: composerContainer.leadingAnchor),
            composerTopBorder.trailingAnchor.constraint(equalTo: composerContainer.trailingAnchor),
            composerTopBorder.heightAnchor.constraint(equalToConstant: 1 / UIScreen.main.scale),

            // WeChat strip: [+]  (capsule field)  [↑]
            attachButton.leadingAnchor.constraint(equalTo: composerContainer.leadingAnchor, constant: 10),
            attachButton.centerYAnchor.constraint(equalTo: fieldContainer.centerYAnchor),
            attachButton.widthAnchor.constraint(equalToConstant: 32),
            attachButton.heightAnchor.constraint(equalToConstant: 32),

            fieldContainer.leadingAnchor.constraint(equalTo: attachButton.trailingAnchor, constant: 8),
            fieldContainer.topAnchor.constraint(equalTo: composerContainer.topAnchor, constant: 10),
            fieldContainer.bottomAnchor.constraint(equalTo: composerContainer.bottomAnchor, constant: -10),
            fieldContainer.trailingAnchor.constraint(equalTo: sendButton.leadingAnchor, constant: -8),

            textView.leadingAnchor.constraint(equalTo: fieldContainer.leadingAnchor, constant: 4),
            textView.trailingAnchor.constraint(equalTo: fieldContainer.trailingAnchor, constant: -4),
            textView.topAnchor.constraint(equalTo: fieldContainer.topAnchor),
            textView.bottomAnchor.constraint(equalTo: fieldContainer.bottomAnchor),
            height,

            sendButton.trailingAnchor.constraint(equalTo: composerContainer.trailingAnchor, constant: -10),
            sendButton.centerYAnchor.constraint(equalTo: fieldContainer.centerYAnchor),
            sendButton.widthAnchor.constraint(equalToConstant: 32),
            sendButton.heightAnchor.constraint(equalToConstant: 32),

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
            // Chronological ascending (Discord channel log).
            messages = page.messages.sorted { $0.id < $1.id }
            canLoadMorePast = page.canLoadMorePast
            tableView.reloadData()
            scrollToBottom(animated: false)
            if let latest = messages.last?.id, !isThread {
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
        guard canLoadMorePast, !isLoading, let oldest = messages.first else { return }
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
            let older = page.messages.sorted { $0.id < $1.id }
            let anchorID = oldest.id
            messages = older + messages
            canLoadMorePast = page.canLoadMorePast
            tableView.reloadData()
            // Keep visual position after prepending history.
            if let index = messages.firstIndex(where: { $0.id == anchorID }) {
                tableView.scrollToRow(
                    at: IndexPath(row: index, section: 0),
                    at: .top,
                    animated: false
                )
            }
        } catch {
            presentError(error)
        }
    }

    private func scrollToBottom(animated: Bool) {
        guard !messages.isEmpty else { return }
        let index = IndexPath(row: messages.count - 1, section: 0)
        tableView.scrollToRow(at: index, at: .bottom, animated: animated)
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
        let wasNearBottom = isNearBottom()
        messages.append(message)
        tableView.insertRows(at: [IndexPath(row: messages.count - 1, section: 0)], with: .fade)
        if wasNearBottom {
            scrollToBottom(animated: true)
        }
    }

    private func isNearBottom() -> Bool {
        guard !messages.isEmpty else { return true }
        let visible = tableView.indexPathsForVisibleRows ?? []
        guard let lastVisible = visible.map(\.row).max() else { return true }
        return lastVisible >= messages.count - 3
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
            messages = page.messages.sorted { $0.id < $1.id }
            canLoadMorePast = page.canLoadMorePast
            tableView.reloadData()
            scrollToBottom(animated: true)
            if let latest = messages.last?.id, !isThread {
                try? await viewModel.markChatChannelRead(channelID: channel.id, messageID: latest)
                onRead(channel.id)
            }
        } catch {
            // Keep bus path as primary; soft refresh failures are non-fatal.
        }
    }

    func textViewDidChange(_ textView: UITextView) {
        let fittingWidth = max(textView.bounds.width, 120)
        let size = textView.sizeThatFits(CGSize(width: fittingWidth, height: .greatestFiniteMagnitude))
        textViewHeightConstraint?.constant = min(max(size.height, 36), 120)
        textView.isScrollEnabled = size.height > 120
        view.layoutIfNeeded()
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
        let previous = indexPath.row > 0 ? messages[indexPath.row - 1] : nil
        let grouped = FireChatTime.shouldGroup(previous: previous, current: message)
        cell.configure(
            message: message,
            groupedWithPrevious: grouped,
            baseURLString: viewModel.bootstrapBaseURLString()
        )
        cell.onThreadTap = { [weak self] in
            guard let self else { return }
            Task { await self.openThread(for: message) }
        }
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
        // Load older history when scrolling toward the top of the channel log.
        if indexPath.row <= 2 {
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
            if let uploadID = upload.id, uploadID > 0 {
                await send(message: "", uploadIDs: [uploadID])
            } else {
                let alt = upload.originalFilename?.isEmpty == false
                    ? upload.originalFilename!
                    : "image"
                await send(message: "![\(alt)](\(upload.shortUrl))", uploadIDs: [])
            }
        } catch {
            presentError(error)
        }
    }
}
