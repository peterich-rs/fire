import Foundation
import SwiftUI

typealias FireTopicCategoryPresentation = TopicCategoryState
typealias FireTopicRowPresentation = TopicRowState
typealias FireTopicReplyPresentation = TopicThreadReplyState
typealias FireTopicReplySectionPresentation = TopicThreadSectionState
typealias FireTopicThreadPresentation = TopicThreadState

extension TopicCategoryState {
    var displayName: String {
        name.isEmpty ? "Category #\(id)" : name
    }
}

struct FireCookedImage: Identifiable, Hashable, Sendable {
    let url: URL
    let altText: String?
    let width: CGFloat?
    let height: CGFloat?

    var id: String { url.absoluteString }

    var aspectRatio: CGFloat? {
        guard let width, let height, width > 0, height > 0 else {
            return nil
        }
        return width / height
    }
}

struct FireReactionOption: Identifiable, Hashable, Sendable {
    let id: String
    let symbol: String
    let label: String
}

enum FireTopicPresentation {
    static func formatTimestamp(_ rawValue: String?) -> String? {
        guard let rawValue, !rawValue.isEmpty else {
            return nil
        }

        let date = fractionalISO8601.date(from: rawValue) ?? basicISO8601.date(from: rawValue)
        guard let date else {
            return rawValue
        }
        return displayFormatter.string(from: date)
    }

    static func compactTimestamp(_ rawValue: String?) -> String? {
        TimestampFormatter(style: .compact).format(rawValue)
    }

    static func compactTimestamp(unixMs: UInt64?) -> String? {
        guard let unixMs else {
            return nil
        }
        return TimestampFormatter(style: .compact).format(
            date: Date(timeIntervalSince1970: Double(unixMs) / 1000.0)
        )
    }

    static func compactCount(_ value: UInt32) -> String {
        compactCount(UInt64(value))
    }

    static func plainText(from html: String) -> String {
        guard !html.isEmpty else {
            return ""
        }

        let normalized = html
            .replacingOccurrences(of: "<br\\s*/?>", with: "\n", options: .regularExpression)
            .replacingOccurrences(of: "</p>", with: "\n\n", options: .regularExpression)
            .replacingOccurrences(of: "</li>", with: "\n", options: .regularExpression)
        let stripped = normalized
            .replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
        return normalizeWhitespace(in: decodeCommonEntities(in: stripped))
    }

    static func previewText(from html: String?) -> String? {
        guard let html, !html.isEmpty else {
            return nil
        }

        let compact = normalizeWhitespace(in: plainText(from: html).replacingOccurrences(of: "\n", with: " "))
        return compact.isEmpty ? nil : compact
    }

    static func attributedText(from html: String) -> AttributedString? {
        guard !html.isEmpty else {
            return nil
        }

        let normalized = html
            .replacingOccurrences(of: "<img\\b[^>]*>", with: "", options: .regularExpression)
            .replacingOccurrences(of: "<br\\s*/?>", with: "<br />", options: .regularExpression)

        guard let data = normalized.data(using: .utf8),
              let attributed = try? NSAttributedString(
                  data: data,
                  options: [
                      .documentType: NSAttributedString.DocumentType.html,
                      .characterEncoding: String.Encoding.utf8.rawValue,
                  ],
                  documentAttributes: nil
              )
        else {
            return nil
        }

        return AttributedString(attributed)
    }

    static func imageAttachments(from html: String, baseURLString: String) -> [FireCookedImage] {
        guard !html.isEmpty else {
            return []
        }

        let nsRange = NSRange(html.startIndex..., in: html)
        let tags = imageTagRegex.matches(in: html, range: nsRange)
        var images: [FireCookedImage] = []
        var seenURLs: Set<String> = []

        for match in tags {
            guard let range = Range(match.range, in: html) else {
                continue
            }

            let tag = String(html[range])
            let classes = attributeValue(named: "class", in: tag)?
                .split(separator: " ")
                .map(String.init) ?? []
            if classes.contains(where: { $0.caseInsensitiveCompare("emoji") == .orderedSame }) {
                continue
            }

            guard
                let rawSource = attributeValue(named: "src", in: tag),
                let sourceURL = resolvedAssetURL(from: rawSource, baseURLString: baseURLString)
            else {
                continue
            }

            let absoluteURL = sourceURL.absoluteString
            if absoluteURL.contains("/images/emoji/") || seenURLs.contains(absoluteURL) {
                continue
            }

            seenURLs.insert(absoluteURL)
            images.append(
                FireCookedImage(
                    url: sourceURL,
                    altText: attributeValue(named: "alt", in: tag),
                    width: attributeValue(named: "width", in: tag).flatMap(Double.init).map { CGFloat($0) },
                    height: attributeValue(named: "height", in: tag).flatMap(Double.init).map { CGFloat($0) }
                )
            )
        }

        return images
    }

