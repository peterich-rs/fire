package com.fire.app.ui.notifications

import android.os.Bundle
import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import android.widget.ProgressBar
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
import androidx.paging.insertSeparators
import androidx.paging.map
import androidx.recyclerview.widget.LinearLayoutManager
import androidx.recyclerview.widget.RecyclerView
import androidx.swiperefreshlayout.widget.SwipeRefreshLayout
import com.fire.app.MainActivity
import com.fire.app.R
import com.fire.app.core.ext.optimizeForPaging
import com.fire.app.session.FireSessionStore
import com.fire.app.session.FireSessionStoreRepository
import com.fire.app.ui.topicdetail.TopicDetailActivity
import java.time.LocalDate
import java.time.OffsetDateTime
import kotlinx.coroutines.flow.collectLatest
import kotlinx.coroutines.launch
import uniffi.fire_uniffi_notifications.NotificationItemState

class NotificationHistoryFragment : Fragment() {

    private lateinit var recyclerView: RecyclerView
    private lateinit var adapter: NotificationHistoryAdapter
    private lateinit var swipeRefresh: SwipeRefreshLayout
    private lateinit var emptyView: TextView
    private lateinit var loadingView: ProgressBar
    private lateinit var offlineBanner: View

    private var viewModel: NotificationsViewModel? = null

    override fun onCreateView(
        inflater: LayoutInflater,
        container: ViewGroup?,
        savedInstanceState: Bundle?,
    ): View? {
        return inflater.inflate(R.layout.fragment_notification_history, container, false)
    }

    override fun onViewCreated(view: View, savedInstanceState: Bundle?) {
        super.onViewCreated(view, savedInstanceState)

        recyclerView = view.findViewById(R.id.notification_history_list)
        swipeRefresh = view.findViewById(R.id.swipe_refresh)
        emptyView = view.findViewById(R.id.empty_view)
        loadingView = view.findViewById(R.id.loading_view)
        offlineBanner = view.findViewById(R.id.offline_banner)

        viewLifecycleOwner.lifecycleScope.launch {
            val sessionStore = FireSessionStoreRepository.get(requireContext())
            viewModel = ViewModelProvider(
                this@NotificationHistoryFragment,
                NotificationsViewModelFactory(sessionStore),
            )[NotificationsViewModel::class.java]

            adapter = NotificationHistoryAdapter(::onNotificationClick)
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
                viewModel?.prepareFullNotificationRefresh()
                viewModel?.refreshNotificationCenter()
                adapter.refresh()
            }

            val vm = viewModel ?: return@launch
            viewLifecycleOwner.repeatOnLifecycle(Lifecycle.State.STARTED) {
                launch {
                    vm.notificationPagingFlow()
                        .collectLatest { pagingData ->
                            adapter.submitData(
                                pagingData
                                    .map { notification -> NotificationHistoryRow.Item(notification) }
                                    .insertSeparators { before, after ->
                                        val afterGroup = after?.notification?.historyGroup() ?: return@insertSeparators null
                                        val beforeGroup = before?.notification?.historyGroup()
                                        if (afterGroup == beforeGroup) {
                                            null
                                        } else {
                                            NotificationHistoryRow.Header(
                                                groupKey = afterGroup,
                                                label = afterGroup.label(),
                                            )
                                        }
                                    },
                            )
                        }
                }
                launch {
                    vm.notificationCenter.collect { state ->
                        if (state != null) {
                            (activity as? MainActivity)?.refreshNotificationBadge()
                        }
                    }
                }
                launch {
                    vm.isFullOffline.collect { isOffline ->
                        offlineBanner.visibility = if (isOffline) View.VISIBLE else View.GONE
                    }
                }
                launch {
                    vm.error.collect { error ->
                        if (!error.isNullOrBlank()) {
                            Toast.makeText(requireContext(), error, Toast.LENGTH_SHORT).show()
                        }
                    }
                }
            }
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
            val action = NotificationHistoryFragmentDirections
                .actionNotificationHistoryToProfile(username)
            findNavController().navigate(action)
            return
        }

        Toast.makeText(requireContext(), R.string.notifications_no_target, Toast.LENGTH_SHORT).show()
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

    private fun NotificationItemState.historyGroup(): NotificationHistoryGroup {
        val createdDate = createdAt?.localDate()
        val today = LocalDate.now()
        return when (createdDate) {
            today -> NotificationHistoryGroup.TODAY
            today.minusDays(1) -> NotificationHistoryGroup.YESTERDAY
            else -> NotificationHistoryGroup.EARLIER
        }
    }

    private fun String.localDate(): LocalDate? {
        return runCatching {
            OffsetDateTime.parse(this).toLocalDate()
        }.getOrNull()
    }

    private fun NotificationHistoryGroup.label(): String {
        return when (this) {
            NotificationHistoryGroup.TODAY -> getString(R.string.notifications_history_today)
            NotificationHistoryGroup.YESTERDAY -> getString(R.string.notifications_history_yesterday)
            NotificationHistoryGroup.EARLIER -> getString(R.string.notifications_history_earlier)
        }
    }

    private class NotificationsViewModelFactory(
        private val sessionStore: FireSessionStore,
    ) : ViewModelProvider.Factory {
        @Suppress("UNCHECKED_CAST")
        override fun <T : ViewModel> create(modelClass: Class<T>): T {
            if (modelClass.isAssignableFrom(NotificationsViewModel::class.java)) {
                return NotificationsViewModel.create(sessionStore) as T
            }
            throw IllegalArgumentException("Unknown ViewModel class: ${modelClass.name}")
        }
    }
}
