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
    private var loadGeneration: UInt64 = 0

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
    }

    func clearTracking(for channelID: UInt64) {
        trackingByChannelID[channelID] = (0, 0)
        recomputeBadge()
    }

    func reset() {
        loadGeneration &+= 1
        publicChannels = []
        directMessageChannels = []
        trackingByChannelID = [:]
        totalUnreadBadge = 0
        isLoading = false
        hasLoadedOnce = false
        errorMessage = nil
        selectedSegment = .directMessages
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
}
