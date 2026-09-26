package com.fire.app.ui.topicdetail

import android.view.View
import androidx.lifecycle.lifecycleScope
import com.fire.app.R
import com.fire.app.core.ui.FireToast
import kotlinx.coroutines.flow.collectLatest
import kotlinx.coroutines.launch

internal fun TopicDetailActivity.observeViewModel() {
    val vm = viewModel ?: return
    lifecycleScope.launch {
        vm.isLoading.collectLatest { loading ->
            loadingView.visibility = if (loading) View.VISIBLE else View.GONE
            recyclerView.visibility = if (loading && vm.postRows.value.isEmpty()) View.GONE else View.VISIBLE
        }
    }

    lifecycleScope.launch {
        vm.errorMessage.collectLatest { error ->
            if (error != null) {
                errorView.visibility = View.VISIBLE
                errorText.text = error
                if (vm.postRows.value.isEmpty() && vm.detail.value == null) {
                    recyclerView.visibility = View.GONE
                }
            } else {
                errorView.visibility = View.GONE
                recyclerView.visibility = if (vm.isLoading.value && vm.postRows.value.isEmpty()) {
                    View.GONE
                } else {
                    View.VISIBLE
                }
            }
        }
    }

    lifecycleScope.launch {
        vm.isCloudflareError.collectLatest { isCloudflare ->
            (retryButton as? com.google.android.material.button.MaterialButton)?.text =
                getString(
                    if (isCloudflare) R.string.action_cloudflare_verify else R.string.action_retry,
                )
        }
    }

    lifecycleScope.launch {
        vm.detail.collectLatest { detail ->
            headerAdapter.detail = detail
            if (detail != null) {
                pinnedTopicTitle = detail.title.trim()
                if (toolbarTitlePinned) {
                    binding.topicDetailToolbar.title = pinnedTopicTitle
                }
            }
            updateTopicNotificationToolbar(detail)
            recomputeTopicSearch()
            updateVisiblePostTimings()
        }
    }

    lifecycleScope.launch {
        vm.topicAiSummary.collectLatest { summary ->
            headerAdapter.aiSummary = summary
        }
    }

    lifecycleScope.launch {
        vm.postRows.collectLatest { rows ->
            postListAdapter.submitList(rows) {
                updateVisiblePostTimings()
                pendingScrollTargetPostNumber?.let { scrollToPostNumber(it) }
            }
            recomputeTopicSearch()
        }
    }

    lifecycleScope.launch {
        vm.scrollTargetPostNumber.collectLatest { postNumber ->
            scrollToPostNumber(postNumber)
        }
    }

    lifecycleScope.launch {
        vm.actionError.collectLatest { error ->
            FireToast.show(binding.root, error, FireToast.Style.ERROR)
        }
    }

    lifecycleScope.launch {
        vm.bookmarkEvents.collectLatest { event ->
            when (event) {
                is BookmarkEvent.Saved -> {
                    FireToast.show(
                        binding.root,
                        R.string.topic_detail_bookmark_saved,
                        FireToast.Style.SUCCESS,
                    )
                    val key = BookmarkReminderKey(event.bookmarkableId, event.bookmarkableType)
                    pendingBookmarkReminders.remove(key)?.let { request ->
                        scheduleBookmarkReminderAfterSave(request.copy(reminderAt = event.reminderAt))
                    }
                }
                is BookmarkEvent.Deleted -> {
                    FireToast.show(
                        binding.root,
                        R.string.topic_detail_bookmark_deleted,
                        FireToast.Style.INFO,
                    )
                    val key = BookmarkReminderKey(event.bookmarkableId, event.bookmarkableType)
                    pendingBookmarkReminders.remove(key)
                    BookmarkReminderScheduler.cancel(
                        this@observeViewModel,
                        event.bookmarkableId,
                        event.bookmarkableType,
                    )
                }
            }
        }
    }

    lifecycleScope.launch {
        vm.isLoadingMore.collectLatest { loadingMore ->
            loadingFooterAdapter.isLoading = loadingMore
        }
    }

    lifecycleScope.launch {
        vm.typingUsers.collectLatest { usernames ->
            val label = binding.topicDetailTyping
            if (usernames.isEmpty()) {
                label.visibility = View.GONE
                label.text = null
            } else {
                val leading = usernames.take(3).joinToString("、")
                label.text = if (usernames.size > 3) {
                    getString(R.string.topic_detail_typing_many, leading, usernames.size.toString())
                } else {
                    getString(R.string.topic_detail_typing, leading)
                }
                label.visibility = View.VISIBLE
            }
        }
    }
}

internal fun TopicDetailActivity.loadRoute(route: TopicDetailActivity.TopicDetailRoute) {
    val targetPostNumber = route.targetPostNumber.takeIf { it > 0 }?.toUInt()
    viewModel?.loadTopicDetail(route.topicId.toULong(), targetPostNumber)
}
