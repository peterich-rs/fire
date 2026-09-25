package com.fire.app.ui.topicdetail

import uniffi.fire_uniffi_topics.TopicPostState
import uniffi.fire_uniffi_topics.TopicTreeRowState

object TopicDetailPostRows {
    data class SearchMatch(
        val postId: ULong,
        val postNumber: UInt,
    )

    fun uniqueTreeRows(
        rows: List<TopicTreeRowState>,
        bodyPostId: ULong? = null,
    ): List<TopicTreeRowState> {
        val rowsByPostId = LinkedHashMap<ULong, TopicTreeRowState>(rows.size)
        for (row in rows) {
            if (row.postId == bodyPostId) continue
            rowsByPostId[row.postId] = row
        }
        return rowsByPostId.values.toList()
    }

    fun initialScrollTargetPostNumber(
        explicitTargetPostNumber: UInt?,
        suggestedUnreadRootPostNumber: UInt?,
        shouldUseSuggestedUnreadRootTarget: Boolean,
    ): UInt? {
        explicitTargetPostNumber?.takeIf { it > 0u }?.let { return it }
        if (!shouldUseSuggestedUnreadRootTarget) return null
        return suggestedUnreadRootPostNumber?.takeIf { it > 1u }
    }

    fun usesBoostBarrage(row: PostRow): Boolean {
        return row.depth == 0 && row.post.boosts.isNotEmpty()
    }

    fun searchMatches(query: String, posts: List<TopicPostState>): List<SearchMatch> {
        val needle = query.trim()
        if (needle.isEmpty()) return emptyList()

        val seenPostIds = LinkedHashSet<ULong>()
        return posts
            .asSequence()
            .filter { post -> seenPostIds.add(post.id) }
            .filter { post ->
                post.presentation
                    ?.plainText()
                    ?.contains(needle, ignoreCase = true) == true
            }
            .sortedWith(
                compareBy<TopicPostState> { it.postNumber }
                    .thenBy { it.id },
            )
            .map { post ->
                SearchMatch(
                    postId = post.id,
                    postNumber = post.postNumber,
                )
            }
            .toList()
    }

    fun projectRows(
        rows: List<TopicTreeRowState>,
        postsById: Map<ULong, TopicPostState>,
        expandedReplyRootPostIds: Set<ULong> = emptySet(),
        focusedPostNumber: UInt? = null,
    ): List<PostRow> {
        val availableRows = rows.mapNotNull { row ->
            val post = postsById[row.postId] ?: return@mapNotNull null
            ProjectableReplyRow(row = row, post = post)
        }
        if (availableRows.isEmpty()) return emptyList()

        val rowByPostNumber = availableRows
            .mapIndexed { index, projected -> projected.row.postNumber to index }
            .toMap()
        val rootIndexByIndex = availableRows.indices.associateWith { index ->
            rootIndexFor(index, availableRows, rowByPostNumber)
        }
        val secondaryIndicesByRoot = LinkedHashMap<Int, MutableList<Int>>()
        for (index in availableRows.indices) {
            val rootIndex = rootIndexByIndex[index] ?: index
            if (rootIndex != index) {
                secondaryIndicesByRoot.getOrPut(rootIndex) { mutableListOf() }.add(index)
            }
        }

        val focusedIndex = focusedPostNumber?.let(rowByPostNumber::get)
        val focusedSecondaryIndices = focusedIndex
            ?.let { selectedAncestryIndices(it, availableRows, rowByPostNumber, rootIndexByIndex) }
            .orEmpty()

        return buildList {
            availableRows.forEachIndexed { index, projected ->
                val rootIndex = rootIndexByIndex[index] ?: index
                if (rootIndex != index) return@forEachIndexed

                val secondaryIndices = secondaryIndicesByRoot[index].orEmpty()
                val isExpanded = expandedReplyRootPostIds.contains(projected.post.id)
                val selectedSecondaryIndices = if (isExpanded) {
                    secondaryIndices.toSet()
                } else {
                    focusedSecondaryIndices.intersect(secondaryIndices.toSet())
                }
                val hiddenReplyCount = (secondaryIndices.size - selectedSecondaryIndices.size).coerceAtLeast(0)
                add(
                    postRow(
                        projected = projected,
                        hiddenReplyCount = hiddenReplyCount.toUInt().takeIf { it > 0u } ?: 0u,
                    ),
                )
                secondaryIndices.forEach { secondaryIndex ->
                    if (!selectedSecondaryIndices.contains(secondaryIndex)) return@forEach
                    add(postRow(projected = availableRows[secondaryIndex]))
                }
            }
        }
    }

    private fun rootIndexFor(
        startIndex: Int,
        rows: List<ProjectableReplyRow>,
        rowByPostNumber: Map<UInt, Int>,
    ): Int {
        var index = startIndex
        val visited = mutableSetOf<Int>()
        while (visited.add(index)) {
            val row = rows[index].row
            val parentNumber = row.parentPostNumber
            if (row.depth.toInt() <= 1 || parentNumber == null || parentNumber <= 1u) {
                return index
            }
            index = rowByPostNumber[parentNumber] ?: return index
        }
        return startIndex
    }

    private fun selectedAncestryIndices(
        focusedIndex: Int,
        rows: List<ProjectableReplyRow>,
        rowByPostNumber: Map<UInt, Int>,
        rootIndexByIndex: Map<Int, Int>,
    ): Set<Int> {
        val rootIndex = rootIndexByIndex[focusedIndex] ?: focusedIndex
        if (rootIndex == focusedIndex) return emptySet()

        val selected = linkedSetOf<Int>()
        var index = focusedIndex
        val visited = mutableSetOf<Int>()
        while (index != rootIndex && visited.add(index)) {
            selected += index
            val parentNumber = rows[index].row.parentPostNumber ?: break
            index = rowByPostNumber[parentNumber] ?: break
        }
        return selected
    }

    private fun postRow(
        projected: ProjectableReplyRow,
        hiddenReplyCount: UInt = 0u,
    ): PostRow {
        return projected.row.let { row ->
            PostRow(
                post = projected.post,
                depth = row.depth.toInt(),
                parentPostNumber = row.parentPostNumber,
                hasChildren = row.hasChildren,
                hiddenReplyCount = hiddenReplyCount,
            )
        }
    }

    fun postsForDetail(
        bodyPost: TopicPostState,
        loadedPosts: List<TopicPostState>,
        replyRows: List<TopicTreeRowState>,
    ): List<TopicPostState> {
        val postsById = postsById(listOf(bodyPost) + loadedPosts)
        return uniquePosts(
            listOf(bodyPost) + replyRows.mapNotNull { row ->
                if (row.postId == bodyPost.id) null else postsById[row.postId]
            },
        )
    }

    fun postsById(posts: List<TopicPostState>): Map<ULong, TopicPostState> {
        return posts.associateBy { it.id }
    }

    fun uniquePosts(posts: List<TopicPostState>): List<TopicPostState> {
        val postsById = LinkedHashMap<ULong, TopicPostState>(posts.size)
        for (post in posts) {
            postsById[post.id] = post
        }
        return postsById.values.toList()
    }

    private data class ProjectableReplyRow(
        val row: TopicTreeRowState,
        val post: TopicPostState,
    )
}

object TopicDetailBoostPresentation {
    const val BODY_BARRAGE_VISIBLE_LINE_LIMIT = 5
    const val BODY_BARRAGE_MAX_LANES = 5
}
