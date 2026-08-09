import Combine
import Foundation

@MainActor
final class FireChatChannelsStore: ObservableObject {
    enum Segment: Int, CaseIterable, Hashable {
        case directMessages
        case publicChannels

        var title: String {
            switch self {
            case .directMessages: return "私信"
            case .publicChannels: return "频道"
            }
        }
    }

    @Published private(set) var publicChannels: [ChatChannelState] = []
    @Published private(set) var directMessageChannels: [ChatChannelState] = []
    @Published private(set) var trackingByChannelID: [UInt64: (unread: UInt32, mention: UInt32)] = [:]
    @Published private(set) var totalUnreadBadge: Int = 0
    @Published private(set) var isLoading = false
    @Published private(set) var hasLoadedOnce = false
    @Published var errorMessage: String?
    @Published var selectedSegment: Segment = .directMessages

    private let viewModel: FireAppViewModel
    private let ownerToken = "chat-channels-list"
    private var loadGeneration: UInt64 = 0
    private var subscribedNewMessageChannels = Set<UInt64>()
    private var globalBusLastIDs: [String: Int64] = [:]

    init(viewModel: FireAppViewModel) {
        self.viewModel = viewModel
    }

    var displayedChannels: [ChatChannelState] {
        switch selectedSegment {
        case .directMessages:
            return sorted(directMessageChannels)
        case .publicChannels:
            return sorted(publicChannels)
        }
    }

    func badge(for channel: ChatChannelState) -> UInt32 {
        if channel.currentUserMembership?.muted == true {
            return 0
        }
        let tracking = trackingByChannelID[channel.id]
        if channel.isDirectMessage {
            return (tracking?.unread ?? 0) &+ (tracking?.mention ?? 0)
        }
        return tracking?.mention ?? 0
    }

    func loadIfNeeded() async {
        guard !hasLoadedOnce, !isLoading else { return }
        await refresh()
    }

    func refresh() async {
        loadGeneration &+= 1
        let generation = loadGeneration
        isLoading = true
        defer {
            if generation == loadGeneration {
                isLoading = false
            }
        }

        do {
            let response = try await viewModel.fetchMyChatChannels()
            guard generation == loadGeneration else { return }
            apply(response)
            await resubscribeMessageBus(with: response)
            errorMessage = nil
            hasLoadedOnce = true
        } catch {
            guard generation == loadGeneration else { return }
            errorMessage = error.localizedDescription
            hasLoadedOnce = true
        }
    }

    func selectSegment(_ segment: Segment) {
        selectedSegment = segment
    }

    func upsert(_ channel: ChatChannelState) {
        if channel.isDirectMessage {
            directMessageChannels = upsert(channel, into: directMessageChannels)
        } else {
            publicChannels = upsert(channel, into: publicChannels)
        }
        Task { await subscribeNewMessagesIfNeeded(for: channel) }
    }

    func clearTracking(for channelID: UInt64) {
        trackingByChannelID[channelID] = (0, 0)
        recomputeBadge()
    }

    func applyIncomingLastMessage(_ message: ChatMessageState, isSelf: Bool) {
        let channelID = message.channelId
        if !isSelf {
            let old = trackingByChannelID[channelID] ?? (0, 0)
            trackingByChannelID[channelID] = (old.unread &+ 1, old.mention)
            recomputeBadge()
        }
        if let index = directMessageChannels.firstIndex(where: { $0.id == channelID }) {
            directMessageChannels[index] = withLastMessage(directMessageChannels[index], message)
            directMessageChannels = sorted(directMessageChannels)
            return
        }
        if let index = publicChannels.firstIndex(where: { $0.id == channelID }) {
            publicChannels[index] = withLastMessage(publicChannels[index], message)
            publicChannels = sorted(publicChannels)
        }
    }

    func handleMessageBusEvent(_ event: MessageBusEventState) {
        let channel = event.channel
        if channel == "/chat/new-channel" {
            handleNewChannel(event)
            return
        }
        if channel.hasPrefix("/chat/user-tracking-state/") {
            handleTracking(event)
            return
        }
        if channel.hasSuffix("/new-messages") {
            handleNewMessages(event)
        }
    }

