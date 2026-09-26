import Foundation

extension FireSessionStore {
    public func fetchMyChatChannels() async throws -> MyChatChannelsState {
        try await runPersistingSessionChanges {
            try await core.chat().fetchMyChatChannels()
        }
    }

    public func cachedMyChatChannels() throws -> MyChatChannelsState? {
        try core.chat().cachedMyChatChannels()
    }

    public func chatListSnapshot() throws -> MyChatChannelsState? {
        try core.chat().chatListSnapshot()
    }

    public func applyChatListTracking(
        channelId: UInt64,
        unread: UInt32,
        mention: UInt32,
        explicitMarkRead: Bool
    ) throws -> MyChatChannelsState {
        try core.chat().applyChatListTracking(
            channelId: channelId,
            unread: unread,
            mention: mention,
            explicitMarkRead: explicitMarkRead
        )
    }

    public func applyChatListBusEvent(
        payloadJson: String,
        eventType: String?,
        fallbackChannelId: UInt64?
    ) throws -> MyChatChannelsState {
        try core.chat().applyChatListBusEvent(
            payloadJson: payloadJson,
            eventType: eventType,
            fallbackChannelId: fallbackChannelId
        )
    }

    public func chatChannelRuntimeSnapshot(
        channelId: UInt64,
        threadId: UInt64?
    ) throws -> ChatChannelRuntimeState? {
        try core.chat().chatChannelRuntimeSnapshot(channelId: channelId, threadId: threadId)
    }

    public func applyChatChannelBusEvent(
        channelId: UInt64,
        threadId: UInt64?,
        payloadJson: String,
        eventType: String?
    ) throws -> ChatChannelRuntimeState {
        try core.chat().applyChatChannelBusEvent(
            channelId: channelId,
            threadId: threadId,
            payloadJson: payloadJson,
            eventType: eventType
        )
    }

    public func closeChatChannelRuntime(channelId: UInt64, threadId: UInt64?) throws {
        try core.chat().closeChatChannelRuntime(channelId: channelId, threadId: threadId)
    }

    public func cachedChatMessages(channelID: UInt64, threadID: UInt64?) throws -> ChatMessagesState? {
        try core.chat().cachedChatMessages(channelId: channelID, threadId: threadID)
    }

    public func fetchChatChannel(channelID: UInt64) async throws -> ChatChannelState {
        try await runPersistingSessionChanges {
            try await core.chat().fetchChatChannel(channelId: channelID)
        }
    }

    public func createDirectMessageChannel(
        request: CreateDirectMessageChannelRequestState
    ) async throws -> ChatChannelState {
        try await runAuthenticatedWritePersistingSessionChanges {
            try await core.chat().createDirectMessageChannel(request: request)
        }
    }

    public func fetchChatMessages(query: ChatMessagesQueryState) async throws -> ChatMessagesState {
        try await runPersistingSessionChanges {
            try await core.chat().fetchChatMessages(query: query)
        }
    }

    public func sendChatMessage(
        request: SendChatMessageRequestState
    ) async throws -> SendChatMessageResultState {
        try await runAuthenticatedWritePersistingSessionChanges {
            try await core.chat().sendChatMessage(request: request)
        }
    }

    public func markChatChannelRead(channelID: UInt64, messageID: UInt64? = nil) async throws {
        try await runAuthenticatedWritePersistingSessionChanges {
            try await core.chat().markChatChannelRead(channelId: channelID, messageId: messageID)
        }
    }

    public func browseChatChannels(
        query: BrowseChatChannelsQueryState
    ) async throws -> [ChatChannelState] {
        try await runPersistingSessionChanges {
            try await core.chat().browseChatChannels(query: query)
        }
    }

    public func joinChatChannel(channelID: UInt64) async throws {
        try await runAuthenticatedWritePersistingSessionChanges {
            try await core.chat().joinChatChannel(channelId: channelID)
        }
    }

    public func leaveChatChannel(channelID: UInt64) async throws {
        try await runAuthenticatedWritePersistingSessionChanges {
            try await core.chat().leaveChatChannel(channelId: channelID)
        }
    }

