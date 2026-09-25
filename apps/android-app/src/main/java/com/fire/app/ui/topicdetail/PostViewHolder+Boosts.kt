package com.fire.app.ui.topicdetail

import android.animation.Animator
import android.animation.ValueAnimator
import android.content.Context
import android.graphics.drawable.GradientDrawable
import android.text.SpannableStringBuilder
import android.text.Spanned
import android.text.TextUtils
import android.text.style.ForegroundColorSpan
import android.util.AttributeSet
import android.view.View
import android.view.ViewGroup
import android.view.animation.LinearInterpolator
import android.widget.FrameLayout
import android.widget.HorizontalScrollView
import android.widget.LinearLayout
import android.widget.TextView
import com.fire.app.R
import com.fire.app.richtext.FireRenderPresentation
import com.fire.app.richtext.FireRichTextView
import com.fire.app.richtext.FireSpannableBuilder
import uniffi.fire_uniffi_topics.TopicPostBoostState
import uniffi.fire_uniffi_topics.TopicPostState

internal fun PostViewHolder.bindBoosts(row: PostRow) {
    val post = row.post
    boostContainer.removeAllViews()
    clearBoostBarrage()
    if (post.boosts.isEmpty()) {
        boostContainer.visibility = View.GONE
        boostBarrageContainer.visibility = View.GONE
        applyActionsTopMargin(ACTIONS_DEFAULT_TOP_MARGIN_DP)
        return
    }

    if (TopicDetailPostRows.usesBoostBarrage(row) && bodyHasTextTarget) {
        boostContainer.visibility = View.GONE
        bindBoostBarrage(post)
        applyActionsTopMargin(ACTIONS_DEFAULT_TOP_MARGIN_DP)
        return
    }

    boostBarrageContainer.visibility = View.GONE
    boostContainer.visibility = View.VISIBLE
    bindManualBoostScroller(post.boosts)
    applyActionsTopMargin(0)
}

internal fun PostViewHolder.bindManualBoostScroller(boosts: List<TopicPostBoostState>) {
    val context = itemView.context
    val scroller = HorizontalScrollView(context).apply {
        isHorizontalScrollBarEnabled = false
        isVerticalScrollBarEnabled = false
        overScrollMode = View.OVER_SCROLL_IF_CONTENT_SCROLLS
        clipToPadding = false
        isFillViewport = true
        layoutParams = LinearLayout.LayoutParams(
            LinearLayout.LayoutParams.MATCH_PARENT,
            LinearLayout.LayoutParams.WRAP_CONTENT,
        )
    }
    val rowsContainer = FixedBoostManualChipLayout(context).apply {
        rowCount = FIXED_BOOST_MANUAL_ROWS
        rowHeightPx = dp(FIXED_BOOST_MANUAL_ROW_HEIGHT_DP)
        rowSpacingPx = dp(FIXED_BOOST_MANUAL_ROW_SPACING_DP)
        chipHeightPx = dp(FIXED_BOOST_MANUAL_CHIP_HEIGHT_DP)
        chipSpacingPx = dp(FIXED_BOOST_MANUAL_CHIP_SPACING_DP)
        minChipWidthPx = dp(FIXED_BOOST_MANUAL_MIN_CHIP_WIDTH_DP)
        clipToPadding = false
        layoutParams = FrameLayout.LayoutParams(
            FrameLayout.LayoutParams.MATCH_PARENT,
            FrameLayout.LayoutParams.WRAP_CONTENT,
        )
    }
    boosts.forEach { boost ->
        val boostView = boostChipView(
            boost = boost,
            textColor = context.getColor(R.color.fire_text_secondary),
            backgroundColor = context.getColor(R.color.fire_boost_background),
            heightDp = FIXED_BOOST_MANUAL_CHIP_HEIGHT_DP,
        ).apply {
            layoutParams = ViewGroup.LayoutParams(
                ViewGroup.LayoutParams.WRAP_CONTENT,
                dp(FIXED_BOOST_MANUAL_CHIP_HEIGHT_DP),
            )
        }
        rowsContainer.addView(boostView)
    }
    scroller.addView(rowsContainer)
    boostContainer.addView(scroller)
}

