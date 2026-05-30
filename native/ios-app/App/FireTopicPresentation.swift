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

struct FireTopicPostRenderSignature: Hashable, Sendable {
    let sourceLength: Int
    let sourceChecksum: UInt64
    let imageIDs: [String]

    var token: String {
        var parts: [String] = []
        parts.reserveCapacity(imageIDs.count + 2)
        parts.append(String(sourceLength))
        parts.append(String(sourceChecksum, radix: 16))
        parts.append(contentsOf: imageIDs)
        return parts.joined(separator: ":")
    }

    static func make(source: String, imageAttachments: [FireCookedImage]) -> Self {
        FireTopicPostRenderSignature(
            sourceLength: source.utf8.count,
            sourceChecksum: stableChecksum(source),
            imageIDs: imageAttachments.map(\.id)
        )
    }

    private static func stableChecksum(_ value: String) -> UInt64 {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in value.utf8 {
            hash ^= UInt64(byte)
            hash &*= 0x100000001b3
        }
        hash ^= hash >> 33
        hash &*= 0xff51afd7ed558ccd
        hash ^= hash >> 33
        hash &*= 0xc4ceb9fe1a85ec53
        hash ^= hash >> 33
        return hash
    }
}

// NSAttributedString is not Sendable; render content is built during cache preparation and then shared immutably.
struct FireTopicPostRenderContent: @unchecked Sendable {
    let plainText: String
    let attributedText: NSAttributedString?
    let imageAttachments: [FireCookedImage]
    let signature: FireTopicPostRenderSignature
}

struct FirePreparedTopicTimelineRow: Identifiable, Sendable {
    let entry: FireTopicTimelineEntry

    var id: UInt64 { entry.postId }
}

struct FireTopicTimelineRowInput: Equatable, Sendable {
    let postID: UInt64
    let postNumber: UInt32
    let replyToPostNumber: UInt32?
}

struct FireTopicPostRenderInput: Equatable, Sendable {
    let cooked: String
}

struct FireTopicDetailRenderState: Sendable {
    let originalRow: FirePreparedTopicTimelineRow?
    let replyRows: [FirePreparedTopicTimelineRow]
    let contentByPostID: [UInt64: FireTopicPostRenderContent]
}

struct FireTopicDetailRenderCache: Sendable {
    let baseURLString: String
    let rowInputs: [FireTopicTimelineRowInput]
    let contentInputsByPostID: [UInt64: FireTopicPostRenderInput]
    let renderState: FireTopicDetailRenderState
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

    static func imageAttachments(from html: String, baseURLString: String) -> [FireCookedImage] {
        guard !html.isEmpty else {
            return []
        }

        return FireRichTextParser.parse(html: html, baseURLString: baseURLString).imageAttachments
    }

    static func renderContent(from html: String, baseURLString: String) -> FireTopicPostRenderContent {
        let richContent = FireRichTextParser.parse(html: html, baseURLString: baseURLString)
        let attributedText = richContent.nodes.isEmpty ? nil :
            FireRichTextAttributedStringBuilder.build(from: richContent.nodes)
        return FireTopicPostRenderContent(
            plainText: richContent.plainText,
            attributedText: attributedText,
            imageAttachments: richContent.imageAttachments,
            signature: FireTopicPostRenderSignature.make(
                source: html,
                imageAttachments: richContent.imageAttachments
            )
        )
    }

    static func detailRenderState(
        from detail: TopicDetailState,
        baseURLString: String
    ) -> FireTopicDetailRenderState {
        detailRenderCache(
            from: detail,
            baseURLString: baseURLString
        ).renderState
    }

    private static func timelineRowInput(for post: TopicPostState) -> FireTopicTimelineRowInput {
        FireTopicTimelineRowInput(
            postID: post.id,
            postNumber: post.postNumber,
            replyToPostNumber: post.replyToPostNumber
        )
    }

    private static func originalTimelineRow(for post: TopicPostState) -> FirePreparedTopicTimelineRow {
        FirePreparedTopicTimelineRow(
            entry: FireTopicTimelineEntry(
                postId: post.id,
                postNumber: post.postNumber,
                parentPostNumber: nil,
                depth: 0,
                isOriginalPost: true
            )
        )
    }

    private static func replyTimelineRow(from responseRow: TopicResponseRowState) -> FirePreparedTopicTimelineRow {
        FirePreparedTopicTimelineRow(
            entry: FireTopicTimelineEntry(
                postId: responseRow.post.id,
                postNumber: responseRow.post.postNumber,
                parentPostNumber: responseRow.parentPostNumber,
                depth: UInt32(responseRow.depth),
                isOriginalPost: false
            )
        )
    }

