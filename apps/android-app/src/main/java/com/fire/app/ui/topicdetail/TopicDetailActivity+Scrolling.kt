package com.fire.app.ui.topicdetail

import androidx.core.view.ViewCompat
import androidx.core.view.WindowInsetsCompat
import androidx.core.view.updatePadding
import androidx.recyclerview.widget.LinearLayoutManager
import androidx.recyclerview.widget.RecyclerView

internal fun TopicDetailActivity.scheduleLoadMorePosts(rv: RecyclerView) {
    if (loadMorePostsPosted) return
    loadMorePostsPosted = true
    rv.post {
        loadMorePostsPosted = false
        viewModel?.loadMorePosts()
    }
}

internal fun TopicDetailActivity.updateVisiblePostTimings() {
    val tracker = timingTracker ?: return
    val layoutManager = recyclerView.layoutManager as? LinearLayoutManager ?: return
    val firstVisible = layoutManager.findFirstVisibleItemPosition()
    val lastVisible = layoutManager.findLastVisibleItemPosition()
    if (firstVisible == RecyclerView.NO_POSITION || lastVisible == RecyclerView.NO_POSITION) {
        tracker.updateVisiblePostNumbers(emptySet())
        return
    }

    val visiblePostNumbers = buildSet {
        for (adapterPosition in firstVisible..lastVisible) {
            visiblePostNumberForAdapterPosition(adapterPosition)?.let(::add)
        }
    }
    if (visiblePostNumbers.isNotEmpty()) {
        tracker.recordInteraction()
    }
    tracker.updateVisiblePostNumbers(visiblePostNumbers)
}

internal fun TopicDetailActivity.visiblePostNumberForAdapterPosition(adapterPosition: Int): UInt? {
    if (adapterPosition < 0) return null
    if (adapterPosition < headerAdapter.itemCount) {
        return viewModel?.detail?.value?.postStream?.posts
            ?.minByOrNull { it.postNumber }
            ?.postNumber
    }

    val rowIndex = adapterPosition - headerAdapter.itemCount
    return postListAdapter.currentList.getOrNull(rowIndex)?.post?.postNumber
}

internal fun TopicDetailActivity.scrollToPostNumber(postNumber: UInt) {
    pendingScrollTargetPostNumber = postNumber
    val adapterPosition = if (postNumber <= 1u) {
        0
    } else {
        val rowIndex = postListAdapter.currentList.indexOfFirst {
            it.post.postNumber == postNumber
        }
        if (rowIndex < 0) return
        headerAdapter.itemCount + rowIndex
    }
    pendingScrollTargetPostNumber = null

    recyclerView.post {
        val layoutManager = recyclerView.layoutManager as? LinearLayoutManager
        if (layoutManager != null) {
            layoutManager.scrollToPositionWithOffset(adapterPosition, 0)
        } else {
            recyclerView.scrollToPosition(adapterPosition)
        }
    }
}

internal fun TopicDetailActivity.updatePinnedToolbarTitle(firstVisible: Int) {
    val shouldPin = firstVisible > 0
    if (shouldPin == toolbarTitlePinned) return
    toolbarTitlePinned = shouldPin
    binding.topicDetailToolbar.title = if (shouldPin) pinnedTopicTitle.orEmpty() else ""
}

internal fun TopicDetailActivity.applySystemBarInsets() {
    val root = binding.root
    val initialLeft = root.paddingLeft
    val initialTop = root.paddingTop
    val initialRight = root.paddingRight
    val initialBottom = root.paddingBottom
    ViewCompat.setOnApplyWindowInsetsListener(root) { view, insets ->
        val systemBars = insets.getInsets(WindowInsetsCompat.Type.systemBars())
        view.updatePadding(
            left = initialLeft + systemBars.left,
            top = initialTop + systemBars.top,
            right = initialRight + systemBars.right,
            bottom = initialBottom + systemBars.bottom,
        )
        insets
    }
    ViewCompat.requestApplyInsets(root)
}
