package com.fire.app.ui.topicdetail

import android.view.View
import android.view.ViewGroup
import android.widget.LinearLayout
import com.fire.app.R
import com.fire.app.richtext.FireRichTextBlock
import com.fire.app.richtext.FireRenderPresentation
import com.fire.app.richtext.FireRichTextView
import com.fire.app.richtext.FireSpannableBuilder
import uniffi.fire_uniffi_types.RenderDocumentHandle

internal fun PostViewHolder.bindPostBody(
    contentId: String,
    presentation: RenderDocumentHandle?,
    callbacks: PostRowCallbacks,
) {
    bodyContainer.removeAllViews()
    bodyHasTextTarget = false

    if (presentation != null) {
        val blocks = FireRenderPresentation.blocks(presentation)
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

internal fun PostViewHolder.addTextBlock(
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

internal fun PostViewHolder.addImageBlock(
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

internal fun PostViewHolder.bodyBlockLayoutParams(index: Int): LinearLayout.LayoutParams {
    return LinearLayout.LayoutParams(
        LinearLayout.LayoutParams.MATCH_PARENT,
        LinearLayout.LayoutParams.WRAP_CONTENT,
    ).apply {
        if (index > 0) topMargin = itemView.resources.displayMetrics.density.times(8).toInt()
    }
}

internal fun PostViewHolder.applyContentWidthMode(usesTitleWidthBody: Boolean) {
    val leadingMargin = if (usesTitleWidthBody) 0 else POST_CONTENT_LEADING_MARGIN_DP
    applyStartMargin(replyContextText, leadingMargin)
    applyStartMargin(bodyFrame, leadingMargin)
    applyStartMargin(pollContainer, leadingMargin)
    applyStartMargin(boostContainer, leadingMargin)
    applyStartMargin(actionsScroll, leadingMargin)
}

internal fun PostViewHolder.applyStartMargin(view: View, marginDp: Int) {
    val params = view.layoutParams as? ViewGroup.MarginLayoutParams ?: return
    val marginPx = dp(marginDp)
    if (params.marginStart == marginPx) return
    params.marginStart = marginPx
    view.layoutParams = params
}

private const val POST_CONTENT_LEADING_MARGIN_DP = 46
