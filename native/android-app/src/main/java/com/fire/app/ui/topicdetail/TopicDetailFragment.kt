package com.fire.app.ui.topicdetail

import android.os.Bundle
import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import android.widget.ProgressBar
import android.widget.TextView
import androidx.fragment.app.Fragment
import androidx.lifecycle.lifecycleScope
import androidx.navigation.fragment.navArgs
import androidx.recyclerview.widget.ConcatAdapter
import androidx.recyclerview.widget.LinearLayoutManager
import androidx.recyclerview.widget.RecyclerView
import com.fire.app.R
import com.fire.app.session.FireSessionStoreRepository
import kotlinx.coroutines.flow.collectLatest
import kotlinx.coroutines.launch

class TopicDetailFragment : Fragment() {

    private val args: TopicDetailFragmentArgs by navArgs()

    private lateinit var recyclerView: RecyclerView
    private lateinit var loadingView: ProgressBar
    private lateinit var errorView: View
    private lateinit var errorText: TextView
    private lateinit var retryButton: View
    private lateinit var replyFab: View

    private var viewModel: TopicDetailViewModel? = null

    private val headerAdapter = HeaderAdapter()
    private val postListAdapter = PostListAdapter { /* post click handler */ }
    private val loadingFooterAdapter = LoadingFooterAdapter()

    override fun onCreateView(
        inflater: LayoutInflater,
        container: ViewGroup?,
        savedInstanceState: Bundle?,
    ): View? {
        return inflater.inflate(R.layout.fragment_topic_detail, container, false)
    }

    override fun onViewCreated(view: View, savedInstanceState: Bundle?) {
        super.onViewCreated(view, savedInstanceState)

        recyclerView = view.findViewById(R.id.post_list)
        loadingView = view.findViewById(R.id.loading_view)
        errorView = view.findViewById(R.id.error_view)
        errorText = view.findViewById(R.id.error_text)
        retryButton = view.findViewById(R.id.retry_button)
        replyFab = view.findViewById(R.id.reply_fab)

        val sessionStore = FireSessionStoreRepository.get(requireContext())
        viewModel = TopicDetailViewModel.create(sessionStore)

        val concatAdapter = ConcatAdapter(headerAdapter, postListAdapter, loadingFooterAdapter)
        recyclerView.layoutManager = LinearLayoutManager(requireContext())
        recyclerView.adapter = concatAdapter

        recyclerView.addOnScrollListener(object : RecyclerView.OnScrollListener() {
            override fun onScrolled(rv: RecyclerView, dx: Int, dy: Int) {
                val layoutManager = rv.layoutManager as? LinearLayoutManager ?: return
                val totalItemCount = layoutManager.itemCount
                val lastVisible = layoutManager.findLastVisibleItemPosition()
                if (lastVisible >= totalItemCount - 5) {
                    viewModel?.loadMorePosts()
                }
            }
        })

        val topicId = args.topicId.toULong()
        val targetPostNumber = args.targetPostNumber?.toUInt()

        viewModel?.let { vm ->
            viewLifecycleOwner.lifecycleScope.launch {
                vm.isLoading.collectLatest { loading ->
                    loadingView.visibility = if (loading) View.VISIBLE else View.GONE
                    recyclerView.visibility = if (loading && vm.postRows.value.isEmpty()) View.GONE else View.VISIBLE
                }
            }

            viewLifecycleOwner.lifecycleScope.launch {
                vm.errorMessage.collectLatest { error ->
                    if (error != null) {
                        errorView.visibility = View.VISIBLE
                        errorText.text = error
                    } else {
                        errorView.visibility = View.GONE
                    }
                }
            }

            viewLifecycleOwner.lifecycleScope.launch {
                vm.detail.collectLatest { detail ->
                    headerAdapter.detail = detail
                }
            }

            viewLifecycleOwner.lifecycleScope.launch {
                vm.postRows.collectLatest { rows ->
                    postListAdapter.submitList(rows)
                }
            }

            viewLifecycleOwner.lifecycleScope.launch {
                vm.isLoadingMore.collectLatest { loadingMore ->
                    loadingFooterAdapter.isLoading = loadingMore
                }
            }
        }

        retryButton.setOnClickListener {
            viewModel?.loadTopicDetail(topicId, targetPostNumber)
        }

        val topicTitle = args.topicTitle ?: getString(R.string.topic_detail_title_fallback, args.topicId)
        requireActivity().title = topicTitle

        viewModel?.loadTopicDetail(topicId, targetPostNumber)
    }
}
