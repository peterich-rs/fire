import Foundation

extension FireTopicPresentation {
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
    static func uniqueTreeRowsPreservingOrder(
        _ rows: [TopicTreeRowState]
    ) -> [TopicTreeRowState] {
        var orderedPostIDs: [UInt64] = []
        orderedPostIDs.reserveCapacity(rows.count)
        var rowsByPostID: [UInt64: TopicTreeRowState] = [:]
        rowsByPostID.reserveCapacity(rows.count)

        for row in rows {
            if rowsByPostID[row.postId] == nil {
                orderedPostIDs.append(row.postId)
            }
            rowsByPostID[row.postId] = row
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
    static func comparePosts(_ lhs: TopicPostState, _ rhs: TopicPostState) -> Bool {
        if lhs.postNumber != rhs.postNumber {
            return lhs.postNumber < rhs.postNumber
        }
        return lhs.id < rhs.id
    }
}
