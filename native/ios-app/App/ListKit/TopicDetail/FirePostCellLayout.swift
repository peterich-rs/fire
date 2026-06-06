import Foundation
import UIKit

struct FirePostLayoutTraitSignature: Hashable, Sendable {
    let contentWidthPixels: Int
    let contentSizeCategory: String
}

struct FirePostCellLayoutKey: Hashable, Sendable {
    let postID: UInt64
    let depth: Int
    let showsThreadLine: Bool
    let showsDivider: Bool
    let replyTargetPostNumber: UInt32?
    let replyContext: String?
    let textContentID: String
    let imageSignature: [String]
    let pollSignature: [String]
    let hasReactions: Bool
    let replyShortcutCount: UInt32?
    let textExpansionState: FirePostTextExpansionState
    let acceptedAnswer: Bool
    let trait: FirePostLayoutTraitSignature
}

struct FirePostCellLayout: Equatable, Sendable {
    let key: FirePostCellLayoutKey
    let totalHeight: CGFloat
    let avatarFrame: CGRect
    let threadLineFrame: CGRect?
    let metaFrame: CGRect
    let textFrame: CGRect?
    let textContainerSize: CGSize
    let textExpansionFrame: CGRect?
    let imageFrames: [CGRect]
    let pollFrames: [CGRect]
    let replyShortcutFrame: CGRect?
    let reactionsFrame: CGRect?
    let menuFrame: CGRect?
    let dividerFrame: CGRect?
}

enum FirePostReactionDisplayPolicy {
    static let replyVisibleReactionLimit = 3
    static let wrappedReactionMaxLines = 2

    static func visibleReactions(
        from reactions: [TopicReactionState],
        depth: Int
    ) -> [TopicReactionState] {
        guard depth > 0 else {
            return reactions
        }
        return Array(reactions.prefix(replyVisibleReactionLimit))
    }

    static func allowsWrapping(depth: Int) -> Bool {
        depth == 0
    }
}

struct FirePostTextExpansionState: Hashable, Sendable {
    static let collapsedLineLimit = 4

    let isCollapsible: Bool
    let isExpanded: Bool

    static let disabled = FirePostTextExpansionState(
        isCollapsible: false,
        isExpanded: true
    )

    var isCollapsed: Bool {
        isCollapsible && !isExpanded
    }
}

struct FirePostCellRenderPayload {
    let post: TopicPostState
    let renderContent: FireTopicPostRenderContent
    let baseURLString: String
    let canWriteInteractions: Bool
    let isMutating: Bool
    let replyContext: String?
    let replyTargetPostNumber: UInt32?
    let replyShortcutCount: UInt32?
    let isLoadingReplyContext: Bool
    let textExpansionState: FirePostTextExpansionState
    let showsDivider: Bool
    let layoutWidth: CGFloat
    let layout: FirePostCellLayout?
    let layoutKey: FirePostCellLayoutKey?

    init(
        post: TopicPostState,
        renderContent: FireTopicPostRenderContent,
        baseURLString: String,
        canWriteInteractions: Bool,
        isMutating: Bool,
        replyContext: String?,
        replyTargetPostNumber: UInt32?,
        replyShortcutCount: UInt32?,
        isLoadingReplyContext: Bool,
        textExpansionState: FirePostTextExpansionState,
        showsDivider: Bool,
        layoutWidth: CGFloat,
        layout: FirePostCellLayout? = nil,
        layoutKey: FirePostCellLayoutKey? = nil
    ) {
        self.post = post
        self.renderContent = renderContent
        self.baseURLString = baseURLString
        self.canWriteInteractions = canWriteInteractions
        self.isMutating = isMutating
        self.replyContext = replyContext
        self.replyTargetPostNumber = replyTargetPostNumber
        self.replyShortcutCount = replyShortcutCount
        self.isLoadingReplyContext = isLoadingReplyContext
        self.textExpansionState = textExpansionState
        self.showsDivider = showsDivider
        self.layoutWidth = layoutWidth
        self.layout = layout
        self.layoutKey = layoutKey
    }
}

struct FirePostCellCallbacks {
    let onLinkTapped: (URL) -> Void
    let onOpenImage: (FireCookedImage) -> Void
    let onToggleLike: (TopicPostState) -> Void
    let onSelectReaction: (TopicPostState, String) -> Void
    let onEditPost: (TopicPostState) -> Void
    let onBookmarkPost: (TopicPostState) -> Void
    let onDeletePost: (TopicPostState) -> Void
    let onRecoverPost: (TopicPostState) -> Void
    let onFlagPost: (TopicPostState) -> Void
    let onOpenReplyTarget: (UInt32) -> Void
    let onOpenReplies: (TopicPostState) -> Void
    let onExpandText: (TopicPostState) -> Void
    let onVotePoll: (TopicPostState, PollState, [String]) -> Void
    let onUnvotePoll: (TopicPostState, PollState) -> Void
    let onSwipeReply: (TopicPostState) -> Void
}
