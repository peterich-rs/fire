import Foundation

struct FireChatPendingUpload {
    let fileName: String
    let mimeType: String
    let bytes: Data
}

@MainActor
final class FireChatChannelSession {
    struct Snapshot {
        let channel: ChatChannelState
        let messages: [ChatMessageState]
        let pins: [ChatMessageState]
        let canLoadMorePast: Bool
    }

    enum Change {
        case cached
        case initial
        case older(anchorMessageID: UInt64)
        case latest
        case messageInserted
        case messageUpdated(index: Int)
        case messageDeleted(index: Int)
        case pins
    }

    enum Command {
        case loadMorePast
        case send(message: String, uploads: [FireChatPendingUpload])
        case toggleReaction(messageID: UInt64, emoji: String)
        case setPinned(messageID: UInt64, pinned: Bool)
        case deleteMessage(messageID: UInt64)
        case resolveThread(messageID: UInt64)
    }

    enum CommandResult {
        case none
        case threadID(UInt64)
    }

    var onChange: ((Snapshot, Change) -> Void)?
    var onRead: ((UInt64) -> Void)?
    var onError: ((Error) -> Void)?

    private let viewModel: FireAppViewModel
    private let threadID: UInt64?
    private let ownerToken: String
    private var channel: ChatChannelState
    private var messages: [ChatMessageState] = []
    private var pins: [ChatMessageState] = []
    private var canLoadMorePast = false
    private var isLoading = false
    private var isSending = false
    private var lifecycleGeneration: UInt64 = 0
    private var isOpen = false
    private var busObserver: NSObjectProtocol?

    init(
        channel: ChatChannelState,
        viewModel: FireAppViewModel,
        threadID: UInt64?
    ) {
        self.channel = channel
        self.viewModel = viewModel
        self.threadID = threadID
        ownerToken = "chat-channel-\(channel.id)-\(threadID.map(String.init) ?? "main")"
    }

    func open() async {
        guard !isOpen else { return }
        isOpen = true
        lifecycleGeneration &+= 1
        let generation = lifecycleGeneration
        observeMessageBus()
        await applyCachedMessages(generation: generation)
        await loadInitial(generation: generation)
    }

    func close() {
        guard isOpen || busObserver != nil else { return }
        isOpen = false
        lifecycleGeneration &+= 1
        if let busObserver {
            NotificationCenter.default.removeObserver(busObserver)
            self.busObserver = nil
        }
        let channelName = messageBusChannelName
        Task { [viewModel, ownerToken] in
            try? await viewModel.unsubscribeMessageBusChannel(
                channel: channelName,
                ownerToken: ownerToken
            )
        }
        let channelID = channel.id
        let threadID = threadID
        Task { [viewModel] in
            try? await viewModel.sessionStore?.closeChatChannelRuntime(
                channelId: channelID,
                threadId: threadID
            )
        }
    }

    func command(_ command: Command) async throws -> CommandResult {
        switch command {
        case .loadMorePast:
            try await loadMorePast()
            return .none
        case let .send(message, uploads):
            try await send(message: message, uploads: uploads)
            return .none
        case let .toggleReaction(messageID, emoji):
            try await toggleReaction(messageID: messageID, emoji: emoji)
            return .none
        case let .setPinned(messageID, pinned):
            if pinned {
                try await viewModel.pinChatMessage(channelID: channel.id, messageID: messageID)
            } else {
                try await viewModel.unpinChatMessage(channelID: channel.id, messageID: messageID)
            }
            return .none
        case let .deleteMessage(messageID):
            try await viewModel.deleteChatMessage(channelID: channel.id, messageID: messageID)
            return .none
        case let .resolveThread(messageID):
            guard let message = messages.first(where: { $0.id == messageID }) else {
                throw FireChatChannelSessionError.messageNotFound
            }
            if let existing = message.threadId ?? message.thread?.id {
                return .threadID(existing)
            }
            let created = try await viewModel.createChatThread(
                channelID: channel.id,
                originalMessageID: message.id
            )
            return .threadID(created)
        }
    }

