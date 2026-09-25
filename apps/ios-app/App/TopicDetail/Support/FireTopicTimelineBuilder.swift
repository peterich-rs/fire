import Foundation

extension FireTopicPresentation {
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
    private static func normalizedReplyTarget(_ replyToPostNumber: UInt32?) -> UInt32? {
        guard let replyToPostNumber, replyToPostNumber > 0 else {
            return nil
        }
        return replyToPostNumber
    }
}
