package com.fire.app.ui.chat

import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import android.widget.ImageView
import android.widget.TextView
import androidx.recyclerview.widget.DiffUtil
import androidx.recyclerview.widget.ListAdapter
import androidx.recyclerview.widget.RecyclerView
import com.fire.app.R
import com.fire.app.core.image.FireAvatarUrls
import com.fire.app.core.image.FireImageLoader
import uniffi.fire_uniffi_chat.ChatChannelState

data class ChatChannelRow(
    val channel: ChatChannelState,
    val badge: UInt,
)

class ChatChannelAdapter(
    private val onClick: (ChatChannelState) -> Unit,
) : ListAdapter<ChatChannelRow, ChatChannelAdapter.Holder>(Diff) {

    override fun onCreateViewHolder(parent: ViewGroup, viewType: Int): Holder {
        val view = LayoutInflater.from(parent.context)
            .inflate(R.layout.item_chat_channel, parent, false)
        return Holder(view, onClick)
    }

    override fun onBindViewHolder(holder: Holder, position: Int) {
        holder.bind(getItem(position))
    }

    class Holder(
        itemView: View,
        private val onClick: (ChatChannelState) -> Unit,
    ) : RecyclerView.ViewHolder(itemView) {
        private val avatar: ImageView = itemView.findViewById(R.id.channel_avatar)
        private val title: TextView = itemView.findViewById(R.id.channel_title)
        private val preview: TextView = itemView.findViewById(R.id.channel_preview)
        private val badge: TextView = itemView.findViewById(R.id.channel_badge)

        fun bind(row: ChatChannelRow) {
            title.text = row.channel.displayTitle
            preview.text = row.channel.lastMessage?.previewText
                ?.takeIf { it.isNotBlank() }
                ?: row.channel.description
                ?: itemView.context.getString(R.string.chat_no_messages)
            if (row.badge > 0u) {
                badge.visibility = View.VISIBLE
                badge.text = if (row.badge > 99u) "99+" else row.badge.toString()
            } else {
                badge.visibility = View.GONE
            }

            avatar.setImageDrawable(null)
            val peer = row.channel.dmUsers.firstOrNull()
            if (row.channel.isDirectMessage) {
                FireAvatarUrls.build(peer?.avatarTemplate)?.let { url ->
                    FireImageLoader.load(url, avatar)
                } ?: avatar.setImageResource(R.drawable.ic_profile)
            } else {
                avatar.setImageResource(R.drawable.ic_home)
            }
            itemView.setOnClickListener { onClick(row.channel) }
        }
    }

    private object Diff : DiffUtil.ItemCallback<ChatChannelRow>() {
        override fun areItemsTheSame(oldItem: ChatChannelRow, newItem: ChatChannelRow): Boolean {
            return oldItem.channel.id == newItem.channel.id
        }

        override fun areContentsTheSame(oldItem: ChatChannelRow, newItem: ChatChannelRow): Boolean {
            return oldItem == newItem
        }
    }
}
