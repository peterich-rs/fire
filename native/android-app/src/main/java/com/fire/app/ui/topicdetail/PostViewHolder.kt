package com.fire.app.ui.topicdetail

import android.animation.ValueAnimator
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.text.SpannableStringBuilder
import android.text.Spanned
import android.text.TextUtils
import android.text.style.ForegroundColorSpan
import android.text.style.StyleSpan
import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import android.view.animation.LinearInterpolator
import android.widget.CheckBox
import android.widget.FrameLayout
import android.widget.HorizontalScrollView
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
    private val authorChips: LinearLayout = itemView.findViewById(R.id.post_author_chips)
    private val authorMetadataText: TextView = itemView.findViewById(R.id.post_author_metadata)
    private val metaText: TextView = itemView.findViewById(R.id.post_meta)
    private val floorText: TextView = itemView.findViewById(R.id.post_floor)
    private val replyContextText: TextView = itemView.findViewById(R.id.post_reply_context)
    private val bodyFrame: FrameLayout = itemView.findViewById(R.id.post_body_frame)
    private val bodyContainer: LinearLayout = itemView.findViewById(R.id.post_body_container)
    private val pollContainer: LinearLayout = itemView.findViewById(R.id.post_poll_container)
    private val boostContainer: LinearLayout = itemView.findViewById(R.id.post_boost_container)
    private val boostBarrageContainer: FrameLayout = itemView.findViewById(R.id.post_boost_barrage_container)
    private val actionsScroll: HorizontalScrollView = itemView.findViewById(R.id.post_actions_scroll)
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
    private var boostAnimationsEnabled = true
    private var isAttachedToWindow = false

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
        applyContentWidthMode(row.usesTitleWidthBody)

        val normalizedUsername = post.username.trim().takeIf { it.isNotEmpty() }
        usernameText.isClickable = normalizedUsername != null
        avatar.isClickable = normalizedUsername != null
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
        boostContainer.visibility = View.VISIBLE
        bindManualBoostScroller(post.boosts)
    }

    private fun bindManualBoostScroller(boosts: List<TopicPostBoostState>) {
        val context = itemView.context
        val scroller = HorizontalScrollView(context).apply {
            isHorizontalScrollBarEnabled = false
            isVerticalScrollBarEnabled = false
            overScrollMode = View.OVER_SCROLL_IF_CONTENT_SCROLLS
            clipToPadding = false
            layoutParams = LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT,
                LinearLayout.LayoutParams.WRAP_CONTENT,
            )
        }
        val rowsContainer = LinearLayout(context).apply {
            orientation = LinearLayout.VERTICAL
            clipToPadding = false
            layoutParams = FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.WRAP_CONTENT,
                FrameLayout.LayoutParams.WRAP_CONTENT,
            )
        }
        val manualRows = mutableListOf<LinearLayout>()
        boosts.forEachIndexed { index, boost ->
            val rowIndex = index % FIXED_BOOST_MANUAL_ROWS
            val row = manualRows.getOrNull(rowIndex) ?: LinearLayout(context).apply {
                orientation = LinearLayout.HORIZONTAL
                clipToPadding = false
                layoutParams = LinearLayout.LayoutParams(
                    LinearLayout.LayoutParams.MATCH_PARENT,
                    dp(FIXED_BOOST_MANUAL_ROW_HEIGHT_DP),
                ).apply {
                    if (manualRows.isNotEmpty()) topMargin = dp(4)
                }
                rowsContainer.addView(this)
                manualRows += this
            }
            val boostView = boostChipView(
                boost = boost,
                textColor = context.getColor(R.color.fire_text_secondary),
                backgroundColor = context.getColor(R.color.fire_boost_background),
                heightDp = FIXED_BOOST_MANUAL_CHIP_HEIGHT_DP,
            ).apply {
                layoutParams = LinearLayout.LayoutParams(
                    LinearLayout.LayoutParams.WRAP_CONTENT,
                    dp(FIXED_BOOST_MANUAL_CHIP_HEIGHT_DP),
                ).apply {
                    if (row.childCount > 0) marginStart = dp(8)
                }
            }
            row.addView(boostView)
        }
        scroller.addView(rowsContainer)
        boostContainer.addView(scroller)
    }

    private fun bindBoostBarrage(boosts: List<TopicPostBoostState>) {
        val context = itemView.context
        boostBarrageContainer.visibility = View.VISIBLE
        val visibleBoosts = boosts.take(TopicDetailBoostPresentation.BODY_BARRAGE_VISIBLE_LINE_LIMIT)
        visibleBoosts.forEach { boost ->
            val boostView = boostChipView(
                boost = boost,
                textColor = context.getColor(R.color.fire_text_primary),
                backgroundColor = context.getColor(R.color.fire_boost_barrage_background),
                heightDp = BARRAGE_CHIP_HEIGHT_DP,
            ).apply {
                importantForAccessibility = View.IMPORTANT_FOR_ACCESSIBILITY_NO
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

    private fun boostChipView(
        boost: TopicPostBoostState,
        textColor: Int,
        backgroundColor: Int,
        heightDp: Int,
    ): FireRichTextView {
        return FireRichTextView(itemView.context).apply {
            setTextAppearance(androidx.appcompat.R.style.TextAppearance_AppCompat_Caption)
            setTextColor(textColor)
            maxLines = 1
            ellipsize = TextUtils.TruncateAt.END
            includeFontPadding = false
            setPadding(dp(10), 0, dp(10), 0)
            background = GradientDrawable().apply {
                cornerRadius = dp(heightDp / 2).toFloat()
                setColor(backgroundColor)
            }
            val contentId = listOf(
                boost.id,
                boost.displayText.hashCode(),
                boost.cooked.hashCode(),
                boost.renderDocument?.plainText?.hashCode() ?: 0,
            ).joinToString(separator = ":")
            setContent(
                "boost:$contentId",
                buildBoostChipText(boost, textColor),
            )
        }
    }

    private fun buildBoostChipText(boost: TopicPostBoostState, textColor: Int): Spanned {
        val builder = SpannableStringBuilder()
        val authorStart = builder.length
        builder.append(boostAuthor(boost))
        builder.setSpan(StyleSpan(Typeface.BOLD), authorStart, builder.length, Spanned.SPAN_EXCLUSIVE_EXCLUSIVE)

        val content = boost.renderDocument?.let { FireRenderBlockBuilder.build(it) }
        val richText = content
            ?.nodes
            ?.takeIf { it.isNotEmpty() }
            ?.let { nodes ->
                trimSpannable(
                    FireSpannableBuilder.build(
                        nodes = nodes,
                        context = itemView.context,
                        onLinkClicked = null,
                    ),
                )
            }
            ?.takeIf { it.isNotBlank() }
        val fallbackText = cleaned(boost.displayText)
        when {
            richText != null -> {
                builder.append(": ")
                builder.append(richText)
            }
            fallbackText != null -> builder.append(": ").append(fallbackText)
        }
        builder.setSpan(ForegroundColorSpan(textColor), 0, builder.length, Spanned.SPAN_EXCLUSIVE_EXCLUSIVE)
        return builder
    }

    private fun trimSpannable(value: SpannableStringBuilder): SpannableStringBuilder {
        while (value.isNotEmpty() && value.first().isWhitespace()) {
            value.delete(0, 1)
        }
        while (value.isNotEmpty() && value.last().isWhitespace()) {
            value.delete(value.length - 1, value.length)
        }
        return value
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
        boostBarrageStartRunnable = null
        val width = boostBarrageContainer.width
        val height = boostBarrageContainer.height
        if (width <= 0 || height <= 0) {
            scheduleBoostBarrageAfterLayout()
            return
        }

        val childCount = boostBarrageContainer.childCount
        val laneHeight = dp(BARRAGE_CHIP_HEIGHT_DP)
        val laneGap = dp(BARRAGE_MIN_LANE_GAP_DP)
        val availableLaneCount = ((height + laneGap) / (laneHeight + laneGap))
            .coerceAtLeast(1)
        val laneCount = minOf(
            childCount,
            TopicDetailBoostPresentation.BODY_BARRAGE_MAX_LANES,
            availableLaneCount,
        ).coerceAtLeast(1)
        val verticalStride = if (laneCount <= 1) {
            0
        } else {
            ((height - laneHeight).coerceAtLeast(0) / (laneCount - 1))
        }
        val maxChipWidth = (width * 0.72f).toInt().coerceAtLeast(1)
        val animationsEnabled = ValueAnimator.areAnimatorsEnabled()

        for (index in 0 until childCount) {
            val child = boostBarrageContainer.getChildAt(index) as? TextView ?: continue
            child.animate().cancel()
            child.measure(
                View.MeasureSpec.makeMeasureSpec(maxChipWidth, View.MeasureSpec.AT_MOST),
                View.MeasureSpec.makeMeasureSpec(dp(BARRAGE_CHIP_HEIGHT_DP), View.MeasureSpec.EXACTLY),
            )
            val chipWidth = child.measuredWidth.coerceIn(dp(48), maxChipWidth)
            val lane = index % laneCount
            val y = (lane * verticalStride).coerceAtMost((height - laneHeight).coerceAtLeast(0))
            val params = child.layoutParams as FrameLayout.LayoutParams
            params.width = chipWidth
            params.height = laneHeight
            child.layoutParams = params
            child.translationY = y.toFloat()
            child.alpha = BARRAGE_START_ALPHA

            if (!animationsEnabled || !shouldRunBoostAnimations()) {
                val slotProgress = (index + 1).toFloat() / (childCount + 1).toFloat()
                child.translationX = ((width - chipWidth).coerceAtLeast(0) * slotProgress)
                continue
            }

            val round = index / laneCount
            val laneStagger = lane * BARRAGE_LANE_STAGGER_MS
            val roundStagger = round * BARRAGE_ROUND_STAGGER_MS
            val startX = width.toFloat() + lane * dp(18)
            child.translationX = startX
            val endX = -chipWidth.toFloat() - dp(16)
            val animator = ValueAnimator.ofFloat(startX, endX).apply {
                duration = BARRAGE_BASE_DURATION_MS + lane * BARRAGE_LANE_DURATION_STEP_MS
                startDelay = laneStagger + roundStagger
                repeatCount = ValueAnimator.INFINITE
                repeatMode = ValueAnimator.RESTART
                interpolator = LinearInterpolator()
                addUpdateListener { animation ->
                    child.translationX = animation.animatedValue as Float
                    child.alpha = BARRAGE_START_ALPHA - animation.animatedFraction * BARRAGE_ALPHA_DELTA
                }
            }
            boostBarrageAnimators.add(animator)
            animator.start()
        }
    }

    private fun scheduleBoostBarrageAfterLayout() {
        if (boostBarrageStartRunnable != null || boostBarrageContainer.childCount == 0) return
        val startRunnable = Runnable { startBoostBarrageAnimations() }
        boostBarrageStartRunnable = startRunnable
        boostBarrageContainer.postDelayed(startRunnable, BARRAGE_LAYOUT_RETRY_MS)
    }

    private fun updateBoostAnimationState() {
        if (shouldRunBoostAnimations()) {
            if (boostBarrageContainer.visibility == View.VISIBLE) {
                if (!resumePausedAnimators(boostBarrageAnimators) && boostBarrageAnimators.isEmpty()) {
                    scheduleBoostBarrageAfterLayout()
                }
            }
        } else {
            pauseBoostAnimations()
        }
    }

    private fun pauseBoostAnimations() {
        boostBarrageStartRunnable?.let(boostBarrageContainer::removeCallbacks)
        boostBarrageStartRunnable = null
        pauseAnimators(boostBarrageAnimators)
    }

    private fun stopBoostAnimations() {
        boostBarrageStartRunnable?.let(boostBarrageContainer::removeCallbacks)
        boostBarrageStartRunnable = null
        boostBarrageAnimators.forEach { it.cancel() }
        boostBarrageAnimators.clear()
    }

    private fun pauseAnimators(animators: List<ValueAnimator>) {
        animators.forEach { animator ->
            if (animator.isStarted && !animator.isPaused) {
                animator.pause()
            }
        }
    }

    private fun resumePausedAnimators(animators: List<ValueAnimator>): Boolean {
        if (animators.isEmpty()) return false
        var resumed = false
        animators.forEach { animator ->
            if (animator.isPaused) {
                animator.resume()
                resumed = true
            }
        }
        return resumed || animators.any { it.isStarted }
    }

    private fun shouldRunBoostAnimations(): Boolean {
        return isAttachedToWindow && boostAnimationsEnabled
    }

    private fun applyContentWidthMode(usesTitleWidthBody: Boolean) {
        val leadingMargin = if (usesTitleWidthBody) 0 else POST_CONTENT_LEADING_MARGIN_DP
        applyStartMargin(replyContextText, leadingMargin)
        applyStartMargin(bodyFrame, leadingMargin)
        applyStartMargin(pollContainer, leadingMargin)
        applyStartMargin(boostContainer, leadingMargin)
        applyStartMargin(actionsScroll, leadingMargin)
    }

    private fun applyStartMargin(view: View, marginDp: Int) {
        val params = view.layoutParams as? ViewGroup.MarginLayoutParams ?: return
        val marginPx = dp(marginDp)
        if (params.marginStart == marginPx) return
        params.marginStart = marginPx
        view.layoutParams = params
    }

    private fun bindAuthorChips(chips: List<AuthorMetadataChip>) {
        authorChips.removeAllViews()
        authorChips.visibility = if (chips.isEmpty()) View.GONE else View.VISIBLE
        val context = itemView.context
        chips.forEachIndexed { index, chip ->
            val chipView = TextView(context).apply {
                text = chip.label
                setTextAppearance(androidx.appcompat.R.style.TextAppearance_AppCompat_Caption)
                setTextColor(context.getColor(chip.textColorRes))
                maxLines = 1
                ellipsize = TextUtils.TruncateAt.END
                includeFontPadding = false
                setPadding(dp(6), dp(2), dp(6), dp(2))
                background = GradientDrawable().apply {
                    cornerRadius = dp(9).toFloat()
                    setColor(context.getColor(chip.backgroundColorRes))
                }
                layoutParams = LinearLayout.LayoutParams(
                    LinearLayout.LayoutParams.WRAP_CONTENT,
                    LinearLayout.LayoutParams.WRAP_CONTENT,
                ).apply {
                    if (index > 0) marginStart = dp(4)
                }
            }
            authorChips.addView(chipView)
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
        private const val BARRAGE_CHIP_HEIGHT_DP = 24
        private const val BARRAGE_MIN_LANE_GAP_DP = 4
        private const val BARRAGE_BASE_DURATION_MS = 12_500L
        private const val BARRAGE_LANE_DURATION_STEP_MS = 1_400L
        private const val BARRAGE_LANE_STAGGER_MS = 1_500L
        private const val BARRAGE_ROUND_STAGGER_MS = 4_600L
        private const val BARRAGE_START_ALPHA = 0.82f
        private const val BARRAGE_ALPHA_DELTA = 0.16f
        private const val BARRAGE_LAYOUT_RETRY_MS = 48L
        private const val FIXED_BOOST_MANUAL_ROWS = 2
        private const val FIXED_BOOST_MANUAL_ROW_HEIGHT_DP = 30
        private const val FIXED_BOOST_MANUAL_CHIP_HEIGHT_DP = 26
        private const val POST_CONTENT_LEADING_MARGIN_DP = 46

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

        private fun primaryMetadataParts(post: TopicPostState): List<AuthorMetadataChip> {
            val metadata = post.authorMetadata
            val title = cleaned(metadata.userTitle)
            val group = cleaned(metadata.primaryGroupName)
            val flair = cleaned(metadata.flairName)

            return buildList {
                trustLevelChip(title)?.let(::add)
                if (metadata.admin) {
                    add(AuthorMetadataChip("管理员", R.color.fire_error, R.color.fire_chip_error_background))
                }
                if (metadata.moderator) {
                    add(AuthorMetadataChip("版主", R.color.fire_link, R.color.fire_chip_link_background))
                }
                if (metadata.groupModerator) {
                    add(AuthorMetadataChip("组版主", R.color.fire_warning, R.color.fire_chip_warning_background))
                }
                group?.let {
                    add(AuthorMetadataChip(compactChipLabel(it), R.color.fire_success, R.color.fire_chip_success_background))
                }
                if (flair != null && !flair.equals(group, ignoreCase = true)) {
                    add(AuthorMetadataChip(compactChipLabel(flair), R.color.fire_accent, R.color.fire_chip_accent_background))
                }
            }.take(MAX_PRIMARY_METADATA_CHIPS)
        }

        private fun secondaryMetadataParts(post: TopicPostState): List<String> {
            val metadata = post.authorMetadata
            val username = cleaned(post.username)
            val title = cleaned(metadata.userTitle)
            val statusDescription = cleaned(metadata.userStatusDescription)
            val statusEmoji = cleaned(metadata.userStatusEmoji)?.let { ":$it:" }

            return buildList {
                username?.let { add("@$it") }
                if (title != null && trustLevelChip(title) == null) {
                    add(compactSecondaryLabel(title))
                }
                if (statusDescription != null) {
                    add(compactSecondaryLabel(statusDescription))
                } else {
                    statusEmoji?.let(::add)
                }
            }
        }

        private fun trustLevelChip(title: String?): AuthorMetadataChip? {
            val label = title?.let { TRUST_LEVEL_REGEX.find(it)?.groupValues?.getOrNull(1) } ?: return null
            return AuthorMetadataChip("Lv.$label", R.color.fire_warning, R.color.fire_chip_warning_background)
        }

        private fun boostAuthor(boost: TopicPostBoostState): String {
            return cleaned(boost.user.username)?.let { "@$it" }
                ?: cleaned(boost.user.name)
                ?: "User ${boost.user.id}"
        }

        private fun cleaned(value: String?): String? {
            return value?.trim()?.takeIf { it.isNotEmpty() }
        }

        private fun compactChipLabel(value: String): String {
            return if (value.length <= MAX_CHIP_LABEL_LENGTH) {
                value
            } else {
                value.take(MAX_CHIP_LABEL_LENGTH - 1) + "…"
            }
        }

        private fun compactSecondaryLabel(value: String): String {
            return if (value.length <= MAX_SECONDARY_LABEL_LENGTH) {
                value
            } else {
                value.take(MAX_SECONDARY_LABEL_LENGTH - 1) + "…"
            }
        }

        private const val MAX_PRIMARY_METADATA_CHIPS = 3
        private const val MAX_CHIP_LABEL_LENGTH = 10
        private const val MAX_SECONDARY_LABEL_LENGTH = 16
        private val TRUST_LEVEL_REGEX = Regex("""(?i)(?:trust\s*level|tl|level|等级)\D*(\d+)""")
    }
}

private data class AuthorMetadataChip(
    val label: String,
    val textColorRes: Int,
    val backgroundColorRes: Int,
)
