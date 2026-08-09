import Foundation

extension FireAppViewModel {
    func fetchMyChatChannels() async throws -> MyChatChannelsState {
        let sessionStore = try await sessionStoreValue()
        return try await sessionStore.fetchMyChatChannels()
    }

    func fetchChatChannel(channelID: UInt64) async throws -> ChatChannelState {
        let sessionStore = try await sessionStoreValue()
        return try await sessionStore.fetchChatChannel(channelID: channelID)
    }

    func createDirectMessageChannel(
        request: CreateDirectMessageChannelRequestState
    ) async throws -> ChatChannelState {
        let sessionStore = try await sessionStoreValue()
        return try await sessionStore.createDirectMessageChannel(request: request)
    }

    func fetchChatMessages(query: ChatMessagesQueryState) async throws -> ChatMessagesState {
        let sessionStore = try await sessionStoreValue()
        return try await sessionStore.fetchChatMessages(query: query)
    }

    func sendChatMessage(
        request: SendChatMessageRequestState
    ) async throws -> SendChatMessageResultState {
        let sessionStore = try await sessionStoreValue()
        return try await sessionStore.sendChatMessage(request: request)
    }

    func markChatChannelRead(channelID: UInt64, messageID: UInt64? = nil) async throws {
        let sessionStore = try await sessionStoreValue()
        try await sessionStore.markChatChannelRead(channelID: channelID, messageID: messageID)
    }

    func browseChatChannels(
        query: BrowseChatChannelsQueryState
    ) async throws -> [ChatChannelState] {
        let sessionStore = try await sessionStoreValue()
        return try await sessionStore.browseChatChannels(query: query)
    }

    func joinChatChannel(channelID: UInt64) async throws {
        let sessionStore = try await sessionStoreValue()
        try await sessionStore.joinChatChannel(channelID: channelID)
    }

    func leaveChatChannel(channelID: UInt64) async throws {
        let sessionStore = try await sessionStoreValue()
        try await sessionStore.leaveChatChannel(channelID: channelID)
    }

    func starChatChannel(channelID: UInt64, starred: Bool) async throws {
        let sessionStore = try await sessionStoreValue()
        try await sessionStore.starChatChannel(channelID: channelID, starred: starred)
    }

    func updateChatChannelNotifications(
        channelID: UInt64,
        muted: Bool? = nil,
        notificationLevel: String? = nil
    ) async throws {
        let sessionStore = try await sessionStoreValue()
        try await sessionStore.updateChatChannelNotifications(
            channelID: channelID,
            muted: muted,
            notificationLevel: notificationLevel
        )
    }

    func deleteChatMessage(channelID: UInt64, messageID: UInt64) async throws {
        let sessionStore = try await sessionStoreValue()
        try await sessionStore.deleteChatMessage(channelID: channelID, messageID: messageID)
    }

    func reactChatMessage(
        channelID: UInt64,
        messageID: UInt64,
        emoji: String,
        reactAction: String
    ) async throws {
        let sessionStore = try await sessionStoreValue()
        try await sessionStore.reactChatMessage(
            channelID: channelID,
            messageID: messageID,
            emoji: emoji,
            reactAction: reactAction
        )
    }

    func searchChatMessages(query: ChatSearchQueryState) async throws -> ChatSearchResultState {
        let sessionStore = try await sessionStoreValue()
        return try await sessionStore.searchChatMessages(query: query)
    }

    func fetchChatChannelPins(channelID: UInt64) async throws -> [ChatMessageState] {
        let sessionStore = try await sessionStoreValue()
        return try await sessionStore.fetchChatChannelPins(channelID: channelID)
    }

    func pinChatMessage(channelID: UInt64, messageID: UInt64) async throws {
        let sessionStore = try await sessionStoreValue()
        try await sessionStore.pinChatMessage(channelID: channelID, messageID: messageID)
    }

    func unpinChatMessage(channelID: UInt64, messageID: UInt64) async throws {
        let sessionStore = try await sessionStoreValue()
        try await sessionStore.unpinChatMessage(channelID: channelID, messageID: messageID)
    }

    func markChatChannelPinsRead(channelID: UInt64) async throws {
        let sessionStore = try await sessionStoreValue()
        try await sessionStore.markChatChannelPinsRead(channelID: channelID)
    }

    func createChatThread(channelID: UInt64, originalMessageID: UInt64) async throws -> UInt64 {
        let sessionStore = try await sessionStoreValue()
        return try await sessionStore.createChatThread(
            channelID: channelID,
            originalMessageID: originalMessageID
        )
    }

    func fetchChatThreadMessages(
        channelID: UInt64,
        threadID: UInt64,
        query: ChatMessagesQueryState
    ) async throws -> ChatMessagesState {
        let sessionStore = try await sessionStoreValue()
        return try await sessionStore.fetchChatThreadMessages(
            channelID: channelID,
            threadID: threadID,
            query: query
        )
    }

    func markChatThreadRead(channelID: UInt64, threadID: UInt64) async throws {
        let sessionStore = try await sessionStoreValue()
        try await sessionStore.markChatThreadRead(channelID: channelID, threadID: threadID)
    }

    func subscribeMessageBusChannel(
        channel: String,
        ownerToken: String,
        lastMessageId: Int64?
    ) async throws {
        let sessionStore = try await sessionStoreValue()
        try await sessionStore.subscribeMessageBusChannel(
            channel: channel,
            ownerToken: ownerToken,
            lastMessageId: lastMessageId
        )
    }

    func unsubscribeMessageBusChannel(channel: String, ownerToken: String) async throws {
        let sessionStore = try await sessionStoreValue()
        try await sessionStore.unsubscribeMessageBusChannel(channel: channel, ownerToken: ownerToken)
    }

    func bootstrapBaseURLString() -> String? {
        session.bootstrap.baseUrl
    }

    var currentUserID: UInt64? {
        session.bootstrap.currentUserId
    }
}
