package com.fire.app.ui.topicdetail

import android.animation.ValueAnimator
import android.graphics.drawable.GradientDrawable
import android.text.TextUtils
import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import android.view.animation.LinearInterpolator
import android.widget.CheckBox
import android.widget.FrameLayout
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.TextView
import android.widget.Toast
import androidx.recyclerview.widget.RecyclerView
import com.fire.app.R
import com.fire.app.TopicPresentation
import com.fire.app.core.image.FireAvatarUrls
import com.fire.app.core.image.FireImageLoader
import com.fire.app.richtext.FireRichTextBlock
import com.fire.app.richtext.FireRichTextBlockBuilder
import com.fire.app.richtext.FireRichTextContent
import com.fire.app.richtext.FireRenderBlockBuilder
import com.fire.app.richtext.FireRichTextView
import com.fire.app.richtext.FireSpannableBuilder
import uniffi.fire_uniffi_topics.PollState
import uniffi.fire_uniffi_topics.TopicPostBoostState
import uniffi.fire_uniffi_topics.TopicPostState

class PostViewHolder(itemView: View) : RecyclerView.ViewHolder(itemView) {

    private val avatar: ImageView = itemView.findViewById(R.id.post_avatar)
    private val usernameText: TextView = itemView.findViewById(R.id.post_username)
    private val authorMetadataText: TextView = itemView.findViewById(R.id.post_author_metadata)
    private val metaText: TextView = itemView.findViewById(R.id.post_meta)
    private val floorText: TextView = itemView.findViewById(R.id.post_floor)
    private val replyContextText: TextView = itemView.findViewById(R.id.post_reply_context)
    private val bodyContainer: LinearLayout = itemView.findViewById(R.id.post_body_container)
    private val pollContainer: LinearLayout = itemView.findViewById(R.id.post_poll_container)
    private val boostContainer: LinearLayout = itemView.findViewById(R.id.post_boost_container)
    private val boostBarrageContainer: FrameLayout = itemView.findViewById(R.id.post_boost_barrage_container)
    private val likeAction: TextView = itemView.findViewById(R.id.action_like)
    private val reactAction: TextView = itemView.findViewById(R.id.action_react)
    private val replyAction: TextView = itemView.findViewById(R.id.action_reply)
    private val bookmarkAction: TextView = itemView.findViewById(R.id.action_bookmark)
    private val reactionsAction: TextView = itemView.findViewById(R.id.action_reactions)
    private val editAction: TextView = itemView.findViewById(R.id.action_edit)
    private val deleteRecoverAction: TextView = itemView.findViewById(R.id.action_delete_recover)
    private val flagAction: TextView = itemView.findViewById(R.id.action_flag)
    private var boostBarrageStartRunnable: Runnable? = null
    private val boostBarrageAnimators = mutableListOf<ValueAnimator>()
    private var bodyHasTextTarget: Boolean = false

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

        usernameText.text = displayName(post)
        usernameText.setOnClickListener { callbacks.onAuthorClick(post.username) }
        avatar.setOnClickListener { callbacks.onAuthorClick(post.username) }
        val authorMetadata = authorMetadataParts(post)
        if (authorMetadata.isEmpty()) {
            authorMetadataText.visibility = View.GONE
            authorMetadataText.text = null
        } else {
            authorMetadataText.visibility = View.VISIBLE
            authorMetadataText.text = authorMetadata.joinToString(" · ")
        }

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

