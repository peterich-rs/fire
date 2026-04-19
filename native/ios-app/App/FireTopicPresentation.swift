import Foundation
import SwiftUI

typealias FireTopicCategoryPresentation = TopicCategoryState
typealias FireTopicRowPresentation = TopicRowState

struct FireTopicTimelineEntry: Hashable, Sendable {
    let postId: UInt64
    let postNumber: UInt32
    let parentPostNumber: UInt32?
    let depth: UInt32
    let isOriginalPost: Bool
}

struct FireTopicTimelineRow: Identifiable {
    let entry: FireTopicTimelineEntry
    let post: TopicPostState?
    var id: UInt64 { entry.postId }
    var isLoaded: Bool { post != nil }
}

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

struct FireTopicPostRenderContent: Sendable {
    let plainText: String
    let imageAttachments: [FireCookedImage]
}

struct FirePreparedTopicTimelineRow: Identifiable, Sendable {
    let entry: FireTopicTimelineEntry

    var id: UInt64 { entry.postId }
}

struct FireTopicDetailRenderState: Sendable {
    let originalRow: FirePreparedTopicTimelineRow?
    let replyRows: [FirePreparedTopicTimelineRow]
    let contentByPostID: [UInt64: FireTopicPostRenderContent]
}

struct FireReactionOption: Identifiable, Hashable, Sendable {
    let id: String
    let symbol: String
    let label: String
}

