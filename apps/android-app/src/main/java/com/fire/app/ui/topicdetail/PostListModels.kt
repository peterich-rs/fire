package com.fire.app.ui.topicdetail

import com.fire.app.richtext.FireCookedImage
import uniffi.fire_uniffi_topics.PollState
import uniffi.fire_uniffi_topics.TopicPostState

data class PostRow(
    val post: TopicPostState,
    val depth: Int = 0,
    val parentPostNumber: UInt? = null,
    val hasChildren: Boolean = false,
    val usesTitleWidthBody: Boolean = false,
    val hiddenReplyCount: UInt = 0u,
)

data class PostRowCallbacks(
    val reactionIds: () -> List<String> = { emptyList() },
    val onPostClick: (TopicPostState) -> Unit = {},
    val onReplyClick: (TopicPostState) -> Unit = {},
    val onQuoteClick: (TopicPostState) -> Unit = {},
    val onHeartClick: (TopicPostState) -> Unit = {},
    val onReactClick: (TopicPostState) -> Unit = {},
    val onBookmarkClick: (TopicPostState) -> Unit = {},
    val onVotePoll: (TopicPostState, PollState, List<String>) -> Unit = { _, _, _ -> },
    val onUnvotePoll: (TopicPostState, PollState) -> Unit = { _, _ -> },
    val onReactionsClick: (TopicPostState) -> Unit = {},
    val onReplyContextClick: (TopicPostState) -> Unit = {},
    val onMoreRepliesClick: (TopicPostState) -> Unit = {},
    val onDeletePostClick: (TopicPostState) -> Unit = {},
    val onRecoverPostClick: (TopicPostState) -> Unit = {},
    val onFlagPostClick: (TopicPostState) -> Unit = {},
    val onAcceptSolutionClick: (TopicPostState) -> Unit = {},
    val onBoostClick: (TopicPostState) -> Unit = {},
    val onEditPostClick: (TopicPostState) -> Unit = {},
    val onImageClick: (FireCookedImage) -> Unit = {},
    val onAuthorClick: (String) -> Unit = {},
    val onLinkClick: (String) -> Unit = {},
)
