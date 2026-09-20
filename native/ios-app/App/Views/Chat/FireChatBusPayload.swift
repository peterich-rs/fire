import Foundation

extension Notification.Name {
    static let fireChatMessageBusEvent = Notification.Name("fire.chat.messageBusEvent")
}

enum FireChatBusPayload {
    static func event(
        from busEvent: MessageBusEventState,
        fallbackChannelID: UInt64?,
        baseURLString: String
    ) -> ChatBusEventState {
        guard let payload = busEvent.payloadJson else {
            return .ignored
        }
        return chatBusEventFromPayload(
            payloadJson: payload,
            eventType: busEvent.detailEventType ?? busEvent.messageType,
            fallbackChannelId: fallbackChannelID ?? busEvent.topicId,
            baseUrl: baseURLString
        )
    }

    static func chatMessage(
        from event: MessageBusEventState,
        fallbackChannelID: UInt64?,
        baseURLString: String
    ) -> ChatMessageState? {
        switch Self.event(from: event, fallbackChannelID: fallbackChannelID, baseURLString: baseURLString) {
        case let .messageUpsert(message):
            return message
        default:
            guard let payload = event.payloadJson else { return nil }
            return chatMessageFromBusPayload(
                payloadJson: payload,
                fallbackChannelId: fallbackChannelID ?? event.topicId,
                baseUrl: baseURLString
            )
        }
    }

    static func channel(
        from event: MessageBusEventState,
        baseURLString: String
    ) -> ChatChannelState? {
        switch Self.event(from: event, fallbackChannelID: event.topicId, baseURLString: baseURLString) {
        case let .channelUpsert(channel):
            return channel
        default:
            guard let payload = event.payloadJson else { return nil }
            return chatChannelFromBusPayload(payloadJson: payload, baseUrl: baseURLString)
        }
    }
}
