package com.fire.app.ui.topicdetail

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test
import uniffi.fire_uniffi_topics.TopicDetailAuthorDisplayState
import uniffi.fire_uniffi_topics.TopicDetailChromeState
import uniffi.fire_uniffi_topics.TopicDetailComposerModelState
import uniffi.fire_uniffi_topics.TopicDetailPhaseState
import uniffi.fire_uniffi_topics.TopicDetailReplyContextChangeState
import uniffi.fire_uniffi_topics.TopicDetailRevisionsState
import uniffi.fire_uniffi_topics.TopicDetailSidecarModelState
import uniffi.fire_uniffi_topics.TopicDetailSnapshotChangeState
import uniffi.fire_uniffi_topics.TopicDetailUiRowState
import uniffi.fire_uniffi_topics.TopicDetailUiSnapshotState

class TopicDetailSnapshotMirrorTest {
    @Test
    fun firstChangePullsFullSnapshot() {
        val mirror = TopicDetailSnapshotMirror()
        val full = snapshot(generation = 1uL, rows = listOf(row(postId = 1uL, likeCount = 0u)))
        val applied = mirror.apply(
            change(generation = 1uL, baseGeneration = null),
            TopicDetailFullSnapshotSource { full },
        )
        assertEquals(1uL, applied?.generation)
        assertEquals(listOf(1uL), applied?.rows?.map { it.postId })
    }

    @Test
    fun likeChangeUpsertsOneRow() {
        val mirror = TopicDetailSnapshotMirror()
        val first = snapshot(
            generation = 1uL,
            rows = listOf(
                row(postId = 1uL, likeCount = 0u),
                row(postId = 2uL, likeCount = 0u, isOriginalPost = false),
            ),
        )
        mirror.apply(change(generation = 1uL, baseGeneration = null), TopicDetailFullSnapshotSource { first })
        val liked = row(postId = 2uL, likeCount = 4u, isOriginalPost = false, interactionChecksum = 99uL)
        val applied = mirror.apply(
            change(generation = 2uL, baseGeneration = 1uL, upsertedRows = listOf(liked)),
            TopicDetailFullSnapshotSource { first },
        )
        assertEquals(2uL, applied?.generation)
        assertEquals(0u, applied?.rows?.first { it.postId == 1uL }?.likeCount)
        assertEquals(4u, applied?.rows?.first { it.postId == 2uL }?.likeCount)
    }

    @Test
    fun staleGenerationIsDropped() {
        val mirror = TopicDetailSnapshotMirror()
        val first = snapshot(generation = 2uL, rows = listOf(row(postId = 1uL, likeCount = 0u)))
        mirror.apply(change(generation = 2uL, baseGeneration = null), TopicDetailFullSnapshotSource { first })
        val applied = mirror.apply(
            change(generation = 2uL, baseGeneration = 1uL),
            TopicDetailFullSnapshotSource { first },
        )
        assertNull(applied)
    }

    @Test
    fun mismatchedBaselinePullsFullSnapshot() {
        val mirror = TopicDetailSnapshotMirror()
        val first = snapshot(generation = 1uL, rows = listOf(row(postId = 1uL, likeCount = 0u)))
        mirror.apply(change(generation = 1uL, baseGeneration = null), TopicDetailFullSnapshotSource { first })
        val resync = snapshot(
            generation = 4uL,
            rows = listOf(
                row(postId = 1uL, likeCount = 1u),
                row(postId = 3uL, likeCount = 0u, isOriginalPost = false),
            ),
        )
        val applied = mirror.apply(
            change(generation = 4uL, baseGeneration = 2uL),
            TopicDetailFullSnapshotSource { resync },
        )
        assertEquals(listOf(1uL, 3uL), applied?.rows?.map { it.postId })
    }
}

