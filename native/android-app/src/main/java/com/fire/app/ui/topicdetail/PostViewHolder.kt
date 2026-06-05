package com.fire.app.ui.topicdetail

import android.text.SpannableString
import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import android.widget.CheckBox
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.TextView
import android.widget.Toast
import androidx.core.text.HtmlCompat
import androidx.recyclerview.widget.RecyclerView
import com.fire.app.R
import com.fire.app.TopicPresentation
import com.fire.app.core.image.FireImageLoader
import com.fire.app.richtext.FireCookedImage
import com.fire.app.richtext.FireRichTextContent
import com.fire.app.richtext.FireRichTextParser
import com.fire.app.richtext.FireRichTextView
import com.fire.app.richtext.FireSpannableBuilder
import uniffi.fire_uniffi_topics.PollState
import uniffi.fire_uniffi_topics.TopicPostState

class PostViewHolder(itemView: View) : RecyclerView.ViewHolder(itemView) {

    private val avatar: ImageView = itemView.findViewById(R.id.post_avatar)
    private val usernameText: TextView = itemView.findViewById(R.id.post_username)
    private val metaText: TextView = itemView.findViewById(R.id.post_meta)
    private val floorText: TextView = itemView.findViewById(R.id.post_floor)
    private val replyContextText: TextView = itemView.findViewById(R.id.post_reply_context)
    private val bodyView: FireRichTextView = itemView.findViewById(R.id.post_body)
    private val imageContainer: LinearLayout = itemView.findViewById(R.id.post_image_container)
    private val pollContainer: LinearLayout = itemView.findViewById(R.id.post_poll_container)
    private val likeAction: TextView = itemView.findViewById(R.id.action_like)
    private val reactAction: TextView = itemView.findViewById(R.id.action_react)
    private val replyAction: TextView = itemView.findViewById(R.id.action_reply)
    private val bookmarkAction: TextView = itemView.findViewById(R.id.action_bookmark)
    private val reactionsAction: TextView = itemView.findViewById(R.id.action_reactions)
    private val editAction: TextView = itemView.findViewById(R.id.action_edit)
    private val deleteRecoverAction: TextView = itemView.findViewById(R.id.action_delete_recover)
    private val flagAction: TextView = itemView.findViewById(R.id.action_flag)

    fun bind(
        row: PostRow,
        callbacks: PostRowCallbacks,
    ) {
        val post = row.post
        val context = itemView.context

        // Thread depth indent
        val depthIndent = (row.depth * 24).coerceAtMost(72)
        (itemView.layoutParams as? RecyclerView.LayoutParams)?.let {
            it.marginStart = depthIndent
        }

        usernameText.text = post.name?.ifBlank { null } ?: post.username
        usernameText.setOnClickListener { callbacks.onAuthorClick(post.username) }
        avatar.setOnClickListener { callbacks.onAuthorClick(post.username) }

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
            replyContextText.setOnClickListener { callbacks.onReplyContextClick(post) }
        } else {
            replyContextText.visibility = View.GONE
            replyContextText.setOnClickListener(null)
        }

        // Rich text body
        val contentId = "${post.id}:${post.cooked.hashCode()}"
        val content = if (bodyView.getTag(R.id.tag_post_content_id) == contentId) {
            bodyView.getTag(R.id.tag_post_content) as? FireRichTextContent
        } else {
            val parsed = try {
                FireRichTextParser.parse(post, "https://linux.do")
            } catch (_: Exception) {
                null
            }

            if (parsed != null) {
                val spannable = FireSpannableBuilder.build(parsed.nodes, bodyView.context)
                bodyView.setContent(contentId, spannable)
            } else {
                bodyView.setContent(contentId, SpannableString(post.cooked))
            }
            bodyView.setTag(R.id.tag_post_content_id, contentId)
            bodyView.setTag(R.id.tag_post_content, parsed)
            parsed
        }
        bindImages(content?.imageAttachments.orEmpty(), callbacks)

