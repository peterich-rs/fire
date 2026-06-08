package com.fire.app.ui.notifications

import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import android.widget.TextView
import androidx.paging.PagingDataAdapter
import androidx.recyclerview.widget.DiffUtil
import androidx.recyclerview.widget.RecyclerView
import com.fire.app.R
import uniffi.fire_uniffi_notifications.NotificationItemState

class NotificationHistoryAdapter(
    private val onNotificationClick: (NotificationItemState) -> Unit,
) : PagingDataAdapter<NotificationHistoryRow, RecyclerView.ViewHolder>(DiffCallback) {

    override fun getItemViewType(position: Int): Int {
        return when (getItem(position)) {
            is NotificationHistoryRow.Header -> VIEW_TYPE_HEADER
            is NotificationHistoryRow.Item -> VIEW_TYPE_ITEM
            null -> VIEW_TYPE_ITEM
        }
    }

    override fun onCreateViewHolder(parent: ViewGroup, viewType: Int): RecyclerView.ViewHolder {
        return when (viewType) {
            VIEW_TYPE_HEADER -> HeaderViewHolder.create(parent)
            else -> NotificationViewHolder.create(parent)
        }
    }

    override fun onBindViewHolder(holder: RecyclerView.ViewHolder, position: Int) {
        when (val row = getItem(position)) {
            is NotificationHistoryRow.Header -> (holder as HeaderViewHolder).bind(row)
            is NotificationHistoryRow.Item -> (holder as NotificationViewHolder).bind(
                row.notification,
                onNotificationClick,
            )
            null -> Unit
        }
    }

    private class HeaderViewHolder(itemView: View) : RecyclerView.ViewHolder(itemView) {
        private val label: TextView = itemView.findViewById(R.id.notification_history_header_label)

        fun bind(row: NotificationHistoryRow.Header) {
            label.text = row.label
        }

        companion object {
            fun create(parent: ViewGroup): HeaderViewHolder {
                val view = LayoutInflater.from(parent.context)
                    .inflate(R.layout.item_notification_history_header, parent, false)
                return HeaderViewHolder(view)
            }
        }
    }

    private object DiffCallback : DiffUtil.ItemCallback<NotificationHistoryRow>() {
        override fun areItemsTheSame(
            oldItem: NotificationHistoryRow,
            newItem: NotificationHistoryRow,
        ): Boolean {
            return oldItem.stableId == newItem.stableId
        }

        override fun areContentsTheSame(
            oldItem: NotificationHistoryRow,
            newItem: NotificationHistoryRow,
        ): Boolean {
            return oldItem == newItem
        }
    }

    private companion object {
        const val VIEW_TYPE_HEADER = 0
        const val VIEW_TYPE_ITEM = 1
    }
}

sealed class NotificationHistoryRow {
    abstract val stableId: String

    data class Header(
        val groupKey: NotificationHistoryGroup,
        val label: String,
    ) : NotificationHistoryRow() {
        override val stableId: String = "header:${groupKey.name}"
    }

    data class Item(
        val notification: NotificationItemState,
    ) : NotificationHistoryRow() {
        override val stableId: String = "notification:${notification.id}"
    }
}

enum class NotificationHistoryGroup {
    TODAY,
    YESTERDAY,
    EARLIER,
}