    static func minimumReplyLength(from minPostLength: UInt32) -> Int {
        max(Int(minPostLength), 1)
    }

    static func enabledReactionOptions(from reactionIDs: [String]) -> [FireReactionOption] {
        let ids = reactionIDs.isEmpty ? ["heart"] : reactionIDs
        return ids.reduce(into: [FireReactionOption]()) { result, reactionID in
            guard !result.contains(where: { $0.id == reactionID }) else {
                return
            }
            result.append(reactionOption(for: reactionID))
        }
    }

    static func reactionOption(for reactionID: String) -> FireReactionOption {
        let normalized = reactionID.lowercased()
        let mapping: [String: (String, String)] = [
            "heart": ("❤️", "点赞"),
            "+1": ("👍", "赞同"),
            "-1": ("👎", "反对"),
            "thumbsup": ("👍", "赞同"),
            "laughing": ("😆", "笑哭"),
            "open_mouth": ("😮", "惊讶"),
            "cry": ("😢", "难过"),
            "angry": ("😡", "生气"),
            "confused": ("😕", "困惑"),
            "clap": ("👏", "鼓掌"),
            "tada": ("🎉", "庆祝"),
        ]
        let fallbackLabel = normalized.replacingOccurrences(of: "_", with: " ")
        let (symbol, label) = mapping[normalized] ?? ("🙂", fallbackLabel)
        return FireReactionOption(id: reactionID, symbol: symbol, label: label)
    }

    /// A flattened post ready for display in a list, carrying its nesting depth
    /// and optional reply-context label.
    struct FlatPost: Identifiable, Sendable {
        let post: TopicPostState
        let depth: Int
        let replyContext: String?
        let showsThreadLine: Bool

        var id: UInt64 { post.id }
    }

    /// Flattens a `FireTopicThreadPresentation` into a display-order list.
    ///
    /// The original post comes first, then each reply section's anchor post
    /// (at depth 0) followed by its nested replies (at increasing depth).
    /// This preserves the section anchor's original order in the stream while
    /// visually grouping nested replies underneath.
    static func flattenThreadForDisplay(
        from thread: FireTopicThreadPresentation,
        postsByNumber: [UInt32: TopicPostState]
    ) -> [FlatPost] {
        var result: [FlatPost] = []

        if let originalPost = thread.originalPostNumber.flatMap({ postsByNumber[$0] }) {
            result.append(FlatPost(
                post: originalPost,
                depth: 0,
                replyContext: nil,
                showsThreadLine: !thread.replySections.isEmpty
            ))
        }

        for (sectionIndex, section) in thread.replySections.enumerated() {
            let isLastSection = sectionIndex == thread.replySections.count - 1
            let hasNestedReplies = !section.replies.isEmpty

            guard let anchorPost = postsByNumber[section.anchorPostNumber] else {
                continue
            }

            result.append(FlatPost(
                post: anchorPost,
                depth: 0,
                replyContext: nil,
                showsThreadLine: hasNestedReplies || !isLastSection
            ))

            for (replyIndex, reply) in section.replies.enumerated() {
                guard let replyPost = postsByNumber[reply.postNumber] else {
                    continue
                }
                let isLastReply = replyIndex == section.replies.count - 1
                result.append(FlatPost(
                    post: replyPost,
                    depth: Int(reply.depth),
                    replyContext: reply.parentPostNumber.map { "回复 #\($0)" },
                    showsThreadLine: !isLastReply || !isLastSection
                ))
            }
        }

        return result
    }

    static func topicStatusLabels(for topic: TopicSummaryState) -> [String] {
        var labels: [String] = []

        if topic.pinned {
            labels.append("Pinned")
        }
        if topic.closed {
            labels.append("Closed")
        }
        if topic.archived {
            labels.append("Archived")
        }
        if topic.hasAcceptedAnswer {
            labels.append("Solved")
        }
        if topic.unreadPosts > 0 {
            labels.append("Unread \(topic.unreadPosts)")
        }
        if topic.newPosts > 0 {
            labels.append("New \(topic.newPosts)")
        }

        return labels
    }

    static func tagNames(from tags: [TopicTagState]) -> [String] {
        tags.compactMap { tag in
            if !tag.name.isEmpty {
                return tag.name
            }
            return tag.slug?.isEmpty == false ? tag.slug : nil
        }
    }

