package com.fire.app.ui.notifications

import android.os.Bundle
import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import android.widget.ProgressBar
import android.widget.TextView
import android.widget.Toast
import androidx.fragment.app.Fragment
import androidx.lifecycle.lifecycleScope
import androidx.navigation.fragment.findNavController
import androidx.paging.LoadState
import androidx.recyclerview.widget.LinearLayoutManager
import androidx.recyclerview.widget.RecyclerView
import androidx.swiperefreshlayout.widget.SwipeRefreshLayout
import com.fire.app.MainActivity
import com.fire.app.R
import com.fire.app.session.FireSessionStoreRepository
import com.fire.app.ui.cloudflare.CloudflareChallengeSupport
import com.fire.app.ui.topicdetail.TopicDetailActivity
import kotlinx.coroutines.flow.collectLatest
import kotlinx.coroutines.launch
import uniffi.fire_uniffi_notifications.NotificationItemState

class NotificationsFragment : Fragment() {

    private lateinit var recyclerView: RecyclerView
    private lateinit var adapter: NotificationListAdapter
    private lateinit var swipeRefresh: SwipeRefreshLayout
    private lateinit var emptyView: TextView
    private lateinit var loadingView: ProgressBar
    private lateinit var markAllReadButton: View

    private var viewModel: NotificationsViewModel? = null

    override fun onCreateView(
        inflater: LayoutInflater,
        container: ViewGroup?,
        savedInstanceState: Bundle?,
    ): View? {
        return inflater.inflate(R.layout.fragment_notifications, container, false)
    }

    override fun onViewCreated(view: View, savedInstanceState: Bundle?) {
        super.onViewCreated(view, savedInstanceState)

        recyclerView = view.findViewById(R.id.notification_list)
        swipeRefresh = view.findViewById(R.id.swipe_refresh)
        emptyView = view.findViewById(R.id.empty_view)
        loadingView = view.findViewById(R.id.loading_view)
        markAllReadButton = view.findViewById(R.id.mark_all_read_button)

        val sessionStore = FireSessionStoreRepository.get(requireContext())
        viewModel = NotificationsViewModel.create(sessionStore)

        adapter = NotificationListAdapter(::onNotificationClick)

        recyclerView.layoutManager = LinearLayoutManager(requireContext())
        recyclerView.adapter = adapter
        adapter.addLoadStateListener { loadStates ->
            val refresh = loadStates.refresh
            val challengeError = listOf(loadStates.refresh, loadStates.append, loadStates.prepend)
                .filterIsInstance<LoadState.Error>()
                .firstOrNull { CloudflareChallengeSupport.isChallenge(it.error) }
            if (challengeError != null) {
                context?.let(CloudflareChallengeSupport::openSiteRoot)
            }
            val isInitialLoading = refresh is LoadState.Loading && adapter.itemCount == 0
            loadingView.visibility = if (isInitialLoading) View.VISIBLE else View.GONE
            emptyView.visibility = when {
                refresh is LoadState.Error -> {
                    emptyView.text = refresh.error.localizedMessage
                        ?: getString(R.string.notifications_error)
                    View.VISIBLE
                }
                refresh is LoadState.NotLoading && adapter.itemCount == 0 -> {
                    emptyView.text = getString(R.string.notifications_empty)
                    View.VISIBLE
                }
                else -> View.GONE
            }
            if (refresh !is LoadState.Loading) {
                swipeRefresh.isRefreshing = false
            }
        }

        swipeRefresh.setOnRefreshListener {
            refreshNotifications()
        }

        markAllReadButton.setOnClickListener {
            viewModel?.markAllRead()
        }

        viewModel?.let { vm ->
            viewLifecycleOwner.lifecycleScope.launch {
                vm.notificationPagingFlow().collectLatest { pagingData ->
                    adapter.submitData(pagingData)
                }
            }

            viewLifecycleOwner.lifecycleScope.launch {
                vm.notificationCenter.collect { state ->
                    val unreadCount = state?.counters?.allUnread?.toInt() ?: 0
                    markAllReadButton.visibility = if (unreadCount > 0) View.VISIBLE else View.GONE
                    if (state != null) {
                        adapter.refresh()
                    }
                    (activity as? MainActivity)?.refreshNotificationBadge()
                }
            }

            viewLifecycleOwner.lifecycleScope.launch {
                vm.isRefreshing.collect { refreshing ->
                    swipeRefresh.isRefreshing = refreshing
                }
            }

            viewLifecycleOwner.lifecycleScope.launch {
                vm.error.collect { error ->
                    if (!error.isNullOrBlank()) {
                        Toast.makeText(requireContext(), error, Toast.LENGTH_SHORT).show()
                    }
                }
            }

            viewLifecycleOwner.lifecycleScope.launch {
                vm.cloudflareChallenge.collect {
                    CloudflareChallengeSupport.openSiteRoot(requireContext())
                }
            }

            vm.refreshRecentNotifications()
        }
    }

    private fun onNotificationClick(item: NotificationItemState) {
        if (!item.read) {
            viewModel?.markRead(item.id)
        }

        val topicId = item.topicId
        if (topicId != null) {
            TopicDetailActivity.start(
                context = requireContext(),
                topicId = topicId.toLong(),
                topicTitle = item.fancyTitle,
                targetPostNumber = item.postNumber?.toInt() ?: -1,
            )
            return
        }

        val username = item.resolvedUsername()
        if (username != null) {
            val action = NotificationsFragmentDirections.actionNotificationsToProfile(username)
            findNavController().navigate(action)
            return
        }

        Toast.makeText(requireContext(), R.string.notifications_no_target, Toast.LENGTH_SHORT).show()
    }

    private fun refreshNotifications() {
        viewModel?.refreshRecentNotifications()
        adapter.refresh()
    }

    private fun NotificationItemState.resolvedUsername(): String? {
        return listOf(
            data.displayUsername,
            data.username,
            data.originalUsername,
        ).firstNotNullOfOrNull { value ->
            value?.trim()?.takeIf { it.isNotEmpty() && !it.equals("null", ignoreCase = true) }
        }
    }
}
