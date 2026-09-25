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
                self?.handleBusEvent(event)
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
        messages = cached.messages.sorted { $0.id < $1.id }
        canLoadMorePast = cached.canLoadMorePast
        emit(.cached)
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

            let page = try await fetchMessages(fetchFromLastRead: true)
            guard generation == lifecycleGeneration, isOpen else { return }
            messages = page.messages.sorted { $0.id < $1.id }
            canLoadMorePast = page.canLoadMorePast
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
            emit(.initial)
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
        let page = try await fetchMessages(query: query)
        let older = page.messages.sorted { $0.id < $1.id }
        messages = older + messages
        canLoadMorePast = page.canLoadMorePast
        emit(.older(anchorMessageID: oldest.id))
    }

    private func refreshLatest() async throws {
        let page = try await fetchMessages(fetchFromLastRead: false)
        messages = page.messages.sorted { $0.id < $1.id }
        canLoadMorePast = page.canLoadMorePast
        await markReadIfNeeded()
        emit(.latest)
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
        try await refreshLatest()
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

    private func handleBusEvent(_ event: MessageBusEventState) {
        guard isOpen, event.channel == messageBusChannelName else { return }
        let type = event.detailEventType ?? event.messageType
        let baseURLString = viewModel.bootstrapBaseURLString() ?? "https://linux.do"
        switch type {
        case "sent":
            if let message = FireChatBusPayload.chatMessage(
                from: event,
                fallbackChannelID: channel.id,
                baseURLString: baseURLString
            ) {
                upsertMessage(message, preferAppend: true)
            }
        case "edit", "processed", "refresh", "restore", "thread_created",
             "update_thread_original_message":
            if let message = FireChatBusPayload.chatMessage(
                from: event,
                fallbackChannelID: channel.id,
                baseURLString: baseURLString
            ) {
                upsertMessage(message, preferAppend: false)
            }
        case "delete":
            if case let .messageDeleted(deletedID) = FireChatBusPayload.event(
                from: event,
                fallbackChannelID: channel.id,
                baseURLString: baseURLString
            ), let index = messages.firstIndex(where: { $0.id == deletedID }) {
                messages.remove(at: index)
                emit(.messageDeleted(index: index))
            }
        case "reaction":
            applyReaction(event)
        case "pin":
            if let message = FireChatBusPayload.chatMessage(
                from: event,
                fallbackChannelID: channel.id,
                baseURLString: baseURLString
            ) {
                pins = [message] + pins.filter { $0.id != message.id }
                emit(.pins)
            }
        case "unpin":
            if let message = FireChatBusPayload.chatMessage(
                from: event,
                fallbackChannelID: channel.id,
                baseURLString: baseURLString
            ) {
                pins.removeAll { $0.id == message.id }
                emit(.pins)
            }
        default:
            break
        }
    }

    private func applyReaction(_ event: MessageBusEventState) {
        let baseURLString = viewModel.bootstrapBaseURLString() ?? "https://linux.do"
        guard case let .reaction(messageID, emoji, action, actorID) = FireChatBusPayload.event(
            from: event,
            fallbackChannelID: channel.id,
            baseURLString: baseURLString
        ), let index = messages.firstIndex(where: { $0.id == messageID }) else {
            return
        }
        var message = messages[index]
        var reactions = message.reactions
        let isAdd = action == .add
        if let existing = reactions.firstIndex(where: { $0.emoji == emoji }) {
            let current = reactions[existing]
            let nextCount = isAdd ? current.count &+ 1 : (current.count > 0 ? current.count - 1 : 0)
            let reacted = isAdd && (current.reacted || actorID == viewModel.currentUserID)
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
        } else if isAdd {
            reactions.append(
                ChatMessageReactionState(
                    emoji: emoji,
                    count: 1,
                    reacted: true,
                    users: []
                )
            )
        }
        messages[index] = withReactions(message, reactions)
        emit(.messageUpdated(index: index))
    }

    private func upsertMessage(_ message: ChatMessageState, preferAppend: Bool) {
        if let index = messages.firstIndex(where: { $0.id == message.id }) {
            messages[index] = message
            emit(.messageUpdated(index: index))
            return
        }
        guard preferAppend else { return }
        messages.append(message)
        emit(.messageInserted)
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

    private func withReactions(
        _ message: ChatMessageState,
        _ reactions: [ChatMessageReactionState]
    ) -> ChatMessageState {
        ChatMessageState(
            id: message.id,
            channelId: message.channelId,
            message: message.message,
            presentation: message.presentation,
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

private enum FireChatChannelSessionError: LocalizedError {
    case messageNotFound

    var errorDescription: String? {
        "消息已不存在"
    }
}
