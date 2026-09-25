import SwiftUI

struct FireTopicDetailPostRepliesHost: View {
    @ObservedObject var store: FireTopicDetailStore

    let topicID: UInt64
    let context: FirePostReplyContext
    let baseURLString: String
    let onJumpToPost: (UInt32) -> Void

    var body: some View {
        let snapshot = store.snapshot(for: topicID)
        let appendedIDs = Set(snapshot?.focusedReplyContext?.appendedPostIds ?? [])
        let replies = (snapshot?.rows ?? [])
            .filter { appendedIDs.contains($0.postId) }
            .map(FireTopicDetailUiProjection.post(from:))
        FirePostRepliesSheet(
            post: context.post,
            replies: replies,
            replyHistory: snapshot?.focusedReplyContext?.historyRows.map(FireTopicDetailUiProjection.post(from:)) ?? [],
            isLoading: snapshot?.rows.contains { $0.postId == context.post.id && $0.isLoadingReplyContext } ?? false,
            errorMessage: nil,
            baseURLString: baseURLString,
            onJumpToPost: onJumpToPost,
            onRetry: {
                store.loadReplyContext(topicId: topicID, postId: context.post.id)
            }
        )
        .task(id: context.post.id) {
            store.loadReplyContext(topicId: topicID, postId: context.post.id)
        }
    }
}
