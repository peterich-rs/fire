import Foundation

struct FireWidgetTopicEntry: Codable, Identifiable, Hashable {
    var id: UInt64
    var title: String
    var categoryName: String
    var categoryColorHex: String
    var replyCount: Int
    var likeCount: Int
    var activityTimestampUnixMs: UInt64?
    var activityText: String?
}

struct FireWidgetData: Codable, Hashable {
    var unreadNotificationCount: Int
    var recentTopics: [FireWidgetTopicEntry]
    var username: String
    var updatedAt: TimeInterval

    static let appGroupName = "group.com.fire.app"
    static let sharedDefaultsSuite = appGroupName
    static let widgetDataKey = "fire_widget_data"

    static var empty: FireWidgetData {
        FireWidgetData(
            unreadNotificationCount: 0,
            recentTopics: [],
            username: "",
            updatedAt: Date().timeIntervalSince1970
        )
    }

    static var placeholder: FireWidgetData {
        FireWidgetData(
            unreadNotificationCount: 3,
            recentTopics: [
                FireWidgetTopicEntry(
                    id: 1,
                    title: "Fire Native rebuild progress",
                    categoryName: "Dev",
                    categoryColorHex: "#F57338",
                    replyCount: 12,
                    likeCount: 5,
                    activityTimestampUnixMs: UInt64(Date().timeIntervalSince1970 * 1000),
                    activityText: "now"
                )
            ],
            username: "Fire",
            updatedAt: Date().timeIntervalSince1970
        )
    }

    static var sharedDefaults: UserDefaults? {
        UserDefaults(suiteName: sharedDefaultsSuite)
    }

    static func load() -> FireWidgetData? {
        guard let data = sharedDefaults?.data(forKey: widgetDataKey) else {
            return nil
        }
        return try? JSONDecoder().decode(FireWidgetData.self, from: data)
    }

    func save() {
        guard let data = try? JSONEncoder().encode(self) else {
            return
        }
        Self.sharedDefaults?.set(data, forKey: Self.widgetDataKey)
    }
}
