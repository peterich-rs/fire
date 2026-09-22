package com.fire.app.ui.home

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test
import uniffi.fire_uniffi_topics.TopicHomeUnreadDecisionState
import uniffi.fire_uniffi_types.TopicRowState
import uniffi.fire_uniffi_types.TopicSummaryState

class HomeTopicDetailPatcherTest {
    @Test
    fun repository_keepsLatestPatchForCollectorsThatStartLater() {
        val patch = HomeTopicDetailPatch(
            topicId = 4242uL,
            postsCount = 12u,
            replyCount = 11u,
            views = 222u,
            lastReadPostNumber = 12u,
            highestPostNumber = 12u,
        )

        HomeTopicDetailPatchRepository.publishPatch(patch)

        assertEquals(patch, HomeTopicDetailPatchRepository.patches.value[4242uL])
    }

    @Test
    fun patch_updatesLoadedTopicCountsFromDetailHeader() {
        val row = topicRow(
            topicId = 42uL,
            postsCount = 2u,
            replyCount = 1u,
            views = 10u,
            unreadPosts = 2u,
            newPosts = 1u,
            lastReadPostNumber = 4u,
            highestPostNumber = 9u,
            hasUnreadPosts = true,
        )
        val patched = HomeTopicDetailPatcher.patch(
            row,
            HomeTopicDetailPatch(
                topicId = 42uL,
                postsCount = 9u,
                replyCount = 8u,
                views = 321u,
                lastReadPostNumber = 8u,
                highestPostNumber = 9u,
            ),
        )

        requireNotNull(patched)
        assertEquals(9u, patched.topic.postsCount)
        assertEquals(8u, patched.topic.replyCount)
        assertEquals(321u, patched.topic.views)
        assertEquals(8u, patched.topic.lastReadPostNumber)
        assertEquals(9u, patched.topic.highestPostNumber)
        assertEquals(2u, patched.topic.unreadPosts)
        assertEquals(1u, patched.topic.newPosts)
        assertEquals(true, patched.hasUnreadPosts)
    }

    @Test
    fun patch_clearsUnreadStateWhenReadPositionReachesHighestPost() {
        val row = topicRow(
            topicId = 42uL,
            postsCount = 9u,
            replyCount = 8u,
            views = 321u,
            unreadPosts = 2u,
            newPosts = 1u,
            lastReadPostNumber = 7u,
            highestPostNumber = 9u,
            hasUnreadPosts = true,
        )
        val patched = HomeTopicDetailPatcher.patch(
            row,
            HomeTopicDetailPatch(
                topicId = 42uL,
                postsCount = 9u,
                replyCount = 8u,
                views = 321u,
                lastReadPostNumber = 9u,
                highestPostNumber = 9u,
                unread = TopicHomeUnreadDecisionState.CAUGHT_UP,
            ),
        )

        requireNotNull(patched)
        assertEquals(0u, patched.topic.unreadPosts)
        assertEquals(0u, patched.topic.newPosts)
        assertEquals(false, patched.hasUnreadPosts)
    }

    @Test
    fun patch_ignoresOtherTopics() {
        val row = topicRow(
            topicId = 42uL,
            postsCount = 9u,
            replyCount = 8u,
            views = 321u,
            unreadPosts = 1u,
            lastReadPostNumber = 8u,
            highestPostNumber = 9u,
            hasUnreadPosts = true,
        )

        assertNull(
            HomeTopicDetailPatcher.patch(
                row,
                HomeTopicDetailPatch(
                    topicId = 7uL,
                    postsCount = 9u,
                    replyCount = 8u,
                    views = 321u,
                    lastReadPostNumber = 8u,
                    highestPostNumber = 9u,
                ),
            ),
        )
    }

    @Test
    fun patch_noopsWhenContentAndUnreadStateMatch() {
        val row = topicRow(
            topicId = 42uL,
            postsCount = 9u,
            replyCount = 8u,
            views = 321u,
            unreadPosts = 1u,
            lastReadPostNumber = 8u,
            highestPostNumber = 9u,
            hasUnreadPosts = true,
        )

        assertNull(
            HomeTopicDetailPatcher.patch(
                row,
                HomeTopicDetailPatch(
                    topicId = 42uL,
                    postsCount = 9u,
                    replyCount = 8u,
                    views = 321u,
                    lastReadPostNumber = 8u,
                    highestPostNumber = 9u,
                ),
            ),
        )
    }

    private fun topicRow(
        topicId: ULong,
        postsCount: UInt,
        replyCount: UInt,
        views: UInt,
        unreadPosts: UInt = 0u,
        newPosts: UInt = 0u,
        lastReadPostNumber: UInt? = 8u,
        highestPostNumber: UInt = 9u,
        hasUnreadPosts: Boolean = false,
    ): TopicRowState {
        return TopicRowState(
            topic = TopicSummaryState(
                id = topicId,
                title = "Topic",
                slug = "topic",
                postsCount = postsCount,
                replyCount = replyCount,
                views = views,
                likeCount = 1u,
                excerpt = null,
                createdAt = null,
                lastPostedAt = null,
                lastPosterUsername = null,
                categoryId = null,
                pinned = false,
                visible = true,
                closed = false,
                archived = false,
                tags = emptyList(),
                posters = emptyList(),
                participants = emptyList(),
                unseen = false,
                unreadPosts = unreadPosts,
                newPosts = newPosts,
                lastReadPostNumber = lastReadPostNumber,
                highestPostNumber = highestPostNumber,
                bookmarkedPostNumber = null,
                bookmarkId = null,
                bookmarkName = null,
                bookmarkReminderAt = null,
                bookmarkableType = null,
                hasAcceptedAnswer = false,
                canHaveAnswer = false,
            ),
            excerptText = null,
            originalPosterUsername = "alice",
            originalPosterAvatarTemplate = null,
            tagNames = emptyList(),
            statusLabels = emptyList(),
            isPinned = false,
            isClosed = false,
            isArchived = false,
            hasAcceptedAnswer = false,
            hasUnreadPosts = hasUnreadPosts,
            createdTimestampUnixMs = null,
            activityTimestampUnixMs = null,
            lastPosterUsername = null,
        )
    }
}
