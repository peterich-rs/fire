import UIKit

extension FireChatChannelViewController {
    func handleBusEvent(_ event: MessageBusEventState) {
        let expected = threadID.map { "/chat/\(channel.id)/thread/\($0)" } ?? "/chat/\(channel.id)"
        guard event.channel == expected else { return }
        let type = event.detailEventType ?? event.messageType
        let baseURLString = viewModel.bootstrapBaseURLString() ?? "https://linux.do"
        switch type {
        case "sent":
            if let message = FireChatBusPayload.chatMessage(
                from: event,
                fallbackChannelID: channel.id,
                baseURLString: baseURLString
            ) {
                upsertMessage(message, preferAppend: true)
            }
        case "edit", "processed", "refresh", "restore", "thread_created", "update_thread_original_message":
            if let message = FireChatBusPayload.chatMessage(
                from: event,
                fallbackChannelID: channel.id,
                baseURLString: baseURLString
            ) {
                upsertMessage(message, preferAppend: false)
            }
        case "delete":
            if case let .messageDeleted(deletedID) = FireChatBusPayload.event(
                from: event,
                fallbackChannelID: channel.id,
                baseURLString: baseURLString
            ),
               let index = messages.firstIndex(where: { $0.id == deletedID })
            {
                messages.remove(at: index)
                tableView.reloadData()
            }
        case "reaction":
            applyReaction(event)
        case "pin":
            if let message = FireChatBusPayload.chatMessage(
                from: event,
                fallbackChannelID: channel.id,
                baseURLString: baseURLString
            ) {
                pins = [message] + pins.filter { $0.id != message.id }
                updatePinBanner()
            }
        case "unpin":
            if let message = FireChatBusPayload.chatMessage(
                from: event,
                fallbackChannelID: channel.id,
                baseURLString: baseURLString
            ) {
                pins.removeAll { $0.id == message.id }
                updatePinBanner()
            }
        default:
            break
        }
    }

    func applyReaction(_ event: MessageBusEventState) {
        let baseURLString = viewModel.bootstrapBaseURLString() ?? "https://linux.do"
        guard case let .reaction(messageID, emoji, action, actorID) = FireChatBusPayload.event(
            from: event,
            fallbackChannelID: channel.id,
            baseURLString: baseURLString
        ),
              let index = messages.firstIndex(where: { $0.id == messageID })
        else {
            return
        }
        var message = messages[index]
        var reactions = message.reactions
        let isAdd = action == .add
        if let existing = reactions.firstIndex(where: { $0.emoji == emoji }) {
            let current = reactions[existing]
            let nextCount: UInt32
            let reacted: Bool
            if isAdd {
                nextCount = current.count &+ 1
                reacted = current.reacted || actorID == viewModel.currentUserID
            } else {
                nextCount = current.count > 0 ? current.count - 1 : 0
                reacted = false
            }
            if nextCount == 0 {
                reactions.remove(at: existing)
            } else {
                reactions[existing] = ChatMessageReactionState(
                    emoji: emoji,
                    count: nextCount,
                    reacted: reacted,
                    users: current.users
                )
            }
        } else if isAdd {
            reactions.append(
                ChatMessageReactionState(emoji: emoji, count: 1, reacted: true, users: [])
            )
        }
        message = withReactions(message, reactions)
        messages[index] = message
        tableView.reloadRows(at: [IndexPath(row: index, section: 0)], with: .none)
    }

    func upsertMessage(_ message: ChatMessageState, preferAppend: Bool) {
        if let index = messages.firstIndex(where: { $0.id == message.id }) {
            messages[index] = message
            tableView.reloadRows(at: [IndexPath(row: index, section: 0)], with: .none)
            return
        }
        guard preferAppend else { return }
        let wasNearBottom = isNearBottom()
        messages.append(message)
        tableView.insertRows(at: [IndexPath(row: messages.count - 1, section: 0)], with: .fade)
        if wasNearBottom {
            scrollToBottom(animated: true)
        }
    }

    func isNearBottom() -> Bool {
        guard !messages.isEmpty else { return true }
        let visible = tableView.indexPathsForVisibleRows ?? []
        guard let lastVisible = visible.map(\.row).max() else { return true }
        return lastVisible >= messages.count - 3
    }

    func withReactions(
        _ message: ChatMessageState,
        _ reactions: [ChatMessageReactionState]
    ) -> ChatMessageState {
        ChatMessageState(
            id: message.id,
            channelId: message.channelId,
            message: message.message,
            presentation: message.presentation,
            excerpt: message.excerpt,
            previewText: message.previewText,
            createdAt: message.createdAt,
            deletedAt: message.deletedAt,
            deletedById: message.deletedById,
            edited: message.edited,
            threadId: message.threadId,
            thread: message.thread,
            user: message.user,
            mentionedUsers: message.mentionedUsers,
            reactions: reactions,
            uploads: message.uploads,
            inReplyTo: message.inReplyTo,
            streaming: message.streaming,
            availableFlags: message.availableFlags,
            userFlagStatus: message.userFlagStatus,
            bookmark: message.bookmark,
            pinned: message.pinned,
            isDeleted: message.isDeleted
        )
    }
}
