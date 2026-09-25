import Foundation

@MainActor
final class FireChatListSession {
    struct Snapshot {
        let publicChannels: [ChatChannelState]
        let directMessageChannels: [ChatChannelState]
        let displayedChannels: [ChatChannelState]
        let badgeByChannelID: [UInt64: UInt32]
        let trackingByChannelID: [UInt64: (unread: UInt32, mention: UInt32)]
        let totalUnreadBadge: Int
        let isLoading: Bool
        let hasLoadedOnce: Bool
        let errorMessage: String?
    }

    var onSnapshot: ((Snapshot) -> Void)?

    private let viewModel: FireAppViewModel
    private let ownerToken = "chat-channels-list"
    private var publicChannels: [ChatChannelState] = []
    private var directMessageChannels: [ChatChannelState] = []
    private var trackingByChannelID: [UInt64: (unread: UInt32, mention: UInt32)] = [:]
    private var totalUnreadBadge = 0
    private var isLoading = false
    private var hasLoadedOnce = false
    private var errorMessage: String?
    private var didRefreshFromNetwork = false
    private var loadGeneration: UInt64 = 0
    private var subscribedNewMessageChannels = Set<UInt64>()
    private var globalBusLastIDs: [String: Int64] = [:]

    init(viewModel: FireAppViewModel) {
        self.viewModel = viewModel
    }

    func open() async {
        if !hasLoadedOnce {
            await loadCachedIfAvailable()
        }
        guard !didRefreshFromNetwork, !isLoading else { return }
        await refresh()
    }

    func refresh() async {
        loadGeneration &+= 1
        let generation = loadGeneration
        isLoading = true
        didRefreshFromNetwork = true
        emitSnapshot()
        defer {
            if generation == loadGeneration {
                isLoading = false
                emitSnapshot()
            }
        }

        do {
            let response = try await viewModel.fetchMyChatChannels()
            guard generation == loadGeneration else { return }
            apply(response)
            await resubscribeMessageBus(with: response, generation: generation)
            guard generation == loadGeneration else { return }
            errorMessage = nil
            hasLoadedOnce = true
            emitSnapshot()
        } catch {
            guard generation == loadGeneration else { return }
            if publicChannels.isEmpty && directMessageChannels.isEmpty {
                errorMessage = error.localizedDescription
            }
            hasLoadedOnce = true
            emitSnapshot()
        }
    }

    func upsert(_ channel: ChatChannelState) {
        if channel.isDirectMessage {
            directMessageChannels = upsert(channel, into: directMessageChannels)
        } else {
            publicChannels = upsert(channel, into: publicChannels)
        }
        emitSnapshot()
        let generation = loadGeneration
        Task { await subscribeNewMessagesIfNeeded(for: channel, generation: generation) }
    }

    func clearTracking(for channelID: UInt64) {
        trackingByChannelID[channelID] = (0, 0)
        recomputeBadge()
        emitSnapshot()
    }

    func handleMessageBusEvent(_ event: MessageBusEventState) {
        let channel = event.channel
        if channel == "/chat/new-channel" {
            handleNewChannel(event)
        } else if channel.hasPrefix("/chat/user-tracking-state/") {
            handleTracking(event)
        } else if channel.hasSuffix("/new-messages") {
            handleNewMessages(event)
        }
    }

    func close(reset: Bool) {
        loadGeneration &+= 1
        let channels = subscriptionChannelNames()
        subscribedNewMessageChannels.removeAll()
        Task { [viewModel, ownerToken] in
            for channel in channels {
                try? await viewModel.unsubscribeMessageBusChannel(
                    channel: channel,
                    ownerToken: ownerToken
                )
            }
        }

        guard reset else { return }
        publicChannels = []
        directMessageChannels = []
        trackingByChannelID = [:]
        totalUnreadBadge = 0
        isLoading = false
        hasLoadedOnce = false
        didRefreshFromNetwork = false
        errorMessage = nil
        globalBusLastIDs = [:]
        emitSnapshot()
    }

    private func loadCachedIfAvailable() async {
        guard let cached = try? await viewModel.cachedMyChatChannels() else { return }
        apply(cached)
        hasLoadedOnce = true
        emitSnapshot()
    }

    private func handleNewChannel(_ event: MessageBusEventState) {
        let baseURLString = viewModel.bootstrapBaseURLString() ?? "https://linux.do"
        guard let channel = FireChatBusPayload.channel(from: event, baseURLString: baseURLString),
              channel.isDirectMessage
        else {
            return
        }
        upsert(channel)
    }

