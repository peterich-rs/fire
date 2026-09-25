package com.fire.app.ui.topicdetail

import android.view.View
import android.widget.CheckBox
import android.widget.LinearLayout
import android.widget.TextView
import android.widget.Toast
import com.fire.app.R
import uniffi.fire_uniffi_topics.PollState
import uniffi.fire_uniffi_topics.TopicPostState

internal fun PostViewHolder.bindPolls(post: TopicPostState, callbacks: PostRowCallbacks) {
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

internal fun PostViewHolder.pollTitleView(poll: PollState): TextView {
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

internal fun PostViewHolder.pollOptionsView(
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

internal fun PostViewHolder.pollActionsView(
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

internal fun PostViewHolder.sectionDivider(): View {
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
