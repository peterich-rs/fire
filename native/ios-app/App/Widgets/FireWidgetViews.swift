import SwiftUI
import WidgetKit

struct FireWidgetPanel<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        ZStack {
            Color.fireWidgetBackground
            content
                .padding(12)
        }
    }
}

struct FireWidgetEmptyView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Fire")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(Color.fireWidgetAccent)
            Text("Open Fire to load topics")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Color.fireWidgetSecondaryText)
                .lineLimit(2)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .accessibilityElement(children: .combine)
    }
}

struct FireWidgetTopicRow: View {
    let topic: FireWidgetTopicEntry
    var showsTimelineMarker = false

    var body: some View {
        Link(destination: URL(string: "fire://topic/\(topic.id)")!) {
            HStack(alignment: .top, spacing: 8) {
                if showsTimelineMarker {
                    VStack(spacing: 4) {
                        Circle()
                            .fill(Color(fireWidgetHex: topic.categoryColorHex))
                            .frame(width: 7, height: 7)
                        Rectangle()
                            .fill(Color.white.opacity(0.08))
                            .frame(width: 1)
                    }
                    .frame(width: 10)
                } else {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color(fireWidgetHex: topic.categoryColorHex))
                        .frame(width: 4)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(topic.title)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.fireWidgetPrimaryText)
                        .lineLimit(1)

                    HStack(spacing: 6) {
                        if !topic.categoryName.isEmpty {
                            Text(topic.categoryName)
                        }
                        if topic.replyCount > 0 {
                            Label("\(topic.replyCount)", systemImage: "bubble.right")
                        }
                        if topic.likeCount > 0 {
                            Label("\(topic.likeCount)", systemImage: "heart")
                        }
                        if let activityText = topic.activityText {
                            Text(activityText)
                        }
                    }
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Color.fireWidgetSecondaryText)
                    .lineLimit(1)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
    }

    private var accessibilityLabel: String {
        var parts = [topic.title]
        if !topic.categoryName.isEmpty {
            parts.append(topic.categoryName)
        }
        parts.append("\(topic.replyCount) replies")
        if topic.likeCount > 0 {
            parts.append("\(topic.likeCount) likes")
        }
        return parts.joined(separator: ", ")
    }
}

extension View {
    @ViewBuilder
    func fireWidgetContainerBackground() -> some View {
        if #available(iOSApplicationExtension 17.0, *) {
            self.containerBackground(for: .widget) {
                Color.fireWidgetBackground
            }
        } else {
            self.background(Color.fireWidgetBackground)
        }
    }
}

extension Color {
    static let fireWidgetBackground = Color(red: 0.05, green: 0.055, blue: 0.06)
    static let fireWidgetSurface = Color(red: 0.10, green: 0.105, blue: 0.115)
    static let fireWidgetAccent = Color(red: 0.96, green: 0.45, blue: 0.22)
    static let fireWidgetPrimaryText = Color(red: 0.96, green: 0.95, blue: 0.93)
    static let fireWidgetSecondaryText = Color(red: 0.65, green: 0.66, blue: 0.70)

    init(fireWidgetHex hex: String) {
        let cleaned = hex
            .trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
            .uppercased()
        guard cleaned.count == 6, let value = Int(cleaned, radix: 16) else {
            self = .fireWidgetAccent
            return
        }
        self.init(
            .sRGB,
            red: Double((value >> 16) & 0xFF) / 255.0,
            green: Double((value >> 8) & 0xFF) / 255.0,
            blue: Double(value & 0xFF) / 255.0,
            opacity: 1.0
        )
    }
}