    func searchMentions(term: String) async -> [FireBottomInputMention] {
        do {
            let result = try await viewModel.searchService.searchUsers(
                term: term,
                includeGroups: true,
                limit: 8
            )
            let users = result.users.map { user in
                FireBottomInputMention(
                    handle: user.username,
                    displayName: user.name?.trimmingCharacters(in: .whitespacesAndNewlines)
                        ?? user.username
                )
            }
            let groups = result.groups.map { group in
                FireBottomInputMention(
                    handle: group.name,
                    displayName: group.fullName?.trimmingCharacters(in: .whitespacesAndNewlines)
                        ?? group.name
                )
            }
            return users + groups
        } catch {
            return []
        }
    }

    private var messageBusChannelName: String {
        threadID.map { "/chat/\(channel.id)/thread/\($0)" } ?? "/chat/\(channel.id)"
    }

    private func observeMessageBus() {
        guard busObserver == nil else { return }
        busObserver = NotificationCenter.default.addObserver(
            forName: .fireChatMessageBusEvent,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let event = notification.userInfo?["event"] as? MessageBusEventState else { return }
            Task { @MainActor [weak self] in
                await self?.handleBusEvent(event)
            }
        }
    }

    private func applyCachedMessages(generation: UInt64) async {
        guard let cached = try? await viewModel.cachedChatMessages(
            channelID: channel.id,
            threadID: threadID
        ), generation == lifecycleGeneration, isOpen, !cached.messages.isEmpty else {
            return
        }
        await adoptRuntime(preferred: .cached)
    }

    private func loadInitial(generation: UInt64) async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            if threadID == nil {
                let fetchedChannel = try await viewModel.fetchChatChannel(channelID: channel.id)
                guard generation == lifecycleGeneration, isOpen else { return }
                channel = fetchedChannel
                pins = try await viewModel.fetchChatChannelPins(channelID: channel.id)
                guard generation == lifecycleGeneration, isOpen else { return }
                if !pins.isEmpty {
                    try? await viewModel.markChatChannelPinsRead(channelID: channel.id)
                }
            }

