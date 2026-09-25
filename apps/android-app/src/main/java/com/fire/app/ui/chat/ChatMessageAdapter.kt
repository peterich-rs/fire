package com.fire.app.ui.chat

import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.TextView
import androidx.recyclerview.widget.RecyclerView
import com.fire.app.R
import com.fire.app.core.image.FireAvatarUrls
import com.fire.app.core.image.FireImageLoader
import com.fire.app.richtext.FireRenderPresentation
import com.fire.app.richtext.FireRichTextBlock
import com.fire.app.richtext.FireRichTextView
import com.fire.app.richtext.FireSpannableBuilder
import uniffi.fire_uniffi_chat.ChatMessageState

class ChatMessageAdapter(
    private val onClick: (ChatMessageState) -> Unit,
    private val onThreadClick: (ChatMessageState) -> Unit,
    private val onAuthorClick: (String) -> Unit,
    private var baseUrl: String = "https://linux.do",
) : RecyclerView.Adapter<ChatMessageAdapter.Holder>() {
    private var items: List<ChatMessageState> = emptyList()

    fun submit(messages: List<ChatMessageState>, baseUrl: String = this.baseUrl) {
        this.baseUrl = baseUrl
        items = messages
        notifyDataSetChanged()
    }

    override fun onCreateViewHolder(parent: ViewGroup, viewType: Int): Holder {
        val view = LayoutInflater.from(parent.context)
            .inflate(R.layout.item_chat_message, parent, false)
        return Holder(view, onClick, onThreadClick, onAuthorClick, baseUrl)
    }

    override fun onBindViewHolder(holder: Holder, position: Int) {
        val previous = items.getOrNull(position - 1)
        holder.bind(items[position], previous)
    }

    override fun getItemCount(): Int = items.size

    class Holder(
        itemView: View,
        private val onClick: (ChatMessageState) -> Unit,
        private val onThreadClick: (ChatMessageState) -> Unit,
        private val onAuthorClick: (String) -> Unit,
        private val baseUrl: String,
    ) : RecyclerView.ViewHolder(itemView) {
        private val avatarContainer: View = itemView.findViewById(R.id.message_avatar_container)
        private val avatar: ImageView = itemView.findViewById(R.id.message_avatar)
        private val monogram: TextView = itemView.findViewById(R.id.message_avatar_monogram)
        private val header: View = itemView.findViewById(R.id.message_header)
        private val author: TextView = itemView.findViewById(R.id.message_author)
        private val time: TextView = itemView.findViewById(R.id.message_time)
        private val bodyContainer: LinearLayout = itemView.findViewById(R.id.message_body_container)
        private val meta: TextView = itemView.findViewById(R.id.message_meta)
        private val thread: TextView = itemView.findViewById(R.id.message_thread)

        fun bind(message: ChatMessageState, previous: ChatMessageState?) {
            val username = message.user?.username ?: "user"
            val grouped = shouldGroup(previous, message)
            author.text = username
            time.text = formatTime(message.createdAt)
            bindBody(message)
            bindMeta(message)
            bindThread(message)
            bindAvatar(username, message.user?.avatarTemplate, grouped)

            itemView.setPadding(
                itemView.paddingLeft,
                if (grouped) dp(2) else dp(8),
                itemView.paddingRight,
                itemView.paddingBottom,
            )
            itemView.setOnClickListener { onClick(message) }
            avatar.setOnClickListener { onAuthorClick(username) }
            author.setOnClickListener { onAuthorClick(username) }
        }

        private fun bindBody(message: ChatMessageState) {
            bodyContainer.removeAllViews()
            val contentId = "chat:${message.id}:${message.presentation?.checksum() ?: 0uL}"
            if (message.isDeleted) {
                bodyContainer.addView(
                    TextView(itemView.context).apply {
                        text = itemView.context.getString(R.string.chat_message_deleted)
                        setTextColor(itemView.context.getColor(R.color.fire_text_secondary))
                        setTypeface(typeface, android.graphics.Typeface.ITALIC)
                        textSize = 15f
                    },
                )
                return
            }

            val presentation = message.presentation
            if (presentation != null) {
                val blocks = FireRenderPresentation.blocks(presentation)
                if (blocks.isNotEmpty()) {
                    blocks.forEachIndexed { index, block ->
                        when (block) {
                            is FireRichTextBlock.Text -> {
                                val spannable = FireSpannableBuilder.build(
                                    nodes = block.nodes,
                                    context = itemView.context,
                                    onLinkClicked = null,
                                )
                                if (spannable.isNotBlank()) {
                                    val textView = FireRichTextView(itemView.context).apply {
                                        setTextAppearance(androidx.appcompat.R.style.TextAppearance_AppCompat_Body1)
                                        setTextColor(itemView.context.getColor(R.color.fire_text_primary))
                                        setTextIsSelectable(false)
                                        setContent("$contentId:text:$index", spannable)
                                    }
                                    bodyContainer.addView(textView)
                                }
                            }
                            is FireRichTextBlock.Image -> {
                                val imageView = ImageView(itemView.context).apply {
                                    adjustViewBounds = true
                                    maxHeight = dp(220)
                                    scaleType = ImageView.ScaleType.CENTER_CROP
                                    layoutParams = LinearLayout.LayoutParams(
                                        LinearLayout.LayoutParams.MATCH_PARENT,
                                        LinearLayout.LayoutParams.WRAP_CONTENT,
                                    ).apply {
                                        if (index > 0) topMargin = dp(6)
                                    }
                                }
                                FireImageLoader.load(block.image.url, imageView)
                                bodyContainer.addView(imageView)
                            }
                        }
                    }
                    if (bodyContainer.childCount > 0) return
                }
                val plain = presentation.plainText().trim()
                if (plain.isNotEmpty()) {
                    bodyContainer.addView(plainTextView(plain))
                    return
                }
            }

            val plain = when {
                message.message.isNotBlank() -> message.message
                message.uploads.isNotEmpty() -> itemView.context.getString(R.string.chat_image_attachment)
                else -> message.previewText
            }
            bodyContainer.addView(plainTextView(plain))
        }

        private fun plainTextView(textValue: String): TextView {
            return TextView(itemView.context).apply {
                text = textValue
                setTextColor(itemView.context.getColor(R.color.fire_text_primary))
                textSize = 15f
            }
        }

        private fun bindMeta(message: ChatMessageState) {
            val parts = buildList {
                if (message.edited) add(itemView.context.getString(R.string.chat_edited))
                if (message.pinned) add(itemView.context.getString(R.string.chat_pinned_message))
                if (message.reactions.isNotEmpty()) {
                    add(message.reactions.joinToString("  ") { ":${it.emoji}: ${it.count}" })
                }
            }
            if (parts.isEmpty()) {
                meta.visibility = View.GONE
            } else {
                meta.visibility = View.VISIBLE
                meta.text = parts.joinToString(" · ")
            }
        }

        private fun bindThread(message: ChatMessageState) {
            val replyCount = message.thread?.replyCount ?: 0u
            if (replyCount > 0u) {
                thread.visibility = View.VISIBLE
                thread.text = itemView.context.getString(R.string.chat_thread_replies, replyCount.toInt())
                thread.setOnClickListener { onThreadClick(message) }
            } else {
                thread.visibility = View.GONE
                thread.setOnClickListener(null)
            }
        }

        private fun bindAvatar(username: String, avatarTemplate: String?, grouped: Boolean) {
            if (grouped) {
                header.visibility = View.GONE
                avatarContainer.visibility = View.INVISIBLE
                return
            }
            header.visibility = View.VISIBLE
            avatarContainer.visibility = View.VISIBLE
            monogram.text = username.take(1).uppercase()
            monogram.visibility = View.VISIBLE
            avatar.setImageDrawable(null)
            FireAvatarUrls.build(avatarTemplate, baseUrl = baseUrl)?.let { url ->
                FireImageLoader.load(url, avatar)
            }
        }

        private fun dp(value: Int): Int =
            (value * itemView.resources.displayMetrics.density).toInt()

        private fun formatTime(value: String?): String {
            if (value.isNullOrBlank()) return ""
            return value
                .removeSuffix("Z")
                .substringAfter('T')
                .take(5)
                .ifBlank { value.takeLast(5) }
        }

        private fun shouldGroup(previous: ChatMessageState?, current: ChatMessageState): Boolean {
            if (previous == null) return false
            if (previous.user?.id == null || previous.user?.id != current.user?.id) return false
            val prev = previous.createdAt ?: return false
            val curr = current.createdAt ?: return false
            return prev.take(16) == curr.take(16) || prev.take(13) == curr.take(13)
        }
    }
}
