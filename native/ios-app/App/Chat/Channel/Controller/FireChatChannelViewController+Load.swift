import UIKit

extension FireChatChannelViewController {
    func applyCachedMessages() async {
        guard let cached = try? await viewModel.cachedChatMessages(
            channelID: channel.id,
            threadID: threadID
        ), !cached.messages.isEmpty else {
            return
        }
        messages = cached.messages.sorted { $0.id < $1.id }
        canLoadMorePast = cached.canLoadMorePast
        tableView.reloadData()
        scrollToBottom(animated: false)
    }

    func loadInitial() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            if !isThread {
                channel = try await viewModel.fetchChatChannel(channelID: channel.id)
                title = channel.displayTitle
                pins = try await viewModel.fetchChatChannelPins(channelID: channel.id)
                updatePinBanner()
                if !pins.isEmpty {
                    try? await viewModel.markChatChannelPinsRead(channelID: channel.id)
                }
            }
            let query = ChatMessagesQueryState(
                channelId: channel.id,
                direction: nil,
                targetMessageId: nil,
                fetchFromLastRead: true,
                pageSize: 50
            )
            let page: ChatMessagesState
            if let threadID {
                page = try await viewModel.fetchChatThreadMessages(
                    channelID: channel.id,
                    threadID: threadID,
                    query: query
                )
                try? await viewModel.markChatThreadRead(channelID: channel.id, threadID: threadID)
            } else {
                page = try await viewModel.fetchChatMessages(query: query)
            }
            // Chronological ascending (Discord channel log).
            messages = page.messages.sorted { $0.id < $1.id }
            canLoadMorePast = page.canLoadMorePast
            tableView.reloadData()
            scrollToBottom(animated: false)
            if let latest = messages.last?.id, !isThread {
                try? await viewModel.markChatChannelRead(channelID: channel.id, messageID: latest)
                onRead(channel.id)
            }
            let busName = threadID.map { "/chat/\(channel.id)/thread/\($0)" } ?? "/chat/\(channel.id)"
            let lastID = isThread ? nil : channel.busLastIds.channelMessageBusLastId
            try? await viewModel.subscribeMessageBusChannel(
                channel: busName,
                ownerToken: ownerToken,
                lastMessageId: lastID
            )
        } catch {
            presentError(error)
        }
    }

    func loadMorePast() async {
        guard canLoadMorePast, !isLoading, let oldest = messages.first else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let query = ChatMessagesQueryState(
                channelId: channel.id,
                direction: "past",
                targetMessageId: oldest.id,
                fetchFromLastRead: false,
                pageSize: 50
            )
            let page: ChatMessagesState
            if let threadID {
                page = try await viewModel.fetchChatThreadMessages(
                    channelID: channel.id,
                    threadID: threadID,
                    query: query
                )
            } else {
                page = try await viewModel.fetchChatMessages(query: query)
            }
            let older = page.messages.sorted { $0.id < $1.id }
            let anchorID = oldest.id
            messages = older + messages
            canLoadMorePast = page.canLoadMorePast
            tableView.reloadData()
            // Keep visual position after prepending history.
            if let index = messages.firstIndex(where: { $0.id == anchorID }) {
                tableView.scrollToRow(
                    at: IndexPath(row: index, section: 0),
                    at: .top,
                    animated: false
                )
            }
        } catch {
            presentError(error)
        }
    }

    func softRefreshLatest() async {
        do {
            let query = ChatMessagesQueryState(
                channelId: channel.id,
                direction: nil,
                targetMessageId: nil,
                fetchFromLastRead: false,
                pageSize: 50
            )
            let page: ChatMessagesState
            if let threadID {
                page = try await viewModel.fetchChatThreadMessages(
                    channelID: channel.id,
                    threadID: threadID,
                    query: query
                )
            } else {
                page = try await viewModel.fetchChatMessages(query: query)
            }
            messages = page.messages.sorted { $0.id < $1.id }
            canLoadMorePast = page.canLoadMorePast
            tableView.reloadData()
            scrollToBottom(animated: true)
            if let latest = messages.last?.id, !isThread {
                try? await viewModel.markChatChannelRead(channelID: channel.id, messageID: latest)
                onRead(channel.id)
            }
        } catch {
            // Keep bus path as primary; soft refresh failures are non-fatal.
        }
    }

    func scrollToBottom(animated: Bool) {
        guard !messages.isEmpty else { return }
        let index = IndexPath(row: messages.count - 1, section: 0)
        tableView.scrollToRow(at: index, at: .bottom, animated: animated)
    }
}
