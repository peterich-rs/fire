import Foundation

extension Notification.Name {
    static let fireChatMessageBusEvent = Notification.Name("fire.chat.messageBusEvent")
}

enum FireChatBusPayload {
    static func jsonObject(from event: MessageBusEventState) -> [String: Any]? {
        guard let payload = event.payloadJson,
              let data = payload.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return nil
        }
        return object
    }

    static func chatMessage(from event: MessageBusEventState, fallbackChannelID: UInt64?) -> ChatMessageState? {
        guard let object = jsonObject(from: event) else { return nil }
        let raw = (object["chat_message"] as? [String: Any])
            ?? (object["message"] as? [String: Any])
        guard let raw else { return nil }
        return parseMessage(raw, fallbackChannelID: fallbackChannelID ?? event.topicId)
    }

    static func parseMessage(_ raw: [String: Any], fallbackChannelID: UInt64?) -> ChatMessageState {
        let id = uint64(raw["id"]) ?? 0
        let channelID = uint64(raw["chat_channel_id"])
            ?? uint64(raw["channel_id"])
            ?? fallbackChannelID
            ?? 0
        let userObject = raw["user"] as? [String: Any]
        let reactions = (raw["reactions"] as? [[String: Any]] ?? []).map { item in
            ChatMessageReactionState(
                emoji: string(item["emoji"]) ?? "",
                count: uint32(item["count"]) ?? 0,
                reacted: bool(item["reacted"]),
                users: []
            )
        }
        // Bus payloads only need presence of attachments for preview; full metadata
        // arrives on REST reloads. Avoid reserved-keyword field construction here.
        let uploads: [ChatUploadState] = []
        let hasUploads = !(raw["uploads"] as? [Any] ?? []).isEmpty
        let message = string(raw["message"]) ?? ""
        let cooked = string(raw["cooked"]) ?? ""
        let excerpt = string(raw["excerpt"])
        let preview = excerpt?.isEmpty == false
            ? excerpt!
            : (message.isEmpty ? (hasUploads ? "[附件]" : "") : message)
        return ChatMessageState(
            id: id,
            channelId: channelID,
            message: message,
            cooked: cooked,
            excerpt: excerpt,
            previewText: preview,
            createdAt: string(raw["created_at"]),
            deletedAt: string(raw["deleted_at"]),
            deletedById: uint64(raw["deleted_by_id"]),
            edited: bool(raw["edited"]),
            threadId: uint64(raw["thread_id"]),
            thread: nil,
            user: userObject.map {
                ChatUserState(
                    id: uint64($0["id"]) ?? 0,
                    username: string($0["username"]) ?? "",
                    name: string($0["name"]),
                    avatarTemplate: string($0["avatar_template"])
                )
            },
            mentionedUsers: [],
            reactions: reactions,
            uploads: uploads,
            inReplyTo: nil,
            streaming: bool(raw["streaming"]),
            availableFlags: [],
            userFlagStatus: nil,
            bookmark: nil,
            pinned: bool(raw["pinned"]),
            isDeleted: string(raw["deleted_at"]) != nil
        )
    }

    static func channel(from object: [String: Any]) -> ChatChannelState? {
        guard let id = uint64(object["id"]) else { return nil }
        let chatable = object["chatable"] as? [String: Any]
        let membership = object["current_user_membership"] as? [String: Any]
        let title = string(object["title"])
        let unicodeTitle = string(object["unicode_title"])
        let display = (unicodeTitle?.isEmpty == false ? unicodeTitle : title) ?? "#\(id)"
        let chatableType = string(object["chatable_type"]) ?? ""
        let isDM = chatableType.caseInsensitiveCompare("DirectMessage") == .orderedSame
        let dmUsers = (chatable?["users"] as? [[String: Any]] ?? []).map {
            ChatUserState(
                id: uint64($0["id"]) ?? 0,
                username: string($0["username"]) ?? "",
                name: string($0["name"]),
                avatarTemplate: string($0["avatar_template"])
            )
        }
        let lastRaw = object["last_message"] as? [String: Any]
        let lastMessage: ChatMessageState? = {
            guard let lastRaw, lastRaw["id"] != nil else { return nil }
            return parseMessage(lastRaw, fallbackChannelID: id)
        }()
        return ChatChannelState(
            id: id,
            title: title,
            unicodeTitle: unicodeTitle,
            displayTitle: display,
            slug: string(object["slug"]),
            description: string(object["description"]),
            chatableType: chatableType,
            status: string(object["status"]),
            threadingEnabled: bool(object["threading_enabled"]),
            membershipsCount: uint32(object["memberships_count"]),
            isGroupDm: bool(chatable?["group"]),
            isDirectMessage: isDM,
            isPublicChannel: chatableType.caseInsensitiveCompare("Category") == .orderedSame,
            dmUsers: dmUsers,
            categoryColor: string(chatable?["color"]),
            categoryName: string(chatable?["name"]),
            emoji: string(object["emoji"]),
            currentUserMembership: membership.map {
                ChatChannelMembershipState(
                    following: bool($0["following"]),
                    muted: bool($0["muted"]),
                    starred: bool($0["starred"]),
                    notificationLevel: string($0["notification_level"]),
                    lastReadMessageId: uint64($0["last_read_message_id"]),
                    lastViewedAt: string($0["last_viewed_at"])
                )
            },
            lastMessage: lastMessage,
            busLastIds: ChatChannelBusLastIdsState(
                channelMessageBusLastId: nil,
                newMessages: nil,
                newMentions: nil,
                kick: nil
            ),
            canModerate: false,
            canManagePins: false,
            canDeleteSelf: false,
            canDeleteOthers: false,
            canRemoveMembers: false,
            canFlag: false
        )
    }

    private static func string(_ value: Any?) -> String? {
        switch value {
        case let value as String:
            return value
        case let value as NSNumber:
            return value.stringValue
        default:
            return nil
        }
    }

    private static func bool(_ value: Any?) -> Bool {
        switch value {
        case let value as Bool:
            return value
        case let value as NSNumber:
            return value.boolValue
        case let value as String:
            return value == "true" || value == "1"
        default:
            return false
        }
    }

    private static func uint64(_ value: Any?) -> UInt64? {
        switch value {
        case let value as UInt64:
            return value
        case let value as Int:
            return value >= 0 ? UInt64(value) : nil
        case let value as NSNumber:
            return value.uint64Value
        case let value as String:
            return UInt64(value)
        default:
            return nil
        }
    }

    private static func uint32(_ value: Any?) -> UInt32? {
        guard let number = uint64(value), number <= UInt64(UInt32.max) else { return nil }
        return UInt32(number)
    }
}
