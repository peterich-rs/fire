import Foundation
import UIKit
import WebKit

extension FireAppViewModel {
    func updateWidgetData() {
        guard session.readiness.canReadAuthenticatedApi else {
            FireWidgetSnapshotWriter.clear()
            return
        }
        FireWidgetSnapshotWriter.update(
            session: session,
            topicRows: homeFeedStore?.topicRows ?? [],
            unreadNotificationCount: notificationStore?.unreadCount ?? 0
        )
    }

    // MARK: - Lifecycle

    var boundTopicDetailStore: FireTopicDetailStore? {
        topicDetailStore
    }
}
