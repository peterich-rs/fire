package com.fire.app

import android.graphics.Color
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.os.Bundle
import android.view.View
import android.view.ViewGroup
import android.widget.Button
import android.widget.FrameLayout
import android.widget.LinearLayout
import android.widget.ProgressBar
import android.widget.TextView
import android.widget.Toast
import androidx.appcompat.app.AppCompatActivity
import androidx.lifecycle.lifecycleScope
import androidx.recyclerview.widget.DiffUtil
import androidx.recyclerview.widget.LinearLayoutManager
import androidx.recyclerview.widget.ListAdapter
import androidx.recyclerview.widget.RecyclerView
import com.fire.app.session.FireSessionStore
import com.fire.app.session.FireSessionStoreRepository
import kotlinx.coroutines.launch
import uniffi.fire_uniffi.plainTextFromHtml
import uniffi.fire_uniffi_notifications.NotificationCenterState
import uniffi.fire_uniffi_notifications.NotificationItemState
import uniffi.fire_uniffi_notifications.NotificationListState

class NotificationsActivity : AppCompatActivity() {
    private data class NotificationListItem(
        val key: String,
        val stableId: Long,
        val contentSignature: String,
        val buildView: () -> View,
    )

    private class NotificationListAdapter :
        ListAdapter<NotificationListItem, NotificationListAdapter.DynamicViewHolder>(DiffCallback) {

        init {
            setHasStableIds(true)
        }

        override fun getItemId(position: Int): Long = getItem(position).stableId

        override fun onCreateViewHolder(parent: ViewGroup, viewType: Int): DynamicViewHolder {
            return DynamicViewHolder(FrameLayout(parent.context))
        }

        override fun onBindViewHolder(holder: DynamicViewHolder, position: Int) {
            holder.bind(getItem(position).buildView())
        }

        class DynamicViewHolder(private val container: FrameLayout) : RecyclerView.ViewHolder(container) {
            fun bind(view: View) {
                container.removeAllViews()
                if (view.parent != null) {
                    (view.parent as? ViewGroup)?.removeView(view)
                }
                container.addView(
                    view,
                    FrameLayout.LayoutParams(
                        ViewGroup.LayoutParams.MATCH_PARENT,
                        ViewGroup.LayoutParams.WRAP_CONTENT,
                    ),
                )
            }
        }

        private object DiffCallback : DiffUtil.ItemCallback<NotificationListItem>() {
            override fun areItemsTheSame(
                oldItem: NotificationListItem,
                newItem: NotificationListItem,
            ): Boolean = oldItem.key == newItem.key

            override fun areContentsTheSame(
                oldItem: NotificationListItem,
                newItem: NotificationListItem,
            ): Boolean = oldItem.contentSignature == newItem.contentSignature
        }
    }

    private lateinit var sessionStore: FireSessionStore
    private lateinit var loadingIndicator: ProgressBar
    private lateinit var titleText: TextView
    private lateinit var metaText: TextView
    private lateinit var errorText: TextView
    private lateinit var notificationList: RecyclerView
    private lateinit var refreshButton: Button
    private lateinit var markAllReadButton: Button
    private lateinit var loadMoreButton: Button
    private val notificationListAdapter = NotificationListAdapter()

