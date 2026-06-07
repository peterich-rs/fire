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
) : PagingDataAdapter<NotificationItemState, NotificationListAdapter.NotificationViewHolder>(DiffCallback) {

    override fun onCreateViewHolder(parent: ViewGroup, viewType: Int): NotificationViewHolder {
        val view = LayoutInflater.from(parent.context)
            .inflate(R.layout.item_notification, parent, false)
        return NotificationViewHolder(view)
    }

    override fun onBindViewHolder(holder: NotificationViewHolder, position: Int) {
        getItem(position)?.let { holder.bind(it, onNotificationClick) }
    }

    class NotificationViewHolder(itemView: View) : RecyclerView.ViewHolder(itemView) {
        private val avatar: ImageView = itemView.findViewById(R.id.notification_avatar)
        private val titleText: TextView = itemView.findViewById(R.id.notification_title)
        private val metaText: TextView = itemView.findViewById(R.id.notification_meta)
        private val unreadIndicator: View = itemView.findViewById(R.id.unread_indicator)

        fun bind(item: NotificationItemState, onClick: (NotificationItemState) -> Unit) {
            titleText.text = item.displayDescription()

            val time = item.createdAt?.let { TopicPresentation.formatTimestamp(it) }
            metaText.text = buildList {
                item.resolvedUsername()?.let { add(it) }
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

        private fun NotificationItemState.resolvedUsername(): String? {
            return listOf(
                data.displayUsername,
                data.username,
                data.originalUsername,
            ).firstNotNullOfOrNull { value ->
                value?.trim()?.takeIf { it.isNotEmpty() && !it.equals("null", ignoreCase = true) }
            }
        }

        private fun NotificationItemState.displayDescription(): String {
            val actor = resolvedUsername() ?: "Someone"
            val title = fancyTitle ?: data.topicTitle
            val suffix = title?.takeIf { it.isNotBlank() }?.let { ": $it" }.orEmpty()
            return when (notificationType) {
                1 -> "$actor mentioned you$suffix"
                2 -> "$actor replied to you$suffix"
                3 -> "$actor quoted your post$suffix"
                5 -> "$actor liked your post$suffix"
                6 -> "$actor sent you a message$suffix"
                12 -> data.badgeName?.let { "You earned badge: $it" }
                    ?: itemView.context.getString(R.string.notifications_item_fallback, id.toString())
                24 -> "Bookmark reminder$suffix"
                25 -> "$actor reacted to your post$suffix"
                800 -> "$actor followed you"
                801 -> "$actor created a topic$suffix"
                802 -> "$actor replied$suffix"
                else -> title ?: itemView.context.getString(
                    R.string.notifications_item_fallback,
                    id.toString(),
                )
            }
        }
    }

    private object DiffCallback : DiffUtil.ItemCallback<NotificationItemState>() {
        override fun areItemsTheSame(old: NotificationItemState, new: NotificationItemState): Boolean =
            old.id == new.id

        override fun areContentsTheSame(old: NotificationItemState, new: NotificationItemState): Boolean =
            old == new
    }
}