    static func detailRenderCache(
        from detail: TopicDetailState,
        baseURLString: String,
        previous: FireTopicDetailRenderCache? = nil
    ) -> FireTopicDetailRenderCache {
        let orderedPosts = uniqueTopicPostsPreservingOrder(
            mergeTopicPosts(
                existing: detail.postStream.posts,
                incoming: [],
                orderedPostIDs: detail.postStream.stream
            )
        )
        let rowInputs = orderedPosts.map(timelineRowInput(for:))
        let contentInputsByPostID = Dictionary(
            orderedPosts.map { post in
                (post.id, FireTopicPostRenderInput(cooked: post.cooked))
            },
            uniquingKeysWith: { _, newest in newest }
        )

        let originalRow: FirePreparedTopicTimelineRow?
        let replyRows: [FirePreparedTopicTimelineRow]
        if previous?.rowInputs == rowInputs {
            originalRow = previous?.renderState.originalRow
            replyRows = previous?.renderState.replyRows ?? []
        } else {
            let rows = rebuildTimelineEntries(from: orderedPosts).map(FirePreparedTopicTimelineRow.init)
            let resolvedOriginalRow = rows.first(where: { $0.entry.isOriginalPost })
            originalRow = resolvedOriginalRow
            replyRows = rows.filter { row in
                row.entry.postId != resolvedOriginalRow?.entry.postId
            }
        }

        var contentByPostID: [UInt64: FireTopicPostRenderContent] = [:]
        contentByPostID.reserveCapacity(orderedPosts.count)
        let canReuseContent = previous?.baseURLString == baseURLString
        for post in orderedPosts {
            if canReuseContent,
               previous?.contentInputsByPostID[post.id] == contentInputsByPostID[post.id],
               let cachedContent = previous?.renderState.contentByPostID[post.id] {
                contentByPostID[post.id] = cachedContent
            } else {
                contentByPostID[post.id] = renderContent(
                    from: post.cooked,
                    baseURLString: baseURLString
                )
            }
        }

        return FireTopicDetailRenderCache(
            baseURLString: baseURLString,
            rowInputs: rowInputs,
            contentInputsByPostID: contentInputsByPostID,
            renderState: FireTopicDetailRenderState(
                originalRow: originalRow,
                replyRows: replyRows,
                contentByPostID: contentByPostID
            )
        )
    }

    static func detailRenderCache(
        screen: TopicScreenState,
        responseRows: [TopicResponseRowState],
        baseURLString: String,
        previous: FireTopicDetailRenderCache? = nil
    ) -> FireTopicDetailRenderCache {
        let responseRows = uniqueResponseRowsPreservingOrder(responseRows).filter { row in
            row.post.id != screen.body.post.id
        }
        let orderedPosts = uniqueTopicPostsPreservingOrder(
            [screen.body.post] + responseRows.map(\.post)
        )
        let rowInputs = orderedPosts.map(timelineRowInput(for:))
        let contentInputsByPostID = Dictionary(
            orderedPosts.map { post in
                (post.id, FireTopicPostRenderInput(cooked: post.cooked))
            },
            uniquingKeysWith: { _, newest in newest }
        )

        let originalRow = originalTimelineRow(for: screen.body.post)
        let replyRows: [FirePreparedTopicTimelineRow]
        if let previous,
           previous.rowInputs.count <= rowInputs.count,
           Array(rowInputs.prefix(previous.rowInputs.count)) == previous.rowInputs {
            let suffixRows = responseRows.dropFirst(previous.renderState.replyRows.count).map(replyTimelineRow(from:))
            replyRows = previous.renderState.replyRows + suffixRows
        } else {
            replyRows = responseRows.map(replyTimelineRow(from:))
        }

        var contentByPostID: [UInt64: FireTopicPostRenderContent] = [:]
        contentByPostID.reserveCapacity(orderedPosts.count)
        let canReuseContent = previous?.baseURLString == baseURLString
        for post in orderedPosts {
            if canReuseContent,
               previous?.contentInputsByPostID[post.id] == contentInputsByPostID[post.id],
               let cachedContent = previous?.renderState.contentByPostID[post.id] {
                contentByPostID[post.id] = cachedContent
            } else {
                contentByPostID[post.id] = renderContent(
                    from: post.cooked,
                    baseURLString: baseURLString
                )
            }
        }

        return FireTopicDetailRenderCache(
            baseURLString: baseURLString,
            rowInputs: rowInputs,
            contentInputsByPostID: contentInputsByPostID,
            renderState: FireTopicDetailRenderState(
                originalRow: originalRow,
                replyRows: replyRows,
                contentByPostID: contentByPostID
            )
        )
    }

