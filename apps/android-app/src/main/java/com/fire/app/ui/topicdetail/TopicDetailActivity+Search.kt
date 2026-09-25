package com.fire.app.ui.topicdetail

import android.view.View

internal fun TopicDetailActivity.showTopicSearch() {
    searchOverlay.visibility = View.VISIBLE
    searchOverlay.focusSearch()
    recomputeTopicSearch()
}

internal fun TopicDetailActivity.hideTopicSearch() {
    topicSearchQuery = ""
    topicSearchMatches = emptyList()
    topicSearchIndex = -1
    searchOverlay.reset()
    searchOverlay.visibility = View.GONE
    applyTopicSearchHighlight()
}

internal fun TopicDetailActivity.updateTopicSearchQuery(query: String) {
    topicSearchQuery = query
    recomputeTopicSearch(scrollToActiveMatch = true)
}

internal fun TopicDetailActivity.recomputeTopicSearch(scrollToActiveMatch: Boolean = false) {
    if (searchOverlay.visibility != View.VISIBLE && topicSearchQuery.isBlank()) {
        return
    }
    val posts = viewModel?.detail?.value?.postStream?.posts.orEmpty()
    val previousPostId = topicSearchMatches.getOrNull(topicSearchIndex)?.postId
    topicSearchMatches = TopicDetailPostRows.searchMatches(topicSearchQuery, posts)
    topicSearchIndex = when {
        topicSearchMatches.isEmpty() -> -1
        previousPostId != null -> topicSearchMatches
            .indexOfFirst { it.postId == previousPostId }
            .takeIf { it >= 0 }
            ?: 0
        else -> 0
    }
    searchOverlay.updateResult(topicSearchIndex, topicSearchMatches.size)
    applyTopicSearchHighlight()
    if (scrollToActiveMatch) {
        topicSearchMatches.getOrNull(topicSearchIndex)?.postNumber?.let { scrollToPostNumber(it) }
    }
}

internal fun TopicDetailActivity.navigateTopicSearch(delta: Int) {
    if (topicSearchMatches.isEmpty()) return
    val size = topicSearchMatches.size
    topicSearchIndex = Math.floorMod(topicSearchIndex + delta, size)
    searchOverlay.updateResult(topicSearchIndex, size)
    applyTopicSearchHighlight()
    topicSearchMatches[topicSearchIndex].postNumber.let { scrollToPostNumber(it) }
}

internal fun TopicDetailActivity.applyTopicSearchHighlight() {
    val highlightedPostId = topicSearchMatches.getOrNull(topicSearchIndex)?.postId
    headerAdapter.highlightedPostId = highlightedPostId
    postListAdapter.highlightedPostId = highlightedPostId
}
