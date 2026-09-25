import Foundation

final class FireTopicDetailRuntimeInteractions {
    let isMutatingPost: (UInt64) -> Bool
    let isPostTextExpanded: (UInt64) -> Bool
    let isReplyThreadExpanded: (UInt64) -> Bool
    let isLoadingPostReplyContext: (UInt64) -> Bool
    let onVisiblePostNumbersChanged: (Set<UInt32>) -> Void
    let onRefresh: () async -> Void
    let onLoadTopicDetail: () async -> Void
    let onScrollTargetHandled: (UInt32) -> Void
    let onLoadMoreTopicPosts: () -> Bool
    let onReloadTopicAiSummary: () -> Void
    let onToggleTopicAiSummaryExpanded: () -> Void
    let onOpenComposer: (TopicPostState?) -> Void
    let onOpenPostNumber: (UInt32) -> Void
    let onOpenPostReplies: (TopicPostState) -> Void
    let onLinkTapped: (URL) -> Void
    let onOpenProfile: (String) -> Void
    let onOpenImage: (FireCookedImage) -> Void
    let onToggleLike: (TopicPostState) -> Void
    let onSelectReaction: (TopicPostState, String) -> Void
    let onToggleReactionPicker: (TopicPostState) -> Void
    let onBoostPost: (TopicPostState) -> Void
    let quickReactionOptionsProvider: () -> [FireReactionOption]
    let isReactionPickerExpanded: (UInt64) -> Bool
    let onQuotePost: (TopicPostState) -> Void
    let onEditPost: (TopicPostState) -> Void
    let onBookmarkPost: (TopicPostState) -> Void
    let onDeletePost: (TopicPostState) -> Void
    let onRecoverPost: (TopicPostState) -> Void
    let onFlagPost: (TopicPostState) -> Void
    let onExpandPostText: (TopicPostState) -> Void
    let onVotePoll: (TopicPostState, PollState, [String]) -> Void
    let onUnvotePoll: (TopicPostState, PollState) -> Void
    let onToggleTopicVote: () async -> Void
    let onShowTopicVoters: () async -> Void
    let onOpenCategory: (FireTopicCategoryPresentation) -> Void
    let onOpenTag: (String) -> Void

    init(
        isMutatingPost: @escaping (UInt64) -> Bool,
        isPostTextExpanded: @escaping (UInt64) -> Bool,
        isReplyThreadExpanded: @escaping (UInt64) -> Bool,
        isLoadingPostReplyContext: @escaping (UInt64) -> Bool,
        onVisiblePostNumbersChanged: @escaping (Set<UInt32>) -> Void,
        onRefresh: @escaping () async -> Void,
        onLoadTopicDetail: @escaping () async -> Void,
        onScrollTargetHandled: @escaping (UInt32) -> Void,
        onLoadMoreTopicPosts: @escaping () -> Bool,
        onReloadTopicAiSummary: @escaping () -> Void,
        onToggleTopicAiSummaryExpanded: @escaping () -> Void,
        onOpenComposer: @escaping (TopicPostState?) -> Void,
        onOpenPostNumber: @escaping (UInt32) -> Void,
        onOpenPostReplies: @escaping (TopicPostState) -> Void,
        onLinkTapped: @escaping (URL) -> Void,
        onOpenProfile: @escaping (String) -> Void,
        onOpenImage: @escaping (FireCookedImage) -> Void,
        onToggleLike: @escaping (TopicPostState) -> Void,
        onSelectReaction: @escaping (TopicPostState, String) -> Void,
        onToggleReactionPicker: @escaping (TopicPostState) -> Void,
        onBoostPost: @escaping (TopicPostState) -> Void,
        quickReactionOptionsProvider: @escaping () -> [FireReactionOption],
        isReactionPickerExpanded: @escaping (UInt64) -> Bool,
        onQuotePost: @escaping (TopicPostState) -> Void,
        onEditPost: @escaping (TopicPostState) -> Void,
        onBookmarkPost: @escaping (TopicPostState) -> Void,
        onDeletePost: @escaping (TopicPostState) -> Void,
        onRecoverPost: @escaping (TopicPostState) -> Void,
        onFlagPost: @escaping (TopicPostState) -> Void,
        onExpandPostText: @escaping (TopicPostState) -> Void,
        onVotePoll: @escaping (TopicPostState, PollState, [String]) -> Void,
        onUnvotePoll: @escaping (TopicPostState, PollState) -> Void,
        onToggleTopicVote: @escaping () async -> Void,
        onShowTopicVoters: @escaping () async -> Void,
        onOpenCategory: @escaping (FireTopicCategoryPresentation) -> Void,
        onOpenTag: @escaping (String) -> Void
    ) {
        self.isMutatingPost = isMutatingPost
        self.isPostTextExpanded = isPostTextExpanded
        self.isReplyThreadExpanded = isReplyThreadExpanded
        self.isLoadingPostReplyContext = isLoadingPostReplyContext
        self.onVisiblePostNumbersChanged = onVisiblePostNumbersChanged
        self.onRefresh = onRefresh
        self.onLoadTopicDetail = onLoadTopicDetail
        self.onScrollTargetHandled = onScrollTargetHandled
        self.onLoadMoreTopicPosts = onLoadMoreTopicPosts
        self.onReloadTopicAiSummary = onReloadTopicAiSummary
        self.onToggleTopicAiSummaryExpanded = onToggleTopicAiSummaryExpanded
        self.onOpenComposer = onOpenComposer
        self.onOpenPostNumber = onOpenPostNumber
        self.onOpenPostReplies = onOpenPostReplies
        self.onLinkTapped = onLinkTapped
        self.onOpenProfile = onOpenProfile
        self.onOpenImage = onOpenImage
        self.onToggleLike = onToggleLike
        self.onSelectReaction = onSelectReaction
        self.onToggleReactionPicker = onToggleReactionPicker
        self.onBoostPost = onBoostPost
        self.quickReactionOptionsProvider = quickReactionOptionsProvider
        self.isReactionPickerExpanded = isReactionPickerExpanded
        self.onQuotePost = onQuotePost
        self.onEditPost = onEditPost
        self.onBookmarkPost = onBookmarkPost
        self.onDeletePost = onDeletePost
        self.onRecoverPost = onRecoverPost
        self.onFlagPost = onFlagPost
        self.onExpandPostText = onExpandPostText
        self.onVotePoll = onVotePoll
        self.onUnvotePoll = onUnvotePoll
        self.onToggleTopicVote = onToggleTopicVote
        self.onShowTopicVoters = onShowTopicVoters
        self.onOpenCategory = onOpenCategory
        self.onOpenTag = onOpenTag
    }
}
