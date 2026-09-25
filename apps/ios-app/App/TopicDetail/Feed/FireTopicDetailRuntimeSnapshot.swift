import Foundation

struct FireTopicDetailRuntimeSnapshot: Sendable {
    let items: [FireTopicDetailRuntimeItem]
    let replyIndexByPostID: [UInt64: Int]
}

struct FireTopicDetailRuntimePostContext {
    let post: TopicPostState
    let renderContent: FireTopicPostRenderContent
    let depth: Int
    let replyContext: String?
    let replyTargetPostNumber: UInt32?
    let showsThreadLine: Bool
    let showsDivider: Bool
    let replyShortcutCount: UInt32?
    let isReplyThreadExpanded: Bool
    let isLoadingReplyContext: Bool
    let textExpansionState: FirePostTextExpansionState
    /// Original/main post keeps actions in the nav toolbar; only replies show cell `...`.
    let allowsInlineOverflowActions: Bool
}

struct FireTopicDetailReplyDisplayPlan {
    struct DisplayedRow {
        let row: FirePreparedTopicTimelineRow
        let sourceIndex: Int
        let showsThreadLine: Bool
        let showsDivider: Bool
        let replyShortcutCount: UInt32?
        let isReplyThreadExpanded: Bool
    }

    let rows: [DisplayedRow]
    let sourceIndexByPostID: [UInt64: Int]
}

struct FireTopicDetailReplyThreadIndex {
    let rootIndexBySourceIndex: [Int: Int]
    let secondaryIndicesByRoot: [Int: [Int]]
}
