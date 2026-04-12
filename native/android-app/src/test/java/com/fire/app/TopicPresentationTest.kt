package com.fire.app

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import uniffi.fire_uniffi.TopicPosterState
import uniffi.fire_uniffi.TopicRowState
import uniffi.fire_uniffi.TopicSummaryState
import uniffi.fire_uniffi.TopicTagState

class TopicPresentationTest {
    @Test
    fun formatTimestamp_unixMs_formatsWithoutReturningNull() {
        val formatted = TopicPresentation.formatTimestamp(1_711_624_600_000uL)
        assertTrue(formatted != null)
    }

    @Test
    fun tagNames_prefersExplicitName_thenSlug() {
        val tags = TopicPresentation.tagNames(
            listOf(
                TopicTagState(id = 1uL, name = "Rust", slug = "rust"),
                TopicTagState(id = 2uL, name = "", slug = "linuxdo"),
            ),
        )

        assertEquals(listOf("Rust", "linuxdo"), tags)
    }

    @Test
    fun topicRowState_carriesRustStatusLabels() {
        val row = TopicRowState(
            topic = TopicSummaryState(
                id = 1uL,
                title = "Topic",
                slug = "topic",
                postsCount = 3u,
                replyCount = 2u,
                views = 10u,
                likeCount = 1u,
                excerpt = null,
                createdAt = null,
                lastPostedAt = null,
                lastPosterUsername = null,
                categoryId = null,
                pinned = true,
                visible = true,
                closed = false,
                archived = true,
                tags = emptyList(),
                posters = listOf(TopicPosterState(userId = 9uL, description = null, extras = null)),
                participants = emptyList(),
                unseen = false,
                unreadPosts = 2u,
                newPosts = 1u,
                lastReadPostNumber = null,
                highestPostNumber = 3u,
                bookmarkedPostNumber = null,
                bookmarkId = null,
                bookmarkName = null,
                bookmarkReminderAt = null,
                bookmarkableType = null,
                hasAcceptedAnswer = true,
                canHaveAnswer = true,
            ),
            excerptText = "Hello Fire",
            originalPosterUsername = "alice",
            originalPosterAvatarTemplate = null,
            tagNames = listOf("Rust"),
            statusLabels = listOf("Pinned", "Archived", "Solved", "Unread 2", "New 1"),
            isPinned = true,
            isClosed = false,
            isArchived = true,
            hasAcceptedAnswer = true,
            hasUnreadPosts = true,
            createdTimestampUnixMs = 1_711_624_600_000uL,
            activityTimestampUnixMs = 1_711_630_000_000uL,
            lastPosterUsername = "alice",
        )

        assertEquals(listOf("Pinned", "Archived", "Solved", "Unread 2", "New 1"), row.statusLabels)
        assertTrue(row.isPinned)
        assertTrue(row.hasUnreadPosts)
    }
}
