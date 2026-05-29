package com.fire.app.ui.notifications

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
import androidx.swiperefreshlayout.widget.SwipeRefreshLayout
import com.fire.app.R
import com.fire.app.session.FireSessionStoreRepository
import kotlinx.coroutines.flow.collectLatest
import kotlinx.coroutines.launch
import uniffi.fire_uniffi_notifications.NotificationItemState

class NotificationsFragment : Fragment() {

    private lateinit var recyclerView: RecyclerView
    private lateinit var adapter: NotificationListAdapter
    private lateinit var swipeRefresh: SwipeRefreshLayout
    private lateinit var emptyView: TextView
    private lateinit var loadingView: ProgressBar

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

        val sessionStore = FireSessionStoreRepository.get(requireContext())
        viewModel = NotificationsViewModel.create(sessionStore)

        adapter = NotificationListAdapter(::onNotificationClick)

        recyclerView.layoutManager = LinearLayoutManager(requireContext())
        recyclerView.adapter = adapter

        swipeRefresh.setOnRefreshListener {
            refreshNotifications()
        }

        viewModel?.let { vm ->
            viewLifecycleOwner.lifecycleScope.launch {
                vm.notificationPagingFlow().collectLatest { pagingData ->
                    adapter.submitData(pagingData)
                }
            }
        }

        setupMarkAllReadMenu()
    }

    private fun onNotificationClick(item: NotificationItemState) {
        val topicId = item.topicId
        if (topicId != null) {
            val action = NotificationsFragmentDirections
                .actionNotificationsToTopicDetail(
                    topicId = topicId.toLong(),
                    topicSlug = item.slug,
                    topicTitle = item.fancyTitle,
                    targetPostNumber = item.postNumber?.toInt() ?: -1,
                )
            findNavController().navigate(action)
        }
    }

    private fun refreshNotifications() {
        viewModel = viewModel?.let { vm ->
            val sessionStore = FireSessionStoreRepository.get(requireContext())
            val newVm = NotificationsViewModel.create(sessionStore)
            viewLifecycleOwner.lifecycleScope.launch {
                newVm.notificationPagingFlow().collectLatest { pagingData ->
                    adapter.submitData(pagingData)
                    swipeRefresh.isRefreshing = false
                }
            }
            newVm
        }
    }

    private fun setupMarkAllReadMenu() {
        // Will be replaced by toolbar menu when toolbar is added to the layout.
        // For now, mark-all-read is accessible via the ViewModel.
    }
}