    static func monogram(for username: String) -> String {
        let scalars = username
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .compactMap { component in component.first }
        let letters = scalars.prefix(2).map { String($0).uppercased() }
        if !letters.isEmpty {
            return letters.joined()
        }

        return String(username.prefix(1)).uppercased()
    }

    private static func compactCount(_ value: UInt64) -> String {
        switch value {
        case 0..<1_000:
            return "\(value)"
        case 1_000..<10_000:
            return compactCountSegment(Double(value), divisor: 1_000, suffix: "k")
        case 10_000..<100_000_000:
            return compactCountSegment(Double(value), divisor: 10_000, suffix: "万")
        default:
            return compactCountSegment(Double(value), divisor: 100_000_000, suffix: "亿")
        }
    }

    private static func compactCountSegment(_ value: Double, divisor: Double, suffix: String) -> String {
        let compact = value / divisor
        let formatted: String

        if compact >= 10 {
            formatted = String(format: "%.0f", compact.rounded())
        } else {
            formatted = String(format: "%.1f", compact)
        }

        return formatted.replacingOccurrences(of: ".0", with: "") + suffix
    }

    private static let fractionalISO8601: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let basicISO8601: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    private static let displayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()

    private static let imageTagRegex = try! NSRegularExpression(
        pattern: #"<img\b[^>]*>"#,
        options: [.caseInsensitive]
    )

    private static func normalizeWhitespace(in string: String) -> String {
        string
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\n{3,}", with: "\n\n", options: .regularExpression)
            .replacingOccurrences(of: "[ \\t]{2,}", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func decodeCommonEntities(in string: String) -> String {
        var decoded = string
        let entities = [
            ("&nbsp;", " "),
            ("&#160;", " "),
            ("&amp;", "&"),
            ("&quot;", "\""),
            ("&#34;", "\""),
            ("&#39;", "'"),
            ("&#x27;", "'"),
            ("&lt;", "<"),
            ("&gt;", ">"),
        ]

        for (entity, replacement) in entities {
            decoded = decoded.replacingOccurrences(of: entity, with: replacement)
        }

        return decoded
    }

    private static func attributeValue(named name: String, in tag: String) -> String? {
        let escapedName = NSRegularExpression.escapedPattern(for: name)
        let pattern = #"(?i)\b\#(escapedName)\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s>]+))"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return nil
        }

        let range = NSRange(tag.startIndex..., in: tag)
        guard let match = regex.firstMatch(in: tag, range: range) else {
            return nil
        }

        for index in 1...3 {
            let capture = match.range(at: index)
            guard
                capture.location != NSNotFound,
                let captureRange = Range(capture, in: tag)
            else {
                continue
            }
            return decodeCommonEntities(in: String(tag[captureRange]))
        }

        return nil
    }

    private static func resolvedAssetURL(from rawValue: String, baseURLString: String) -> URL? {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return nil
        }

        if trimmed.hasPrefix("//") {
            return URL(string: "https:\(trimmed)")
        }

        if let absoluteURL = URL(string: trimmed), absoluteURL.scheme != nil {
            return absoluteURL
        }

        return URL(string: trimmed, relativeTo: URL(string: baseURLString))?.absoluteURL
    }
}

private struct TimestampFormatter {
    private let fractionalISO8601: ISO8601DateFormatter
    private let basicISO8601: ISO8601DateFormatter
    private let style: Style

    enum Style {
        case full
        case compact
    }

    init(style: Style = .full) {
        self.style = style

        let fractionalISO8601 = ISO8601DateFormatter()
        fractionalISO8601.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        self.fractionalISO8601 = fractionalISO8601

        let basicISO8601 = ISO8601DateFormatter()
        basicISO8601.formatOptions = [.withInternetDateTime]
        self.basicISO8601 = basicISO8601
    }

    func format(_ rawValue: String?) -> String? {
        guard let rawValue, !rawValue.isEmpty else {
            return nil
        }

        let date = fractionalISO8601.date(from: rawValue) ?? basicISO8601.date(from: rawValue)
        guard let date else {
            return rawValue
        }

        return format(date: date)
    }

    func format(date: Date) -> String {
        switch style {
        case .full:
            return Self.fullFormatter.string(from: date)
        case .compact:
            return Self.compactFormatter.localizedString(for: date, relativeTo: Date())
        }
    }

    private static let fullFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()

    private static let compactFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter
    }()
}

extension Color {
    init?(fireHex hex: String?) {
        guard let hex else {
            return nil
        }

        let cleaned = hex
            .trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
            .uppercased()
        guard cleaned.count == 6, let value = Int(cleaned, radix: 16) else {
            return nil
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