internal fun PostViewHolder.bindBoostBarrage(post: TopicPostState) {
    val context = itemView.context
    val visibleBoosts = post.boosts.take(TopicDetailBoostPresentation.BODY_BARRAGE_VISIBLE_LINE_LIMIT)
    val signature = boostBarrageSignature(post, visibleBoosts)
    boostBarrageSignature = signature
    if (visibleBoosts.isEmpty() || hasPlayedBoostBarrage(signature)) {
        boostBarrageContainer.visibility = View.GONE
        return
    }

    boostBarrageContainer.visibility = View.VISIBLE
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

internal fun PostViewHolder.boostBarrageSignature(
    post: TopicPostState,
    boosts: List<TopicPostBoostState>,
): String {
    return buildString {
        append(post.id)
        boosts.forEach { boost ->
            append('|')
            append(boost.id)
            append(':')
            append(boost.displayText.hashCode())
            append(':')
            append(boost.presentation?.checksum()?.toInt() ?: 0)
        }
    }
}

internal fun PostViewHolder.boostChipView(
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
        gravity = android.view.Gravity.CENTER_VERTICAL
        setPadding(dp(10), 0, dp(10), 0)
        background = GradientDrawable().apply {
            cornerRadius = dp(heightDp / 2).toFloat()
            setColor(backgroundColor)
        }
        val contentId = listOf(
            boost.id,
            boost.displayText.hashCode(),
            boost.presentation?.checksum()?.toInt() ?: 0,
        ).joinToString(separator = ":")
        setContent(
            "boost:$contentId",
            buildBoostChipText(boost, textColor),
        )
    }
}

internal fun PostViewHolder.buildBoostChipText(boost: TopicPostBoostState, textColor: Int): Spanned {
    val content = boost.presentation?.let(FireRenderPresentation::content)
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
    val builder = when {
        richText != null -> stripLeadingBoostAttribution(richText, boost)
        fallbackText != null -> SpannableStringBuilder(stripLeadingBoostAttribution(fallbackText, boost))
        else -> SpannableStringBuilder()
    }
    builder.setSpan(ForegroundColorSpan(textColor), 0, builder.length, Spanned.SPAN_EXCLUSIVE_EXCLUSIVE)
    return builder
}

internal fun PostViewHolder.stripLeadingBoostAttribution(
    value: SpannableStringBuilder,
    boost: TopicPostBoostState,
): SpannableStringBuilder {
    trimSpannable(value)
    val plain = value.toString()
    for (candidate in boostAttributionCandidates(boost)) {
        val prefix = "$candidate:"
        if (plain.startsWith(prefix, ignoreCase = true)) {
            value.delete(0, prefix.length)
            return trimSpannable(value)
        }
    }
    val generic = BOOST_ATTRIBUTION_PREFIX_REGEX.find(plain)?.value
    if (generic != null) {
        value.delete(0, generic.length)
        return trimSpannable(value)
    }
    return value
}

internal fun PostViewHolder.stripLeadingBoostAttribution(value: String, boost: TopicPostBoostState): String {
    val trimmed = value.trim()
    for (candidate in boostAttributionCandidates(boost)) {
        val prefix = "$candidate:"
        if (trimmed.startsWith(prefix, ignoreCase = true)) {
            return trimmed.drop(prefix.length).trim()
        }
    }
    return BOOST_ATTRIBUTION_PREFIX_REGEX.replace(trimmed, "").trim()
}

