package com.fire.app.ui.home

import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import android.widget.TextView
import androidx.recyclerview.widget.RecyclerView
import com.fire.app.R
import com.fire.app.TopicPresentation
import uniffi.fire_uniffi_types.TopicRowState

class TopicRowViewHolder(itemView: View) : RecyclerView.ViewHolder(itemView) {

    private val titleText: TextView = itemView.findViewById(R.id.topic_title)
    private val metaText: TextView = itemView.findViewById(R.id.topic_meta)
    private val excerptText: TextView = itemView.findViewById(R.id.topic_excerpt)
    private val categoryChip: TextView = itemView.findViewById(R.id.topic_category)
    private val tagText: TextView = itemView.findViewById(R.id.topic_tags)

    fun bind(row: TopicRowState, onClick: (TopicRowState) -> Unit) {
        val topic = row.topic
        titleText.text = topic.title

        val meta = buildList {
            add("${topic.postsCount} 帖")
            add("${topic.views} 浏览")
            add("${topic.likeCount} 赞")
            row.lastPosterUsername?.let { add(it) }
            TopicPresentation.formatTimestamp(row.activityTimestampUnixMs ?: row.createdTimestampUnixMs)?.let { add(it) }
        }.joinToString(" · ")
        metaText.text = meta

        val excerpt = row.excerptText?.trim()?.ifBlank { null }
        excerptText.visibility = if (excerpt != null) View.VISIBLE else View.GONE
        excerptText.text = excerpt

        val tags = row.tagNames
        tagText.visibility = if (tags.isEmpty()) View.GONE else View.VISIBLE
        tagText.text = tags.joinToString(" ") { "#$it" }

        itemView.setOnClickListener { onClick(row) }
    }

    companion object {
        fun create(parent: ViewGroup): TopicRowViewHolder {
            val view = LayoutInflater.from(parent.context)
                .inflate(R.layout.item_topic_row, parent, false)
            return TopicRowViewHolder(view)
        }
    }
}
