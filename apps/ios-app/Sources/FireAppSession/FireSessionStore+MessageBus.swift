import Foundation

extension FireSessionStore {
    public func stopMessageBus(clearSubscriptions: Bool = false) throws {
        try core.messagebus().stopMessageBus(clearSubscriptions: clearSubscriptions)
    }

    public func subscribeTopicDetailChannel(
        topicId: UInt64,
        ownerToken: String,
        lastMessageId: Int64?
    ) throws {
        try core.messagebus().subscribeChannel(
            subscription: MessageBusSubscriptionState(
                ownerToken: ownerToken,
                channel: "/topic/\(topicId)",
                lastMessageId: lastMessageId,
                scope: .transient
            )
        )
    }

    public func unsubscribeTopicDetailChannel(topicId: UInt64, ownerToken: String) throws {
        try core.messagebus().unsubscribeChannel(ownerToken: ownerToken, channel: "/topic/\(topicId)")
    }

    public func subscribeTopicReactionChannel(topicId: UInt64, ownerToken: String) throws {
        try core.messagebus().subscribeChannel(
            subscription: MessageBusSubscriptionState(
                ownerToken: ownerToken,
                channel: "/topic/\(topicId)/reactions",
                lastMessageId: nil,
                scope: .transient
            )
        )
    }

    public func unsubscribeTopicReactionChannel(topicId: UInt64, ownerToken: String) throws {
        try core.messagebus().unsubscribeChannel(ownerToken: ownerToken, channel: "/topic/\(topicId)/reactions")
    }

    public func subscribeTopicPollsChannel(topicId: UInt64, ownerToken: String) throws {
        try core.messagebus().subscribeChannel(
            subscription: MessageBusSubscriptionState(
                ownerToken: ownerToken,
                channel: "/polls/\(topicId)",
                lastMessageId: 0,
                scope: .transient
            )
        )
    }

    public func unsubscribeTopicPollsChannel(topicId: UInt64, ownerToken: String) throws {
        try core.messagebus().unsubscribeChannel(ownerToken: ownerToken, channel: "/polls/\(topicId)")
    }

    public func subscribeMessageBusChannel(
        channel: String,
        ownerToken: String,
        lastMessageId: Int64?,
        scope: MessageBusSubscriptionScopeState = .transient
    ) throws {
        try core.messagebus().subscribeChannel(
            subscription: MessageBusSubscriptionState(
                ownerToken: ownerToken,
                channel: channel,
                lastMessageId: lastMessageId,
                scope: scope
            )
        )
    }

    public func unsubscribeMessageBusChannel(channel: String, ownerToken: String) throws {
        try core.messagebus().unsubscribeChannel(ownerToken: ownerToken, channel: channel)
    }

    public func topicReplyPresenceState(topicId: UInt64) throws -> TopicPresenceState {
        try core.messagebus().topicReplyPresenceState(topicId: topicId)
    }

    public func bootstrapTopicReplyPresence(
        topicId: UInt64,
        ownerToken: String
    ) async throws -> TopicPresenceState {
        try await runPersistingSessionChanges {
            try await core.messagebus().bootstrapTopicReplyPresence(topicId: topicId, ownerToken: ownerToken)
        }
    }

    public func unsubscribeTopicReplyPresenceChannel(topicId: UInt64, ownerToken: String) throws {
        try core.messagebus().unsubscribeChannel(
            ownerToken: ownerToken,
            channel: "/presence/discourse-presence/reply/\(topicId)"
        )
    }

    public func updateTopicReplyPresence(topicId: UInt64, active: Bool) async throws {
        try await runAuthenticatedWritePersistingSessionChanges {
            try await core.messagebus().updateTopicReplyPresence(topicId: topicId, active: active)
        }
    }

    // MARK: - Logout

    private func topicTrackingStateMetaForMessageBus() throws -> [String: Int64]? {
        let raw = try core.session().snapshot().bootstrap.topicTrackingStateMeta?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let raw, !raw.isEmpty else {
            return nil
        }
        let data = Data(raw.utf8)
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        var result: [String: Int64] = [:]
        for (key, value) in object {
            if let number = value as? NSNumber {
                result[key] = number.int64Value
            } else if let text = value as? String, let number = Int64(text) {
                result[key] = number
            }
        }
        return result.isEmpty ? nil : result
    }

    @discardableResult
    public func startMessageBus(handler: any MessageBusEventHandler) async throws -> String {
        try await runPersistingSessionChanges {
            try await core.messagebus().startMessageBus(
                mode: .foreground,
                handler: handler,
                topicTrackingStateMeta: try topicTrackingStateMetaForMessageBus()
            )
        }
    }
}
