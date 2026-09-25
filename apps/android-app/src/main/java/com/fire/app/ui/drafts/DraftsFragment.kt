package com.fire.app.ui.drafts

import android.os.Bundle
import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import android.widget.ProgressBar
import android.widget.TextView
import android.widget.Toast
import androidx.appcompat.app.AlertDialog
import androidx.fragment.app.Fragment
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.ViewModel
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.lifecycleScope
import androidx.lifecycle.repeatOnLifecycle
import androidx.paging.LoadState
import androidx.recyclerview.widget.LinearLayoutManager
import androidx.recyclerview.widget.RecyclerView
import androidx.swiperefreshlayout.widget.SwipeRefreshLayout
import com.fire.app.R
import com.fire.app.core.ext.optimizeForPaging
import com.fire.app.session.FireSessionStore
import com.fire.app.session.FireSessionStoreRepository
import com.fire.app.ui.composer.PrivateMessageComposerSheet
import com.fire.app.ui.composer.ReplyComposerSheet
import com.fire.app.ui.composer.TopicComposerSheet
import com.fire.app.ui.topicdetail.TopicDetailActivity
import kotlinx.coroutines.flow.collectLatest
import kotlinx.coroutines.launch
import uniffi.fire_uniffi_types.DraftState

class DraftsFragment : Fragment() {

    private lateinit var recyclerView: RecyclerView
    private lateinit var adapter: DraftsAdapter
    private lateinit var swipeRefresh: SwipeRefreshLayout
    private lateinit var emptyView: TextView
    private lateinit var loadingView: ProgressBar

    private var viewModel: DraftsViewModel? = null

    override fun onCreateView(
        inflater: LayoutInflater,
        container: ViewGroup?,
        savedInstanceState: Bundle?,
    ): View? {
        return inflater.inflate(R.layout.fragment_drafts, container, false)
    }

    override fun onViewCreated(view: View, savedInstanceState: Bundle?) {
        super.onViewCreated(view, savedInstanceState)

        recyclerView = view.findViewById(R.id.drafts_list)
        swipeRefresh = view.findViewById(R.id.swipe_refresh)
        emptyView = view.findViewById(R.id.empty_view)
        loadingView = view.findViewById(R.id.loading_view)

        viewLifecycleOwner.lifecycleScope.launch {
            val sessionStore = FireSessionStoreRepository.get(requireContext())
            viewModel = ViewModelProvider(
                this@DraftsFragment,
                DraftsViewModelFactory(sessionStore),
            )[DraftsViewModel::class.java]

            adapter = DraftsAdapter(
                onDraftClick = ::openDraft,
                onDraftDelete = ::confirmDeleteDraft,
            )
            recyclerView.layoutManager = LinearLayoutManager(requireContext())
            recyclerView.adapter = adapter
            recyclerView.optimizeForPaging()
            adapter.addLoadStateListener { loadStates ->
                val refresh = loadStates.refresh
                val isInitialLoading = refresh is LoadState.Loading && adapter.itemCount == 0
                loadingView.visibility = if (isInitialLoading) View.VISIBLE else View.GONE
                emptyView.visibility = when {
                    refresh is LoadState.Error -> {
                        emptyView.text = refresh.error.localizedMessage
                            ?: getString(R.string.feed_drafts_empty)
                        View.VISIBLE
                    }
                    refresh is LoadState.NotLoading && adapter.itemCount == 0 -> {
                        emptyView.text = getString(R.string.feed_drafts_empty)
                        View.VISIBLE
                    }
                    else -> View.GONE
                }
                if (refresh !is LoadState.Loading) {
                    swipeRefresh.isRefreshing = false
                }
            }

            swipeRefresh.setOnRefreshListener {
                adapter.refresh()
            }

            val vm = viewModel ?: return@launch
            viewLifecycleOwner.repeatOnLifecycle(Lifecycle.State.STARTED) {
                launch {
                    vm.draftsPagingFlow.collectLatest { pagingData ->
                        adapter.submitData(pagingData)
                    }
                }
                launch {
                    vm.error.collectLatest { error ->
                        if (!error.isNullOrBlank()) {
                            Toast.makeText(requireContext(), error, Toast.LENGTH_SHORT).show()
                            vm.clearError()
                        }
                    }
                }
            }
        }
    }

