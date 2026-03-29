import Foundation
import SwiftUI

struct FireTopicCategoryPresentation: Equatable, Sendable {
    let id: UInt64
    let name: String
    let slug: String
    let parentCategoryID: UInt64?
    let colorHex: String?
    let textColorHex: String?

    var displayName: String {
        name.isEmpty ? "Category #\(id)" : name
    }
}

struct FireTopicRowPresentation: Identifiable, Sendable {
    let topic: TopicSummaryState
    let excerptText: String?
    let lastPosterUsername: String?
    let activityTimestampText: String?
    let statusLabels: [String]
    let tagSummaryText: String?

    var id: UInt64 {
        topic.id
    }
}

struct FireTopicReplyPresentation: Identifiable, Sendable {
    let post: TopicPostState
    let depth: Int
    let parentPostNumber: UInt32?

    var id: UInt64 {
        post.id
    }
}

struct FireTopicReplySectionPresentation: Identifiable, Sendable {
    let anchorPost: TopicPostState
    let replies: [FireTopicReplyPresentation]

    var id: UInt64 {
        anchorPost.id
    }
}

struct FireTopicThreadPresentation: Sendable {
    let originalPost: TopicPostState?
    let replySections: [FireTopicReplySectionPresentation]
}

enum FireTopicPresentation {
    static func parseCategories(from preloadedJSON: String?) -> [UInt64: FireTopicCategoryPresentation] {
        guard
            let preloadedJSON,
            let data = preloadedJSON.data(using: .utf8),
            let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return [:]
        }

        let candidates: [Any?] = [
            (root["site"] as? [String: Any])?["categories"],
            (root["site"] as? [String: Any])?["category_list"],
            root["categories"],
            root["category_list"],
        ]

        let categories = candidates
            .compactMap { value -> [[String: Any]]? in
                if let dictionaries = value as? [[String: Any]] {
                    return dictionaries
                }
                if let dictionary = value as? [String: Any],
                   let nested = dictionary["categories"] as? [[String: Any]] {
                    return nested
                }
                if let array = value as? [Any] {
                    return array.compactMap { $0 as? [String: Any] }
                }
                return nil
            }
            .first ?? []

