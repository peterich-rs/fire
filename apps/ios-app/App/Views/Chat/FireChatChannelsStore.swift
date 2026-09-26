import Combine
import Foundation

@MainActor
final class FireChatChannelsStore: ObservableObject {
    @Published private(set) var publicChannels: [ChatChannelState] = []
    @Published private(set) var directMessageChannels: [ChatChannelState] = []
    @Published private(set) var trackingByChannelID: [UInt64: (unread: UInt32, mention: UInt32)] = [:]
    @Published private(set) var totalUnreadBadge: Int = 0
    @Published private(set) var isLoading = false
    @Published private(set) var hasLoadedOnce = false
    @Published var errorMessage: String?

    private let session: FireChatListSession
    private var orderedChannels: [ChatChannelState] = []
    private var badgeByChannelID: [UInt64: UInt32] = [:]

    init(viewModel: FireAppViewModel) {
        let session = FireChatListSession(viewModel: viewModel)
        self.session = session
        session.onSnapshot = { [weak self] snapshot in
            self?.apply(snapshot)
        }
    }

    var displayedChannels: [ChatChannelState] {
        orderedChannels
    }

    func badge(for channel: ChatChannelState) -> UInt32 {
        badgeByChannelID[channel.id] ?? 0
    }

    func loadIfNeeded() async {
        await session.open()
    }

    func refresh() async {
        await session.refresh()
    }

    func upsert(_ channel: ChatChannelState) async {
        await session.upsert(channel)
    }

    func clearTracking(for channelID: UInt64) async {
        await session.clearTracking(for: channelID)
    }

    func handleMessageBusEvent(_ event: MessageBusEventState) async {
        await session.handleMessageBusEvent(event)
    }

    func reset() {
        session.close(reset: true)
    }

    private func apply(_ snapshot: FireChatListSession.Snapshot) {
        publicChannels = snapshot.publicChannels
        directMessageChannels = snapshot.directMessageChannels
        orderedChannels = snapshot.displayedChannels
        badgeByChannelID = snapshot.badgeByChannelID
        trackingByChannelID = snapshot.trackingByChannelID
        totalUnreadBadge = snapshot.totalUnreadBadge
        isLoading = snapshot.isLoading
        hasLoadedOnce = snapshot.hasLoadedOnce
        errorMessage = snapshot.errorMessage
    }
}
