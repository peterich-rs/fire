package com.fire.app.ui.search

import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import android.widget.ImageView
import android.widget.TextView
import androidx.recyclerview.widget.DiffUtil
import androidx.recyclerview.widget.ListAdapter
import androidx.recyclerview.widget.RecyclerView
import com.fire.app.R
import com.fire.app.TopicPresentation
import com.fire.app.core.image.FireAvatarUrls
import com.fire.app.core.image.FireImageLoader
import uniffi.fire_uniffi_search.SearchPostState
import uniffi.fire_uniffi_search.SearchTopicState
import uniffi.fire_uniffi_search.SearchUserState

sealed class SearchRow {
    data class SectionHeader(val title: String) : SearchRow()
    data class TopicRow(val topic: SearchTopicState) : SearchRow()
    data class PostRow(val post: SearchPostState) : SearchRow()
    data class UserRow(val user: SearchUserState) : SearchRow()
}

class SearchResultsAdapter(
    private val onTopicClick: (SearchTopicState) -> Unit,
    private val onPostClick: (SearchPostState) -> Unit,
    private val onUserClick: (SearchUserState) -> Unit,
) : ListAdapter<SearchRow, RecyclerView.ViewHolder>(DiffCallback) {

    companion object {
        private const val TYPE_TOPIC = 0
        private const val TYPE_POST = 1
        private const val TYPE_USER = 2
        private const val TYPE_SECTION = 3
    }

    override fun getItemViewType(position: Int): Int = when (getItem(position)) {
        is SearchRow.TopicRow -> TYPE_TOPIC
        is SearchRow.PostRow -> TYPE_POST
        is SearchRow.UserRow -> TYPE_USER
        is SearchRow.SectionHeader -> TYPE_SECTION
    }

    override fun onCreateViewHolder(parent: ViewGroup, viewType: Int): RecyclerView.ViewHolder {
        val inflater = LayoutInflater.from(parent.context)
        return when (viewType) {
            TYPE_TOPIC -> TopicViewHolder(
                inflater.inflate(R.layout.item_search_topic, parent, false),
            )
            TYPE_POST -> PostViewHolder(
                inflater.inflate(R.layout.item_search_post, parent, false),
            )
            TYPE_USER -> UserViewHolder(
                inflater.inflate(R.layout.item_search_user, parent, false),
            )
            TYPE_SECTION -> SectionViewHolder(
                inflater.inflate(R.layout.item_search_section, parent, false),
            )
            else -> throw IllegalArgumentException("Unknown view type: $viewType")
        }
    }

    override fun onBindViewHolder(holder: RecyclerView.ViewHolder, position: Int) {
        when (val row = getItem(position)) {
            is SearchRow.TopicRow -> (holder as TopicViewHolder).bind(row.topic, onTopicClick)
            is SearchRow.PostRow -> (holder as PostViewHolder).bind(row.post, onPostClick)
            is SearchRow.UserRow -> (holder as UserViewHolder).bind(row.user, onUserClick)
            is SearchRow.SectionHeader -> (holder as SectionViewHolder).bind(row.title)
        }
    }

    private object DiffCallback : DiffUtil.ItemCallback<SearchRow>() {
        override fun areItemsTheSame(oldItem: SearchRow, newItem: SearchRow): Boolean {
            return when {
                oldItem is SearchRow.SectionHeader && newItem is SearchRow.SectionHeader ->
                    oldItem.title == newItem.title
                oldItem is SearchRow.TopicRow && newItem is SearchRow.TopicRow ->
                    oldItem.topic.id == newItem.topic.id
                oldItem is SearchRow.PostRow && newItem is SearchRow.PostRow ->
                    oldItem.post.id == newItem.post.id
                oldItem is SearchRow.UserRow && newItem is SearchRow.UserRow ->
                    oldItem.user.id == newItem.user.id
                else -> false
            }
        }

        override fun areContentsTheSame(oldItem: SearchRow, newItem: SearchRow): Boolean =
            oldItem == newItem
    }

    class TopicViewHolder(itemView: View) : RecyclerView.ViewHolder(itemView) {
        private val title: TextView = itemView.findViewById(R.id.search_topic_title)
        private val meta: TextView = itemView.findViewById(R.id.search_topic_meta)
        private val tags: TextView = itemView.findViewById(R.id.search_topic_tags)

        fun bind(topic: SearchTopicState, onClick: (SearchTopicState) -> Unit) {
            title.text = topic.title
            meta.text = itemView.context.getString(
                R.string.search_topic_meta,
                topic.postsCount.toString(),
                topic.views.toString(),
            )
            if (topic.tags.isNotEmpty()) {
                tags.text = topic.tags.joinToString(" · ")
                tags.visibility = View.VISIBLE
            } else {
                tags.visibility = View.GONE
            }
            itemView.setOnClickListener { onClick(topic) }
        }
    }

    class PostViewHolder(itemView: View) : RecyclerView.ViewHolder(itemView) {
        private val title: TextView = itemView.findViewById(R.id.search_post_title)
        private val meta: TextView = itemView.findViewById(R.id.search_post_meta)
        private val blurb: TextView = itemView.findViewById(R.id.search_post_blurb)

        fun bind(post: SearchPostState, onClick: (SearchPostState) -> Unit) {
            title.text = post.topicTitleHeadline ?: itemView.context.getString(
                R.string.topic_detail_title_fallback, post.topicId?.toString() ?: "?",
            )
            meta.text = itemView.context.getString(
                R.string.search_post_meta,
                post.username,
                post.postNumber.toString(),
                post.likeCount.toString(),
            )
            blurb.text = post.blurb
            itemView.setOnClickListener { onClick(post) }
        }
    }

    class UserViewHolder(itemView: View) : RecyclerView.ViewHolder(itemView) {
        private val avatar: ImageView = itemView.findViewById(R.id.search_user_avatar)
        private val username: TextView = itemView.findViewById(R.id.search_user_username)
        private val name: TextView = itemView.findViewById(R.id.search_user_name)

        fun bind(user: SearchUserState, onClick: (SearchUserState) -> Unit) {
            username.text = itemView.context.getString(R.string.search_user_meta, user.username)
            name.text = user.name ?: ""
            name.visibility = if (user.name.isNullOrBlank()) View.GONE else View.VISIBLE
            val avatarTemplate = user.avatarTemplate
            if (!avatarTemplate.isNullOrBlank()) {
                FireAvatarUrls.build(avatarTemplate)?.let { url ->
                    FireImageLoader.load(url, avatar)
                }
            } else {
                avatar.setImageDrawable(null)
            }
            itemView.setOnClickListener { onClick(user) }
        }
    }

    class SectionViewHolder(itemView: View) : RecyclerView.ViewHolder(itemView) {
        private val title: TextView = itemView.findViewById(R.id.section_title)

        fun bind(value: String) {
            title.text = value
        }
    }
}
