package com.fire.app.ui.notifications

import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import android.widget.ImageView
import android.widget.TextView
import androidx.paging.PagingDataAdapter
import androidx.recyclerview.widget.DiffUtil
import androidx.recyclerview.widget.RecyclerView
import com.fire.app.R
import com.fire.app.TopicPresentation
import com.fire.app.core.image.FireAvatarUrls
import com.fire.app.core.image.FireImageLoader
import uniffi.fire_uniffi_notifications.NotificationItemState

class NotificationListAdapter(
    private val onNotificationClick: (NotificationItemState) -> Unit,
) : PagingDataAdapter<NotificationItemState, NotificationViewHolder>(DiffCallback) {

    override fun onCreateViewHolder(parent: ViewGroup, viewType: Int): NotificationViewHolder {
        return NotificationViewHolder.create(parent)
    }

    override fun onBindViewHolder(holder: NotificationViewHolder, position: Int) {
        getItem(position)?.let { holder.bind(it, onNotificationClick) }
    }

    private object DiffCallback : DiffUtil.ItemCallback<NotificationItemState>() {
        override fun areItemsTheSame(old: NotificationItemState, new: NotificationItemState): Boolean =
            old.id == new.id

        override fun areContentsTheSame(old: NotificationItemState, new: NotificationItemState): Boolean =
            old == new
    }
}

class NotificationViewHolder(itemView: View) : RecyclerView.ViewHolder(itemView) {
    private val avatar: ImageView = itemView.findViewById(R.id.notification_avatar)
    private val titleText: TextView = itemView.findViewById(R.id.notification_title)
    private val metaText: TextView = itemView.findViewById(R.id.notification_meta)
    private val unreadIndicator: View = itemView.findViewById(R.id.unread_indicator)

    fun bind(item: NotificationItemState, onClick: (NotificationItemState) -> Unit) {
        titleText.text = NotificationPresentation.displayDescription(item)

        val time = item.createdAt?.let { TopicPresentation.formatTimestamp(it) }
        metaText.text = buildList {
            NotificationPresentation.resolvedUsername(item)?.let { add(it) }
            time?.let { add(it) }
            if (item.highPriority) add(itemView.context.getString(R.string.notifications_high_priority))
        }.joinToString(" · ")

        unreadIndicator.visibility = if (!item.read) View.VISIBLE else View.GONE

        val avatarTemplate = item.actingUserAvatarTemplate
        if (!avatarTemplate.isNullOrBlank()) {
            FireAvatarUrls.build(avatarTemplate)?.let { url ->
                FireImageLoader.load(url, avatar)
            }
        } else {
            avatar.setImageDrawable(null)
        }

        itemView.setOnClickListener { onClick(item) }
    }

    companion object {
        fun create(parent: ViewGroup): NotificationViewHolder {
            val view = LayoutInflater.from(parent.context)
                .inflate(R.layout.item_notification, parent, false)
            return NotificationViewHolder(view)
        }
    }
}
