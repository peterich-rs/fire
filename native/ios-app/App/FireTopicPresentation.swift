import Foundation
import SwiftUI

typealias FireTopicCategoryPresentation = TopicCategoryState
typealias FireTopicRowPresentation = TopicRowState
typealias FireTopicFlatPostPresentation = TopicThreadFlatPostState
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

struct FireTopicThreadComposition {
    let thread: TopicThreadState
    let flatPosts: [TopicThreadFlatPostState]
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

    static func recomposedDetail(_ detail: TopicDetailState) -> TopicDetailState {
        var detail = detail
        detail.postStream = TopicPostStreamState(
            posts: mergeTopicPosts(
                existing: detail.postStream.posts,
                incoming: [],
                orderedPostIDs: detail.postStream.stream
            ),
            stream: detail.postStream.stream
        )

        let composition = composeThread(posts: detail.postStream.posts)
        detail.thread = composition.thread
        detail.flatPosts = composition.flatPosts
        return detail
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

        let indexByID = Dictionary(uniqueKeysWithValues: orderedPostIDs.enumerated().map { ($1, $0) })
        var maxLoadedIndex = -1
        for post in loadedPosts {
            if let index = indexByID[post.id] {
                maxLoadedIndex = max(maxLoadedIndex, index)
            }
        }
        return maxLoadedIndex + 1
    }

