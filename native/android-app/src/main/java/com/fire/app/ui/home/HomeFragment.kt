package com.fire.app.ui.home

import android.os.Bundle
import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import android.widget.TextView
import android.widget.Toast
import androidx.fragment.app.Fragment
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.ViewModel
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.lifecycleScope
import androidx.lifecycle.repeatOnLifecycle
import androidx.navigation.fragment.findNavController
import androidx.paging.LoadState
import androidx.recyclerview.widget.LinearLayoutManager
import androidx.recyclerview.widget.RecyclerView
import androidx.swiperefreshlayout.widget.SwipeRefreshLayout
import com.fire.app.R
import com.fire.app.core.ext.optimizeForPaging
import com.fire.app.session.FireSessionStore
import com.fire.app.session.FireSessionStoreRepository
import com.fire.app.ui.composer.TopicComposerSheet
import com.fire.app.ui.topicdetail.TopicDetailActivity
import com.google.android.material.chip.Chip
import com.google.android.material.chip.ChipGroup
import kotlinx.coroutines.flow.collectLatest
import kotlinx.coroutines.launch
import uniffi.fire_uniffi_types.TopicListKindState

class HomeFragment : Fragment() {

    private lateinit var recyclerView: RecyclerView
    private lateinit var adapter: TopicListAdapter
    private lateinit var emptyView: TextView
    private lateinit var loadingSkeletonView: View
    private lateinit var swipeRefresh: SwipeRefreshLayout
    private lateinit var categoryBar: RecyclerView
    private lateinit var categoryAdapter: HomeCategoryAdapter
    private lateinit var feedKindBar: RecyclerView
    private lateinit var feedKindAdapter: FeedKindAdapter
    private lateinit var selectedTagsScroll: View
    private lateinit var selectedTagsGroup: ChipGroup
    private lateinit var searchButton: View
    private lateinit var createTopicButton: View

    private var viewModel: HomeViewModel? = null
    private var pendingAutoRefresh = false

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
        loadingSkeletonView = view.findViewById(R.id.loading_skeleton_view)
        swipeRefresh = view.findViewById(R.id.swipe_refresh)
        categoryBar = view.findViewById(R.id.category_bar)
        feedKindBar = view.findViewById(R.id.feed_kind_bar)
        selectedTagsScroll = view.findViewById(R.id.selected_tags_scroll)
        selectedTagsGroup = view.findViewById(R.id.selected_tags_group)
        searchButton = view.findViewById(R.id.search_button)
        createTopicButton = view.findViewById(R.id.create_topic_button)