        val contentId = "${post.id}:${post.renderDocument.hashCode()}"
        if (bodyContainer.getTag(R.id.tag_post_content_id) != contentId) {
            val parsed = post.renderDocument?.let { FireRenderBlockBuilder.build(it) }
            bindPostBody(contentId, parsed, callbacks)
            bodyContainer.setTag(R.id.tag_post_content_id, contentId)
            bodyContainer.setTag(R.id.tag_post_content, parsed)
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

    private fun bindPostBody(
        contentId: String,
        content: FireRichTextContent?,
        callbacks: PostRowCallbacks,
    ) {
        bodyContainer.removeAllViews()
        bodyHasTextTarget = false

        if (content != null) {
            val blocks = FireRichTextBlockBuilder.build(content)
            blocks.forEachIndexed { index, block ->
                when (block) {
                    is FireRichTextBlock.Text -> {
                        bodyHasTextTarget = addTextBlock(contentId, index, block, callbacks) || bodyHasTextTarget
                    }
                    is FireRichTextBlock.Image -> addImageBlock(index, block, callbacks)
                }
            }
        }

        bodyContainer.visibility = if (bodyContainer.childCount == 0) View.GONE else View.VISIBLE
    }

    private fun addTextBlock(
        contentId: String,
        index: Int,
        block: FireRichTextBlock.Text,
        callbacks: PostRowCallbacks,
    ): Boolean {
        val spannable = FireSpannableBuilder.build(
            nodes = block.nodes,
            context = itemView.context,
            onLinkClicked = callbacks.onLinkClick,
        )
        if (spannable.isBlank()) return false
        val textView = FireRichTextView(itemView.context).apply {
            setTextAppearance(androidx.appcompat.R.style.TextAppearance_AppCompat_Body1)
            setTextColor(itemView.context.getColor(R.color.fire_text_primary))
            setTextIsSelectable(true)
            setOnLongClickListener {
                requestFocus()
                false
            }
            setContent("$contentId:text:$index", spannable)
            layoutParams = bodyBlockLayoutParams(index)
        }
        bodyContainer.addView(textView)
        return true
    }

    private fun addImageBlock(
        index: Int,
        block: FireRichTextBlock.Image,
        callbacks: PostRowCallbacks,
    ) {
        val imageView = TopicPostImageView(itemView.context).apply {
            layoutParams = bodyBlockLayoutParams(index)
            bind(block.image, callbacks.onImageClick)
        }
        bodyContainer.addView(imageView)
    }

    private fun bodyBlockLayoutParams(index: Int): LinearLayout.LayoutParams {
        return LinearLayout.LayoutParams(
            LinearLayout.LayoutParams.MATCH_PARENT,
            LinearLayout.LayoutParams.WRAP_CONTENT,
        ).apply {
            if (index > 0) topMargin = itemView.resources.displayMetrics.density.times(8).toInt()
        }
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

    private fun bindBoosts(row: PostRow) {
        val post = row.post
        boostContainer.removeAllViews()
        clearBoostBarrage()
        if (post.boosts.isEmpty()) {
            boostContainer.visibility = View.GONE
            boostBarrageContainer.visibility = View.GONE
            return
        }

        if (TopicDetailPostRows.usesBoostBarrage(row) && bodyHasTextTarget) {
            boostContainer.visibility = View.GONE
            bindBoostBarrage(post.boosts)
            return
        }

        boostBarrageContainer.visibility = View.GONE
        val context = itemView.context
        boostContainer.visibility = View.VISIBLE
        post.boosts.forEachIndexed { index, boost ->
            val boostView = TextView(context).apply {
                text = displayBoostLine(boost)
                setTextAppearance(androidx.appcompat.R.style.TextAppearance_AppCompat_Caption)
                setTextColor(context.getColor(R.color.fire_text_secondary))
                maxLines = 2
                ellipsize = TextUtils.TruncateAt.END
                setPadding(dp(10), dp(6), dp(10), dp(6))
                background = GradientDrawable().apply {
                    cornerRadius = dp(13).toFloat()
                    setColor(context.getColor(R.color.fire_boost_background))
                }
                layoutParams = LinearLayout.LayoutParams(
                    LinearLayout.LayoutParams.MATCH_PARENT,
                    LinearLayout.LayoutParams.WRAP_CONTENT,
                ).apply {
                    if (index > 0) topMargin = dp(6)
                }
            }
            boostContainer.addView(boostView)
        }
    }

    private fun bindBoostBarrage(boosts: List<TopicPostBoostState>) {
        val context = itemView.context
        boostBarrageContainer.visibility = View.VISIBLE
        val visibleBoosts = boosts.take(MAX_BARRAGE_BOOSTS)
        visibleBoosts.forEach { boost ->
            val boostView = TextView(context).apply {
                text = displayBoostLine(boost)
                setTextAppearance(androidx.appcompat.R.style.TextAppearance_AppCompat_Caption)
                setTextColor(context.getColor(R.color.fire_text_primary))
                maxLines = 1
                ellipsize = TextUtils.TruncateAt.END
                importantForAccessibility = View.IMPORTANT_FOR_ACCESSIBILITY_NO
                setPadding(dp(10), 0, dp(10), 0)
                background = GradientDrawable().apply {
                    cornerRadius = dp(12).toFloat()
                    setColor(context.getColor(R.color.fire_boost_barrage_background))
                }
                layoutParams = FrameLayout.LayoutParams(
                    FrameLayout.LayoutParams.WRAP_CONTENT,
                    dp(24),
                )
            }
            boostBarrageContainer.addView(boostView)
        }
        val startRunnable = Runnable { startBoostBarrageAnimations() }
        boostBarrageStartRunnable = startRunnable
        boostBarrageContainer.post(startRunnable)
    }

    private fun clearBoostBarrage() {
        boostBarrageStartRunnable?.let(boostBarrageContainer::removeCallbacks)
        boostBarrageStartRunnable = null
        boostBarrageAnimators.forEach { it.cancel() }
        boostBarrageAnimators.clear()
        for (index in 0 until boostBarrageContainer.childCount) {
            boostBarrageContainer.getChildAt(index).animate().cancel()
        }
        boostBarrageContainer.removeAllViews()
    }

    private fun startBoostBarrageAnimations() {
        val width = boostBarrageContainer.width
        val height = boostBarrageContainer.height
        if (width <= 0 || height <= 0) return

        val laneCount = boostBarrageContainer.childCount.coerceIn(1, MAX_BARRAGE_LANES)
        val laneHeight = (dp(28)).coerceAtMost((height / laneCount).coerceAtLeast(dp(24)))
        val maxChipWidth = (width * 0.86f).toInt().coerceAtLeast(1)
        val animationsEnabled = ValueAnimator.areAnimatorsEnabled()

        for (index in 0 until boostBarrageContainer.childCount) {
            val child = boostBarrageContainer.getChildAt(index) as? TextView ?: continue
            child.animate().cancel()
            child.measure(
                View.MeasureSpec.makeMeasureSpec(maxChipWidth, View.MeasureSpec.AT_MOST),
                View.MeasureSpec.makeMeasureSpec(dp(24), View.MeasureSpec.EXACTLY),
            )
            val chipWidth = child.measuredWidth.coerceIn(dp(48), maxChipWidth)
            val lane = index % laneCount
            val y = (lane * laneHeight).coerceAtMost((height - dp(24)).coerceAtLeast(0))
            val params = child.layoutParams as FrameLayout.LayoutParams
            params.width = chipWidth
            params.height = dp(24)
            child.layoutParams = params
            child.translationY = y.toFloat()
            child.alpha = 0.92f

            if (!animationsEnabled) {
                val slotProgress = (index + 1).toFloat() / (boostBarrageContainer.childCount + 1).toFloat()
                child.translationX = ((width - chipWidth).coerceAtLeast(0) * slotProgress)
                continue
            }

            val startX = width.toFloat() + index * dp(28)
            child.translationX = startX
            val endX = -chipWidth.toFloat() - dp(16)
            val animator = ValueAnimator.ofFloat(startX, endX).apply {
                duration = 7_500L + (index % MAX_BARRAGE_LANES) * 800L
                startDelay = index * 350L
                repeatCount = ValueAnimator.INFINITE
                repeatMode = ValueAnimator.RESTART
                interpolator = LinearInterpolator()
                addUpdateListener { animation ->
                    child.translationX = animation.animatedValue as Float
                    child.alpha = 0.92f - animation.animatedFraction * 0.2f
                }
            }
            boostBarrageAnimators.add(animator)
            animator.start()
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
                    option.plainText.trim().ifBlank { option.id },
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

    private fun dp(value: Int): Int {
        return itemView.resources.displayMetrics.density.times(value).toInt()
    }

    companion object {
        private const val HEART_REACTION_ID = "heart"
        private const val MAX_BARRAGE_BOOSTS = 6
        private const val MAX_BARRAGE_LANES = 3

        fun create(parent: ViewGroup): PostViewHolder {
            val view = LayoutInflater.from(parent.context)
                .inflate(R.layout.item_post, parent, false)
            return PostViewHolder(view)
        }

        private fun displayName(post: TopicPostState): String {
            return cleaned(post.name)
                ?: cleaned(post.username)
                ?: "Unknown"
        }

        private fun authorMetadataParts(post: TopicPostState): List<String> {
            val metadata = post.authorMetadata
            val username = cleaned(post.username)
            val displayName = displayName(post)
            val title = cleaned(metadata.userTitle)
            val group = cleaned(metadata.primaryGroupName)
            val flair = cleaned(metadata.flairName)
            val statusDescription = cleaned(metadata.userStatusDescription)
            val statusEmoji = cleaned(metadata.userStatusEmoji)?.let { ":$it:" }
            val hasMetadataBeyondUsername = title != null ||
                group != null ||
                flair != null ||
                metadata.admin ||
                metadata.moderator ||
                metadata.groupModerator ||
                statusDescription != null ||
                statusEmoji != null

            return buildList {
                if (
                    username != null &&
                    (!displayName.equals(username, ignoreCase = true) || hasMetadataBeyondUsername)
                ) {
                    add("@$username")
                }
                title?.let(::add)
                group?.let(::add)
                if (flair != null && !flair.equals(group, ignoreCase = true)) {
                    add(flair)
                }
                if (metadata.admin) {
                    add("管理员")
                }
                if (metadata.moderator) {
                    add("版主")
                }
                if (metadata.groupModerator) {
                    add("组版主")
                }
                if (statusDescription != null) {
                    add(statusDescription)
                } else {
                    statusEmoji?.let(::add)
                }
            }
        }

        private fun displayBoostLine(boost: TopicPostBoostState): String {
            val username = cleaned(boost.user.username)?.let { "@$it" }
            val displayName = cleaned(boost.user.name)
            val author = username ?: displayName ?: "User ${boost.user.id}"
            val text = cleaned(boost.displayText)
            return if (text == null) author else "$author: $text"
        }

        private fun cleaned(value: String?): String? {
            return value?.trim()?.takeIf { it.isNotEmpty() }
        }
    }
}