    static func missingPostIDs(
        in detail: TopicDetailState,
        upTo targetLoadedCount: Int,
        excluding exhaustedPostIDs: Set<UInt64> = []
    ) -> [UInt64] {
        let targetCount = max(0, min(targetLoadedCount, detail.postStream.stream.count))
        guard targetCount > 0 else {
            return []
        }

        let loadedIDs = Set(detail.postStream.posts.map(\.id))
        return detail.postStream.stream.prefix(targetCount).filter { postID in
            !loadedIDs.contains(postID) && !exhaustedPostIDs.contains(postID)
        }
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

    private static func composeThread(posts: [TopicPostState]) -> FireTopicThreadComposition {
        let orderedPosts = posts.sorted(by: comparePosts(_:_:))
        guard let originalPost = orderedPosts.min(by: comparePosts(_:_:)) else {
            return FireTopicThreadComposition(
                thread: TopicThreadState(
                    originalPostNumber: nil,
                    replySections: []
                ),
                flatPosts: []
            )
        }

        let rootPostNumber = originalPost.postNumber
        let postNumbers = Set(orderedPosts.map(\.postNumber))
        let postsByNumber = Dictionary(uniqueKeysWithValues: orderedPosts.map { ($0.postNumber, $0) })
        var childrenByParent: [UInt32: [TopicPostState]] = [:]

        for post in orderedPosts where post.postNumber != rootPostNumber {
            guard let parentPostNumber = normalizedReplyTarget(post.replyToPostNumber) else {
                continue
            }
            guard parentPostNumber != post.postNumber else {
                continue
            }
            childrenByParent[parentPostNumber, default: []].append(post)
        }

        for parentPostNumber in childrenByParent.keys {
            childrenByParent[parentPostNumber]?.sort(by: comparePosts(_:_:))
        }

        var consumedPostNumbers: Set<UInt32> = [rootPostNumber]
        var replySections: [TopicThreadSectionState] = []

        for post in orderedPosts where post.postNumber != rootPostNumber {
            if consumedPostNumbers.contains(post.postNumber) {
                continue
            }

            let normalizedParent = normalizedReplyTarget(post.replyToPostNumber)
            let shouldStartSection = normalizedParent == nil
                || normalizedParent == rootPostNumber
                || normalizedParent.map { !postNumbers.contains($0) } == true
            if !shouldStartSection {
                continue
            }

            consumedPostNumbers.insert(post.postNumber)
            var branchVisited: Set<UInt32> = [post.postNumber]
            let replies = flattenThreadReplies(
                parentPostNumber: post.postNumber,
                depth: 1,
                childrenByParent: childrenByParent,
                consumedPostNumbers: &consumedPostNumbers,
                branchVisited: &branchVisited
            )
            replySections.append(
                TopicThreadSectionState(
                    anchorPostNumber: post.postNumber,
                    replies: replies
                )
            )
        }

        let remainingPostNumbers = orderedPosts
            .filter { $0.postNumber != rootPostNumber }
            .map(\.postNumber)
            .filter { !consumedPostNumbers.contains($0) }

        for postNumber in remainingPostNumbers {
            guard let post = postsByNumber[postNumber] else {
                continue
            }
            consumedPostNumbers.insert(post.postNumber)
            var branchVisited: Set<UInt32> = [post.postNumber]
            let replies = flattenThreadReplies(
                parentPostNumber: post.postNumber,
                depth: 1,
                childrenByParent: childrenByParent,
                consumedPostNumbers: &consumedPostNumbers,
                branchVisited: &branchVisited
            )
            replySections.append(
                TopicThreadSectionState(
                    anchorPostNumber: post.postNumber,
                    replies: replies
                )
            )
        }

        let thread = TopicThreadState(
            originalPostNumber: rootPostNumber,
            replySections: replySections
        )

        var flatPosts: [TopicThreadFlatPostState] = []
        if let original = postsByNumber[rootPostNumber] {
            flatPosts.append(
                TopicThreadFlatPostState(
                    post: original,
                    depth: 0,
                    parentPostNumber: nil,
                    showsThreadLine: !replySections.isEmpty,
                    isOriginalPost: true
                )
            )
        }

        for (sectionIndex, section) in replySections.enumerated() {
            let isLastSection = sectionIndex == replySections.count - 1
            let hasNestedReplies = !section.replies.isEmpty
            guard let anchorPost = postsByNumber[section.anchorPostNumber] else {
                continue
            }

            flatPosts.append(
                TopicThreadFlatPostState(
                    post: anchorPost,
                    depth: 0,
                    parentPostNumber: nil,
                    showsThreadLine: hasNestedReplies || !isLastSection,
                    isOriginalPost: false
                )
            )

            for (replyIndex, reply) in section.replies.enumerated() {
                guard let replyPost = postsByNumber[reply.postNumber] else {
                    continue
                }
                let isLastReply = replyIndex == section.replies.count - 1
                flatPosts.append(
                    TopicThreadFlatPostState(
                        post: replyPost,
                        depth: reply.depth,
                        parentPostNumber: reply.parentPostNumber,
                        showsThreadLine: !isLastReply || !isLastSection,
                        isOriginalPost: false
                    )
                )
            }
        }

        return FireTopicThreadComposition(thread: thread, flatPosts: flatPosts)
    }

    private static func normalizedReplyTarget(_ replyToPostNumber: UInt32?) -> UInt32? {
        guard let replyToPostNumber, replyToPostNumber > 0 else {
            return nil
        }
        return replyToPostNumber
    }

    private static func flattenThreadReplies(
        parentPostNumber: UInt32,
        depth: UInt32,
        childrenByParent: [UInt32: [TopicPostState]],
        consumedPostNumbers: inout Set<UInt32>,
        branchVisited: inout Set<UInt32>
    ) -> [TopicThreadReplyState] {
        guard let children = childrenByParent[parentPostNumber] else {
            return []
        }

        var replies: [TopicThreadReplyState] = []
        for child in children {
            if branchVisited.contains(child.postNumber) {
                continue
            }

            consumedPostNumbers.insert(child.postNumber)
            replies.append(
                TopicThreadReplyState(
                    postNumber: child.postNumber,
                    depth: depth,
                    parentPostNumber: normalizedReplyTarget(child.replyToPostNumber)
                )
            )

            branchVisited.insert(child.postNumber)
            replies.append(contentsOf: flattenThreadReplies(
                parentPostNumber: child.postNumber,
                depth: depth + 1,
                childrenByParent: childrenByParent,
                consumedPostNumbers: &consumedPostNumbers,
                branchVisited: &branchVisited
            ))
            branchVisited.remove(child.postNumber)
        }

        return replies
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
