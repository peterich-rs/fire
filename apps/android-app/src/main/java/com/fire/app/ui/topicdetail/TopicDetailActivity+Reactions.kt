package com.fire.app.ui.topicdetail

import android.widget.ArrayAdapter
import android.widget.LinearLayout
import android.widget.ListView
import androidx.appcompat.app.AlertDialog
import androidx.core.widget.doAfterTextChanged
import androidx.lifecycle.lifecycleScope
import com.fire.app.R
import com.fire.app.core.ext.dp
import com.fire.app.core.ui.FireToast
import com.google.android.material.textfield.TextInputEditText
import com.google.android.material.textfield.TextInputLayout
import kotlinx.coroutines.launch
import uniffi.fire_uniffi_topics.ReactionUsersGroupState
import uniffi.fire_uniffi_topics.TopicPostState

internal fun TopicDetailActivity.showReactionUsers(post: TopicPostState) {
    showReactionUsers(post, reactionId = null)
}

internal fun TopicDetailActivity.showReactionUsers(post: TopicPostState, reactionId: String?) {
    lifecycleScope.launch {
        try {
            val groups = sessionStore.fetchReactionUsers(post.id)
                .filterForReaction(reactionId)
            val message = if (groups.isEmpty()) {
                getString(R.string.topic_detail_reaction_users_empty)
            } else {
                groups.joinToString("\n\n") { formatReactionUsersGroup(it) }
            }
            AlertDialog.Builder(this@showReactionUsers)
                .setTitle(
                    reactionId
                        ?.let { ReactionPresentation.optionFor(it) }
                        ?.let { getString(R.string.topic_detail_reaction_users_title_for_reaction, it.symbol, it.label) }
                        ?: getString(R.string.topic_detail_reaction_users_title),
                )
                .setMessage(message)
                .setPositiveButton(android.R.string.ok, null)
                .show()
        } catch (e: Exception) {
            FireToast.show(
                binding.root,
                e.localizedMessage ?: getString(R.string.topic_detail_reaction_users_error),
                FireToast.Style.ERROR,
            )
        }
    }
}

private fun List<ReactionUsersGroupState>.filterForReaction(reactionId: String?): List<ReactionUsersGroupState> {
    val trimmedReactionId = reactionId?.trim()?.takeIf { it.isNotEmpty() } ?: return this
    return filter { group -> group.id.equals(trimmedReactionId, ignoreCase = true) }
}

internal fun TopicDetailActivity.formatReactionUsersGroup(group: ReactionUsersGroupState): String {
    val users = group.users
        .joinToString(", ") { user ->
            user.name?.takeIf { it.isNotBlank() } ?: "@${user.username}"
        }
        .ifBlank { getString(R.string.topic_detail_reaction_users_empty) }
    return getString(
        R.string.topic_detail_reaction_users_group,
        group.id,
        group.count.toString(),
    ) + "\n" + users
}

internal fun TopicDetailActivity.showReactionPicker(post: TopicPostState) {
    val currentReaction = post.currentUserReaction
    if (currentReaction?.canUndo == false) {
        FireToast.show(
            binding.root,
            R.string.topic_detail_reaction_locked,
            FireToast.Style.WARNING,
        )
        return
    }

    lifecycleScope.launch {
        val options = fullReactionOptionsForPost(post)
        if (options.isEmpty()) {
            FireToast.show(
                binding.root,
                R.string.topic_detail_reaction_empty,
                FireToast.Style.INFO,
            )
            return@launch
        }

        val content = LinearLayout(this@showReactionPicker).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(dp(20), dp(8), dp(20), 0)
        }
        val searchLayout = TextInputLayout(this@showReactionPicker).apply {
            hint = getString(R.string.topic_detail_reaction_search_hint)
        }
        val searchInput = TextInputEditText(searchLayout.context).apply {
            isSingleLine = true
        }
        searchLayout.addView(
            searchInput,
            LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT,
                LinearLayout.LayoutParams.WRAP_CONTENT,
            ),
        )
        val listView = ListView(this@showReactionPicker).apply {
            divider = null
            choiceMode = ListView.CHOICE_MODE_NONE
        }
        content.addView(
            searchLayout,
            LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT,
                LinearLayout.LayoutParams.WRAP_CONTENT,
            ),
        )
        content.addView(
            listView,
            LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT,
                dp(360),
            ),
        )

        var visibleOptions = options
        val adapter = ArrayAdapter(
            this@showReactionPicker,
            android.R.layout.simple_list_item_1,
            visibleOptions.map { option -> reactionChoiceLabel(post, option) }.toMutableList(),
        )
        fun submitVisibleOptions(query: String) {
            visibleOptions = ReactionPresentation.filteredOptions(options, query)
            adapter.clear()
            adapter.addAll(visibleOptions.map { option -> reactionChoiceLabel(post, option) })
            adapter.notifyDataSetChanged()
        }
        listView.adapter = adapter
        listView.setOnItemLongClickListener { _, _, position, _ ->
            visibleOptions.getOrNull(position)?.let { option ->
                showReactionUsers(post, option.id)
            }
            true
        }
        searchInput.doAfterTextChanged { text ->
            submitVisibleOptions(text?.toString().orEmpty())
        }

        val dialog = AlertDialog.Builder(this@showReactionPicker)
            .setTitle(
                getString(
                    R.string.topic_detail_reaction_title,
                    post.postNumber.toString(),
                ),
            )
            .setView(content)
            .setNegativeButton(android.R.string.cancel, null)
            .create()
        listView.setOnItemClickListener { _, _, position, _ ->
            visibleOptions.getOrNull(position)?.let { option ->
                viewModel?.toggleReaction(post, option.id)
                dialog.dismiss()
            }
        }
        dialog.show()
    }
}

internal fun TopicDetailActivity.reactionChoiceLabel(post: TopicPostState, option: ReactionOption): String {
    val count = post.reactions
        .firstOrNull { it.id.equals(option.id, ignoreCase = true) }
        ?.count
        ?: 0u
    val label = getString(
        R.string.topic_detail_reaction_choice,
        "${option.symbol} ${option.label}",
        count.toString(),
    )
    return if (post.currentUserReaction?.id?.equals(option.id, ignoreCase = true) == true) {
        getString(R.string.topic_detail_reaction_choice_selected, label)
    } else {
        label
    }
}

internal suspend fun TopicDetailActivity.fullReactionOptionsForPost(post: TopicPostState): List<ReactionOption> {
    if (enabledReactionIds.isEmpty()) {
        enabledReactionIds = runCatching {
            sessionStore.snapshot().bootstrap.enabledReactionIds
        }.getOrDefault(emptyList())
        refreshReactionRows()
    }
    return ReactionPresentation.fullOptions(
        reactionIds = enabledReactionIds,
        currentReactionId = post.currentUserReaction?.id,
    )
}

internal fun TopicDetailActivity.loadEnabledReactionIds() {
    lifecycleScope.launch {
        enabledReactionIds = runCatching {
            sessionStore.snapshot().bootstrap.enabledReactionIds
        }.getOrDefault(emptyList())
        refreshReactionRows()
    }
}

internal fun TopicDetailActivity.refreshReactionRows() {
    headerAdapter.refreshRows()
    postListAdapter.refreshRows()
}