enum FireTopicPresentation {
    static func isPrivateMessageArchetype(_ archetype: String?) -> Bool {
        let trimmed = archetype?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmed.isEmpty else {
            return false
        }
        return trimmed.caseInsensitiveCompare("private_message") == .orderedSame
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

    static func renderContent(from html: String, baseURLString: String) -> FireTopicPostRenderContent {
        FireTopicPostRenderContent(
            plainText: plainTextFromHtml(rawHtml: html),
            imageAttachments: imageAttachments(from: html, baseURLString: baseURLString)
        )
    }

    static func detailRenderState(
        from detail: TopicDetailState,
        baseURLString: String
    ) -> FireTopicDetailRenderState {
        let orderedPosts = mergeTopicPosts(
            existing: detail.postStream.posts,
            incoming: [],
            orderedPostIDs: detail.postStream.stream
        )
        let rows = rebuildTimelineEntries(from: orderedPosts).map(FirePreparedTopicTimelineRow.init)
        let originalRow = rows.first(where: { $0.entry.isOriginalPost })
        let replyRows = rows.filter { row in
            row.entry.postId != originalRow?.entry.postId
        }

        var contentByPostID: [UInt64: FireTopicPostRenderContent] = [:]
        contentByPostID.reserveCapacity(orderedPosts.count)
        for post in orderedPosts {
            contentByPostID[post.id] = renderContent(
                from: post.cooked,
                baseURLString: baseURLString
            )
        }

        return FireTopicDetailRenderState(
            originalRow: originalRow,
            replyRows: replyRows,
            contentByPostID: contentByPostID
        )
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

    static func mergeTopicPosts(
        existing: [TopicPostState],
        incoming: [TopicPostState],
        orderedPostIDs: [UInt64]
    ) -> [TopicPostState] {
        var postsByID: [UInt64: TopicPostState] = [:]
        for post in existing {
            postsByID[post.id] = post
        }
        for post in incoming {
            postsByID[post.id] = post
        }

        var mergedPosts: [TopicPostState] = []
        mergedPosts.reserveCapacity(postsByID.count)
        for postID in orderedPostIDs {
            if let post = postsByID.removeValue(forKey: postID) {
                mergedPosts.append(post)
            }
        }

        let trailingPosts = postsByID.values.sorted(by: comparePosts(_:_:))
        mergedPosts.append(contentsOf: trailingPosts)
        return mergedPosts
    }

    // MARK: - Timeline Entries

    static func rebuildTimelineEntries(from posts: [TopicPostState]) -> [FireTopicTimelineEntry] {
        let postNumbers = Set(posts.map(\.postNumber))
        let minPN = posts.map(\.postNumber).min() ?? 0
        let sorted = posts.sorted(by: comparePosts(_:_:))

        return sorted.map { post in
            let parent = normalizedReplyTarget(post.replyToPostNumber)
            let depth: UInt32
            if let pn = parent, pn != post.postNumber {
                depth = computeDepthWalk(
                    parentPN: pn, posts: posts, loaded: postNumbers, currentDepth: 1
                )
            } else {
                depth = 0
            }
            return FireTopicTimelineEntry(
                postId: post.id,
                postNumber: post.postNumber,
                parentPostNumber: parent,
                depth: depth,
                isOriginalPost: post.postNumber == minPN
            )
        }
    }

    static func timelineRows(
        entries: [FireTopicTimelineEntry],
        posts: [TopicPostState]
    ) -> [FireTopicTimelineRow] {
        let postsByID = Dictionary(uniqueKeysWithValues: posts.map { ($0.id, $0) })
        return entries.map { entry in
            FireTopicTimelineRow(entry: entry, post: postsByID[entry.postId])
        }
    }

    static func missingPostIDs(
        orderedPostIDs: [UInt64],
        in requestedRange: Range<Int>,
        loadedPostIDs: Set<UInt64>,
        excluding exhaustedPostIDs: Set<UInt64>
    ) -> [UInt64] {
        let clampedRange = requestedRange.clamped(to: 0..<orderedPostIDs.count)
        guard !clampedRange.isEmpty else { return [] }

        return orderedPostIDs[clampedRange].filter { postID in
            !loadedPostIDs.contains(postID) && !exhaustedPostIDs.contains(postID)
        }
    }

    private static func computeDepthWalk(
        parentPN: UInt32,
        posts: [TopicPostState],
        loaded: Set<UInt32>,
        currentDepth: UInt32
    ) -> UInt32 {
        guard loaded.contains(parentPN) else { return currentDepth }
        guard let parentPost = posts.first(where: { $0.postNumber == parentPN }) else {
            return currentDepth
        }
        if let gp = normalizedReplyTarget(parentPost.replyToPostNumber), gp != parentPN {
            return computeDepthWalk(
                parentPN: gp, posts: posts, loaded: loaded, currentDepth: currentDepth + 1
            )
        }
        return currentDepth
    }

    static func interactionCount(for detail: TopicDetailState) -> UInt32 {
        interactionCount(
            likeCount: detail.likeCount,
            posts: detail.postStream.posts
        )
    }

    static func interactionCount(
        likeCount: UInt32,
        posts: [TopicPostState]
    ) -> UInt32 {
        let extraReactionCount = posts
            .flatMap(\.reactions)
            .filter { $0.id.caseInsensitiveCompare("heart") != .orderedSame }
            .reduce(0 as UInt32) { partialResult, reaction in
                partialResult > UInt32.max - reaction.count
                    ? UInt32.max
                    : partialResult + reaction.count
            }
        return likeCount > UInt32.max - extraReactionCount
            ? UInt32.max
            : likeCount + extraReactionCount
    }

    static func loadedWindowCount(detail: TopicDetailState) -> Int {
        loadedWindowCount(
            orderedPostIDs: detail.postStream.stream,
            loadedPosts: detail.postStream.posts
        )
    }

    static func loadedWindowCount(
        orderedPostIDs: [UInt64],
        loadedPosts: [TopicPostState]
    ) -> Int {
        guard !orderedPostIDs.isEmpty else {
            return loadedPosts.count
        }

        let loadedPostIDs = Set(loadedPosts.map(\.id))
        var loadedWindowCount = 0
        for postID in orderedPostIDs {
            guard loadedPostIDs.contains(postID) else {
                break
            }
            loadedWindowCount += 1
        }
        return loadedWindowCount
    }

    static func missingPostIDs(
        orderedPostIDs: [UInt64],
        loadedPostIDs: Set<UInt64>,
        upTo targetLoadedCount: Int,
        excluding exhaustedPostIDs: Set<UInt64> = []
    ) -> [UInt64] {
        let targetCount = max(0, min(targetLoadedCount, orderedPostIDs.count))
        guard targetCount > 0 else {
            return []
        }

        return orderedPostIDs.prefix(targetCount).filter { postID in
            !loadedPostIDs.contains(postID) && !exhaustedPostIDs.contains(postID)
        }
    }

    static func missingPostIDs(
        in detail: TopicDetailState,
        upTo targetLoadedCount: Int,
        excluding exhaustedPostIDs: Set<UInt64> = []
    ) -> [UInt64] {
        missingPostIDs(
            orderedPostIDs: detail.postStream.stream,
            loadedPostIDs: Set(detail.postStream.posts.map(\.id)),
            upTo: targetLoadedCount,
            excluding: exhaustedPostIDs
        )
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

    private static func normalizedReplyTarget(_ replyToPostNumber: UInt32?) -> UInt32? {
        guard let replyToPostNumber, replyToPostNumber > 0 else {
            return nil
        }
        return replyToPostNumber
    }

    private static func comparePosts(_ lhs: TopicPostState, _ rhs: TopicPostState) -> Bool {
        if lhs.postNumber != rhs.postNumber {
            return lhs.postNumber < rhs.postNumber
        }
        return lhs.id < rhs.id
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