    static func detailRenderCache(
        screen: TopicScreenState,
        appending responseRows: [TopicResponseRowState],
        baseURLString: String,
        previous: FireTopicDetailRenderCache
    ) -> FireTopicDetailRenderCache? {
        guard !responseRows.isEmpty,
              previous.baseURLString == baseURLString,
              previous.rowInputs.first == timelineRowInput(for: screen.body.post),
              previous.rowInputs.count == previous.renderState.replyRows.count + 1 else {
            return nil
        }

        var rowInputs = previous.rowInputs
        rowInputs.reserveCapacity(rowInputs.count + responseRows.count)

        var contentInputsByPostID = previous.contentInputsByPostID
        contentInputsByPostID.reserveCapacity(contentInputsByPostID.count + responseRows.count)

        var replyRows = previous.renderState.replyRows
        replyRows.reserveCapacity(replyRows.count + responseRows.count)

        var contentByPostID = previous.renderState.contentByPostID
        contentByPostID.reserveCapacity(contentByPostID.count + responseRows.count)

        for responseRow in responseRows {
            let post = responseRow.post
            guard contentInputsByPostID[post.id] == nil else {
                return nil
            }

            rowInputs.append(timelineRowInput(for: post))
            contentInputsByPostID[post.id] = FireTopicPostRenderInput(cooked: post.cooked)
            replyRows.append(replyTimelineRow(from: responseRow))
            contentByPostID[post.id] = renderContent(
                from: post.cooked,
                baseURLString: baseURLString
            )
        }

        return FireTopicDetailRenderCache(
            baseURLString: baseURLString,
            rowInputs: rowInputs,
            contentInputsByPostID: contentInputsByPostID,
            renderState: FireTopicDetailRenderState(
                originalRow: previous.renderState.originalRow ?? originalTimelineRow(for: screen.body.post),
                replyRows: replyRows,
                contentByPostID: contentByPostID
            )
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
        let orderedPostIDs = uniqueTopicPostIDsPreservingOrder(orderedPostIDs)
        if incoming.isEmpty,
           existing.count == orderedPostIDs.count,
           zip(existing, orderedPostIDs).allSatisfy({ post, postID in
               post.id == postID
           }) {
            return existing
        }

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

    static func uniqueTopicPostsPreservingOrder(_ posts: [TopicPostState]) -> [TopicPostState] {
        var orderedPostIDs: [UInt64] = []
        orderedPostIDs.reserveCapacity(posts.count)
        var postsByID: [UInt64: TopicPostState] = [:]
        postsByID.reserveCapacity(posts.count)

        for post in posts {
            if postsByID[post.id] == nil {
                orderedPostIDs.append(post.id)
            }
            postsByID[post.id] = post
        }

        return orderedPostIDs.compactMap { postsByID[$0] }
    }

    static func uniqueResponseRowsPreservingOrder(
        _ rows: [TopicResponseRowState]
    ) -> [TopicResponseRowState] {
        var orderedPostIDs: [UInt64] = []
        orderedPostIDs.reserveCapacity(rows.count)
        var rowsByPostID: [UInt64: TopicResponseRowState] = [:]
        rowsByPostID.reserveCapacity(rows.count)

        for row in rows {
            if rowsByPostID[row.post.id] == nil {
                orderedPostIDs.append(row.post.id)
            }
            rowsByPostID[row.post.id] = row
        }

        return orderedPostIDs.compactMap { rowsByPostID[$0] }
    }

    static func uniqueTopicPostIDsPreservingOrder(_ postIDs: [UInt64]) -> [UInt64] {
        var seenPostIDs = Set<UInt64>()
        seenPostIDs.reserveCapacity(postIDs.count)
        var orderedPostIDs: [UInt64] = []
        orderedPostIDs.reserveCapacity(postIDs.count)

        for postID in postIDs where seenPostIDs.insert(postID).inserted {
            orderedPostIDs.append(postID)
        }

        return orderedPostIDs
    }

    static func topicPostsByID(_ posts: [TopicPostState]) -> [UInt64: TopicPostState] {
        Dictionary(
            posts.map { ($0.id, $0) },
            uniquingKeysWith: { _, newest in newest }
        )
    }

    // MARK: - Timeline Entries

    /// Builds timeline entries using DFS ordering: children are grouped immediately
    /// after their parent so that the visual thread structure is correct.
    /// When the original post is not in the loaded set (partial/anchored load), falls
    /// back to postNumber ordering with depth computed by walking the reply chain.
    static func rebuildTimelineEntries(from posts: [TopicPostState]) -> [FireTopicTimelineEntry] {
        guard !posts.isEmpty else { return [] }

        let postNumbers = Set(posts.map(\.postNumber))
        let minPN = posts.map(\.postNumber).min() ?? 0

        // Detect the original post: the earliest post with no parent reference.
        // If no such post exists, this is a partial/anchored load — use flat ordering.
        let opPost = posts
            .filter { normalizedReplyTarget($0.replyToPostNumber) == nil }
            .min(by: comparePosts(_:_:))

        guard let opPost, opPost.postNumber == minPN else {
            // Partial load — fall back to flat postNumber ordering with depth walk
            return flatTimelineEntries(from: posts, postNumbers: postNumbers, minPN: minPN)
        }

        // Full/near-full load: use DFS ordering
        return dfsTimelineEntries(from: posts, opPost: opPost, postNumbers: postNumbers)
    }

    /// Flat postNumber ordering with depth computed by walking the parent chain.
    /// Used for partial/anchored loads where the OP may not be present.
    private static func flatTimelineEntries(
        from posts: [TopicPostState],
        postNumbers: Set<UInt32>,
        minPN: UInt32
    ) -> [FireTopicTimelineEntry] {
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
                isOriginalPost: post.postNumber == minPN && parent == nil
            )
        }
    }

