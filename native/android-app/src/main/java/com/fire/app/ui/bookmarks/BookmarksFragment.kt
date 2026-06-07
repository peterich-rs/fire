package com.fire.app.ui.bookmarks

import android.os.Bundle
import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import android.widget.ProgressBar
import android.widget.TextView
import androidx.fragment.app.Fragment
import androidx.lifecycle.lifecycleScope
import androidx.paging.LoadState
import androidx.recyclerview.widget.LinearLayoutManager
import androidx.recyclerview.widget.RecyclerView
import com.fire.app.R
import com.fire.app.core.error.launchWithFireErrorHandling
import com.fire.app.session.FireSessionStoreRepository
import com.fire.app.ui.home.TopicListAdapter
import com.fire.app.ui.topicdetail.TopicDetailActivity
import kotlinx.coroutines.flow.collectLatest
import kotlinx.coroutines.launch

class BookmarksFragment : Fragment() {

    private lateinit var recyclerView: RecyclerView
    private lateinit var adapter: TopicListAdapter
    private lateinit var emptyView: TextView
    private lateinit var loadingView: ProgressBar

    private var viewModel: BookmarksViewModel? = null

    override fun onCreateView(
        inflater: LayoutInflater,
        container: ViewGroup?,
        savedInstanceState: Bundle?,
    ): View? {
        return inflater.inflate(R.layout.fragment_bookmarks, container, false)
    }

    override fun onViewCreated(view: View, savedInstanceState: Bundle?) {
        super.onViewCreated(view, savedInstanceState)

        recyclerView = view.findViewById(R.id.bookmarks_list)
        emptyView = view.findViewById(R.id.empty_view)
        loadingView = view.findViewById(R.id.loading_view)

        adapter = TopicListAdapter { row ->
            TopicDetailActivity.start(
                context = requireContext(),
                topicId = row.topic.id.toLong(),
                topicTitle = row.topic.title,
                targetPostNumber = row.topic.bookmarkedPostNumber?.toInt() ?: -1,
            )
        }

        recyclerView.layoutManager = LinearLayoutManager(requireContext())
        recyclerView.adapter = adapter
        adapter.addLoadStateListener { loadStates ->
            val refresh = loadStates.refresh
            val isInitialLoading = refresh is LoadState.Loading && adapter.itemCount == 0
            loadingView.visibility = if (isInitialLoading) View.VISIBLE else View.GONE
            emptyView.visibility = when {
                refresh is LoadState.Error -> {
                    emptyView.text = refresh.error.localizedMessage
                        ?: getString(R.string.feed_bookmarks_empty)
                    View.VISIBLE
                }
                refresh is LoadState.NotLoading && adapter.itemCount == 0 -> {
                    emptyView.text = getString(R.string.feed_bookmarks_empty)
                    View.VISIBLE
                }
                else -> View.GONE
            }
        }

        // Get username and set up paging
        viewLifecycleOwner.lifecycleScope.launch {
            val sessionStore = FireSessionStoreRepository.get(requireContext())
            viewLifecycleOwner.lifecycleScope.launchWithFireErrorHandling(
                operation = "bookmarks.restore_session_snapshot",
                sessionStore = sessionStore,
                fallbackMessage = getString(R.string.feed_bookmarks_login_required),
                onError = { error ->
                    emptyView.text = error.displayMessage
                    emptyView.visibility = View.VISIBLE
                },
            ) {
                val session = sessionStore.snapshot()
                val username = session.bootstrap.currentUsername
                if (username.isNullOrBlank()) {
                    emptyView.text = getString(R.string.feed_bookmarks_login_required)
                    emptyView.visibility = View.VISIBLE
                } else {
                    viewModel = BookmarksViewModel.create(sessionStore, username)

                    viewModel?.bookmarksPagingFlow()?.collectLatest { pagingData ->
                        adapter.submitData(pagingData)
                    }
                }
            }
        }
    }
}
