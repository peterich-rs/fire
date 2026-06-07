package com.fire.app.ui.topicdetail

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test
import uniffi.fire_uniffi_topics.TopicPostAuthorMetadataState
import uniffi.fire_uniffi_topics.TopicPostState
import uniffi.fire_uniffi_topics.TopicTreeRowState

class TopicDetailPostRowsTest {
    @Test
    fun uniqueTreeRows_excludesBodyPostAndKeepsLatestDuplicateValue() {
        val body = post(id = 1uL, postNumber = 1u, username = "author")
        val firstReply = post(id = 2uL, postNumber = 2u, username = "reply-old")
        val refreshedReply = post(id = 2uL, postNumber = 2u, username = "reply-new")
        val secondReply = post(id = 3uL, postNumber = 3u, username = "reply-b")

        val rows = TopicDetailPostRows.uniqueTreeRows(
            rows = listOf(row(body), row(firstReply), row(refreshedReply), row(secondReply)),
            bodyPostId = body.id,
        )

        assertEquals(listOf(2uL, 3uL), rows.map { it.postId })
        assertEquals(listOf(2u, 3u), rows.map { it.postNumber })
    }

    @Test
    fun postsForDetail_keepsBodyPostAndDeduplicatesTreeRows() {
        val body = post(id = 1uL, postNumber = 1u, username = "author")
        val duplicateBody = post(id = 1uL, postNumber = 1u, username = "duplicate-author")
        val firstReply = post(id = 2uL, postNumber = 2u, username = "reply-old")
        val refreshedReply = post(id = 2uL, postNumber = 2u, username = "reply-new")

        val posts = TopicDetailPostRows.postsForDetail(
            bodyPost = body,
            loadedPosts = listOf(duplicateBody, firstReply, refreshedReply),
            replyRows = listOf(row(duplicateBody), row(firstReply), row(refreshedReply)),
        )

        assertEquals(listOf(1uL, 2uL), posts.map { it.id })
        assertEquals(listOf("author", "reply-new"), posts.map { it.username })
    }

    @Test
    fun initialScrollTargetPostNumber_prefersExplicitTarget() {
        val target = TopicDetailPostRows.initialScrollTargetPostNumber(
            explicitTargetPostNumber = 42u,
            suggestedUnreadRootPostNumber = 7u,
            shouldUseSuggestedUnreadRootTarget = true,
        )

        assertEquals(42u, target)
    }

    @Test
    fun initialScrollTargetPostNumber_usesSuggestedUnreadRootOnlyWhenAllowed() {
        assertEquals(
            7u,
            TopicDetailPostRows.initialScrollTargetPostNumber(
                explicitTargetPostNumber = null,
                suggestedUnreadRootPostNumber = 7u,
                shouldUseSuggestedUnreadRootTarget = true,
            ),
        )
        assertNull(
            TopicDetailPostRows.initialScrollTargetPostNumber(
                explicitTargetPostNumber = null,
                suggestedUnreadRootPostNumber = 7u,
                shouldUseSuggestedUnreadRootTarget = false,
            ),
        )
        assertNull(
            TopicDetailPostRows.initialScrollTargetPostNumber(
                explicitTargetPostNumber = 0u,
                suggestedUnreadRootPostNumber = 1u,
                shouldUseSuggestedUnreadRootTarget = true,
            ),
        )
    }

    private fun post(
        id: ULong,
        postNumber: UInt,
        username: String,
    ): TopicPostState {
        return TopicPostState(
            id = id,
            username = username,
            name = null,
            avatarTemplate = null,
            authorMetadata = emptyAuthorMetadata(),
            cooked = "<p>$username</p>",
            raw = null,
            postNumber = postNumber,
            postType = 1,
            createdAt = "2026-03-28T10:00:00Z",
            updatedAt = "2026-03-28T10:00:00Z",
            likeCount = 0u,
            replyCount = 0u,
            replyToPostNumber = null,
            replyToUser = null,
            bookmarked = false,
            bookmarkId = null,
            bookmarkName = null,
            bookmarkReminderAt = null,
            reactions = emptyList(),
            currentUserReaction = null,
            polls = emptyList(),
            renderDocument = null,
            acceptedAnswer = false,
            canAcceptAnswer = false,
            canUnacceptAnswer = false,
            canEdit = false,
            canDelete = false,
            canRecover = false,
            hidden = false,
        )
    }

    private fun row(post: TopicPostState): TopicTreeRowState {
        return TopicTreeRowState(
            postId = post.id,
            postNumber = post.postNumber,
            rootPostNumber = 1u,
            parentPostNumber = 1u,
            depth = 1u.toUShort(),
            preorderIndex = post.postNumber - 1u,
            hasChildren = false,
            descendantCount = 0u,
            siblingIndex = 0u.toUShort(),
            isLastSibling = true,
        )
    }

    private fun emptyAuthorMetadata(): TopicPostAuthorMetadataState {
        return TopicPostAuthorMetadataState(
            userId = null,
            userTitle = null,
            primaryGroupName = null,
            flairUrl = null,
            flairName = null,
            flairBgColor = null,
            flairColor = null,
            flairGroupId = null,
            moderator = false,
            admin = false,
            groupModerator = false,
            userStatusEmoji = null,
            userStatusDescription = null,
        )
    }
}
