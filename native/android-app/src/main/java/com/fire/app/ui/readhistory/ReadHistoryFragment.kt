package com.fire.app.ui.readhistory

import android.os.Bundle
import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import android.widget.ProgressBar
import android.widget.TextView
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
import com.fire.app.ui.home.TopicListAdapter
import com.fire.app.ui.topicdetail.TopicDetailActivity
import kotlinx.coroutines.flow.collectLatest
import kotlinx.coroutines.launch

class ReadHistoryFragment : Fragment() {

    private lateinit var recyclerView: RecyclerView
    private lateinit var adapter: TopicListAdapter
    private lateinit var swipeRefresh: SwipeRefreshLayout
    private lateinit var emptyView: TextView
    private lateinit var loadingView: ProgressBar

    private var viewModel: ReadHistoryViewModel? = null

    override fun onCreateView(
        inflater: LayoutInflater,
        container: ViewGroup?,
        savedInstanceState: Bundle?,
    ): View? {
        return inflater.inflate(R.layout.fragment_read_history, container, false)
    }

    override fun onViewCreated(view: View, savedInstanceState: Bundle?) {
        super.onViewCreated(view, savedInstanceState)

        recyclerView = view.findViewById(R.id.read_history_list)
        swipeRefresh = view.findViewById(R.id.swipe_refresh)
        emptyView = view.findViewById(R.id.empty_view)
        loadingView = view.findViewById(R.id.loading_view)

        viewLifecycleOwner.lifecycleScope.launch {
            val sessionStore = FireSessionStoreRepository.get(requireContext())
            viewModel = ViewModelProvider(
                this@ReadHistoryFragment,
                ReadHistoryViewModelFactory(sessionStore),
            )[ReadHistoryViewModel::class.java]

            adapter = TopicListAdapter { row ->
                TopicDetailActivity.start(
                    context = requireContext(),
                    topicId = row.topic.id.toLong(),
                    topicTitle = row.topic.title,
                    targetPostNumber = row.topic.lastReadPostNumber?.toInt() ?: -1,
                )
            }
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
                            ?: getString(R.string.feed_read_history_empty)
                        View.VISIBLE
                    }
                    refresh is LoadState.NotLoading && adapter.itemCount == 0 -> {
                        emptyView.text = getString(R.string.feed_read_history_empty)
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
                vm.readHistoryPagingFlow.collectLatest { pagingData ->
                    adapter.submitData(pagingData)
                }
            }
        }
    }

    private class ReadHistoryViewModelFactory(
        private val sessionStore: FireSessionStore,
    ) : ViewModelProvider.Factory {
        @Suppress("UNCHECKED_CAST")
        override fun <T : ViewModel> create(modelClass: Class<T>): T {
            if (modelClass.isAssignableFrom(ReadHistoryViewModel::class.java)) {
                return ReadHistoryViewModel.create(sessionStore) as T
            }
            throw IllegalArgumentException("Unknown ViewModel class: ${modelClass.name}")
        }
    }
}
