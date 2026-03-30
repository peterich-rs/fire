package com.fire.app

import org.junit.Assert.assertEquals
import org.junit.Test
import uniffi.fire_uniffi.TopicSummaryState
import uniffi.fire_uniffi.TopicTagState

class TopicPresentationTest {
    @Test
    fun plainTextFromHtml_normalizesBasicMarkup() {
        assertEquals(
            "Hello\n\n World",
            TopicPresentation.plainTextFromHtml("<p>Hello</p><p>World</p>"),
        )
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
    fun topicStatusLabels_reflects_flags_and_counters() {
        val labels = TopicPresentation.topicStatusLabels(
            TopicSummaryState(
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
                posters = emptyList(),
                unseen = false,
                unreadPosts = 2u,
                newPosts = 1u,
                lastReadPostNumber = null,
                highestPostNumber = 3u,
                hasAcceptedAnswer = true,
                canHaveAnswer = true,
            ),
        )

        assertEquals(listOf("Pinned", "Archived", "Solved", "2 unread", "1 new"), labels)
    }
}