        // Avatar
        val avatarTemplate = post.avatarTemplate
        if (!avatarTemplate.isNullOrBlank()) {
            val baseUrl = "https://linux.do"
            val size = 72
            val url = buildAvatarUrl(baseUrl, avatarTemplate, size)
            FireImageLoader.load(url, avatar)
        }

        bindPolls(post, callbacks)

        // Actions
        val likedByCurrentUser = post.currentUserReaction?.id == HEART_REACTION_ID
        likeAction.text = context.getString(
            if (likedByCurrentUser) {
                R.string.topic_detail_unlike_post
            } else {
                R.string.topic_detail_like_post
            },
            post.likeCount.toString(),
        )
        likeAction.setTextColor(
            context.getColor(
                if (likedByCurrentUser) R.color.fire_accent else R.color.fire_text_secondary,
            ),
        )
        likeAction.setOnClickListener { callbacks.onHeartClick(post) }

        val currentReactionId = post.currentUserReaction?.id?.trim()
        val currentCustomReactionId = currentReactionId
            ?.takeIf { it.isNotEmpty() && !it.equals(ReactionPresentation.HEART_ID, ignoreCase = true) }
        val hasCustomReactionOptions = ReactionPresentation
            .customOptions(callbacks.reactionIds(), currentCustomReactionId)
            .isNotEmpty()
        val canUndoCurrentReaction = post.currentUserReaction?.canUndo ?: true
        if (hasCustomReactionOptions) {
            reactAction.visibility = View.VISIBLE
            reactAction.isEnabled = canUndoCurrentReaction
            reactAction.text = if (currentCustomReactionId != null) {
                val option = ReactionPresentation.optionFor(currentCustomReactionId)
                context.getString(
                    R.string.topic_detail_reaction_choice_selected,
                    "${option.symbol} ${option.label}",
                )
            } else {
                context.getString(R.string.topic_detail_react_post)
            }
            reactAction.setTextColor(
                context.getColor(
                    if (currentCustomReactionId != null) R.color.fire_accent else R.color.fire_text_secondary,
                ),
            )
            reactAction.setOnClickListener { callbacks.onReactClick(post) }
        } else {
            reactAction.visibility = View.GONE
            reactAction.setOnClickListener(null)
        }

        replyAction.text = if (post.replyCount > 0u) {
            "${context.getString(R.string.topic_detail_reply_post)} (${post.replyCount})"
        } else {
            context.getString(R.string.topic_detail_reply_post)
        }
        replyAction.setOnClickListener { callbacks.onReplyClick(post) }

        bookmarkAction.text = context.getString(
            if (post.bookmarked) {
                R.string.topic_detail_bookmark_post_active
            } else {
                R.string.topic_detail_bookmark_post
            },
        )
        bookmarkAction.setTextColor(
            context.getColor(
                if (post.bookmarked) R.color.fire_accent else R.color.fire_text_secondary,
            ),
        )
        bookmarkAction.setOnClickListener { callbacks.onBookmarkClick(post) }

        if (post.reactions.isNotEmpty()) {
            reactionsAction.visibility = View.VISIBLE
            val reactionSummary = post.reactions.joinToString(" ") { r ->
                "${ReactionPresentation.optionFor(r.id).symbol} ${r.count}"
            }
            reactionsAction.text = reactionSummary
            reactionsAction.setOnClickListener { callbacks.onReactionsClick(post) }
        } else {
            reactionsAction.visibility = View.GONE
            reactionsAction.setOnClickListener(null)
        }

        if (post.canEdit) {
            editAction.visibility = View.VISIBLE
            editAction.setOnClickListener { callbacks.onEditPostClick(post) }
        } else {
            editAction.visibility = View.GONE
            editAction.setOnClickListener(null)
        }

