package com.fire.app.ui.topicdetail

import android.animation.ValueAnimator
import android.graphics.drawable.GradientDrawable
import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import android.widget.FrameLayout
import android.widget.HorizontalScrollView
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.TextView
import androidx.recyclerview.widget.RecyclerView
import com.fire.app.R
import com.fire.app.TopicPresentation
import com.fire.app.core.image.FireAvatarUrls
import com.fire.app.core.image.FireImageLoader

class PostViewHolder(itemView: View) : RecyclerView.ViewHolder(itemView) {

    private val avatar: ImageView = itemView.findViewById(R.id.post_avatar)
    private val usernameText: TextView = itemView.findViewById(R.id.post_username)
    internal val authorChips: LinearLayout = itemView.findViewById(R.id.post_author_chips)
    private val authorMetadataText: TextView = itemView.findViewById(R.id.post_author_metadata)
    private val metaText: TextView = itemView.findViewById(R.id.post_meta)
    private val floorText: TextView = itemView.findViewById(R.id.post_floor)
    internal val replyContextText: TextView = itemView.findViewById(R.id.post_reply_context)
    internal val bodyFrame: FrameLayout = itemView.findViewById(R.id.post_body_frame)
    internal val bodyContainer: LinearLayout = itemView.findViewById(R.id.post_body_container)
    internal val pollContainer: LinearLayout = itemView.findViewById(R.id.post_poll_container)
    internal val boostContainer: LinearLayout = itemView.findViewById(R.id.post_boost_container)
    internal val boostBarrageContainer: FrameLayout = itemView.findViewById(R.id.post_boost_barrage_container)
    internal val actionsScroll: HorizontalScrollView = itemView.findViewById(R.id.post_actions_scroll)
    internal val moreRepliesAction: TextView = itemView.findViewById(R.id.action_more_replies)
    internal val likeAction: TextView = itemView.findViewById(R.id.action_like)
    private val reactAction: TextView = itemView.findViewById(R.id.action_react)
    private val replyAction: TextView = itemView.findViewById(R.id.action_reply)
    private val quoteAction: TextView = itemView.findViewById(R.id.action_quote)
    private val bookmarkAction: TextView = itemView.findViewById(R.id.action_bookmark)
    private val reactionsAction: TextView = itemView.findViewById(R.id.action_reactions)
    private val editAction: TextView = itemView.findViewById(R.id.action_edit)
    private val deleteRecoverAction: TextView = itemView.findViewById(R.id.action_delete_recover)
    private val flagAction: TextView = itemView.findViewById(R.id.action_flag)
    internal var boostBarrageStartRunnable: Runnable? = null
    internal val boostBarrageAnimators = mutableListOf<ValueAnimator>()
    internal var boostBarrageSignature: String? = null
    internal var boostBarrageExpectedCompletions = 0
    internal var boostBarrageCompletedCount = 0
    internal var bodyHasTextTarget: Boolean = false
    internal var boostAnimationsEnabled = true
    internal var isAttachedToWindow = false

