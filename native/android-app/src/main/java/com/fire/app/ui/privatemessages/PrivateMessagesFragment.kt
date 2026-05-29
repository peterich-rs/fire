package com.fire.app.ui.privatemessages

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
import com.fire.app.session.FireSessionStoreRepository
import com.fire.app.ui.cloudflare.CloudflareChallengeSupport
import com.fire.app.ui.home.TopicListAdapter
import com.fire.app.ui.topicdetail.TopicDetailActivity
import kotlinx.coroutines.flow.collectLatest
import kotlinx.coroutines.launch

class PrivateMessagesFragment : Fragment() {

    private lateinit var recyclerView: RecyclerView
    private lateinit var adapter: TopicListAdapter
    private lateinit var emptyView: TextView
    private lateinit var loadingView: ProgressBar

    private var viewModel: PrivateMessagesViewModel? = null

    override fun onCreateView(
        inflater: LayoutInflater,
        container: ViewGroup?,
        savedInstanceState: Bundle?,
    ): View? {
        return inflater.inflate(R.layout.fragment_private_messages, container, false)
    }

    override fun onViewCreated(view: View, savedInstanceState: Bundle?) {
        super.onViewCreated(view, savedInstanceState)

        recyclerView = view.findViewById(R.id.pm_list)
        emptyView = view.findViewById(R.id.empty_view)
        loadingView = view.findViewById(R.id.loading_view)

        val sessionStore = FireSessionStoreRepository.get(requireContext())
        viewModel = PrivateMessagesViewModel.create(sessionStore)

        adapter = TopicListAdapter { row ->
            TopicDetailActivity.start(
                context = requireContext(),
                topicId = row.topic.id.toLong(),
                topicTitle = row.topic.title,
            )
        }

        recyclerView.layoutManager = LinearLayoutManager(requireContext())
        recyclerView.adapter = adapter
        adapter.addLoadStateListener { loadStates ->
            listOf(loadStates.refresh, loadStates.append, loadStates.prepend)
                .filterIsInstance<LoadState.Error>()
                .firstOrNull { CloudflareChallengeSupport.isChallenge(it.error) }
                ?.let { context?.let(CloudflareChallengeSupport::openSiteRoot) }
        }

        viewModel?.let { vm ->
            viewLifecycleOwner.lifecycleScope.launch {
                vm.pmPagingFlow().collectLatest { pagingData ->
                    adapter.submitData(pagingData)
                }
            }
        }
    }
}