    func reset() {
        loadGeneration &+= 1
        Task { await teardownSubscriptions() }
        publicChannels = []
        directMessageChannels = []
        trackingByChannelID = [:]
        totalUnreadBadge = 0
        isLoading = false
        hasLoadedOnce = false
        errorMessage = nil
        selectedSegment = .directMessages
        subscribedNewMessageChannels.removeAll()
        globalBusLastIDs = [:]
    }

    private func handleNewChannel(_ event: MessageBusEventState) {
        guard let object = FireChatBusPayload.jsonObject(from: event) else { return }
        let channelObject = (object["channel"] as? [String: Any]) ?? object
        guard let channel = FireChatBusPayload.channel(from: channelObject),
              channel.isDirectMessage
        else {
            return
        }
        upsert(channel)
    }

    private func handleTracking(_ event: MessageBusEventState) {
        guard let object = FireChatBusPayload.jsonObject(from: event) else { return }
        if object["thread_id"] != nil { return }
        guard let channelID = (object["channel_id"] as? NSNumber)?.uint64Value
            ?? (object["channel_id"] as? UInt64)
        else {
            return
        }
        let unread = (object["unread_count"] as? NSNumber)?.uint32Value ?? 0
        let mention = (object["mention_count"] as? NSNumber)?.uint32Value ?? 0
        trackingByChannelID[channelID] = (unread, mention)
        recomputeBadge()
    }

    private func handleNewMessages(_ event: MessageBusEventState) {
        guard let object = FireChatBusPayload.jsonObject(from: event) else { return }
        // Only channel-level messages update list last-message preview.
        if let type = object["type"] as? String, type != "channel" {
            return
        }
        let channelID = event.topicId
            ?? (object["channel_id"] as? NSNumber)?.uint64Value
            ?? 0
        guard channelID > 0,
              let message = FireChatBusPayload.chatMessage(from: event, fallbackChannelID: channelID)
        else {
            return
        }
        let isSelf = message.user?.id == viewModel.currentUserID
        applyIncomingLastMessage(message, isSelf: isSelf)
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

    private func resubscribeMessageBus(with response: MyChatChannelsState) async {
        await teardownSubscriptions()
        let userID = viewModel.currentUserID
        let trackingChannel = userID.map { "/chat/user-tracking-state/\($0)" }
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
        }
        for channel in response.directMessageChannels + response.publicChannels {
            await subscribeNewMessagesIfNeeded(for: channel)
        }
    }

    private func subscribeNewMessagesIfNeeded(for channel: ChatChannelState) async {
        guard !subscribedNewMessageChannels.contains(channel.id) else { return }
        subscribedNewMessageChannels.insert(channel.id)
        try? await viewModel.subscribeMessageBusChannel(
            channel: "/chat/\(channel.id)/new-messages",
            ownerToken: ownerToken,
            lastMessageId: channel.busLastIds.newMessages
        )
    }

    private func teardownSubscriptions() async {
        let channels = subscribedNewMessageChannels.map { "/chat/\($0)/new-messages" }
            + [
                "/chat/new-channel",
                "/chat/channel-edits",
            ]
            + (viewModel.currentUserID.map { ["/chat/user-tracking-state/\($0)"] } ?? [])
        for channel in channels {
            try? await viewModel.unsubscribeMessageBusChannel(channel: channel, ownerToken: ownerToken)
        }
        subscribedNewMessageChannels.removeAll()
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

    private func upsert(
        _ channel: ChatChannelState,
        into channels: [ChatChannelState]
    ) -> [ChatChannelState] {
        var next = channels.filter { $0.id != channel.id }
        next.insert(channel, at: 0)
        return next
    }

    private func withLastMessage(_ channel: ChatChannelState, _ message: ChatMessageState) -> ChatChannelState {
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
