import Foundation

enum FireNotificationsCollectionSection: Hashable {
    case content
}

enum FireNotificationsCollectionItem: Hashable {
    case blockingError(String)
    case loading
    case empty
    case offlineBanner
    case inlineErrorBanner(String)
    case notification(UInt64)
    case historyLink
}

enum FireNotificationHistoryCollectionSection: Hashable {
    case content
}

enum FireNotificationHistoryCollectionItem: Hashable {
    case blockingError(String)
    case loading
    case empty
    case offlineBanner
    case inlineErrorBanner(String)
    case notification(UInt64)
    case retryFooter
    case loadingMore
}

struct FireNotificationItemContentToken: Hashable {
    let id: UInt64
    let read: Bool
    let highPriority: Bool
    let description: String
    let timestamp: String?
    let avatarTemplate: String?
    let typeSystemImage: String
    let routeID: String?

    init(_ item: NotificationItemState) {
        id = item.id
        read = item.read
        highPriority = item.highPriority
        description = item.displayDescription
        timestamp = FireTopicPresentation.compactTimestamp(item.createdAt)
            ?? FireTopicPresentation.compactTimestamp(unixMs: item.createdTimestampUnixMs)
        avatarTemplate = item.actingUserAvatarTemplate ?? item.data.avatarTemplate
        typeSystemImage = item.typeSystemImage
        routeID = item.appRoute?.id
    }
}
