import Foundation

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
struct FirePreparedTopicTimelineRow: Identifiable, Sendable {
    let entry: FireTopicTimelineEntry

    var id: UInt64 { entry.postId }
}
struct FireTopicTimelineRowInput: Equatable, Sendable {
    let postID: UInt64
    let postNumber: UInt32
    let replyToPostNumber: UInt32?
    let responseParentPostNumber: UInt32?
    let responseDepth: UInt16?
    let responsePreorderIndex: UInt32?
    let responseHasChildren: Bool?
    let responseDescendantCount: UInt32?
    let responseSiblingIndex: UInt16?
    let responseIsLastSibling: Bool?

    init(
        postID: UInt64,
        postNumber: UInt32,
        replyToPostNumber: UInt32?,
        responseParentPostNumber: UInt32? = nil,
        responseDepth: UInt16? = nil,
        responsePreorderIndex: UInt32? = nil,
        responseHasChildren: Bool? = nil,
        responseDescendantCount: UInt32? = nil,
        responseSiblingIndex: UInt16? = nil,
        responseIsLastSibling: Bool? = nil
    ) {
        self.postID = postID
        self.postNumber = postNumber
        self.replyToPostNumber = replyToPostNumber
        self.responseParentPostNumber = responseParentPostNumber
        self.responseDepth = responseDepth
        self.responsePreorderIndex = responsePreorderIndex
        self.responseHasChildren = responseHasChildren
        self.responseDescendantCount = responseDescendantCount
        self.responseSiblingIndex = responseSiblingIndex
        self.responseIsLastSibling = responseIsLastSibling
    }
}