internal fun PostViewHolder.boostAttributionCandidates(boost: TopicPostBoostState): List<String> {
    return listOfNotNull(
        cleaned(boost.user.username)?.let { "@$it" },
        cleaned(boost.user.username),
        cleaned(boost.user.name),
    ).distinctBy { it.lowercase() }
}

internal fun PostViewHolder.trimSpannable(value: SpannableStringBuilder): SpannableStringBuilder {
    while (value.isNotEmpty() && value.first().isWhitespace()) {
        value.delete(0, 1)
    }
    while (value.isNotEmpty() && value.last().isWhitespace()) {
        value.delete(value.length - 1, value.length)
    }
    return value
}

internal fun PostViewHolder.clearBoostBarrage() {
    boostBarrageStartRunnable?.let(boostBarrageContainer::removeCallbacks)
    boostBarrageStartRunnable = null
    boostBarrageAnimators.forEach { it.cancel() }
    boostBarrageAnimators.clear()
    boostBarrageExpectedCompletions = 0
    boostBarrageCompletedCount = 0
    for (index in 0 until boostBarrageContainer.childCount) {
        boostBarrageContainer.getChildAt(index).animate().cancel()
    }
    boostBarrageContainer.removeAllViews()
}

internal fun PostViewHolder.startBoostBarrageAnimations() {
    boostBarrageStartRunnable = null
    val width = boostBarrageContainer.width
    val height = boostBarrageContainer.height
    if (width <= 0 || height <= 0) {
        scheduleBoostBarrageAfterLayout()
        return
    }

    val childCount = boostBarrageContainer.childCount
    boostBarrageAnimators.clear()
    boostBarrageExpectedCompletions = 0
    boostBarrageCompletedCount = 0
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
            interpolator = LinearInterpolator()
            addUpdateListener { animation ->
                child.translationX = animation.animatedValue as Float
                child.alpha = BARRAGE_START_ALPHA - animation.animatedFraction * BARRAGE_ALPHA_DELTA
            }
            addListener(object : Animator.AnimatorListener {
                private var canceled = false

                override fun onAnimationStart(animation: Animator) = Unit

                override fun onAnimationEnd(animation: Animator) {
                    if (!canceled) {
                        onBoostBarrageAnimatorFinished(animation)
                    }
                }

                override fun onAnimationCancel(animation: Animator) {
                    canceled = true
                }

                override fun onAnimationRepeat(animation: Animator) = Unit
            })
        }
        boostBarrageAnimators.add(animator)
        boostBarrageExpectedCompletions += 1
        animator.start()
    }
}

internal fun PostViewHolder.onBoostBarrageAnimatorFinished(animation: Animator) {
    (animation as? ValueAnimator)?.let { boostBarrageAnimators.remove(it) }
    boostBarrageCompletedCount += 1
    if (boostBarrageExpectedCompletions <= 0 ||
        boostBarrageCompletedCount < boostBarrageExpectedCompletions
    ) {
        return
    }

    val completedSignature = boostBarrageSignature ?: return
    rememberPlayedBoostBarrage(completedSignature)
    boostBarrageContainer.post {
        if (boostBarrageSignature != completedSignature) return@post
        boostBarrageStartRunnable?.let(boostBarrageContainer::removeCallbacks)
        boostBarrageStartRunnable = null
        boostBarrageAnimators.clear()
        boostBarrageExpectedCompletions = 0
        boostBarrageCompletedCount = 0
        boostBarrageContainer.removeAllViews()
        boostBarrageContainer.visibility = View.GONE
    }
}

internal fun PostViewHolder.scheduleBoostBarrageAfterLayout() {
    if (boostBarrageStartRunnable != null || boostBarrageContainer.childCount == 0) return
    val startRunnable = Runnable { startBoostBarrageAnimations() }
    boostBarrageStartRunnable = startRunnable
    boostBarrageContainer.postDelayed(startRunnable, BARRAGE_LAYOUT_RETRY_MS)
}

