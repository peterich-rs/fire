import SwiftUI
import WidgetKit

struct FireLargeWidget: Widget {
    let kind = "FireLargeWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: FireWidgetProvider()) { entry in
            FireLargeWidgetView(entry: entry)
                .fireWidgetContainerBackground()
        }
        .configurationDisplayName("Fire Timeline")
        .description("View a timeline of recent topics and unread notifications.")
        .supportedFamilies([.systemLarge])
    }
}

struct FireLargeWidgetView: View {
    let entry: FireWidgetEntry

    var body: some View {
        FireWidgetPanel {
            if let data = entry.data, !data.recentTopics.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Fire")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(Color.fireWidgetAccent)
                        Spacer(minLength: 0)
                        if data.unreadNotificationCount > 0 {
                            Link(destination: URL(string: "fire://notifications")!) {
                                Label("\(data.unreadNotificationCount)", systemImage: "bell.fill")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundStyle(Color.fireWidgetAccent)
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    Divider()
                        .overlay(Color.white.opacity(0.08))

                    ForEach(data.recentTopics.prefix(5)) { topic in
                        FireWidgetTopicRow(topic: topic, showsTimelineMarker: true)
                    }
                }
            } else {
                FireWidgetEmptyView()
            }
        }
    }
}