        return Dictionary(uniqueKeysWithValues: categories.compactMap { raw in
            guard let id = unsignedInteger(from: raw["id"]) else {
                return nil
            }

            return (
                id,
                FireTopicCategoryPresentation(
                    id: id,
                    name: stringValue(raw["name"]),
                    slug: stringValue(raw["slug"]),
                    parentCategoryID: unsignedInteger(from: raw["parent_category_id"]),
                    colorHex: stringValue(raw["color"]),
                    textColorHex: stringValue(raw["text_color"])
                )
            )
        })
    }

    static func nextPage(from moreTopicsURL: String?) -> UInt32? {
        guard let moreTopicsURL, !moreTopicsURL.isEmpty else {
            return nil
        }

        let candidates = [
            URLComponents(string: moreTopicsURL),
            URLComponents(string: "https://linux.do\(moreTopicsURL)"),
        ]

        for components in candidates {
            guard let queryItems = components?.queryItems else {
                continue
            }
            if let page = queryItems
                .first(where: { $0.name == "page" })?
                .value
                .flatMap(UInt32.init)
            {
                return page
            }
        }

        return nil
    }

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

    static func buildRowPresentations(from topics: [TopicSummaryState]) -> [FireTopicRowPresentation] {
        let timestampFormatter = TimestampFormatter()

        return topics.map { topic in
            let tagNames = tagNames(from: topic.tags)

            return FireTopicRowPresentation(
                topic: topic,
                excerptText: previewText(from: topic.excerpt),
                lastPosterUsername: topic.lastPosterUsername
                    ?? topic.posters.first?.description
                    ?? topic.posters.first.map { "User \($0.userId)" },
                activityTimestampText: timestampFormatter.format(topic.lastPostedAt ?? topic.createdAt),
                statusLabels: topicStatusLabels(for: topic),
                tagSummaryText: tagNames.isEmpty ? nil : "#\(tagNames.joined(separator: " #"))"
            )
        }
    }

    static func buildThreadPresentation(from posts: [TopicPostState]) -> FireTopicThreadPresentation {
        guard !posts.isEmpty else {
            return FireTopicThreadPresentation(originalPost: nil, replySections: [])
        }

        guard let originalPost = posts.min(by: { $0.postNumber < $1.postNumber }) else {
            return FireTopicThreadPresentation(originalPost: nil, replySections: [])
        }

        let rootPostNumber = originalPost.postNumber
        let postsByNumber = Dictionary(uniqueKeysWithValues: posts.map { ($0.postNumber, $0) })

        var childrenByParent: [UInt32: [TopicPostState]] = [:]
        for post in posts where post.postNumber != rootPostNumber {
            guard let parentPostNumber = normalizedReplyTarget(for: post),
                  parentPostNumber != post.postNumber
            else {
                continue
            }

            childrenByParent[parentPostNumber, default: []].append(post)
        }

        var consumedPostNumbers: Set<UInt32> = [rootPostNumber]
        var replySections: [FireTopicReplySectionPresentation] = []

        for post in posts where post.postNumber != rootPostNumber {
            guard !consumedPostNumbers.contains(post.postNumber) else {
                continue
            }

            let normalizedParent = normalizedReplyTarget(for: post)
            let shouldStartSection = normalizedParent == nil
                || normalizedParent == rootPostNumber
                || normalizedParent.map { postsByNumber[$0] == nil } == true

            guard shouldStartSection else {
                continue
            }

            consumedPostNumbers.insert(post.postNumber)
            var branchVisited: Set<UInt32> = [post.postNumber]
            let replies = flattenReplies(
                for: post.postNumber,
                depth: 1,
                childrenByParent: childrenByParent,
                consumedPostNumbers: &consumedPostNumbers,
                branchVisited: &branchVisited
            )
            replySections.append(
                FireTopicReplySectionPresentation(anchorPost: post, replies: replies)
            )
        }

        for post in posts where post.postNumber != rootPostNumber && !consumedPostNumbers.contains(post.postNumber) {
            consumedPostNumbers.insert(post.postNumber)
            var branchVisited: Set<UInt32> = [post.postNumber]
            let replies = flattenReplies(
                for: post.postNumber,
                depth: 1,
                childrenByParent: childrenByParent,
                consumedPostNumbers: &consumedPostNumbers,
                branchVisited: &branchVisited
            )
            replySections.append(
                FireTopicReplySectionPresentation(anchorPost: post, replies: replies)
            )
        }

        return FireTopicThreadPresentation(
            originalPost: originalPost,
            replySections: replySections
        )
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
        totalPostCount: Int
    ) -> [FlatPost] {
        var result: [FlatPost] = []

        if let originalPost = thread.originalPost {
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

            result.append(FlatPost(
                post: section.anchorPost,
                depth: 0,
                replyContext: nil,
                showsThreadLine: hasNestedReplies || !isLastSection
            ))

            for (replyIndex, reply) in section.replies.enumerated() {
                let isLastReply = replyIndex == section.replies.count - 1
                result.append(FlatPost(
                    post: reply.post,
                    depth: reply.depth,
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

    private static func normalizedReplyTarget(for post: TopicPostState) -> UInt32? {
        guard let replyToPostNumber = post.replyToPostNumber, replyToPostNumber > 0 else {
            return nil
        }

        return replyToPostNumber
    }

    private static func flattenReplies(
        for parentPostNumber: UInt32,
        depth: Int,
        childrenByParent: [UInt32: [TopicPostState]],
        consumedPostNumbers: inout Set<UInt32>,
        branchVisited: inout Set<UInt32>
    ) -> [FireTopicReplyPresentation] {
        guard let children = childrenByParent[parentPostNumber] else {
            return []
        }

        var flattened: [FireTopicReplyPresentation] = []
        for child in children {
            guard !branchVisited.contains(child.postNumber) else {
                continue
            }

            consumedPostNumbers.insert(child.postNumber)
            flattened.append(
                FireTopicReplyPresentation(
                    post: child,
                    depth: depth,
                    parentPostNumber: normalizedReplyTarget(for: child)
                )
            )

            branchVisited.insert(child.postNumber)
            flattened.append(
                contentsOf: flattenReplies(
                    for: child.postNumber,
                    depth: depth + 1,
                    childrenByParent: childrenByParent,
                    consumedPostNumbers: &consumedPostNumbers,
                    branchVisited: &branchVisited
                )
            )
            branchVisited.remove(child.postNumber)
        }

        return flattened
    }

    private static func stringValue(_ value: Any?) -> String {
        switch value {
        case let string as String:
            return string
        case let number as NSNumber:
            return number.stringValue
        default:
            return ""
        }
    }

    private static func unsignedInteger(from value: Any?) -> UInt64? {
        switch value {
        case let int as Int:
            return int >= 0 ? UInt64(int) : nil
        case let int64 as Int64:
            return int64 >= 0 ? UInt64(int64) : nil
        case let number as NSNumber:
            let raw = number.int64Value
            return raw >= 0 ? UInt64(raw) : nil
        case let string as String:
            return UInt64(string)
        default:
            return nil
        }
    }

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
