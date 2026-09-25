import UIKit

extension FireChatChannelViewController {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        messages.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(
            withIdentifier: FireChatMessageCell.reuseID,
            for: indexPath
        ) as! FireChatMessageCell
        let message = messages[indexPath.row]
        let previous = indexPath.row > 0 ? messages[indexPath.row - 1] : nil
        let grouped = FireChatTime.shouldGroup(previous: previous, current: message)
        cell.configure(
            message: message,
            groupedWithPrevious: grouped,
            baseURLString: viewModel.bootstrapBaseURLString()
        )
        cell.onThreadTap = { [weak self] in
            guard let self else { return }
            Task { await self.openThread(for: message) }
        }
        cell.onProfileTap = { [weak self] in
            guard let self, let username = message.user?.username, !username.isEmpty else { return }
            FireUserCard.present(from: self, viewModel: self.viewModel, username: username)
        }
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        presentMessageActions(for: messages[indexPath.row])
    }

    func tableView(
        _ tableView: UITableView,
        willDisplay cell: UITableViewCell,
        forRowAt indexPath: IndexPath
    ) {
        // Load older history when scrolling toward the top of the channel log.
        if indexPath.row <= 2 {
            Task { await loadMorePast() }
        }
    }
}