    private func handleTracking(_ event: MessageBusEventState) {
        let baseURLString = viewModel.bootstrapBaseURLString() ?? "https://linux.do"
        guard case let .tracking(channelID, unread, mention, threadID) = FireChatBusPayload.event(
            from: event,
            fallbackChannelID: event.topicId,
            baseURLString: baseURLString
        ), threadID == nil, channelID > 0 else {
            return
        }
        trackingByChannelID[channelID] = (unread, mention)
        recomputeBadge()
        emitSnapshot()
    }

    private func handleNewMessages(_ event: MessageBusEventState) {
        let baseURLString = viewModel.bootstrapBaseURLString() ?? "https://linux.do"
        switch FireChatBusPayload.event(
            from: event,
            fallbackChannelID: event.topicId,
            baseURLString: baseURLString
        ) {
        case let .newMessages(channelID, isChannelLevel, message, _):
            guard isChannelLevel, channelID > 0, let message else { return }
            applyIncomingLastMessage(
                message,
                isSelf: message.user?.id == viewModel.currentUserID
            )
        case let .messageUpsert(message):
            applyIncomingLastMessage(
                message,
                isSelf: message.user?.id == viewModel.currentUserID
            )
        default:
            break
        }
    }

    private func applyIncomingLastMessage(_ message: ChatMessageState, isSelf: Bool) {
        let channelID = message.channelId
        if !isSelf {
            let old = trackingByChannelID[channelID] ?? (0, 0)
            trackingByChannelID[channelID] = (old.unread &+ 1, old.mention)
            recomputeBadge()
        }
        if let index = directMessageChannels.firstIndex(where: { $0.id == channelID }) {
            directMessageChannels[index] = withLastMessage(directMessageChannels[index], message)
            directMessageChannels = sorted(directMessageChannels)
            emitSnapshot()
            return
        }
        if let index = publicChannels.firstIndex(where: { $0.id == channelID }) {
            publicChannels[index] = withLastMessage(publicChannels[index], message)
            publicChannels = sorted(publicChannels)
            emitSnapshot()
        }
    }

    private func apply(_ response: MyChatChannelsState) {
        publicChannels = response.publicChannels
        directMessageChannels = response.directMessageChannels
        trackingByChannelID = Dictionary(
            uniqueKeysWithValues: response.channelTracking.map {
                ($0.channelId, (unread: $0.unreadCount, mention: $0.mentionCount))
            }
        )
        totalUnreadBadge = Int(response.totalUnreadBadge)
        globalBusLastIDs = Dictionary(
            uniqueKeysWithValues: response.globalBusLastIds.map { ($0.channel, $0.lastId) }
        )
    }

    private func resubscribeMessageBus(
        with response: MyChatChannelsState,
        generation: UInt64
    ) async {
        await teardownSubscriptions()
        guard generation == loadGeneration else { return }
        let trackingChannel = viewModel.currentUserID.map { "/chat/user-tracking-state/\($0)" }
        let globalChannels: [(String, Int64?)] = [
            ("/chat/new-channel", globalBusLastIDs["new_channel"]),
            ("/chat/channel-edits", globalBusLastIDs["channel_edits"]),
        ] + (trackingChannel.map { [($0, globalBusLastIDs["user_tracking_state"])] } ?? [])

        for (channel, lastID) in globalChannels {
            try? await viewModel.subscribeMessageBusChannel(
                channel: channel,
                ownerToken: ownerToken,
                lastMessageId: lastID
            )
            guard generation == loadGeneration else {
                try? await viewModel.unsubscribeMessageBusChannel(
                    channel: channel,
                    ownerToken: ownerToken
                )
                return
            }
        }
        for channel in response.directMessageChannels + response.publicChannels {
            await subscribeNewMessagesIfNeeded(for: channel, generation: generation)
            guard generation == loadGeneration else { return }
        }
    }

    private func subscribeNewMessagesIfNeeded(
        for channel: ChatChannelState,
        generation: UInt64
    ) async {
        guard generation == loadGeneration else { return }
        guard !subscribedNewMessageChannels.contains(channel.id) else { return }
        subscribedNewMessageChannels.insert(channel.id)
        let channelName = "/chat/\(channel.id)/new-messages"
        try? await viewModel.subscribeMessageBusChannel(
            channel: channelName,
            ownerToken: ownerToken,
            lastMessageId: channel.busLastIds.newMessages
        )
        guard generation == loadGeneration else {
            subscribedNewMessageChannels.remove(channel.id)
            try? await viewModel.unsubscribeMessageBusChannel(
                channel: channelName,
                ownerToken: ownerToken
            )
            return
        }
    }

