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
    private var displayedChannels: [ChatChannelState] = []
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

    func upsert(_ channel: ChatChannelState) async {
        if let response = try? await viewModel.sessionStore?.chatListSnapshot() {
            apply(response)
            emitSnapshot()
        }
        let generation = loadGeneration
        Task { await subscribeNewMessagesIfNeeded(for: channel, generation: generation) }
    }

    func clearTracking(for channelID: UInt64) async {
        guard let response = try? await viewModel.sessionStore?.applyChatListTracking(
            channelId: channelID,
            unread: 0,
            mention: 0,
            explicitMarkRead: true
        ) else {
            return
        }
        apply(response)
        emitSnapshot()
    }

    func handleMessageBusEvent(_ event: MessageBusEventState) async {
        let channel = event.channel
        guard channel == "/chat/new-channel"
            || channel == "/chat/channel-edits"
            || channel.hasPrefix("/chat/user-tracking-state/")
            || channel.hasSuffix("/new-messages")
        else {
            return
        }
        await applyListBus(event)
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
        displayedChannels = []
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

    private func applyListBus(_ event: MessageBusEventState) async {
        guard let payload = event.payloadJson,
              let response = try? await viewModel.sessionStore?.applyChatListBusEvent(
                  payloadJson: payload,
                  eventType: event.detailEventType ?? event.messageType,
                  fallbackChannelId: event.topicId
              )
        else {
            return
        }
        let knownIDs = Set((directMessageChannels + publicChannels).map(\.id))
        apply(response)
        emitSnapshot()
        let generation = loadGeneration
        let newcomers = (response.directMessageChannels + response.publicChannels)
            .filter { !knownIDs.contains($0.id) }
        Task {
            for channel in newcomers {
                await subscribeNewMessagesIfNeeded(for: channel, generation: generation)
            }
        }
    }

    private func apply(_ response: MyChatChannelsState) {
        publicChannels = response.publicChannels
        directMessageChannels = response.directMessageChannels
        displayedChannels = response.inboxChannels
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

    private func emitSnapshot() {
        onSnapshot?(
            Snapshot(
                publicChannels: publicChannels,
                directMessageChannels: directMessageChannels,
                displayedChannels: displayedChannels,
                badgeByChannelID: Dictionary(
                    uniqueKeysWithValues: (directMessageChannels + publicChannels).map {
                        ($0.id, $0.unreadBadge)
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
}
