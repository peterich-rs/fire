package com.fire.app.ui.home

import android.graphics.Color
import android.graphics.drawable.GradientDrawable
import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.TextView
import androidx.recyclerview.widget.RecyclerView
import com.fire.app.R
import com.fire.app.TopicPresentation
import com.fire.app.core.ext.dp
import com.fire.app.core.image.FireAvatarUrls
import com.fire.app.core.image.FireImageLoader
import com.fire.app.displayName
import uniffi.fire_uniffi_session.TopicCategoryState
import uniffi.fire_uniffi_types.TopicRowState

class TopicRowViewHolder(itemView: View) : RecyclerView.ViewHolder(itemView) {

    private val avatar: ImageView = itemView.findViewById(R.id.topic_avatar)
    private val titleText: TextView = itemView.findViewById(R.id.topic_title)
    private val chipRow: LinearLayout = itemView.findViewById(R.id.topic_chip_row)
    private val bylineText: TextView = itemView.findViewById(R.id.topic_byline)
    private val repliesText: TextView = itemView.findViewById(R.id.topic_metric_replies)
    private val viewsText: TextView = itemView.findViewById(R.id.topic_metric_views)
    private val likesText: TextView = itemView.findViewById(R.id.topic_metric_likes)

    fun bind(
        row: TopicRowState,
        category: TopicCategoryState?,
        onClick: (TopicRowState) -> Unit,
        onTagClick: (String) -> Unit,
        onLongClick: ((TopicRowState) -> Boolean)? = null,
    ) {
        val topic = row.topic
        titleText.text = topic.title
        val avatarUrl = FireAvatarUrls.build(row.originalPosterAvatarTemplate)
        if (avatarUrl != null) {
            FireImageLoader.load(avatarUrl, avatar)
        } else {
            avatar.setImageDrawable(null)
        }

        bindChips(row, category, onTagClick)

        val username = row.originalPosterUsername ?: row.lastPosterUsername
        val time = TopicPresentation.formatTimestamp(row.activityTimestampUnixMs ?: row.createdTimestampUnixMs)
        bylineText.text = listOfNotNull(username, time).joinToString(" · ")

        repliesText.text = "${topic.postsCount} 帖"
        viewsText.text = "${topic.views} 浏览"
        likesText.text = "${topic.likeCount} 赞"
        applyMetricWeight(repliesText, topic.postsCount.toLong())
        applyMetricWeight(viewsText, topic.views.toLong())
        applyMetricWeight(likesText, topic.likeCount.toLong())

        itemView.setOnClickListener { onClick(row) }
        itemView.setOnLongClickListener {
            onLongClick?.invoke(row) ?: false
        }
    }

    private fun bindChips(
        row: TopicRowState,
        category: TopicCategoryState?,
        onTagClick: (String) -> Unit,
    ) {
        chipRow.removeAllViews()
        val context = itemView.context
        var count = 0
        if (category != null) {
            chipRow.addView(chipView(category.displayName(), parseColor(category.colorHex)))
            count += 1
        }
        row.tagNames.take(3).forEach { tag ->
            val chip = chipView("#$tag", context.getColor(R.color.fire_text_secondary))
            chip.setOnClickListener { onTagClick(tag) }
            chipRow.addView(chip)
            count += 1
        }
        if (row.isPinned) {
            chipRow.addView(chipView("置顶", context.getColor(R.color.fire_warning)))
            count += 1
        }
        if (row.hasAcceptedAnswer) {
            chipRow.addView(chipView("已解决", context.getColor(R.color.fire_success)))
            count += 1
        }
        if (row.hasUnreadPosts) {
            chipRow.addView(chipView("未读", context.getColor(R.color.fire_accent)))
            count += 1
        }
        chipRow.visibility = if (count > 0) View.VISIBLE else View.GONE
    }

    private fun chipView(text: String, color: Int): TextView {
        val context = itemView.context
        return TextView(context).apply {
            this.text = text
            setTextColor(color)
            textSize = 11f
            setPadding(context.dp(8), context.dp(3), context.dp(8), context.dp(3))
            background = GradientDrawable().apply {
                cornerRadius = context.dp(8).toFloat()
                setColor(Color.argb(24, Color.red(color), Color.green(color), Color.blue(color)))
            }
            val params = LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.WRAP_CONTENT,
                ViewGroup.LayoutParams.WRAP_CONTENT,
            )
            params.marginEnd = context.dp(6)
            layoutParams = params
        }
    }

    private fun applyMetricWeight(view: TextView, value: Long) {
        val context = view.context
        view.setTextColor(
            when {
                value >= 1000 -> context.getColor(R.color.fire_accent)
                value >= 100 -> context.getColor(R.color.fire_text_secondary)
                else -> context.getColor(R.color.fire_text_tertiary)
            },
        )
    }

    private fun parseColor(hex: String?): Int {
        val raw = hex?.trim()?.removePrefix("#").orEmpty()
        return runCatching { Color.parseColor(if (raw.length == 6) "#$raw" else hex) }
            .getOrElse { itemView.context.getColor(R.color.fire_accent) }
    }

    companion object {
        fun create(parent: ViewGroup): TopicRowViewHolder {
            val view = LayoutInflater.from(parent.context)
                .inflate(R.layout.item_topic_row, parent, false)
            return TopicRowViewHolder(view)
        }
    }
}
