import UIKit

extension FireChatChannelViewController {
    func loadMorePast() async {
        do {
            _ = try await session.command(.loadMorePast)
        } catch {
            presentError(error)
        }
    }

    func scrollToBottom(animated: Bool) {
        guard !messages.isEmpty else { return }
        let index = IndexPath(row: messages.count - 1, section: 0)
        tableView.scrollToRow(at: index, at: .bottom, animated: animated)
    }
}
