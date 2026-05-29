package com.fire.app.ui.home

import android.graphics.Color
import android.text.SpannableString
import android.text.Spanned
import android.text.TextPaint
import android.text.method.LinkMovementMethod
import android.text.style.ClickableSpan
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

    fun bind(
        row: TopicRowState,
        onClick: (TopicRowState) -> Unit,
        onTagClick: (String) -> Unit,
    ) {
        val topic = row.topic
        titleText.text = topic.title
        categoryChip.visibility = View.GONE

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

        bindTags(row.tagNames, onTagClick)

        itemView.setOnClickListener { onClick(row) }
    }

    private fun bindTags(tags: List<String>, onTagClick: (String) -> Unit) {
        if (tags.isEmpty()) {
            tagText.visibility = View.GONE
            tagText.text = null
            tagText.movementMethod = null
            tagText.isClickable = false
            return
        }

        val labels = tags.map { tag -> "#$tag" }
        val text = labels.joinToString(" ")
        val spannable = SpannableString(text)
        var start = 0

        tags.forEachIndexed { index, tag ->
            val label = labels[index]
            val end = start + label.length
            spannable.setSpan(
                object : ClickableSpan() {
                    override fun onClick(widget: View) {
                        onTagClick(tag)
                    }

                    override fun updateDrawState(ds: TextPaint) {
                        ds.color = tagText.currentTextColor
                        ds.isUnderlineText = false
                    }
                },
                start,
                end,
                Spanned.SPAN_EXCLUSIVE_EXCLUSIVE,
            )
            start = end + 1
        }

        tagText.visibility = View.VISIBLE
        tagText.text = spannable
        tagText.movementMethod = LinkMovementMethod.getInstance()
        tagText.highlightColor = Color.TRANSPARENT
        tagText.isClickable = true
    }

    companion object {
        fun create(parent: ViewGroup): TopicRowViewHolder {
            val view = LayoutInflater.from(parent.context)
                .inflate(R.layout.item_topic_row, parent, false)
            return TopicRowViewHolder(view)
        }
    }
}