    /// DFS ordering: groups children immediately after their parent.
    private static func dfsTimelineEntries(
        from posts: [TopicPostState],
        opPost: TopicPostState,
        postNumbers: Set<UInt32>
    ) -> [FireTopicTimelineEntry] {
        let opPN = opPost.postNumber

        // Build children-by-parent map
        var childrenByParent: [UInt32: [TopicPostState]] = [:]
        var topLevelPosts: [TopicPostState] = []

        for post in posts {
            if post.postNumber == opPN {
                continue
            }

            let parent = normalizedReplyTarget(post.replyToPostNumber)
            // A post is top-level if: no parent, self-ref, replies to OP,
            // or its parent is not loaded.
            let isTopLevel = parent == nil
                || parent == post.postNumber
                || parent == opPN
                || parent.map({ !postNumbers.contains($0) }) ?? false

            if isTopLevel {
                topLevelPosts.append(post)
            } else if let parentPN = parent {
                childrenByParent[parentPN, default: []].append(post)
            }
        }

        // Sort children within each group by postNumber
        for key in childrenByParent.keys {
            childrenByParent[key]?.sort(by: comparePosts(_:_:))
        }
        topLevelPosts.sort(by: comparePosts(_:_:))

        // DFS traversal
        var result: [FireTopicTimelineEntry] = []
        var visited: Set<UInt32> = [opPN]

        // Add OP first
        result.append(FireTopicTimelineEntry(
            postId: opPost.id,
            postNumber: opPost.postNumber,
            parentPostNumber: nil,
            depth: 0,
            isOriginalPost: true
        ))

        func dfs(post: TopicPostState, depth: UInt32) {
            guard !visited.contains(post.postNumber) else { return }
            visited.insert(post.postNumber)

            let parent = normalizedReplyTarget(post.replyToPostNumber)
            result.append(FireTopicTimelineEntry(
                postId: post.id,
                postNumber: post.postNumber,
                parentPostNumber: parent,
                depth: depth,
                isOriginalPost: false
            ))

            if let children = childrenByParent[post.postNumber] {
                for child in children {
                    dfs(post: child, depth: depth + 1)
                }
            }
        }

        // Process top-level posts (depth 1 = direct replies to OP)
        for post in topLevelPosts {
            dfs(post: post, depth: 1)
        }

        // Handle remaining orphans
        let remaining = posts
            .filter { !visited.contains($0.postNumber) }
            .sorted(by: comparePosts(_:_:))
        for post in remaining {
            dfs(post: post, depth: 1)
        }

        return result
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

    static func timelineRows(
        entries: [FireTopicTimelineEntry],
        posts: [TopicPostState]
    ) -> [FireTopicTimelineRow] {
        let postsByID = topicPostsByID(posts)
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
