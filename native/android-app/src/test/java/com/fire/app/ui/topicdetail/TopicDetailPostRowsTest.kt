package com.fire.app.ui.topicdetail

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test
import uniffi.fire_uniffi_topics.TopicPostAuthorMetadataState
import uniffi.fire_uniffi_topics.TopicPostBoostState
import uniffi.fire_uniffi_topics.TopicPostBoostUserState
import uniffi.fire_uniffi_topics.TopicPostState
import uniffi.fire_uniffi_topics.TopicTreeRowState
import uniffi.fire_uniffi_types.RenderDocumentState

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

    @Test
    fun usesBoostBarrage_onlyForOriginalPostRowsWithBoosts() {
        val original = PostRow(
            post = post(id = 1uL, postNumber = 1u, username = "author", boosts = listOf(boost())),
            depth = 0,
        )
        val reply = PostRow(
            post = post(id = 2uL, postNumber = 2u, username = "reply", boosts = listOf(boost())),
            depth = 1,
        )
        val originalWithoutBoosts = PostRow(
            post = post(id = 1uL, postNumber = 1u, username = "author"),
            depth = 0,
        )

        assertEquals(true, TopicDetailPostRows.usesBoostBarrage(original))
        assertEquals(false, TopicDetailPostRows.usesBoostBarrage(reply))
        assertEquals(false, TopicDetailPostRows.usesBoostBarrage(originalWithoutBoosts))
    }

    @Test
    fun manualBoostLayout_fillsFirstRowThenSecondBeforeHorizontalOverflow() {
        val layout = TopicDetailManualBoostLayout.placements(
            chipWidths = listOf(60, 70, 80, 90),
            pageWidth = 200,
            rowCount = 2,
            chipSpacing = 8,
        )

        assertEquals(listOf(0, 0, 1, 1), layout.placements.map { it.rowIndex })
        assertEquals(listOf(0, 68, 0, 88), layout.placements.map { it.x })
        assertEquals(200, layout.contentWidth)
        assertEquals(2, layout.usedRowCount)
    }

    @Test
    fun manualBoostLayout_doesNotBackfillFirstRowAfterMovingToSecondRow() {
        val layout = TopicDetailManualBoostLayout.placements(
            chipWidths = listOf(160, 50, 20),
            pageWidth = 200,
            rowCount = 2,
            chipSpacing = 8,
        )

        assertEquals(listOf(0, 1, 1), layout.placements.map { it.rowIndex })
        assertEquals(listOf(0, 0, 58), layout.placements.map { it.x })
        assertEquals(200, layout.contentWidth)
        assertEquals(2, layout.usedRowCount)
    }

    @Test
    fun manualBoostLayout_addsOverflowAsNextTwoRowPage() {
        val layout = TopicDetailManualBoostLayout.placements(
            chipWidths = listOf(120, 70, 120, 70, 100),
            pageWidth = 200,
            rowCount = 2,
            chipSpacing = 8,
        )

        assertEquals(listOf(0, 0, 1, 1, 0), layout.placements.map { it.rowIndex })
        assertEquals(208, layout.placements[4].x)
        assertEquals(true, layout.contentWidth > 200)
        assertEquals(2, layout.usedRowCount)
    }

    @Test
    fun manualBoostLayout_reportsSingleUsedRowWhenEverythingFitsFirstRow() {
        val layout = TopicDetailManualBoostLayout.placements(
            chipWidths = listOf(40, 50),
            pageWidth = 200,
            rowCount = 2,
            chipSpacing = 8,
        )

        assertEquals(listOf(0, 0), layout.placements.map { it.rowIndex })
        assertEquals(1, layout.usedRowCount)
    }

    @Test
    fun projectRows_preservesTreeOrderAndDepth() {
        val root = post(id = 2uL, postNumber = 2u, username = "root")
        val child = post(id = 3uL, postNumber = 3u, username = "child")
        val laterRoot = post(id = 4uL, postNumber = 4u, username = "later")
        val rows = listOf(
            row(root, parentPostNumber = 1u, depth = 1u),
            row(child, parentPostNumber = 2u, depth = 2u),
            row(laterRoot, parentPostNumber = 1u, depth = 1u),
        )

        val projected = TopicDetailPostRows.projectRows(
            rows = rows,
            postsById = TopicDetailPostRows.postsById(listOf(root, child, laterRoot)),
            expandedReplyRootPostIds = setOf(root.id),
        )

        assertEquals(listOf(2u, 3u, 4u), projected.map { it.post.postNumber })
        assertEquals(listOf(1, 2, 1), projected.map { it.depth })
        assertEquals(listOf(1u, 2u, 1u), projected.map { it.parentPostNumber })
    }

    @Test
    fun projectRows_hidesSecondaryRepliesBehindRootShortcutByDefault() {
        val root = post(id = 2uL, postNumber = 2u, username = "root")
        val child = post(id = 3uL, postNumber = 3u, username = "child")
        val grandchild = post(id = 4uL, postNumber = 4u, username = "grandchild")
        val laterRoot = post(id = 5uL, postNumber = 5u, username = "later")
        val rows = listOf(
            row(root, parentPostNumber = 1u, depth = 1u),
            row(child, parentPostNumber = 2u, depth = 2u),
            row(grandchild, parentPostNumber = 3u, depth = 3u),
            row(laterRoot, parentPostNumber = 1u, depth = 1u),
        )

        val projected = TopicDetailPostRows.projectRows(
            rows = rows,
            postsById = TopicDetailPostRows.postsById(listOf(root, child, grandchild, laterRoot)),
        )

        assertEquals(listOf(2u, 5u), projected.map { it.post.postNumber })
        assertEquals(2u, projected.first().hiddenReplyCount)
        assertEquals(0u, projected.last().hiddenReplyCount)
    }

    @Test
    fun projectRows_keepsFocusedSecondaryAncestryVisibleWithoutExpandingThread() {
        val root = post(id = 2uL, postNumber = 2u, username = "root")
        val child = post(id = 3uL, postNumber = 3u, username = "child")
        val grandchild = post(id = 4uL, postNumber = 4u, username = "grandchild")
        val sibling = post(id = 5uL, postNumber = 5u, username = "sibling")
        val rows = listOf(
            row(root, parentPostNumber = 1u, depth = 1u),
            row(child, parentPostNumber = 2u, depth = 2u),
            row(grandchild, parentPostNumber = 3u, depth = 3u),
            row(sibling, parentPostNumber = 2u, depth = 2u),
        )

        val projected = TopicDetailPostRows.projectRows(
            rows = rows,
            postsById = TopicDetailPostRows.postsById(listOf(root, child, grandchild, sibling)),
            focusedPostNumber = grandchild.postNumber,
        )

        assertEquals(listOf(2u, 3u, 4u), projected.map { it.post.postNumber })
        assertEquals(listOf(1, 2, 3), projected.map { it.depth })
        assertEquals(1u, projected.first().hiddenReplyCount)
    }

    @Test
    fun projectRows_expandedReplyThreadShowsLoadedSecondaryReplies() {
        val root = post(id = 2uL, postNumber = 2u, username = "root")
        val child = post(id = 3uL, postNumber = 3u, username = "child")
        val sibling = post(id = 4uL, postNumber = 4u, username = "sibling")
        val rows = listOf(
            row(root, parentPostNumber = 1u, depth = 1u),
            row(child, parentPostNumber = 2u, depth = 2u),
            row(sibling, parentPostNumber = 2u, depth = 2u),
        )

        val projected = TopicDetailPostRows.projectRows(
            rows = rows,
            postsById = TopicDetailPostRows.postsById(listOf(root, child, sibling)),
            expandedReplyRootPostIds = setOf(root.id),
        )

        assertEquals(listOf(2u, 3u, 4u), projected.map { it.post.postNumber })
        assertEquals(listOf(0u, 0u, 0u), projected.map { it.hiddenReplyCount })
    }

    @Test
    fun searchMatches_usesLoadedRenderPlainTextAndSortsByFloor() {
        val later = post(
            id = 3uL,
            postNumber = 3u,
            username = "later",
            plainText = "Needle in a later post",
        )
        val earlier = post(
            id = 2uL,
            postNumber = 2u,
            username = "earlier",
            plainText = "accent NEEDLE match",
        )
        val duplicate = post(
            id = 2uL,
            postNumber = 2u,
            username = "duplicate",
            plainText = "needle duplicate",
        )
        val cookedOnly = post(
            id = 4uL,
            postNumber = 4u,
            username = "needle-cooked-only",
        )

        val matches = TopicDetailPostRows.searchMatches(
            query = " needle ",
            posts = listOf(later, earlier, duplicate, cookedOnly),
        )

        assertEquals(
            listOf(
                TopicDetailPostRows.SearchMatch(postId = earlier.id, postNumber = 2u),
                TopicDetailPostRows.SearchMatch(postId = later.id, postNumber = 3u),
            ),
            matches,
        )
    }

    private fun post(
        id: ULong,
        postNumber: UInt,
        username: String,
        boosts: List<TopicPostBoostState> = emptyList(),
        replyToPostNumber: UInt? = null,
        plainText: String? = null,
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
            replyToPostNumber = replyToPostNumber,
            replyToUser = null,
            bookmarked = false,
            bookmarkId = null,
            bookmarkName = null,
            bookmarkReminderAt = null,
            reactions = emptyList(),
            currentUserReaction = null,
            boosts = boosts,
            canBoost = false,
            polls = emptyList(),
            renderDocument = plainText?.let {
                RenderDocumentState(
                    blocks = emptyList(),
                    plainText = it,
                    imageAttachments = emptyList(),
                )
            },
            acceptedAnswer = false,
            canAcceptAnswer = false,
            canUnacceptAnswer = false,
            canEdit = false,
            canDelete = false,
            canRecover = false,
            hidden = false,
        )
    }

    private fun boost(): TopicPostBoostState {
        return TopicPostBoostState(
            id = 99uL,
            cooked = "<p>Hello</p>",
            renderDocument = null,
            displayText = "Hello",
            user = TopicPostBoostUserState(
                id = 7uL,
                username = "booster",
                name = null,
                avatarTemplate = null,
            ),
            canDelete = false,
            canFlag = false,
            userFlagStatus = null,
            availableFlags = emptyList(),
        )
    }

    private fun row(
        post: TopicPostState,
        parentPostNumber: UInt = 1u,
        depth: UInt = 1u,
    ): TopicTreeRowState {
        return TopicTreeRowState(
            postId = post.id,
            postNumber = post.postNumber,
            rootPostNumber = 1u,
            parentPostNumber = parentPostNumber,
            depth = depth.toUShort(),
            preorderIndex = post.postNumber - 1u,
            hasChildren = depth == 1u,
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