    public func starChatChannel(channelID: UInt64, starred: Bool) async throws {
        try await runAuthenticatedWritePersistingSessionChanges {
            try await core.chat().starChatChannel(channelId: channelID, starred: starred)
        }
    }

    public func updateChatChannelNotifications(
        channelID: UInt64,
        muted: Bool? = nil,
        notificationLevel: String? = nil
    ) async throws {
        try await runAuthenticatedWritePersistingSessionChanges {
            try await core.chat().updateChatChannelNotifications(
                channelId: channelID,
                muted: muted,
                notificationLevel: notificationLevel
            )
        }
    }

    public func editChatMessage(
        channelID: UInt64,
        messageID: UInt64,
        message: String,
        uploadIDs: [UInt64]? = nil
    ) async throws {
        try await runAuthenticatedWritePersistingSessionChanges {
            try await core.chat().editChatMessage(
                channelId: channelID,
                messageId: messageID,
                message: message,
                uploadIds: uploadIDs
            )
        }
    }

    public func deleteChatMessage(channelID: UInt64, messageID: UInt64) async throws {
        try await runAuthenticatedWritePersistingSessionChanges {
            try await core.chat().deleteChatMessage(channelId: channelID, messageId: messageID)
        }
    }

    public func reactChatMessage(
        channelID: UInt64,
        messageID: UInt64,
        emoji: String,
        reactAction: String
    ) async throws {
        try await runAuthenticatedWritePersistingSessionChanges {
            try await core.chat().reactChatMessage(
                channelId: channelID,
                messageId: messageID,
                emoji: emoji,
                reactAction: reactAction
            )
        }
    }

    public func fetchChatChannelMembers(
        channelID: UInt64,
        offset: UInt32? = nil,
        limit: UInt32? = nil,
        username: String? = nil
    ) async throws -> [ChatChannelMemberState] {
        try await runPersistingSessionChanges {
            try await core.chat().fetchChatChannelMembers(
                channelId: channelID,
                offset: offset,
                limit: limit,
                username: username
            )
        }
    }

    public func searchChatMessages(query: ChatSearchQueryState) async throws -> ChatSearchResultState {
        try await runPersistingSessionChanges {
            try await core.chat().searchChatMessages(query: query)
        }
    }

    public func fetchChatChannelPins(channelID: UInt64) async throws -> [ChatMessageState] {
        try await runPersistingSessionChanges {
            try await core.chat().fetchChatChannelPins(channelId: channelID)
        }
    }

    public func pinChatMessage(channelID: UInt64, messageID: UInt64) async throws {
        try await runAuthenticatedWritePersistingSessionChanges {
            try await core.chat().pinChatMessage(channelId: channelID, messageId: messageID)
        }
    }

    public func unpinChatMessage(channelID: UInt64, messageID: UInt64) async throws {
        try await runAuthenticatedWritePersistingSessionChanges {
            try await core.chat().unpinChatMessage(channelId: channelID, messageId: messageID)
        }
    }

    public func markChatChannelPinsRead(channelID: UInt64) async throws {
        try await runAuthenticatedWritePersistingSessionChanges {
            try await core.chat().markChatChannelPinsRead(channelId: channelID)
        }
    }

    public func createChatThread(channelID: UInt64, originalMessageID: UInt64) async throws -> UInt64 {
        try await runAuthenticatedWritePersistingSessionChanges {
            try await core.chat().createChatThread(
                channelId: channelID,
                originalMessageId: originalMessageID
            )
        }
    }

    public func fetchChatThreadMessages(
        channelID: UInt64,
        threadID: UInt64,
        query: ChatMessagesQueryState
    ) async throws -> ChatMessagesState {
        try await runPersistingSessionChanges {
            try await core.chat().fetchChatThreadMessages(
                channelId: channelID,
                threadId: threadID,
                query: query
            )
        }
    }

    public func markChatThreadRead(channelID: UInt64, threadID: UInt64) async throws {
        try await runAuthenticatedWritePersistingSessionChanges {
            try await core.chat().markChatThreadRead(channelId: channelID, threadId: threadID)
        }
    }
}
