import UIKit

extension FireChatChannelViewController {
    func applySessionSnapshot(
        _ snapshot: FireChatChannelSession.Snapshot,
        change: FireChatChannelSession.Change
    ) {
        let wasNearBottom = isNearBottom()
        channel = snapshot.channel
        messages = snapshot.messages
        pins = snapshot.pins
        canLoadMorePast = snapshot.canLoadMorePast
        title = isThread ? "消息串" : channel.displayTitle
        updatePinBanner()

        switch change {
        case .cached, .initial:
            tableView.reloadData()
            scrollToBottom(animated: false)
        case let .older(anchorMessageID):
            tableView.reloadData()
            if let index = messages.firstIndex(where: { $0.id == anchorMessageID }) {
                tableView.scrollToRow(
                    at: IndexPath(row: index, section: 0),
                    at: .top,
                    animated: false
                )
            }
        case .latest:
            tableView.reloadData()
            scrollToBottom(animated: true)
        case .messageInserted:
            let inserted = IndexPath(row: messages.count - 1, section: 0)
            tableView.insertRows(at: [inserted], with: .fade)
            if wasNearBottom {
                scrollToBottom(animated: true)
            }
        case let .messageUpdated(index):
            tableView.reloadRows(at: [IndexPath(row: index, section: 0)], with: .none)
        case let .messageDeleted(index):
            tableView.deleteRows(at: [IndexPath(row: index, section: 0)], with: .fade)
        case .pins:
            break
        }
    }

    func isNearBottom() -> Bool {
        guard !messages.isEmpty else { return true }
        let visible = tableView.indexPathsForVisibleRows ?? []
        guard let lastVisible = visible.map(\.row).max() else { return true }
        return lastVisible >= messages.count - 3
    }
}