    private func teardownSubscriptions() async {
        let channels = subscriptionChannelNames()
        for channel in channels {
            try? await viewModel.unsubscribeMessageBusChannel(channel: channel, ownerToken: ownerToken)
        }
        subscribedNewMessageChannels.removeAll()
    }

    private func subscriptionChannelNames() -> [String] {
        subscribedNewMessageChannels.map { "/chat/\($0)/new-messages" }
            + [
                "/chat/new-channel",
                "/chat/channel-edits",
            ]
            + (viewModel.currentUserID.map { ["/chat/user-tracking-state/\($0)"] } ?? [])
    }

    private func recomputeBadge() {
        var sum: UInt32 = 0
        for channel in directMessageChannels where !(channel.currentUserMembership?.muted ?? false) {
            let tracking = trackingByChannelID[channel.id]
            sum = sum &+ (tracking?.unread ?? 0) &+ (tracking?.mention ?? 0)
        }
        for channel in publicChannels where !(channel.currentUserMembership?.muted ?? false) {
            sum = sum &+ (trackingByChannelID[channel.id]?.mention ?? 0)
        }
        totalUnreadBadge = Int(sum)
    }

    private func emitSnapshot() {
        onSnapshot?(
            Snapshot(
                publicChannels: publicChannels,
                directMessageChannels: directMessageChannels,
                displayedChannels: sorted(directMessageChannels + publicChannels),
                badgeByChannelID: Dictionary(
                    uniqueKeysWithValues: (directMessageChannels + publicChannels).map {
                        ($0.id, badge(for: $0))
                    }
                ),
                trackingByChannelID: trackingByChannelID,
                totalUnreadBadge: totalUnreadBadge,
                isLoading: isLoading,
                hasLoadedOnce: hasLoadedOnce,
                errorMessage: errorMessage
            )
        )
    }

    private func sorted(_ channels: [ChatChannelState]) -> [ChatChannelState] {
        channels.sorted { lhs, rhs in
            let leftStarred = lhs.currentUserMembership?.starred ?? false
            let rightStarred = rhs.currentUserMembership?.starred ?? false
            if leftStarred != rightStarred {
                return leftStarred && !rightStarred
            }
            let leftTime = lhs.lastMessage?.createdAt ?? ""
            let rightTime = rhs.lastMessage?.createdAt ?? ""
            if leftTime != rightTime {
                return leftTime > rightTime
            }
            return lhs.id > rhs.id
        }
    }

    private func badge(for channel: ChatChannelState) -> UInt32 {
        if channel.currentUserMembership?.muted == true {
            return 0
        }
        let tracking = trackingByChannelID[channel.id]
        if channel.isDirectMessage {
            return (tracking?.unread ?? 0) &+ (tracking?.mention ?? 0)
        }
        return tracking?.mention ?? 0
    }

    private func upsert(
        _ channel: ChatChannelState,
        into channels: [ChatChannelState]
    ) -> [ChatChannelState] {
        var next = channels.filter { $0.id != channel.id }
        next.insert(channel, at: 0)
        return next
    }

    private func withLastMessage(
        _ channel: ChatChannelState,
        _ message: ChatMessageState
    ) -> ChatChannelState {
        ChatChannelState(
            id: channel.id,
            title: channel.title,
            unicodeTitle: channel.unicodeTitle,
            displayTitle: channel.displayTitle,
            slug: channel.slug,
            description: channel.description,
            chatableType: channel.chatableType,
            status: channel.status,
            threadingEnabled: channel.threadingEnabled,
            membershipsCount: channel.membershipsCount,
            isGroupDm: channel.isGroupDm,
            isDirectMessage: channel.isDirectMessage,
            isPublicChannel: channel.isPublicChannel,
            dmUsers: channel.dmUsers,
            categoryColor: channel.categoryColor,
            categoryName: channel.categoryName,
            emoji: channel.emoji,
            formattedEmoji: channel.formattedEmoji,
            currentUserMembership: channel.currentUserMembership,
            lastMessage: message,
            busLastIds: channel.busLastIds,
            canModerate: channel.canModerate,
            canManagePins: channel.canManagePins,
            canDeleteSelf: channel.canDeleteSelf,
            canDeleteOthers: channel.canDeleteOthers,
            canRemoveMembers: channel.canRemoveMembers,
            canFlag: channel.canFlag
        )
    }
}