internal fun PostViewHolder.updateBoostAnimationState() {
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

internal fun PostViewHolder.pauseBoostAnimations() {
    boostBarrageStartRunnable?.let(boostBarrageContainer::removeCallbacks)
    boostBarrageStartRunnable = null
    pauseAnimators(boostBarrageAnimators)
}

internal fun PostViewHolder.stopBoostAnimations() {
    boostBarrageStartRunnable?.let(boostBarrageContainer::removeCallbacks)
    boostBarrageStartRunnable = null
    boostBarrageAnimators.forEach { it.cancel() }
    boostBarrageAnimators.clear()
}

internal fun PostViewHolder.pauseAnimators(animators: List<ValueAnimator>) {
    animators.forEach { animator ->
        if (animator.isStarted && !animator.isPaused) {
            animator.pause()
        }
    }
}

internal fun PostViewHolder.resumePausedAnimators(animators: List<ValueAnimator>): Boolean {
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

internal fun PostViewHolder.shouldRunBoostAnimations(): Boolean {
    return isAttachedToWindow && boostAnimationsEnabled
}

private fun hasPlayedBoostBarrage(signature: String): Boolean {
    return playedBoostBarrageSignatures.contains(signature)
}

private fun rememberPlayedBoostBarrage(signature: String) {
    playedBoostBarrageSignatures.add(signature)
    while (playedBoostBarrageSignatures.size > BARRAGE_PLAYED_CACHE_LIMIT) {
        val iterator = playedBoostBarrageSignatures.iterator()
        if (!iterator.hasNext()) return
        iterator.next()
        iterator.remove()
    }
}

private const val BARRAGE_CHIP_HEIGHT_DP = 24
private const val BARRAGE_MIN_LANE_GAP_DP = 4
private const val BARRAGE_BASE_DURATION_MS = 12_500L
private const val BARRAGE_LANE_DURATION_STEP_MS = 1_400L
private const val BARRAGE_LANE_STAGGER_MS = 1_500L
private const val BARRAGE_ROUND_STAGGER_MS = 4_600L
private const val BARRAGE_START_ALPHA = 0.82f
private const val BARRAGE_ALPHA_DELTA = 0.16f
private const val BARRAGE_LAYOUT_RETRY_MS = 48L
private const val BARRAGE_PLAYED_CACHE_LIMIT = 256
private const val FIXED_BOOST_MANUAL_ROWS = 2
private const val FIXED_BOOST_MANUAL_ROW_HEIGHT_DP = 30
private const val FIXED_BOOST_MANUAL_ROW_SPACING_DP = 4
private const val FIXED_BOOST_MANUAL_CHIP_HEIGHT_DP = 26
private const val FIXED_BOOST_MANUAL_CHIP_SPACING_DP = 8
private const val FIXED_BOOST_MANUAL_MIN_CHIP_WIDTH_DP = 48
private const val ACTIONS_DEFAULT_TOP_MARGIN_DP = 8
private val playedBoostBarrageSignatures = LinkedHashSet<String>()
private val BOOST_ATTRIBUTION_PREFIX_REGEX = Regex("""^@?[^\s:：]{1,40}[:：]\s*""")

private class FixedBoostManualChipLayout @JvmOverloads constructor(
    context: Context,
    attrs: AttributeSet? = null,
) : ViewGroup(context, attrs) {

    var rowCount: Int = 2
    var rowHeightPx: Int = 0
    var rowSpacingPx: Int = 0
    var chipHeightPx: Int = 0
    var chipSpacingPx: Int = 0
    var minChipWidthPx: Int = 0

    private var measuredChipWidths: IntArray = IntArray(0)
    private var layoutResult = TopicDetailManualBoostLayoutResult(
        placements = emptyList(),
        contentWidth = 0,
        usedRowCount = 0,
    )

    override fun onMeasure(widthMeasureSpec: Int, heightMeasureSpec: Int) {
        val viewportWidth = resolvedViewportWidth(widthMeasureSpec)
        val maxChipWidth = (viewportWidth * MAX_CHIP_WIDTH_RATIO).toInt().coerceAtLeast(1)
        val resolvedChipHeight = chipHeightPx.coerceAtLeast(1)
        val childHeightSpec = MeasureSpec.makeMeasureSpec(resolvedChipHeight, MeasureSpec.EXACTLY)
        val childWidthSpec = MeasureSpec.makeMeasureSpec(maxChipWidth, MeasureSpec.AT_MOST)
        val widths = IntArray(childCount)

        for (index in 0 until childCount) {
            val child = getChildAt(index)
            if (child.visibility == GONE) {
                widths[index] = 0
                continue
            }
            child.measure(childWidthSpec, childHeightSpec)
            widths[index] = child.measuredWidth.coerceIn(minChipWidthPx.coerceAtLeast(1), maxChipWidth)
            child.measure(
                MeasureSpec.makeMeasureSpec(widths[index], MeasureSpec.EXACTLY),
                childHeightSpec,
            )
        }

        measuredChipWidths = widths
        layoutResult = TopicDetailManualBoostLayout.placements(
            chipWidths = widths.filter { it > 0 },
            pageWidth = viewportWidth,
            rowCount = rowCount,
            chipSpacing = chipSpacingPx,
        )

        val resolvedRowCount = layoutResult.usedRowCount.coerceIn(0, rowCount.coerceAtLeast(1))
        val resolvedRowHeight = rowHeightPx.coerceAtLeast(resolvedChipHeight)
        val measuredHeight = if (resolvedRowCount == 0) {
            0
        } else {
            resolvedRowCount * resolvedRowHeight +
                (resolvedRowCount - 1) * rowSpacingPx
        }
        setMeasuredDimension(
            layoutResult.contentWidth.coerceAtLeast(viewportWidth),
            resolveSize(measuredHeight, heightMeasureSpec),
        )
    }

    override fun onLayout(changed: Boolean, left: Int, top: Int, right: Int, bottom: Int) {
        val resolvedRowHeight = rowHeightPx.coerceAtLeast(chipHeightPx.coerceAtLeast(1))
        var placementIndex = 0
        for (index in 0 until childCount) {
            val child = getChildAt(index)
            if (child.visibility == GONE) continue
            val placement = layoutResult.placements.getOrNull(placementIndex) ?: break
            val width = measuredChipWidths.getOrNull(index)?.takeIf { it > 0 } ?: child.measuredWidth
            val childTop = placement.rowIndex * (resolvedRowHeight + rowSpacingPx) +
                ((resolvedRowHeight - child.measuredHeight).coerceAtLeast(0) / 2)
            child.layout(
                placement.x,
                childTop,
                placement.x + width,
                childTop + child.measuredHeight,
            )
            placementIndex += 1
        }
    }

    override fun generateDefaultLayoutParams(): LayoutParams {
        return LayoutParams(LayoutParams.WRAP_CONTENT, chipHeightPx.coerceAtLeast(1))
    }

    override fun generateLayoutParams(attrs: AttributeSet): LayoutParams {
        return LayoutParams(context, attrs)
    }

    override fun generateLayoutParams(params: LayoutParams): LayoutParams {
        return LayoutParams(params)
    }

    override fun checkLayoutParams(params: LayoutParams): Boolean {
        return true
    }

    private fun resolvedViewportWidth(widthMeasureSpec: Int): Int {
        val specWidth = MeasureSpec.getSize(widthMeasureSpec)
        if (specWidth > 0) return specWidth
        val parentWidth = (parent as? View)?.width ?: 0
        if (parentWidth > 0) return parentWidth
        return resources.displayMetrics.widthPixels.coerceAtLeast(1)
    }

    private companion object {
        private const val MAX_CHIP_WIDTH_RATIO = 0.72f
    }
}
