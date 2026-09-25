package com.fire.app.ui.home

import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import uniffi.fire_uniffi_topics.TopicHomeRowCountPatchState
import uniffi.fire_uniffi_topics.TopicHomeUnreadDecisionState
import uniffi.fire_uniffi_types.TopicRowState

data class HomeTopicDetailPatch(
    val topicId: ULong,
    val postsCount: UInt,
    val replyCount: UInt,
    val views: UInt,
    val lastReadPostNumber: UInt?,
    val highestPostNumber: UInt,
    val unread: TopicHomeUnreadDecisionState = TopicHomeUnreadDecisionState.STILL_UNREAD,
) {
    companion object {
        fun from(patch: TopicHomeRowCountPatchState): HomeTopicDetailPatch {
            return HomeTopicDetailPatch(
                topicId = patch.topicId,
                postsCount = patch.postsCount,
                replyCount = patch.replyCount,
                views = patch.views,
                lastReadPostNumber = patch.lastReadPostNumber,
                highestPostNumber = patch.highestPostNumber,
                unread = patch.unread,
            )
        }
    }
}

object HomeTopicDetailPatchRepository {
    private val _patches = MutableStateFlow<Map<ULong, HomeTopicDetailPatch>>(emptyMap())
    val patches = _patches.asStateFlow()

    fun publish(patch: TopicHomeRowCountPatchState) {
        publishPatch(HomeTopicDetailPatch.from(patch))
    }

    fun publishPatch(patch: HomeTopicDetailPatch) {
        _patches.value = _patches.value + (patch.topicId to patch)
    }
}

object HomeTopicDetailPatcher {
    fun patch(row: TopicRowState, patch: HomeTopicDetailPatch): TopicRowState? {
        if (row.topic.id != patch.topicId) {
            return null
        }
        val topic = row.topic
        val nextUnreadPosts: UInt
        val nextNewPosts: UInt
        val nextHasUnreadPosts: Boolean
        when (patch.unread) {
            TopicHomeUnreadDecisionState.WHEN_LAST_READ_MISSING -> {
                nextHasUnreadPosts = row.hasUnreadPosts
                if (row.hasUnreadPosts) {
                    nextUnreadPosts = topic.unreadPosts
                    nextNewPosts = topic.newPosts
                } else {
                    nextUnreadPosts = 0u
                    nextNewPosts = 0u
                }
            }
            TopicHomeUnreadDecisionState.CAUGHT_UP -> {
                nextUnreadPosts = 0u
                nextNewPosts = 0u
                nextHasUnreadPosts = false
            }
            TopicHomeUnreadDecisionState.STILL_UNREAD -> {
                nextUnreadPosts = topic.unreadPosts
                nextNewPosts = topic.newPosts
                nextHasUnreadPosts = true
            }
        }
        if (topic.postsCount == patch.postsCount &&
            topic.replyCount == patch.replyCount &&
            topic.views == patch.views &&
            topic.lastReadPostNumber == patch.lastReadPostNumber &&
            topic.highestPostNumber == patch.highestPostNumber &&
            topic.unreadPosts == nextUnreadPosts &&
            topic.newPosts == nextNewPosts &&
            row.hasUnreadPosts == nextHasUnreadPosts
        ) {
            return null
        }

        return row.copy(
            topic = topic.copy(
                postsCount = patch.postsCount,
                replyCount = patch.replyCount,
                views = patch.views,
                lastReadPostNumber = patch.lastReadPostNumber,
                highestPostNumber = patch.highestPostNumber,
                unreadPosts = nextUnreadPosts,
                newPosts = nextNewPosts,
            ),
            hasUnreadPosts = nextHasUnreadPosts,
        )
    }
}