    private val notifications = mutableListOf<NotificationItemState>()
    private var nextOffset: UInt? = null
    private var totalRows: UInt = 0u
    private var counters: NotificationCenterState? = null
    private var isLoading = false

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        sessionStore = FireSessionStoreRepository.get(applicationContext)
        setContentView(buildContentView())
        renderNotifications(emptyMessage = getString(R.string.notifications_loading))
        loadNotifications(reset = true)
    }

    private fun buildContentView(): View {
        return LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL

            addView(
                LinearLayout(context).apply {
                    gravity = android.view.Gravity.CENTER_VERTICAL
                    orientation = LinearLayout.HORIZONTAL
                    setPadding(dp(12), dp(12), dp(12), dp(12))

                    addView(
                        Button(context).apply {
                            text = getString(R.string.action_back)
                            setOnClickListener { finish() }
                        },
                    )

                    addView(
                        LinearLayout(context).apply {
                            orientation = LinearLayout.VERTICAL
                            layoutParams = LinearLayout.LayoutParams(
                                0,
                                ViewGroup.LayoutParams.WRAP_CONTENT,
                                1f,
                            ).apply {
                                marginStart = dp(12)
                                marginEnd = dp(12)
                            }

                            titleText = TextView(context).apply {
                                text = getString(R.string.notifications_title)
                                textSize = 20f
                                setTypeface(typeface, Typeface.BOLD)
                                setTextColor(Color.parseColor("#FF111827"))
                                maxLines = 1
                                ellipsize = android.text.TextUtils.TruncateAt.END
                            }
                            addView(titleText)

                            metaText = TextView(context).apply {
                                text = getString(R.string.notifications_loading)
                                textSize = 12f
                                setTextColor(Color.parseColor("#FF6B7280"))
                                setPadding(0, dp(4), 0, 0)
                            }
                            addView(metaText)
                        },
                    )

                    refreshButton = Button(context).apply {
                        text = getString(R.string.action_refresh)
                        setOnClickListener { loadNotifications(reset = true) }
                    }
                    addView(refreshButton)
                },
            )

            loadingIndicator = ProgressBar(context, null, android.R.attr.progressBarStyleHorizontal).apply {
                max = 100
                visibility = View.GONE
            }
            addView(loadingIndicator)

            errorText = TextView(context).apply {
                visibility = View.GONE
                setTextColor(Color.parseColor("#FFB91C1C"))
                textSize = 14f
                setPadding(dp(16), dp(12), dp(16), dp(4))
            }
            addView(errorText)

            addView(
                LinearLayout(context).apply {
                    orientation = LinearLayout.HORIZONTAL
                    setPadding(dp(16), dp(12), dp(16), dp(4))

                    markAllReadButton = Button(context).apply {
                        isAllCaps = false
                        text = getString(R.string.notifications_mark_all_read)
                        setOnClickListener { markAllNotificationsRead() }
                        layoutParams = LinearLayout.LayoutParams(
                            0,
                            ViewGroup.LayoutParams.WRAP_CONTENT,
                            1f,
                        ).apply {
                            marginEnd = dp(8)
                        }
                    }
                    addView(markAllReadButton)

                    loadMoreButton = Button(context).apply {
                        isAllCaps = false
                        text = getString(R.string.action_load_more)
                        setOnClickListener { loadNotifications(reset = false) }
                        layoutParams = LinearLayout.LayoutParams(
                            0,
                            ViewGroup.LayoutParams.WRAP_CONTENT,
                            1f,
                        )
                    }
                    addView(loadMoreButton)
                },
            )

            notificationList = RecyclerView(context).apply {
                layoutParams = LinearLayout.LayoutParams(
                    ViewGroup.LayoutParams.MATCH_PARENT,
                    0,
                    1f,
                )
                clipToPadding = false
                setPadding(dp(16), dp(12), dp(16), dp(24))
                layoutManager = LinearLayoutManager(this@NotificationsActivity)
                adapter = notificationListAdapter
                itemAnimator = null
                setItemViewCacheSize(8)
                recycledViewPool.setMaxRecycledViews(0, 18)
            }
            addView(notificationList)
        }
    }

    private fun loadNotifications(reset: Boolean) {
        if (isLoading) {
            return
        }
        if (!reset && nextOffset == null) {
            return
        }
        lifecycleScope.launch {
            setLoading(true)
            errorText.visibility = View.GONE
            try {
                counters = sessionStore.notificationState()
                val page = sessionStore.fetchNotifications(
                    limit = NOTIFICATION_PAGE_SIZE,
                    offset = if (reset) null else nextOffset,
                )
                applyPage(page, reset)
                counters = sessionStore.notificationState()
                renderNotifications()
            } catch (error: Exception) {
                errorText.text = error.localizedMessage ?: getString(R.string.notifications_error)
                errorText.visibility = View.VISIBLE
                if (notifications.isEmpty()) {
                    renderNotifications(emptyMessage = getString(R.string.notifications_error))
                }
            } finally {
                setLoading(false)
                renderControls()
            }
        }
    }

    private fun applyPage(page: NotificationListState, reset: Boolean) {
        if (reset) {
            notifications.clear()
        }
        val existingIds = notifications.map { it.id }.toMutableSet()
        page.notifications.forEach { notification ->
            if (existingIds.add(notification.id)) {
                notifications.add(notification)
            }
        }
        totalRows = page.totalRowsNotifications
        nextOffset = page.nextOffset
    }

    private fun renderNotifications(emptyMessage: String? = null) {
        titleText.text = getString(R.string.notifications_title)
        renderControls()
        notificationListAdapter.submitList(notificationListItems(emptyMessage))
    }

    private fun notificationListItems(emptyMessage: String?): List<NotificationListItem> {
        if (notifications.isEmpty()) {
            val message = emptyMessage ?: getString(R.string.notifications_empty)
            return listOf(
                notificationListItem(
                    key = "empty",
                    stableId = -1L,
                    contentSignature = message,
                ) {
                    sectionBodyText(message)
                },
            )
        }

        return notifications.map { notification ->
            notificationListItem(
                key = "notification:${notification.id}",
                stableId = notificationStableId(notification.id),
                contentSignature = notification.toString(),
            ) {
                notificationRow(notification)
            }
        }
    }

    private fun notificationListItem(
        key: String,
        stableId: Long,
        contentSignature: String,
        buildView: () -> View,
    ): NotificationListItem {
        return NotificationListItem(
            key = key,
            stableId = stableId,
            contentSignature = contentSignature,
            buildView = buildView,
        )
    }

    private fun notificationStableId(id: ULong): Long {
        return id.toString().fold(1125899906842597L) { hash, character ->
            (hash * 31) + character.code
        }
    }

    private fun renderControls() {
        val state = counters
        metaText.text = buildList {
            if (state != null) {
                add(getString(R.string.notifications_unread_count, state.counters.unread.toString()))
                add(getString(R.string.notifications_all_unread_count, state.counters.allUnread.toString()))
                add(getString(R.string.notifications_high_priority_count, state.counters.highPriority.toString()))
            }
            if (notifications.isNotEmpty()) {
                add(getString(R.string.notifications_loaded_count, notifications.size.toString(), totalRows.toString()))
            }
        }.takeIf { it.isNotEmpty() }?.joinToString(" · ")
            ?: getString(R.string.notifications_loading)

        refreshButton.isEnabled = !isLoading
        markAllReadButton.isEnabled = !isLoading && notifications.any { !it.read }
        loadMoreButton.isEnabled = !isLoading && nextOffset != null
        loadMoreButton.visibility = if (nextOffset != null || isLoading) View.VISIBLE else View.GONE
        loadMoreButton.text = if (isLoading) {
            getString(R.string.browser_loading_more)
        } else {
            getString(R.string.action_load_more)
        }
    }

    private fun notificationRow(notification: NotificationItemState): View {
        val title = notificationTitle(notification)
        val actor = actorUsername(notification)
        val excerpt = notification.data.excerpt
            ?.let { plainTextFromHtml(it).trim() }
            ?.takeIf { it.isNotBlank() }
        val metadata = buildList {
            add(getString(R.string.notifications_type_label, notification.notificationType.toString()))
            add(if (notification.read) getString(R.string.notifications_read) else getString(R.string.notifications_unread))
            if (notification.highPriority) {
                add(getString(R.string.notifications_high_priority))
            }
            actor?.let { add("@$it") }
            (
                TopicPresentation.formatTimestamp(notification.createdTimestampUnixMs)
                    ?: TopicPresentation.formatTimestamp(notification.createdAt)
                )?.let(::add)
            notification.postNumber?.let {
                add(getString(R.string.notifications_post_number, it.toString()))
            }
        }.joinToString(" · ")

        return LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            isClickable = true
            setOnClickListener { openNotification(notification) }
            setPadding(dp(14), dp(12), dp(14), dp(12))
            background = roundedBackground(
                fillColor = if (notification.read) Color.WHITE else Color.parseColor("#FFEFF6FF"),
                strokeColor = if (notification.highPriority) {
                    Color.parseColor("#FFE11D48")
                } else {
                    Color.parseColor("#1F2563EB")
                },
            )
            layoutParams = LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.WRAP_CONTENT,
            ).apply {
                bottomMargin = dp(10)
            }

            addView(
                TextView(context).apply {
                    text = title
                    textSize = 15f
                    setTypeface(typeface, if (notification.read) Typeface.NORMAL else Typeface.BOLD)
                    setTextColor(Color.parseColor("#FF111827"))
                    maxLines = 2
                    ellipsize = android.text.TextUtils.TruncateAt.END
                },
            )
            addView(
                TextView(context).apply {
                    text = metadata
                    textSize = 12f
                    setTextColor(Color.parseColor("#FF6B7280"))
                    setPadding(0, dp(4), 0, 0)
                },
            )
            if (!excerpt.isNullOrBlank()) {
                addView(
                    TextView(context).apply {
                        text = excerpt
                        textSize = 13f
                        setTextColor(Color.parseColor("#FF374151"))
                        setPadding(0, dp(8), 0, 0)
                        maxLines = 3
                        ellipsize = android.text.TextUtils.TruncateAt.END
                    },
                )
            }
        }
    }

    private fun openNotification(notification: NotificationItemState) {
        lifecycleScope.launch {
            setLoading(true)
            errorText.visibility = View.GONE
            try {
                if (!notification.read) {
                    counters = sessionStore.markNotificationRead(notification.id)
                    replaceNotification(notification.id) { it.copy(read = true) }
                    renderNotifications()
                }
                openNotificationTarget(notification.copy(read = true))
            } catch (error: Exception) {
                errorText.text = error.localizedMessage ?: getString(R.string.notifications_mark_read_error)
                errorText.visibility = View.VISIBLE
            } finally {
                setLoading(false)
                renderControls()
            }
        }
    }

    private fun openNotificationTarget(notification: NotificationItemState) {
        val topicId = notification.topicId
        if (topicId != null) {
            startActivity(
                TopicDetailActivity.intent(
                    context = this,
                    topicId = topicId,
                    topicTitle = notificationTitle(notification),
                    targetPostNumber = notification.postNumber,
                ),
            )
            return
        }

        val username = actorUsername(notification)
        if (username != null) {
            startActivity(ProfileActivity.intent(this, username))
            return
        }

        Toast.makeText(this, R.string.notifications_no_target, Toast.LENGTH_SHORT).show()
    }

    private fun markAllNotificationsRead() {
        if (isLoading) {
            return
        }
        lifecycleScope.launch {
            setLoading(true)
            errorText.visibility = View.GONE
            try {
                counters = sessionStore.markAllNotificationsRead()
                replaceAllNotifications { it.copy(read = true) }
                renderNotifications()
            } catch (error: Exception) {
                errorText.text = error.localizedMessage ?: getString(R.string.notifications_mark_read_error)
                errorText.visibility = View.VISIBLE
            } finally {
                setLoading(false)
                renderControls()
            }
        }
    }

    private fun replaceNotification(
        id: ULong,
        transform: (NotificationItemState) -> NotificationItemState,
    ) {
        val index = notifications.indexOfFirst { it.id == id }
        if (index >= 0) {
            notifications[index] = transform(notifications[index])
        }
    }

    private fun replaceAllNotifications(transform: (NotificationItemState) -> NotificationItemState) {
        notifications.indices.forEach { index ->
            notifications[index] = transform(notifications[index])
        }
    }

    private fun notificationTitle(notification: NotificationItemState): String {
        return listOf(
            notification.fancyTitle,
            notification.data.topicTitle,
            notification.data.badgeName,
            notification.data.groupName,
            notification.data.payloadJson?.takeIf { notification.topicId == null },
        )
            .firstNotNullOfOrNull { value -> value?.trim()?.takeIf { it.isNotBlank() } }
            ?: getString(R.string.notifications_item_fallback, notification.id.toString())
    }

    private fun actorUsername(notification: NotificationItemState): String? {
        return listOf(
            notification.data.displayUsername,
            notification.data.username,
            notification.data.originalUsername,
            notification.data.username2,
        )
            .firstNotNullOfOrNull { value -> value?.trim()?.takeIf { it.isNotBlank() } }
    }

    private fun sectionBodyText(text: String): TextView {
        return TextView(this).apply {
            this.text = text
            textSize = 14f
            setTextColor(Color.parseColor("#FF374151"))
            setPadding(0, dp(4), 0, dp(6))
        }
    }

    private fun setLoading(loading: Boolean) {
        isLoading = loading
        loadingIndicator.visibility = if (loading) View.VISIBLE else View.GONE
        renderControls()
    }

    private fun roundedBackground(fillColor: Int, strokeColor: Int): GradientDrawable {
        return GradientDrawable().apply {
            shape = GradientDrawable.RECTANGLE
            cornerRadius = dp(10).toFloat()
            setColor(fillColor)
            setStroke(dp(1), strokeColor)
        }
    }

    private fun dp(value: Int): Int {
        return (value * resources.displayMetrics.density).toInt()
    }

    companion object {
        private val NOTIFICATION_PAGE_SIZE: UInt = 60u
    }
}
