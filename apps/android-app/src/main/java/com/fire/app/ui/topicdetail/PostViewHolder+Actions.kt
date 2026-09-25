package com.fire.app.ui.topicdetail

import android.content.res.ColorStateList
import android.view.View
import android.view.ViewGroup
import android.widget.TextView
import com.fire.app.R

internal fun PostViewHolder.configureIconAction(
    view: TextView,
    iconRes: Int,
    contentDescription: String,
    active: Boolean = false,
    enabled: Boolean = true,
    onClick: () -> Unit,
) {
    view.visibility = View.VISIBLE
    view.text = null
    view.contentDescription = contentDescription
    view.isEnabled = enabled
    view.alpha = if (enabled) 1f else 0.45f
    view.gravity = android.view.Gravity.CENTER
    view.includeFontPadding = false
    view.setCompoundDrawablesRelativeWithIntrinsicBounds(iconRes, 0, 0, 0)
    view.compoundDrawableTintList = ColorStateList.valueOf(
        itemView.context.getColor(if (active) R.color.fire_accent else R.color.fire_text_secondary),
    )
    view.setTextColor(itemView.context.getColor(if (active) R.color.fire_accent else R.color.fire_text_secondary))
    view.setOnClickListener(if (enabled) View.OnClickListener { onClick() } else null)
}

internal fun PostViewHolder.configureHiddenAction(view: TextView) {
    view.visibility = View.GONE
    view.text = null
    view.contentDescription = null
    view.compoundDrawableTintList = null
    view.setCompoundDrawablesRelativeWithIntrinsicBounds(0, 0, 0, 0)
    view.setOnClickListener(null)
    view.alpha = 1f
    view.isEnabled = true
}

internal fun PostViewHolder.bindMoreRepliesAction(row: PostRow, callbacks: PostRowCallbacks) {
    val count = row.hiddenReplyCount
    if (count == 0u) {
        moreRepliesAction.visibility = View.GONE
        moreRepliesAction.setOnClickListener(null)
        applyActionStartMargin(likeAction, 0)
        return
    }

    moreRepliesAction.visibility = View.VISIBLE
    moreRepliesAction.text = itemView.context.getString(
        R.string.topic_detail_load_more_replies_count,
        count.toString(),
    )
    moreRepliesAction.setOnClickListener { callbacks.onMoreRepliesClick(row.post) }
    applyActionStartMargin(likeAction, 16)
}

internal fun PostViewHolder.applyActionsTopMargin(marginDp: Int) {
    val params = actionsScroll.layoutParams as? ViewGroup.MarginLayoutParams ?: return
    val marginPx = dp(marginDp)
    if (params.topMargin == marginPx) return
    params.topMargin = marginPx
    actionsScroll.layoutParams = params
}

internal fun PostViewHolder.applyActionStartMargin(view: View, marginDp: Int) {
    val params = view.layoutParams as? ViewGroup.MarginLayoutParams ?: return
    val marginPx = dp(marginDp)
    if (params.marginStart == marginPx) return
    params.marginStart = marginPx
    view.layoutParams = params
}