            _ = try await fetchMessages(fetchFromLastRead: true)
            guard generation == lifecycleGeneration, isOpen else { return }
            await adoptRuntime(preferred: .initial)
            await markReadIfNeeded()
            guard generation == lifecycleGeneration, isOpen else { return }
            try? await viewModel.subscribeMessageBusChannel(
                channel: messageBusChannelName,
                ownerToken: ownerToken,
                lastMessageId: threadID == nil ? channel.busLastIds.channelMessageBusLastId : nil
            )
            guard generation == lifecycleGeneration, isOpen else {
                try? await viewModel.unsubscribeMessageBusChannel(
                    channel: messageBusChannelName,
                    ownerToken: ownerToken
                )
                return
            }
        } catch {
            guard generation == lifecycleGeneration, isOpen else { return }
            onError?(error)
        }
    }

    private func loadMorePast() async throws {
        guard canLoadMorePast, !isLoading, let oldest = messages.first else { return }
        isLoading = true
        defer { isLoading = false }
        let query = ChatMessagesQueryState(
            channelId: channel.id,
            direction: "past",
            targetMessageId: oldest.id,
            fetchFromLastRead: false,
            pageSize: 50
        )
        _ = try await fetchMessages(query: query)
        await adoptRuntime(preferred: .older(anchorMessageID: oldest.id))
    }

    private func refreshLatest() async throws {
        _ = try await fetchMessages(fetchFromLastRead: false)
        await adoptRuntime(preferred: .latest)
        await markReadIfNeeded()
    }

    private func fetchMessages(fetchFromLastRead: Bool) async throws -> ChatMessagesState {
        let query = ChatMessagesQueryState(
            channelId: channel.id,
            direction: nil,
            targetMessageId: nil,
            fetchFromLastRead: fetchFromLastRead,
            pageSize: 50
        )
        return try await fetchMessages(query: query)
    }

    private func fetchMessages(query: ChatMessagesQueryState) async throws -> ChatMessagesState {
        if let threadID {
            return try await viewModel.fetchChatThreadMessages(
                channelID: channel.id,
                threadID: threadID,
                query: query
            )
        }
        return try await viewModel.fetchChatMessages(query: query)
    }

    private func markReadIfNeeded() async {
        if let threadID {
            try? await viewModel.markChatThreadRead(channelID: channel.id, threadID: threadID)
        } else if let latest = messages.last?.id {
            try? await viewModel.markChatChannelRead(channelID: channel.id, messageID: latest)
            onRead?(channel.id)
        }
    }

    private func send(message: String, uploads: [FireChatPendingUpload]) async throws {
        guard !isSending else { return }
        isSending = true
        defer { isSending = false }

        var content = message
        var uploadIDs: [UInt64] = []
        for pending in uploads {
            let upload = try await viewModel.uploadImage(
                fileName: pending.fileName,
                mimeType: pending.mimeType,
                bytes: pending.bytes
            )
            if let uploadID = upload.id, uploadID > 0 {
                uploadIDs.append(uploadID)
            } else {
                let alt = upload.originalFilename?.isEmpty == false
                    ? upload.originalFilename!
                    : "image"
                let markdown = "![\(alt)](\(upload.shortUrl))"
                content = content.isEmpty ? markdown : content + "\n\n" + markdown
            }
        }

        do {
            _ = try await viewModel.sendChatMessage(
                request: SendChatMessageRequestState(
                    channelId: channel.id,
                    message: content,
                    stagedId: UUID().uuidString,
                    inReplyToId: nil,
                    threadId: threadID,
                    uploadIds: uploadIDs
                )
            )
        } catch {
            try await refreshLatest()
            throw error
        }
    }

    private func toggleReaction(messageID: UInt64, emoji: String) async throws {
        guard let message = messages.first(where: { $0.id == messageID }) else {
            throw FireChatChannelSessionError.messageNotFound
        }
        let reacted = message.reactions.first(where: { $0.emoji == emoji })?.reacted == true
        try await viewModel.reactChatMessage(
            channelID: message.channelId,
            messageID: message.id,
            emoji: emoji,
            reactAction: reacted ? "remove" : "add"
        )
    }

    private func handleBusEvent(_ event: MessageBusEventState) async {
        guard isOpen, event.channel == messageBusChannelName, let payload = event.payloadJson else {
            return
        }
        let type = event.detailEventType ?? event.messageType
        let previousCount = messages.count
        guard let runtime = try? await viewModel.sessionStore?.applyChatChannelBusEvent(
            channelId: channel.id,
            threadId: threadID,
            payloadJson: payload,
            eventType: type
        ) else {
            return
        }
        applyRuntime(runtime)
        switch type {
        case "pin", "unpin":
            emit(.pins)
        case "delete":
            emit(.messageDeleted(index: 0))
        case "sent":
            emit(messages.count > previousCount ? .messageInserted : .messageUpdated(index: 0))
        default:
            emit(.messageUpdated(index: 0))
        }
    }

    private func adoptRuntime(preferred: Change) async {
        guard let runtime = try? await viewModel.sessionStore?.chatChannelRuntimeSnapshot(
            channelId: channel.id,
            threadId: threadID
        ) else {
            return
        }
        applyRuntime(runtime)
        emit(preferred)
    }

    private func applyRuntime(_ runtime: ChatChannelRuntimeState) {
        messages = runtime.messages
        if threadID == nil {
            pins = runtime.pins
        }
        canLoadMorePast = runtime.canLoadMorePast
    }

    private func emit(_ change: Change) {
        onChange?(
            Snapshot(
                channel: channel,
                messages: messages,
                pins: pins,
                canLoadMorePast: canLoadMorePast
            ),
            change
        )
    }
}

private enum FireChatChannelSessionError: LocalizedError {
    case messageNotFound

    var errorDescription: String? {
        "消息已不存在"
    }
}