    fun bind(
        row: PostRow,
        callbacks: PostRowCallbacks,
        isSearchHighlighted: Boolean = false,
    ) {
        val post = row.post
        val context = itemView.context
        applySearchHighlight(isSearchHighlighted)

        // Thread depth indent
        val depthIndent = (row.depth * 24).coerceAtMost(72)
        (itemView.layoutParams as? RecyclerView.LayoutParams)?.let {
            it.marginStart = depthIndent
        }
        applyContentWidthMode(row.usesTitleWidthBody)

        val normalizedUsername = post.username.trim().takeIf { it.isNotEmpty() }
        usernameText.isClickable = normalizedUsername != null
        usernameText.isFocusable = normalizedUsername != null
        avatar.isClickable = normalizedUsername != null
        avatar.isFocusable = normalizedUsername != null
        usernameText.setOnClickListener {
            normalizedUsername?.let(callbacks.onAuthorClick)
        }
        avatar.setOnClickListener {
            normalizedUsername?.let(callbacks.onAuthorClick)
        }
        usernameText.text = displayName(post)
        bindAuthorChips(primaryMetadataParts(post))

        val secondaryMetadata = secondaryMetadataParts(post)
        if (secondaryMetadata.isEmpty()) {
            authorMetadataText.visibility = View.GONE
            authorMetadataText.text = null
        } else {
            authorMetadataText.visibility = View.VISIBLE
            authorMetadataText.text = secondaryMetadata.joinToString(" · ")
        }

        val meta = buildList {
            post.createdAt?.let { TopicPresentation.formatTimestamp(it)?.let { ts -> add(ts) } }
        }.joinToString(" · ")
        metaText.text = meta

        floorText.text = "#${post.postNumber}楼"

        // Reply context
        val replyToNumber = post.replyToPostNumber
        val parentPostNumber = row.parentPostNumber
        val effectiveReplyTarget = parentPostNumber ?: replyToNumber
        if (effectiveReplyTarget != null && effectiveReplyTarget > 0u && effectiveReplyTarget != 1u) {
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

        val contentId = "${post.id}:${post.presentation.hashCode()}"
        if (bodyContainer.getTag(R.id.tag_post_content_id) != contentId) {
            val presentation = post.presentation
            bindPostBody(contentId, presentation, callbacks)
            bodyContainer.setTag(R.id.tag_post_content_id, contentId)
        }

        // Avatar
        val avatarTemplate = post.avatarTemplate
        if (!avatarTemplate.isNullOrBlank()) {
            FireAvatarUrls.build(avatarTemplate)?.let { url ->
                FireImageLoader.load(url, avatar)
            }
        } else {
            avatar.setImageDrawable(null)
        }

        bindPolls(post, callbacks)
        bindBoosts(row)
        bindMoreRepliesAction(row, callbacks)

        // Actions
        val likedByCurrentUser = post.currentUserReaction?.id == HEART_REACTION_ID
        configureIconAction(
            view = likeAction,
            iconRes = R.drawable.ic_heart,
            active = likedByCurrentUser,
            contentDescription = context.getString(
                if (likedByCurrentUser) {
                    R.string.topic_detail_unlike_post
                } else {
                    R.string.topic_detail_like_post
                },
                post.likeCount.toString(),
            ),
            onClick = { callbacks.onHeartClick(post) },
        )

        val currentReactionId = post.currentUserReaction?.id?.trim()
        val currentCustomReactionId = currentReactionId
            ?.takeIf { it.isNotEmpty() && !it.equals(ReactionPresentation.HEART_ID, ignoreCase = true) }
        val hasCustomReactionOptions = ReactionPresentation
            .customOptions(callbacks.reactionIds(), currentCustomReactionId)
            .isNotEmpty()
        val canUndoCurrentReaction = post.currentUserReaction?.canUndo ?: true
        if (hasCustomReactionOptions) {
            val reactionDescription = if (currentCustomReactionId != null) {
                val option = ReactionPresentation.optionFor(currentCustomReactionId)
                context.getString(
                    R.string.topic_detail_reaction_choice_selected,
                    "${option.symbol} ${option.label}",
                )
            } else {
                context.getString(R.string.topic_detail_react_post)
            }
            configureIconAction(
                view = reactAction,
                iconRes = R.drawable.ic_react,
                active = currentCustomReactionId != null,
                enabled = canUndoCurrentReaction,
                contentDescription = reactionDescription,
                onClick = { callbacks.onReactClick(post) },
            )
        } else {
            configureHiddenAction(reactAction)
        }

        configureIconAction(
            view = replyAction,
            iconRes = R.drawable.ic_reply,
            contentDescription = context.getString(R.string.topic_detail_reply_post),
            onClick = { callbacks.onReplyClick(post) },
        )

        configureIconAction(
            view = quoteAction,
            iconRes = R.drawable.ic_quote,
            contentDescription = context.getString(R.string.topic_detail_quote_post),
            onClick = { callbacks.onQuoteClick(post) },
        )

        configureIconAction(
            view = bookmarkAction,
            iconRes = if (post.bookmarked) R.drawable.ic_bookmark_filled else R.drawable.ic_bookmark,
            active = post.bookmarked,
            contentDescription = context.getString(
                if (post.bookmarked) {
                    R.string.topic_detail_bookmark_post_active
                } else {
                    R.string.topic_detail_bookmark_post
                },
            ),
            onClick = { callbacks.onBookmarkClick(post) },
        )

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
            configureIconAction(
                view = editAction,
                iconRes = R.drawable.ic_edit,
                contentDescription = context.getString(R.string.topic_detail_edit_post),
                onClick = { callbacks.onEditPostClick(post) },
            )
        } else {
            configureHiddenAction(editAction)
        }

        when {
            post.canRecover -> {
                configureIconAction(
                    view = deleteRecoverAction,
                    iconRes = R.drawable.ic_restore,
                    contentDescription = context.getString(R.string.topic_detail_recover_post),
                    onClick = { callbacks.onRecoverPostClick(post) },
                )
            }
            post.canDelete -> {
                configureIconAction(
                    view = deleteRecoverAction,
                    iconRes = R.drawable.ic_delete,
                    contentDescription = context.getString(R.string.topic_detail_delete_post),
                    onClick = { callbacks.onDeletePostClick(post) },
                )
            }
            else -> {
                configureHiddenAction(deleteRecoverAction)
            }
        }

        if (!post.hidden) {
            configureIconAction(
                view = flagAction,
                iconRes = R.drawable.ic_flag,
                contentDescription = context.getString(R.string.topic_detail_flag_post),
                onClick = { callbacks.onFlagPostClick(post) },
            )
        } else {
            configureHiddenAction(flagAction)
        }

        itemView.setOnClickListener { callbacks.onPostClick(post) }
    }

    fun onAttachedToWindow() {
        isAttachedToWindow = true
        updateBoostAnimationState()
    }

    fun onDetachedFromWindow() {
        isAttachedToWindow = false
        stopBoostAnimations()
    }

    fun setBoostAnimationsEnabled(enabled: Boolean) {
        if (boostAnimationsEnabled == enabled) return
        boostAnimationsEnabled = enabled
        updateBoostAnimationState()
    }

    private fun applySearchHighlight(isHighlighted: Boolean) {
        if (itemView.getTag(R.id.tag_post_original_background) == null) {
            itemView.setTag(R.id.tag_post_original_background, itemView.background)
        }

        if (isHighlighted) {
            itemView.background = GradientDrawable().apply {
                cornerRadius = dp(8).toFloat()
                setColor(itemView.context.getColor(R.color.fire_chip_accent_background))
                setStroke(dp(1), itemView.context.getColor(R.color.fire_accent))
            }
        } else {
            itemView.background = itemView.getTag(R.id.tag_post_original_background) as? android.graphics.drawable.Drawable
        }
    }

    internal fun dp(value: Int): Int {
        return itemView.resources.displayMetrics.density.times(value).toInt()
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