    private fun openDraft(draft: DraftState) {
        when {
            draft.draftKey == "new_topic" -> {
                TopicComposerSheet.newInstance { topicId ->
                    adapter.refresh()
                    TopicDetailActivity.start(
                        context = requireContext(),
                        topicId = topicId.toLong(),
                    )
                }.show(childFragmentManager, "topic_composer")
            }
            draft.draftKey == "new_private_message" -> {
                PrivateMessageComposerSheet.newInstance(
                    targetUsername = "",
                    displayName = null,
                    onPrivateMessageCreated = { topicId, title ->
                        adapter.refresh()
                        TopicDetailActivity.start(
                            context = requireContext(),
                            topicId = topicId.toLong(),
                            topicTitle = title,
                        )
                    },
                ).show(childFragmentManager, "private_message_composer")
            }
            else -> {
                val target = draft.replyDraftTarget()
                if (target == null) {
                    Toast.makeText(
                        requireContext(),
                        R.string.feed_drafts_resume_unavailable,
                        Toast.LENGTH_SHORT,
                    ).show()
                    return
                }
                ReplyComposerSheet.newInstance(
                    topicId = target.topicId,
                    replyToPostNumber = target.replyToPostNumber,
                    onReplySubmitted = {
                        adapter.refresh()
                    },
                ).show(childFragmentManager, "reply_composer")
            }
        }
    }

    private fun confirmDeleteDraft(draft: DraftState) {
        AlertDialog.Builder(requireContext())
            .setTitle(R.string.feed_drafts_delete_title)
            .setMessage(R.string.feed_drafts_delete_message)
            .setNegativeButton(R.string.action_cancel, null)
            .setPositiveButton(R.string.feed_drafts_delete_confirm) { _, _ ->
                viewModel?.deleteDraft(draft) {
                    adapter.refresh()
                }
            }
            .show()
    }

    private fun DraftState.replyDraftTarget(): ReplyDraftTarget? {
        val keyTarget = ReplyDraftTarget.fromDraftKey(draftKey)
        val topicId = topicId?.toLong() ?: keyTarget?.topicId ?: return null
        return ReplyDraftTarget(
            topicId = topicId,
            replyToPostNumber = data.replyToPostNumber?.toInt() ?: keyTarget?.replyToPostNumber,
        )
    }

    private data class ReplyDraftTarget(
        val topicId: Long,
        val replyToPostNumber: Int?,
    ) {
        companion object {
            private val TopicDraftKeyPattern = Regex("""^topic_(\d+)(?:_post_(\d+))?$""")

            fun fromDraftKey(draftKey: String): ReplyDraftTarget? {
                val match = TopicDraftKeyPattern.matchEntire(draftKey) ?: return null
                val topicId = match.groupValues[1].toLongOrNull() ?: return null
                val postNumber = match.groupValues.getOrNull(2)
                    ?.takeIf { it.isNotBlank() }
                    ?.toIntOrNull()
                return ReplyDraftTarget(topicId, postNumber)
            }
        }
    }

    private class DraftsViewModelFactory(
        private val sessionStore: FireSessionStore,
    ) : ViewModelProvider.Factory {
        @Suppress("UNCHECKED_CAST")
        override fun <T : ViewModel> create(modelClass: Class<T>): T {
            if (modelClass.isAssignableFrom(DraftsViewModel::class.java)) {
                return DraftsViewModel.create(sessionStore) as T
            }
            throw IllegalArgumentException("Unknown ViewModel class: ${modelClass.name}")
        }
    }
}
