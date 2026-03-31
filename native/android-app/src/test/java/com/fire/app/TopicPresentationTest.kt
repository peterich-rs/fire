package com.fire.app

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test
import uniffi.fire_uniffi.TopicPostState

class TopicPresentationTest {
    @Test
    fun parseCategories_readsSiteCategories() {
        val categories = TopicPresentation.parseCategories(
            """
            {
              "site": {
                "categories": [
                  {
                    "id": 7,
                    "name": "Rust",
                    "slug": "rust",
                    "parent_category_id": 2,
                    "color": "FFFFFF",
                    "text_color": "000000"
                  }
                ]
              }
            }
            """.trimIndent(),
        )

        assertEquals(1, categories.size)
        assertEquals("Rust", categories[7uL]?.name)
        assertEquals("rust", categories[7uL]?.slug)
        assertEquals(2uL, categories[7uL]?.parentCategoryId)
        assertEquals("FFFFFF", categories[7uL]?.colorHex)
        assertEquals("000000", categories[7uL]?.textColorHex)
    }

    @Test
    fun nextPage_readsRelativeAndAbsoluteMoreTopicsUrls() {
        assertEquals(3u, TopicPresentation.nextPage("/latest?page=3"))
        assertEquals(9u, TopicPresentation.nextPage("https://linux.do/latest?page=9"))
        assertNull(TopicPresentation.nextPage("/latest"))
        assertNull(TopicPresentation.nextPage(null))
    }

    @Test
    fun buildThreadPresentation_groupsNestedRepliesUnderTopLevelFloors() {
        val thread = TopicPresentation.buildThreadPresentation(
            listOf(
                post(postNumber = 1u, replyToPostNumber = null, username = "author"),
                post(postNumber = 2u, replyToPostNumber = 1u, username = "floor-a"),
                post(postNumber = 3u, replyToPostNumber = 2u, username = "nested-a1"),
                post(postNumber = 4u, replyToPostNumber = 3u, username = "nested-a2"),
                post(postNumber = 5u, replyToPostNumber = 1u, username = "floor-b"),
                post(postNumber = 6u, replyToPostNumber = 99u, username = "orphan"),
            ),
        )

        assertEquals(1u, thread.originalPost?.postNumber)
        assertEquals(listOf(2u, 5u, 6u), thread.replySections.map { it.anchorPost.postNumber })
        assertEquals(listOf(3u, 4u), thread.replySections[0].replies.map { it.post.postNumber })
        assertEquals(listOf(1, 2), thread.replySections[0].replies.map { it.depth })
        assertEquals(0, thread.replySections[1].replies.size)
        assertEquals(0, thread.replySections[2].replies.size)
    }

    private fun post(postNumber: UInt, replyToPostNumber: UInt?, username: String): TopicPostState {
        return TopicPostState(
            id = postNumber.toULong(),
            username = username,
            name = null,
            avatarTemplate = null,
            cooked = "<p>$username</p>",
            postNumber = postNumber,
            postType = 1,
            createdAt = "2026-03-28T10:00:00Z",
            updatedAt = "2026-03-28T10:00:00Z",
            likeCount = 0u,
            replyCount = 0u,
            replyToPostNumber = replyToPostNumber,
            bookmarked = false,
            bookmarkId = null,
            reactions = emptyList(),
            currentUserReaction = null,
            acceptedAnswer = false,
            canEdit = false,
            canDelete = false,
            canRecover = false,
            hidden = false,
        )
    }
}
