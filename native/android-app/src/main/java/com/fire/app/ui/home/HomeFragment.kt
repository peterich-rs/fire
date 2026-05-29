package com.fire.app.ui.home

import android.os.Bundle
import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import android.widget.ProgressBar
import android.widget.TextView
import androidx.fragment.app.Fragment
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.lifecycleScope
import androidx.lifecycle.repeatOnLifecycle
import androidx.paging.LoadState
import androidx.recyclerview.widget.LinearLayoutManager
import androidx.recyclerview.widget.RecyclerView
import com.fire.app.R
import com.fire.app.core.ext.optimizeForPaging
import com.fire.app.session.FireSessionStoreRepository
import com.fire.app.ui.cloudflare.CloudflareChallengeSupport
import com.fire.app.ui.topicdetail.TopicDetailActivity
import com.google.android.material.chip.Chip
import kotlinx.coroutines.flow.collectLatest
import kotlinx.coroutines.launch
import uniffi.fire_uniffi_types.TopicListKindState

class HomeFragment : Fragment() {

    private lateinit var recyclerView: RecyclerView
    private lateinit var adapter: TopicListAdapter
    private lateinit var emptyView: TextView
    private lateinit var loadingView: ProgressBar
    private lateinit var feedKindBar: RecyclerView
    private lateinit var feedKindAdapter: FeedKindAdapter
    private lateinit var selectedTagChip: Chip

    private var viewModel: HomeViewModel? = null

    override fun onCreateView(
        inflater: LayoutInflater,
        container: ViewGroup?,
        savedInstanceState: Bundle?,
    ): View? {
        return inflater.inflate(R.layout.fragment_home, container, false)
    }

    override fun onViewCreated(view: View, savedInstanceState: Bundle?) {
        super.onViewCreated(view, savedInstanceState)

        recyclerView = view.findViewById(R.id.topic_list)
        emptyView = view.findViewById(R.id.empty_view)
        loadingView = view.findViewById(R.id.loading_view)
        feedKindBar = view.findViewById(R.id.feed_kind_bar)
        selectedTagChip = view.findViewById(R.id.selected_tag_chip)

        val sessionStore = FireSessionStoreRepository.get(requireContext())
        viewModel = HomeViewModel.create(sessionStore)

        adapter = TopicListAdapter(
            onTopicClick = { row ->
                TopicDetailActivity.start(
                    context = requireContext(),
                    topicId = row.topic.id.toLong(),
                    topicTitle = row.topic.title,
                )
            },
            onTagClick = { tag ->
                viewModel?.selectTag(tag)
                recyclerView.scrollToPosition(0)
            },
        )

        recyclerView.layoutManager = LinearLayoutManager(requireContext())
        recyclerView.adapter = adapter
        recyclerView.optimizeForPaging()
        adapter.addLoadStateListener { loadStates ->
            listOf(loadStates.refresh, loadStates.append, loadStates.prepend)
                .filterIsInstance<LoadState.Error>()
                .firstOrNull { CloudflareChallengeSupport.isChallenge(it.error) }
                ?.let { context?.let(CloudflareChallengeSupport::openSiteRoot) }
        }

        setupFeedKindBar()
        setupSelectedTagChip()

        viewModel?.let { vm ->
            viewLifecycleOwner.lifecycleScope.launch {
                viewLifecycleOwner.repeatOnLifecycle(Lifecycle.State.STARTED) {
                    launch {
                        vm.topicPagingFlow.collectLatest { pagingData ->
                            adapter.submitData(pagingData)
                        }
                    }
                    launch {
                        vm.selectedKind.collectLatest { kind ->
                            feedKindAdapter.updateSelectedKind(kind)
                        }
                    }
                    launch {
                        vm.selectedTag.collectLatest { tag ->
                            renderSelectedTag(tag)
                        }
                    }
                }
            }
        }

        viewModel?.restoreSession()
    }

    private fun setupFeedKindBar() {
        val kinds = viewModel?.topicListKinds ?: return
        feedKindAdapter = FeedKindAdapter(kinds, viewModel?.selectedKind?.value ?: TopicListKindState.LATEST) { kind ->
            viewModel?.selectKind(kind)
            recyclerView.scrollToPosition(0)
        }
        feedKindBar.layoutManager = LinearLayoutManager(requireContext(), LinearLayoutManager.HORIZONTAL, false)
        feedKindBar.adapter = feedKindAdapter
    }

    private fun setupSelectedTagChip() {
        selectedTagChip.isCheckable = false
        selectedTagChip.setOnClickListener {
            viewModel?.clearTag()
            recyclerView.scrollToPosition(0)
        }
        selectedTagChip.setOnCloseIconClickListener {
            viewModel?.clearTag()
            recyclerView.scrollToPosition(0)
        }
    }

    private fun renderSelectedTag(tag: String?) {
        if (tag == null) {
            selectedTagChip.visibility = View.GONE
            selectedTagChip.text = null
        } else {
            selectedTagChip.visibility = View.VISIBLE
            selectedTagChip.text = "#$tag"
        }
    }
}
