package com.fire.app.ui.topicdetail

import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import androidx.recyclerview.widget.DiffUtil
import androidx.recyclerview.widget.ListAdapter
import androidx.recyclerview.widget.RecyclerView
import com.fire.app.R
import com.fire.app.TopicPresentation
import com.google.android.material.chip.Chip
import com.google.android.material.chip.ChipGroup
import uniffi.fire_uniffi_topics.TopicDetailState
import uniffi.fire_uniffi_topics.TopicPostState
import uniffi.fire_uniffi_topics.TopicResponseRowState

data class PostRow(
    val post: TopicPostState,
    val depth: Int = 0,
    val parentPostNumber: UInt? = null,
    val hasChildren: Boolean = false,
)

class PostListAdapter(
    private val onPostClick: (TopicPostState) -> Unit,
) : ListAdapter<PostRow, PostViewHolder>(PostDiffCallback) {

    override fun onCreateViewHolder(parent: ViewGroup, viewType: Int): PostViewHolder {
        return PostViewHolder.create(parent)
    }

    override fun onBindViewHolder(holder: PostViewHolder, position: Int) {
        holder.bind(getItem(position), onPostClick)
    }

    private object PostDiffCallback : DiffUtil.ItemCallback<PostRow>() {
        override fun areItemsTheSame(oldItem: PostRow, newItem: PostRow): Boolean =
            oldItem.post.id == newItem.post.id

        override fun areContentsTheSame(oldItem: PostRow, newItem: PostRow): Boolean =
            oldItem == newItem
    }
}

class HeaderAdapter : RecyclerView.Adapter<HeaderAdapter.HeaderViewHolder>() {

    var detail: TopicDetailState? = null
        set(value) {
            field = value
            notifyDataSetChanged()
        }

    override fun onCreateViewHolder(parent: ViewGroup, viewType: Int): HeaderViewHolder {
        val view = LayoutInflater.from(parent.context)
            .inflate(R.layout.item_topic_header, parent, false)
        return HeaderViewHolder(view)
    }

    override fun onBindViewHolder(holder: HeaderViewHolder, position: Int) {
        detail?.let { holder.bind(it) }
    }

    override fun getItemCount(): Int = if (detail != null) 1 else 0

    class HeaderViewHolder(itemView: View) : RecyclerView.ViewHolder(itemView) {
        private val titleText: android.widget.TextView = itemView.findViewById(R.id.topic_title)
        private val chips: ChipGroup = itemView.findViewById(R.id.topic_chips)
        private val statReplies: android.widget.TextView = itemView.findViewById(R.id.stat_replies)
        private val statViews: android.widget.TextView = itemView.findViewById(R.id.stat_views)
        private val statLikes: android.widget.TextView = itemView.findViewById(R.id.stat_likes)

        fun bind(detail: TopicDetailState) {
            titleText.text = detail.title.trim()
            val tagNames = TopicPresentation.tagNames(detail.tags)
            if (tagNames.isNotEmpty() || detail.categoryId != null) {
                chips.visibility = View.VISIBLE
                chips.removeAllViews()
                detail.categoryId?.let { cid ->
                    val chip = Chip(itemView.context).apply {
                        text = "分类 $cid"
                        isClickable = false
                        isCheckable = false
                        setChipBackgroundColorResource(R.color.fire_accent_soft)
                        setTextColor(itemView.context.getColor(R.color.fire_accent))
                    }
                    chips.addView(chip)
                }
                for (tagName in tagNames) {
                    val chip = Chip(itemView.context).apply {
                        text = "#$tagName"
                        isClickable = false
                        isCheckable = false
                        setChipBackgroundColorResource(R.color.fire_accent_soft)
                        setTextColor(itemView.context.getColor(R.color.fire_accent))
                    }
                    chips.addView(chip)
                }
            } else {
                chips.visibility = View.GONE
            }
            statReplies.text = "${maxOf(detail.postsCount, 1u) - 1u}"
            statViews.text = "${detail.views}"
            statLikes.text = "${detail.likeCount}"
        }
    }
}

class LoadingFooterAdapter : RecyclerView.Adapter<LoadingFooterAdapter.FooterViewHolder>() {

    var isLoading: Boolean = false
        set(value) {
            val changed = field != value
            field = value
            if (changed) notifyDataSetChanged()
        }

    override fun onCreateViewHolder(parent: ViewGroup, viewType: Int): FooterViewHolder {
        val view = LayoutInflater.from(parent.context)
            .inflate(R.layout.item_loading_footer, parent, false)
        return FooterViewHolder(view)
    }

    override fun onBindViewHolder(holder: FooterViewHolder, position: Int) {}

    override fun getItemCount(): Int = if (isLoading) 1 else 0

    class FooterViewHolder(itemView: View) : RecyclerView.ViewHolder(itemView)
}
