package com.fire.app.ui.chat

import android.os.Bundle
import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import android.widget.EditText
import android.widget.ProgressBar
import android.widget.TextView
import android.widget.Toast
import androidx.appcompat.app.AlertDialog
import androidx.fragment.app.Fragment
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.lifecycleScope
import androidx.recyclerview.widget.LinearLayoutManager
import androidx.recyclerview.widget.RecyclerView
import androidx.swiperefreshlayout.widget.SwipeRefreshLayout
import com.fire.app.MainActivity
import com.fire.app.R
import com.fire.app.session.FireSessionStoreRepository
import com.google.android.material.floatingactionbutton.FloatingActionButton

import kotlinx.coroutines.flow.collectLatest
import kotlinx.coroutines.launch
import uniffi.fire_uniffi_chat.ChatChannelState

class ChatFragment : Fragment() {

    private lateinit var recyclerView: RecyclerView
    private lateinit var swipeRefresh: SwipeRefreshLayout
    private lateinit var emptyView: TextView
    private lateinit var loadingView: ProgressBar
    private lateinit var newButton: FloatingActionButton
    private lateinit var adapter: ChatChannelAdapter

    private var viewModel: ChatChannelsViewModel? = null

    override fun onCreateView(
        inflater: LayoutInflater,
        container: ViewGroup?,
        savedInstanceState: Bundle?,
    ): View = inflater.inflate(R.layout.fragment_chat, container, false)

    override fun onResume() {
        super.onResume()
        viewModel?.refresh()
    }

    override fun onViewCreated(view: View, savedInstanceState: Bundle?) {
        super.onViewCreated(view, savedInstanceState)
        recyclerView = view.findViewById(R.id.chat_channel_list)
        swipeRefresh = view.findViewById(R.id.chat_swipe_refresh)
        emptyView = view.findViewById(R.id.chat_empty)
        loadingView = view.findViewById(R.id.chat_loading)
        newButton = view.findViewById(R.id.chat_new_button)

        tabLayout.addTab(tabLayout.newTab().setText(R.string.chat_tab_dm))
        tabLayout.addTab(tabLayout.newTab().setText(R.string.chat_tab_public))

        adapter = ChatChannelAdapter(::openChannel)
        recyclerView.layoutManager = LinearLayoutManager(requireContext())
        recyclerView.adapter = adapter

        viewLifecycleOwner.lifecycleScope.launch {
            val sessionStore = FireSessionStoreRepository.get(requireContext())
            viewModel = ViewModelProvider(
                this@ChatFragment,
                ChatChannelsViewModelFactory(sessionStore),
            )[ChatChannelsViewModel::class.java]

            swipeRefresh.setOnRefreshListener { viewModel?.refresh() }
            newButton.setOnClickListener { showNewChatDialog() }
            viewModel?.loadIfNeeded()
            viewModel?.state?.collectLatest { state ->
                adapter.submitList(
                    state.displayedChannels.map { channel ->
                        ChatChannelRow(channel, state.badgeFor(channel))
                    },
                )
                swipeRefresh.isRefreshing = state.isLoading && state.hasLoadedOnce
                loadingView.visibility =
                    if (state.isLoading && !state.hasLoadedOnce) View.VISIBLE else View.GONE
                val emptyText = when {
                    state.errorMessage != null && state.displayedChannels.isEmpty() ->
                        state.errorMessage
                    state.displayedChannels.isEmpty() && state.hasLoadedOnce ->
                        getString(R.string.chat_empty_inbox)
                    else -> null
                }
                emptyView.visibility = if (emptyText != null) View.VISIBLE else View.GONE
                emptyView.text = emptyText
                (activity as? MainActivity)?.updateChatBadge(state.totalUnreadBadge.toInt())
            }
        }
    }

    private fun showNewChatDialog() {
        val input = EditText(requireContext()).apply {
            hint = getString(R.string.chat_new_hint)
            setSingleLine()
        }
        AlertDialog.Builder(requireContext())
            .setTitle(R.string.chat_new)
            .setMessage(R.string.chat_new_message)
            .setView(input)
            .setNegativeButton(R.string.action_cancel, null)
            .setPositiveButton(R.string.chat_start) { _, _ ->
                val usernames = input.text.toString()
                    .split(',')
                    .map { it.trim() }
                    .filter { it.isNotEmpty() }
                if (usernames.isEmpty()) return@setPositiveButton
                viewLifecycleOwner.lifecycleScope.launch {
                    runCatching { viewModel?.createDirectMessage(usernames) }
                        .onSuccess { channel ->
                            if (channel != null) openChannel(channel)
                        }
                        .onFailure { error ->
                            Toast.makeText(
                                requireContext(),
                                error.message ?: getString(R.string.chat_create_failed),
                                Toast.LENGTH_LONG,
                            ).show()
                        }
                }
            }
            .show()
    }

    private fun openChannel(channel: ChatChannelState) {
        startActivity(
            ChatChannelActivity.intent(
                requireContext(),
                channelId = channel.id,
                title = channel.displayTitle,
            ),
        )
    }
}
