package com.fire.app.ui.privatemessages

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
import com.fire.app.session.FireSessionStoreRepository
import com.fire.app.ui.composer.PrivateMessageComposerSheet
import com.fire.app.ui.home.TopicListAdapter
import com.fire.app.ui.topicdetail.TopicDetailActivity
import com.google.android.material.chip.Chip
import com.google.android.material.chip.ChipGroup
import kotlinx.coroutines.flow.collectLatest
import kotlinx.coroutines.launch
import uniffi.fire_uniffi_types.TopicListKindState

class PrivateMessagesFragment : Fragment() {

    private lateinit var recyclerView: RecyclerView
    private lateinit var adapter: TopicListAdapter
    private lateinit var emptyView: TextView
    private lateinit var loadingView: ProgressBar
    private lateinit var scopeChips: ChipGroup
    private lateinit var newMessageButton: View

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
        scopeChips = view.findViewById(R.id.pm_scope_chips)
        newMessageButton = view.findViewById(R.id.pm_new_message_button)

        viewLifecycleOwner.lifecycleScope.launch {
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
                val refresh = loadStates.refresh
                val isInitialLoading = refresh is LoadState.Loading && adapter.itemCount == 0
                loadingView.visibility = if (isInitialLoading) View.VISIBLE else View.GONE
                emptyView.visibility = when {
                    refresh is LoadState.Error -> {
                        emptyView.text = refresh.error.localizedMessage
                            ?: getString(R.string.feed_private_messages_empty)
                        View.VISIBLE
                    }
                    refresh is LoadState.NotLoading && adapter.itemCount == 0 -> {
                        emptyView.text = getString(R.string.feed_private_messages_empty)
                        View.VISIBLE
                    }
                    else -> View.GONE
                }
            }

            setupScopeChips()
            newMessageButton.setOnClickListener {
                showPrivateMessageComposer()
            }
            viewModel?.let { vm ->
                viewLifecycleOwner.repeatOnLifecycle(Lifecycle.State.STARTED) {
                    launch {
                        vm.pmPagingFlow.collectLatest { pagingData ->
                            adapter.submitData(pagingData)
                        }
                    }
                    launch {
                        vm.selectedKind.collectLatest { kind ->
                            updateSelectedScope(kind)
                        }
                    }
                }
            }
        }
    }

    private fun setupScopeChips() {
        val scopes = listOf(
            TopicListKindState.PRIVATE_MESSAGES_INBOX to getString(R.string.feed_private_messages_inbox),
            TopicListKindState.PRIVATE_MESSAGES_SENT to getString(R.string.feed_private_messages_sent),
        )
        scopeChips.removeAllViews()
        for ((kind, label) in scopes) {
            val chip = Chip(requireContext()).apply {
                text = label
                isCheckable = true
                setTag(R.id.tag_pm_scope, kind)
                setOnClickListener {
                    val selectedKind = getTag(R.id.tag_pm_scope) as? TopicListKindState
                    if (selectedKind != null) {
                        viewModel?.selectKind(selectedKind)
                    }
                }
            }
            scopeChips.addView(chip)
        }
        updateSelectedScope(viewModel?.selectedKind?.value ?: TopicListKindState.PRIVATE_MESSAGES_INBOX)
    }

    private fun updateSelectedScope(kind: TopicListKindState) {
        for (index in 0 until scopeChips.childCount) {
            val chip = scopeChips.getChildAt(index) as? Chip ?: continue
            chip.isChecked = chip.getTag(R.id.tag_pm_scope) == kind
        }
    }

    private fun showPrivateMessageComposer() {
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
}
