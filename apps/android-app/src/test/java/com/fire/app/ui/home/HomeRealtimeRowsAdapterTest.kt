package com.fire.app.ui.home

import org.junit.Assert.assertEquals
import org.junit.Test
import uniffi.fire_uniffi_types.TopicRowState
import uniffi.fire_uniffi_types.TopicSummaryState

class HomeRealtimeRowsAdapterTest {
    @Test
    fun upsert_replacesExistingAndPendsWhenNotAtTop() {
        val store = HomeRealtimeRowsStore()
        store.upsertRealtimeRows(listOf(row(1uL, 3u)), prependNow = true)
        assertEquals(1, store.itemCount)
        assertEquals(0, store.pendingCount)

        store.upsertRealtimeRows(listOf(row(1uL, 8u), row(2uL, 1u)), prependNow = false)
        assertEquals(1, store.itemCount)
        assertEquals(1, store.pendingCount)
        assertEquals(8u, store.rowAt(0).topic.postsCount)

        store.flushPendingRows()
        assertEquals(2, store.itemCount)
        assertEquals(0, store.pendingCount)
        assertEquals(setOf(1uL, 2uL), store.snapshotIds())
    }

    @Test
    fun upsert_prependsImmediatelyWhenAtTop() {
        val store = HomeRealtimeRowsStore()
        store.upsertRealtimeRows(listOf(row(2uL, 1u)), prependNow = true)
        assertEquals(1, store.itemCount)
        assertEquals(0, store.pendingCount)
        assertEquals(setOf(2uL), store.snapshotIds())
    }

    private fun row(id: ULong, postsCount: UInt): TopicRowState {
        return TopicRowState(
            topic = TopicSummaryState(
                id = id,
                title = "topic $id",
                slug = "topic-$id",
                postsCount = postsCount,
                replyCount = 0u,
                views = 0u,
                likeCount = 0u,
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
                unreadPosts = 0u,
                newPosts = 0u,
                lastReadPostNumber = null,
                highestPostNumber = postsCount,
                bookmarkedPostNumber = null,
                bookmarkId = null,
                bookmarkName = null,
                bookmarkReminderAt = null,
                bookmarkableType = null,
                hasAcceptedAnswer = false,
                canHaveAnswer = false,
            ),
            excerptText = null,
            originalPosterUsername = null,
            originalPosterAvatarTemplate = null,
            tagNames = emptyList(),
            statusLabels = emptyList(),
            isPinned = false,
            isClosed = false,
            isArchived = false,
            hasAcceptedAnswer = false,
            hasUnreadPosts = false,
            createdTimestampUnixMs = null,
            activityTimestampUnixMs = null,
            lastPosterUsername = null,
        )
    }
}