        viewLifecycleOwner.lifecycleScope.launch {
            val sessionStore = FireSessionStoreRepository.get(requireContext())
            viewModel = ViewModelProvider(this@HomeFragment, HomeViewModelFactory(sessionStore))[HomeViewModel::class.java]

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
            recyclerView.addOnScrollListener(object : RecyclerView.OnScrollListener() {
                override fun onScrolled(recyclerView: RecyclerView, dx: Int, dy: Int) {
                    flushPendingAutoRefreshIfAtTop()
                }
            })
            adapter.addLoadStateListener { loadStates ->
                val refresh = loadStates.refresh
                val isInitialLoading = refresh is LoadState.Loading && adapter.itemCount == 0
                loadingSkeletonView.visibility = if (isInitialLoading) View.VISIBLE else View.GONE
                swipeRefresh.isEnabled = !isInitialLoading
                if (refresh is LoadState.Loading && adapter.itemCount > 0) {
                    swipeRefresh.isRefreshing = true
                }
                emptyView.visibility = when {
                    refresh is LoadState.Error -> {
                        emptyView.text = refresh.error.localizedMessage
                            ?: getString(R.string.browser_empty)
                        View.VISIBLE
                    }
                    refresh is LoadState.NotLoading && adapter.itemCount == 0 -> {
                        emptyView.text = getString(R.string.browser_empty)
                        View.VISIBLE
                    }
                    else -> View.GONE
                }
                if (refresh !is LoadState.Loading) {
                    swipeRefresh.isRefreshing = false
                    flushPendingAutoRefreshIfAtTop()
                }
            }

            setupCategoryBar()
            setupFeedKindBar()
            setupSwipeRefresh()
            setupToolbarActions()

            viewModel?.let { vm ->
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
                        vm.session.collectLatest { session ->
                            categoryAdapter.updateCategories(session?.bootstrap?.categories.orEmpty())
                        }
                    }
                    launch {
                        vm.selectedCategoryId.collectLatest { categoryId ->
                            categoryAdapter.updateSelectedCategory(categoryId)
                        }
                    }
                    launch {
                        vm.selectedTags.collectLatest { tags ->
                            renderSelectedTags(tags)
                        }
                    }
                    launch {
                        vm.topicListRefreshEvents.collect {
                            if (isTopicListAtTop()) {
                                pendingAutoRefresh = false
                                adapter.refresh()
                            } else {
                                pendingAutoRefresh = true
                            }
                        }
                    }
                    launch {
                        vm.error.collect { error ->
                            Toast.makeText(requireContext(), error, Toast.LENGTH_SHORT).show()
                        }
                    }
                }
            }
        }
    }

    private fun setupCategoryBar() {
        categoryAdapter = HomeCategoryAdapter(
            categories = emptyList(),
            selectedCategoryId = viewModel?.selectedCategoryId?.value,
        ) { categoryId ->
            viewModel?.selectCategory(categoryId)
            recyclerView.scrollToPosition(0)
        }
        categoryBar.layoutManager = LinearLayoutManager(requireContext(), LinearLayoutManager.HORIZONTAL, false)
        categoryBar.adapter = categoryAdapter
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

    private fun setupSwipeRefresh() {
        swipeRefresh.setOnRefreshListener {
            pendingAutoRefresh = false
            adapter.refresh()
        }
    }

    private fun setupToolbarActions() {
        searchButton.setOnClickListener {
            findNavController().navigate(HomeFragmentDirections.actionHomeToSearch())
        }

        createTopicButton.setOnClickListener {
            TopicComposerSheet.newInstance { topicId ->
                adapter.refresh()
                TopicDetailActivity.start(
                    context = requireContext(),
                    topicId = topicId.toLong(),
                )
            }.show(parentFragmentManager, "topic_composer")
        }
    }

    private fun renderSelectedTags(tags: List<String>) {
        selectedTagsGroup.removeAllViews()
        selectedTagsScroll.visibility = if (tags.isEmpty()) View.GONE else View.VISIBLE
        for (tag in tags) {
            val chip = Chip(requireContext()).apply {
                text = "#$tag"
                isCheckable = false
                isCloseIconVisible = true
                setOnClickListener {
                    viewModel?.removeTag(tag)
                    recyclerView.scrollToPosition(0)
                }
                setOnCloseIconClickListener {
                    viewModel?.removeTag(tag)
                    recyclerView.scrollToPosition(0)
                }
            }
            selectedTagsGroup.addView(chip)
        }
    }

    private fun isTopicListAtTop(): Boolean {
        val layoutManager = recyclerView.layoutManager as? LinearLayoutManager ?: return true
        val firstVisiblePosition = layoutManager.findFirstVisibleItemPosition()
        if (firstVisiblePosition > 0) {
            return false
        }
        val firstVisibleView = layoutManager.findViewByPosition(firstVisiblePosition)
        return firstVisibleView == null || firstVisibleView.top >= recyclerView.paddingTop
    }

    private fun flushPendingAutoRefreshIfAtTop() {
        if (!pendingAutoRefresh || swipeRefresh.isRefreshing) {
            return
        }
        if (!isTopicListAtTop()) {
            return
        }
        pendingAutoRefresh = false
        adapter.refresh()
    }

    private class HomeViewModelFactory(
        private val sessionStore: FireSessionStore,
    ) : ViewModelProvider.Factory {
        @Suppress("UNCHECKED_CAST")
        override fun <T : ViewModel> create(modelClass: Class<T>): T {
            if (modelClass.isAssignableFrom(HomeViewModel::class.java)) {
                return HomeViewModel.create(sessionStore) as T
            }
            throw IllegalArgumentException("Unknown ViewModel class: ${modelClass.name}")
        }
    }
}
