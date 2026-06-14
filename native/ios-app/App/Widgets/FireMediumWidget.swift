import SwiftUI
import WidgetKit

struct FireMediumWidget: Widget {
    let kind = "FireMediumWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: FireWidgetProvider()) { entry in
            FireMediumWidgetView(entry: entry)
                .fireWidgetContainerBackground()
        }
        .configurationDisplayName("Fire Topics")
        .description("View recent Fire topics.")
        .supportedFamilies([.systemMedium])
    }
}

struct FireMediumWidgetView: View {
    let entry: FireWidgetEntry

    var body: some View {
        FireWidgetPanel {
            if let data = entry.data, !data.recentTopics.isEmpty {
                VStack(alignment: .leading, spacing: 7) {
                    HStack {
                        Text("Fire Topics")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(Color.fireWidgetAccent)
                        Spacer(minLength: 0)
                        if !data.username.isEmpty {
                            Text(data.username)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(Color.fireWidgetSecondaryText)
                                .lineLimit(1)
                        }
                    }

                    Divider()
                        .overlay(Color.white.opacity(0.08))

                    ForEach(data.recentTopics.prefix(3)) { topic in
                        FireWidgetTopicRow(topic: topic)
                    }
                }
            } else {
                FireWidgetEmptyView()
            }
        }
    }
}
