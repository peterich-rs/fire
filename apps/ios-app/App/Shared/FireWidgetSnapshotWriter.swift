import Foundation
import WidgetKit

@MainActor
enum FireWidgetSnapshotWriter {
    private static let topicLimit = 5

    static func update(
        session: SessionState,
        topicRows: [FireTopicRowPresentation],
        unreadNotificationCount: Int
    ) {
        let data = FireWidgetData(
            unreadNotificationCount: max(unreadNotificationCount, 0),
            recentTopics: topicRows.prefix(topicLimit).map { entry(for: $0, session: session) },
            username: session.bootstrap.currentUsername ?? "",
            updatedAt: Date().timeIntervalSince1970
        )
        data.save()
        WidgetCenter.shared.reloadAllTimelines()
    }

    static func clear() {
        FireWidgetData.empty.save()
        WidgetCenter.shared.reloadAllTimelines()
    }

    private static func entry(
        for row: FireTopicRowPresentation,
        session: SessionState
    ) -> FireWidgetTopicEntry {
        let category = row.topic.categoryId.flatMap { categoryID in
            session.bootstrap.categories.first { $0.id == categoryID }
        }
        let fallbackCategory = row.topic.categoryId.map { "Category #\($0)" } ?? ""
        return FireWidgetTopicEntry(
            id: row.topic.id,
            title: row.topic.title,
            categoryName: category?.displayName ?? fallbackCategory,
            categoryColorHex: normalizedColorHex(category?.colorHex),
            replyCount: Int(row.topic.replyCount),
            likeCount: Int(row.topic.likeCount),
            activityTimestampUnixMs: row.activityTimestampUnixMs,
            activityText: FireTopicPresentation.compactTimestamp(unixMs: row.activityTimestampUnixMs)
        )
    }

    private static func normalizedColorHex(_ rawValue: String?) -> String {
        let cleaned = rawValue?
            .trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
            .uppercased()
        guard let cleaned, cleaned.count == 6, Int(cleaned, radix: 16) != nil else {
            return "#F57338"
        }
        return "#\(cleaned)"
    }
}
