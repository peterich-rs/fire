package com.fire.app.ui.home

import android.os.Bundle
import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import android.widget.ProgressBar
import android.widget.TextView
import androidx.fragment.app.Fragment
import androidx.lifecycle.lifecycleScope
import androidx.navigation.fragment.findNavController
import androidx.recyclerview.widget.LinearLayoutManager
import androidx.recyclerview.widget.RecyclerView
import com.fire.app.R
import com.fire.app.TopicPresentation
import com.fire.app.session.FireSessionStoreRepository
import kotlinx.coroutines.flow.collectLatest
import kotlinx.coroutines.launch
import uniffi.fire_uniffi_types.TopicListKindState

class HomeFragment : Fragment() {

    private lateinit var recyclerView: RecyclerView
    private lateinit var adapter: TopicListAdapter
    private lateinit var emptyView: TextView
    private lateinit var loadingView: ProgressBar
    private lateinit var feedKindBar: RecyclerView

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

        val sessionStore = FireSessionStoreRepository.get(requireContext())
        viewModel = HomeViewModel.create(sessionStore)

        adapter = TopicListAdapter { row ->
            val topicId = row.topic.id
            val title = row.topic.title
            val action = HomeFragmentDirections.actionHomeToTopicDetail(
                topicId = topicId.toLong(),
                topicTitle = title,
                topicSlug = row.topic.slug,
                targetPostNumber = null,
            )
            findNavController().navigate(action)
        }

        recyclerView.layoutManager = LinearLayoutManager(requireContext())
        recyclerView.adapter = adapter

        setupFeedKindBar()

        viewModel?.let { vm ->
            viewLifecycleOwner.lifecycleScope.launch {
                vm.topicPagingFlow().collectLatest { pagingData ->
                    adapter.submitData(pagingData)
                }
            }
        }

        viewModel?.restoreSession()
    }

    private fun setupFeedKindBar() {
        val kinds = viewModel?.topicListKinds ?: return
        val kindAdapter = FeedKindAdapter(kinds, viewModel?.selectedKind?.value ?: TopicListKindState.LATEST) { kind ->
            viewModel?.selectKind(kind)
            // Recreate paging flow
            viewLifecycleOwner.lifecycleScope.launch {
                viewModel?.topicPagingFlow()?.collectLatest { pagingData ->
                    adapter.submitData(pagingData)
                }
            }
        }
        feedKindBar.layoutManager = LinearLayoutManager(requireContext(), LinearLayoutManager.HORIZONTAL, false)
        feedKindBar.adapter = kindAdapter
    }
}