private fun change(
    generation: ULong,
    baseGeneration: ULong?,
    upsertedRows: List<TopicDetailUiRowState> = emptyList(),
    rowOrder: List<ULong>? = null,
): TopicDetailSnapshotChangeState {
    return TopicDetailSnapshotChangeState(
        topicId = 42uL,
        generation = generation,
        baseGeneration = baseGeneration,
        revisions = TopicDetailRevisionsState(
            collection = 1uL,
            chrome = 1uL,
            sidecar = 1uL,
            interaction = generation,
            composer = 1uL,
        ),
        status = null,
        chrome = null,
        composer = null,
        sidecar = null,
        replyContext = TopicDetailReplyContextChangeState.Unchanged,
        flagTypes = null,
        rowOrder = rowOrder,
        upsertedRows = upsertedRows,
        homeRowPatch = null,
    )
}

private fun snapshot(
    generation: ULong,
    rows: List<TopicDetailUiRowState>,
): TopicDetailUiSnapshotState {
    return TopicDetailUiSnapshotState(
        topicId = 42uL,
        generation = generation,
        phase = TopicDetailPhaseState.READY,
        loadError = null,
        notice = null,
        hasMore = false,
        isLoadingMore = false,
        loadMoreError = null,
        scrollTargetPostNumber = null,
        collectionRevision = 1uL,
        chromeRevision = 1uL,
        sidecarRevision = 1uL,
        interactionRevision = 1uL,
        composerRevision = 1uL,
        chrome = TopicDetailChromeState(
            title = "topic",
            slug = "topic",
            archetype = null,
            bookmarked = false,
            bookmarkId = null,
            bookmarkName = null,
            bookmarkReminderAt = null,
            notificationLevel = null,
            canEdit = false,
            categoryId = null,
            tags = emptyList(),
            views = 0u,
            postsCount = rows.size.toUInt(),
            replyCount = maxOf(rows.size, 1).toUInt() - 1u,
            likeCount = 0u,
            voteCount = 0,
            userVoted = false,
            canVote = false,
            hasAcceptedAnswer = false,
            createdAt = null,
            highestPostNumber = rows.lastOrNull()?.postNumber ?: 1u,
            lastReadPostNumber = null,
            participants = emptyList(),
            summarizable = false,
        ),
        composer = TopicDetailComposerModelState(typingUsers = emptyList(), isSubmitting = false),
        sidecar = TopicDetailSidecarModelState(
            summarizedText = null,
            algorithm = null,
            outdated = false,
            canRegenerate = false,
            newPostsSinceSummary = 0u,
            updatedAt = null,
            isLoading = false,
            error = null,
        ),
        rows = rows,
        focusedReplyContext = null,
        flagTypes = emptyList(),
        homeRowPatch = null,
    )
}

private fun row(
    postId: ULong,
    likeCount: UInt,
    isOriginalPost: Boolean = true,
    interactionChecksum: ULong = 1uL,
): TopicDetailUiRowState {
    return TopicDetailUiRowState(
        postId = postId,
        postNumber = postId.toUInt(),
        rootPostNumber = 1u,
        parentPostNumber = if (isOriginalPost) null else 1u,
        depth = if (isOriginalPost) 0.toUShort() else 1.toUShort(),
        hasChildren = false,
        isLastSibling = true,
        descendantCount = 0u,
        author = TopicDetailAuthorDisplayState(
            username = "user-$postId",
            name = null,
            avatarTemplate = null,
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
        ),
        presentation = null,
        layoutChecksum = 1uL,
        interactionChecksum = interactionChecksum,
        authorBandChecksum = 1uL,
        textBandChecksum = 1uL,
        actionsBandChecksum = 1uL,
        reactionsBandChecksum = 1uL,
        createdAt = null,
        updatedAt = null,
        postType = 1,
        replyCount = 0u,
        replyToUsername = null,
        replyToUser = null,
        likeCount = likeCount,
        reactions = emptyList(),
        currentReactionId = null,
        polls = emptyList(),
        boosts = emptyList(),
        acceptedAnswer = false,
        canAcceptAnswer = false,
        canUnacceptAnswer = false,
        canEdit = false,
        canDelete = false,
        canRecover = false,
        canBoost = false,
        bookmarked = false,
        bookmarkId = null,
        bookmarkName = null,
        bookmarkReminderAt = null,
        hidden = false,
        isMutating = false,
        isLoadingReplyContext = false,
        isOriginalPost = isOriginalPost,
    )
}
