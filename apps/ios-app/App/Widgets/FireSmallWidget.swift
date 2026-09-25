import SwiftUI
import WidgetKit

struct FireSmallWidget: Widget {
    let kind = "FireSmallWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: FireWidgetProvider()) { entry in
            FireSmallWidgetView(entry: entry)
                .fireWidgetContainerBackground()
        }
        .configurationDisplayName("Fire Unread")
        .description("View unread notifications and the latest topic.")
        .supportedFamilies([.systemSmall])
    }
}

struct FireSmallWidgetView: View {
    let entry: FireWidgetEntry

    var body: some View {
        FireWidgetPanel {
            if let data = entry.data {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .center) {
                        Text("Fire")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(Color.fireWidgetAccent)
                        Spacer(minLength: 0)
                        if data.unreadNotificationCount > 0 {
                            Text("\(data.unreadNotificationCount)")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(Color.fireWidgetAccent, in: Capsule())
                        }
                    }

                    if let topic = data.recentTopics.first {
                        Link(destination: URL(string: "fire://topic/\(topic.id)")!) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(topic.title)
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(Color.fireWidgetPrimaryText)
                                    .lineLimit(2)
                                Text(topic.categoryName.isEmpty ? "Latest topic" : topic.categoryName)
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(Color.fireWidgetSecondaryText)
                                    .lineLimit(1)
                            }
                        }
                        .buttonStyle(.plain)
                    } else {
                        Text(data.unreadNotificationCount == 0 ? "All caught up" : "View notifications")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(Color.fireWidgetPrimaryText)
                            .lineLimit(2)
                    }

                    Spacer(minLength: 0)

                    Link(destination: URL(string: "fire://notifications")!) {
                        Label("Notifications", systemImage: "bell")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Color.fireWidgetAccent)
                    }
                    .buttonStyle(.plain)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel(accessibilityLabel(for: data))
            } else {
                FireWidgetEmptyView()
            }
        }
    }

    private func accessibilityLabel(for data: FireWidgetData) -> String {
        if data.unreadNotificationCount == 0 {
            return "Fire, no unread notifications"
        }
        return "Fire, \(data.unreadNotificationCount) unread notifications"
    }
}