        when {
            post.canRecover -> {
                deleteRecoverAction.visibility = View.VISIBLE
                deleteRecoverAction.text = context.getString(R.string.topic_detail_recover_post)
                deleteRecoverAction.setOnClickListener { callbacks.onRecoverPostClick(post) }
            }
            post.canDelete -> {
                deleteRecoverAction.visibility = View.VISIBLE
                deleteRecoverAction.text = context.getString(R.string.topic_detail_delete_post)
                deleteRecoverAction.setOnClickListener { callbacks.onDeletePostClick(post) }
            }
            else -> {
                deleteRecoverAction.visibility = View.GONE
                deleteRecoverAction.setOnClickListener(null)
            }
        }

        if (!post.hidden) {
            flagAction.visibility = View.VISIBLE
            flagAction.setOnClickListener { callbacks.onFlagPostClick(post) }
        } else {
            flagAction.visibility = View.GONE
            flagAction.setOnClickListener(null)
        }

        itemView.setOnClickListener { callbacks.onPostClick(post) }
    }

    private fun bindImages(
        images: List<FireCookedImage>,
        callbacks: PostRowCallbacks,
    ) {
        imageContainer.removeAllViews()
        if (images.isEmpty()) {
            imageContainer.visibility = View.GONE
            return
        }

        imageContainer.visibility = View.VISIBLE
        images.forEachIndexed { index, image ->
            val imageView = ImageView(itemView.context).apply {
                contentDescription = image.altText ?: itemView.context.getString(R.string.topic_detail_image_attachment)
                scaleType = ImageView.ScaleType.CENTER_CROP
                adjustViewBounds = false
                setBackgroundColor(itemView.context.getColor(R.color.fire_background_surface))
                layoutParams = LinearLayout.LayoutParams(
                    LinearLayout.LayoutParams.MATCH_PARENT,
                    attachmentImageHeight(image),
                ).apply {
                    if (index > 0) topMargin = 8
                }
                setOnClickListener { callbacks.onImageClick(image) }
            }
            FireImageLoader.load(image.url, imageView)
            imageContainer.addView(imageView)
        }
    }

    private fun attachmentImageHeight(image: FireCookedImage): Int {
        val density = itemView.resources.displayMetrics.density
        val width = image.width ?: 0f
        val height = image.height ?: 0f
        val dp = when {
            width > 0f && height > width * 1.2f -> 260
            width > 0f && height > 0f && width > height * 1.4f -> 170
            else -> 220
        }
        return (dp * density).toInt()
    }

    private fun bindPolls(post: TopicPostState, callbacks: PostRowCallbacks) {
        pollContainer.removeAllViews()
        if (post.polls.isEmpty()) {
            pollContainer.visibility = View.GONE
            return
        }

        pollContainer.visibility = View.VISIBLE
        post.polls.forEachIndexed { index, poll ->
            if (index > 0) {
                pollContainer.addView(sectionDivider())
            }
            pollContainer.addView(pollTitleView(poll))
            pollContainer.addView(pollOptionsView(post, poll, callbacks))
        }
    }

    private fun pollTitleView(poll: PollState): TextView {
        val context = itemView.context
        val labels = buildList {
            add(context.getString(R.string.topic_detail_poll_title))
            if (poll.kind.equals("multiple", ignoreCase = true)) {
                add(context.getString(R.string.topic_detail_poll_multiple))
            }
            if (poll.status.equals("closed", ignoreCase = true)) {
                add(context.getString(R.string.topic_detail_poll_closed))
            }
            add(context.getString(R.string.topic_detail_poll_voters_count, poll.voters.toString()))
        }
        return TextView(context).apply {
            text = labels.joinToString(" · ")
            setTextAppearance(androidx.appcompat.R.style.TextAppearance_AppCompat_Caption)
            setTextColor(context.getColor(R.color.fire_text_secondary))
        }
    }

    private fun pollOptionsView(
        post: TopicPostState,
        poll: PollState,
        callbacks: PostRowCallbacks,
    ): LinearLayout {
        val context = itemView.context
        val selected = poll.userVotes.toMutableSet()
        val isMultiple = poll.kind.equals("multiple", ignoreCase = true)
        val isClosed = poll.status.equals("closed", ignoreCase = true)
        val group = LinearLayout(context).apply {
            orientation = LinearLayout.VERTICAL
            layoutParams = LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT,
                LinearLayout.LayoutParams.WRAP_CONTENT,
            )
        }
        val optionChecks = mutableListOf<CheckBox>()

        for (option in poll.options) {
            val checkBox = CheckBox(context).apply {
                text = context.getString(
                    R.string.topic_detail_poll_option_with_votes,
                    optionLabel(option.html),
                    option.votes.toString(),
                )
                isChecked = selected.contains(option.id)
                isEnabled = !isClosed
                setTextColor(context.getColor(R.color.fire_text_primary))
                setOnCheckedChangeListener { _, checked ->
                    if (checked) {
                        if (!isMultiple) {
                            selected.clear()
                            optionChecks.filter { it !== this }.forEach { it.isChecked = false }
                        }
                        selected.add(option.id)
                    } else {
                        selected.remove(option.id)
                    }
                }
            }
            optionChecks.add(checkBox)
            group.addView(checkBox)
        }

        if (!isClosed) {
            group.addView(pollActionsView(post, poll, selected, callbacks))
        }
        return group
    }

    private fun pollActionsView(
        post: TopicPostState,
        poll: PollState,
        selected: MutableSet<String>,
        callbacks: PostRowCallbacks,
    ): LinearLayout {
        val context = itemView.context
        return LinearLayout(context).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = android.view.Gravity.CENTER_VERTICAL
            val submit = TextView(context).apply {
                text = context.getString(R.string.topic_detail_poll_submit)
                setTextAppearance(androidx.appcompat.R.style.TextAppearance_AppCompat_Caption)
                setTextColor(context.getColor(R.color.fire_accent))
                setPadding(0, 8, 18, 8)
                setOnClickListener {
                    val selectedOptions = selected.toList()
                    if (selectedOptions.isEmpty()) {
                        Toast.makeText(
                            context,
                            R.string.topic_detail_poll_select_required,
                            Toast.LENGTH_SHORT,
                        ).show()
                    } else {
                        callbacks.onVotePoll(post, poll, selectedOptions)
                    }
                }
            }
            addView(submit)

            if (poll.userVotes.isNotEmpty()) {
                val unvote = TextView(context).apply {
                    text = context.getString(R.string.topic_detail_poll_unvote)
                    setTextAppearance(androidx.appcompat.R.style.TextAppearance_AppCompat_Caption)
                    setTextColor(context.getColor(R.color.fire_text_secondary))
                    setPadding(0, 8, 0, 8)
                    setOnClickListener {
                        callbacks.onUnvotePoll(post, poll)
                    }
                }
                addView(unvote)
            }
        }
    }

    private fun sectionDivider(): View {
        return View(itemView.context).apply {
            setBackgroundColor(itemView.context.getColor(R.color.fire_divider))
            layoutParams = LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT,
                1,
            ).apply {
                topMargin = 10
                bottomMargin = 10
            }
        }
    }

    private fun optionLabel(html: String): String {
        return HtmlCompat.fromHtml(html, HtmlCompat.FROM_HTML_MODE_LEGACY)
            .toString()
            .trim()
            .ifBlank { html }
    }

    private fun buildAvatarUrl(baseUrl: String, template: String, size: Int): String {
        if (template.startsWith("http")) return template.replace("{size}", size.toString())
        return "${baseUrl.trimEnd('/')}/${template.trimStart('/').replace("{size}", size.toString())}"
    }

    companion object {
        private const val HEART_REACTION_ID = "heart"

        fun create(parent: ViewGroup): PostViewHolder {
            val view = LayoutInflater.from(parent.context)
                .inflate(R.layout.item_post, parent, false)
            return PostViewHolder(view)
        }
    }
}
