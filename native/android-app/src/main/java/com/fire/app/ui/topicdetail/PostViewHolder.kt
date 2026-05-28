package com.fire.app.ui.topicdetail

import android.text.SpannableString
import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import android.widget.ImageView
import android.widget.TextView
import androidx.recyclerview.widget.RecyclerView
import coil.ImageLoader
import coil.request.ImageRequest
import com.fire.app.R
import com.fire.app.TopicPresentation
import com.fire.app.richtext.FireRichTextParser
import com.fire.app.richtext.FireRichTextView
import com.fire.app.richtext.FireSpannableBuilder
import uniffi.fire_uniffi_topics.TopicPostState

class PostViewHolder(itemView: View) : RecyclerView.ViewHolder(itemView) {

    private val avatar: ImageView = itemView.findViewById(R.id.post_avatar)
    private val usernameText: TextView = itemView.findViewById(R.id.post_username)
    private val metaText: TextView = itemView.findViewById(R.id.post_meta)
    private val floorText: TextView = itemView.findViewById(R.id.post_floor)
    private val replyContextText: TextView = itemView.findViewById(R.id.post_reply_context)
    private val bodyView: FireRichTextView = itemView.findViewById(R.id.post_body)
    private val likeAction: TextView = itemView.findViewById(R.id.action_like)
    private val replyAction: TextView = itemView.findViewById(R.id.action_reply)
    private val reactionsAction: TextView = itemView.findViewById(R.id.action_reactions)

    fun bind(
        row: PostRow,
        onClick: (TopicPostState) -> Unit,
    ) {
        val post = row.post

        // Thread depth indent
        val depthIndent = (row.depth * 24).coerceAtMost(72)
        (itemView.layoutParams as? RecyclerView.LayoutParams)?.let {
            it.marginStart = depthIndent
        }

        usernameText.text = post.name?.ifBlank { null } ?: post.username

        val meta = buildList {
            post.createdAt?.let { TopicPresentation.formatTimestamp(it)?.let { ts -> add(ts) } }
        }.joinToString(" · ")
        metaText.text = meta

        floorText.text = "#${post.postNumber}"

        // Reply context
        val replyToNumber = post.replyToPostNumber
        val parentPostNumber = row.parentPostNumber
        val effectiveReplyTarget = parentPostNumber ?: replyToNumber
        if (effectiveReplyTarget != null && effectiveReplyTarget > 0u) {
            val replyUsername = post.replyToUser?.username?.trim()?.ifBlank { null }
            replyContextText.visibility = View.VISIBLE
            replyContextText.text = if (replyUsername != null && parentPostNumber == null) {
                "回复 @$replyUsername"
            } else {
                "回复 #$effectiveReplyTarget"
            }
        } else {
            replyContextText.visibility = View.GONE
        }

        // Rich text body
        val contentId = post.id.toString()
        if (bodyView.renderedContentId != contentId) {
            val content = try {
                FireRichTextParser.parse(post.cooked, "https://linux.do")
            } catch (_: Exception) {
                null
            }

            if (content != null) {
                val spannable = FireSpannableBuilder.build(content.nodes, bodyView.context)
                bodyView.setContent(contentId, spannable)
            } else {
                bodyView.setContent(contentId, SpannableString(post.cooked))
            }
        }

        // Avatar
        val avatarTemplate = post.avatarTemplate
        if (!avatarTemplate.isNullOrBlank()) {
            val baseUrl = "https://linux.do"
            val size = 72
            val url = buildAvatarUrl(baseUrl, avatarTemplate, size)
            val request = ImageRequest.Builder(avatar.context)
                .data(url)
                .crossfade(true)
                .target(avatar)
                .build()
            ImageLoader.Builder(avatar.context).build().enqueue(request)
        }

        // Actions
        likeAction.text = buildActionText("❤", post.likeCount)
        replyAction.text = buildActionText("💬", post.replyCount)
        if (post.reactions.isNotEmpty()) {
            reactionsAction.visibility = View.VISIBLE
            val reactionSummary = post.reactions.joinToString(" ") { r ->
                "${r.id} ${r.count}"
            }
            reactionsAction.text = reactionSummary
        } else {
            reactionsAction.visibility = View.GONE
        }

        itemView.setOnClickListener { onClick(post) }
    }

    private fun buildAvatarUrl(baseUrl: String, template: String, size: Int): String {
        if (template.startsWith("http")) return template.replace("{size}", size.toString())
        return "${baseUrl.trimEnd('/')}/${template.trimStart('/').replace("{size}", size.toString())}"
    }

    private fun buildActionText(emoji: String, count: UInt): String {
        return if (count > 0u) "$emoji $count" else emoji
    }

    companion object {
        fun create(parent: ViewGroup): PostViewHolder {
            val view = LayoutInflater.from(parent.context)
                .inflate(R.layout.item_post, parent, false)
            return PostViewHolder(view)
        }
    }
}
