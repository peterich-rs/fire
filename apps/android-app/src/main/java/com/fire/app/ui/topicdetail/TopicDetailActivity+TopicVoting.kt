package com.fire.app.ui.topicdetail

import android.widget.Toast
import androidx.appcompat.app.AlertDialog
import androidx.lifecycle.lifecycleScope
import com.fire.app.R
import kotlinx.coroutines.launch
import uniffi.fire_uniffi_topics.TopicDetailState
import uniffi.fire_uniffi_topics.VotedUserState

internal fun TopicDetailActivity.updateTopicNotificationToolbar(detail: TopicDetailState?) {
    val item = notificationMenuItem ?: return
    val isPrivateMessageThread = detail?.archetype
        ?.trim()
        ?.equals("private_message", ignoreCase = true) == true
    item.isVisible = detail != null && !isPrivateMessageThread
    if (detail == null || isPrivateMessageThread) return

    val level = detail.details.notificationLevel ?: 1
    val title = topicNotificationTitle(level)
    item.title = getString(R.string.topic_detail_notification_button, title)
    item.setIcon(topicNotificationIcon(level))
    item.isEnabled = true
}

internal fun TopicDetailActivity.topicNotificationTitle(level: Int): String {
    return when (level) {
        0 -> getString(R.string.topic_detail_notification_muted)
        2 -> getString(R.string.topic_detail_notification_tracking)
        3 -> getString(R.string.topic_detail_notification_watching)
        else -> getString(R.string.topic_detail_notification_regular)
    }
}

internal fun TopicDetailActivity.topicNotificationIcon(level: Int): Int {
    return when (level) {
        0 -> R.drawable.ic_notifications_off
        2, 3 -> R.drawable.ic_notifications_active
        else -> R.drawable.ic_notifications
    }
}

internal fun TopicDetailActivity.showTopicNotificationOptions(detail: TopicDetailState) {
    val options = listOf(
        TopicNotificationOption(
            level = 0,
            title = getString(R.string.topic_detail_notification_muted),
        ),
        TopicNotificationOption(
            level = 1,
            title = getString(R.string.topic_detail_notification_regular),
        ),
        TopicNotificationOption(
            level = 2,
            title = getString(R.string.topic_detail_notification_tracking),
        ),
        TopicNotificationOption(
            level = 3,
            title = getString(R.string.topic_detail_notification_watching),
        ),
    )
    val labels = options.map { option ->
        option.title
    }.toTypedArray()
    val selectedIndex = options.indexOfFirst {
        it.level == (detail.details.notificationLevel ?: 1)
    }.coerceAtLeast(0)

    AlertDialog.Builder(this)
        .setTitle(R.string.topic_detail_notification_title)
        .setSingleChoiceItems(labels, selectedIndex) { dialog, which ->
            viewModel?.setTopicNotificationLevel(options[which].level)
            dialog.dismiss()
        }
        .setNegativeButton(android.R.string.cancel, null)
        .show()
}

internal fun TopicDetailActivity.showTopicVoters(detail: TopicDetailState) {
    Toast.makeText(
        this,
        R.string.topic_detail_vote_voters_loading,
        Toast.LENGTH_SHORT,
    ).show()
    lifecycleScope.launch {
        try {
            val voters = sessionStore.fetchTopicVoters(detail.id)
            showTopicVotersDialog(voters)
        } catch (e: Exception) {
            Toast.makeText(
                this@showTopicVoters,
                e.localizedMessage ?: getString(R.string.topic_detail_vote_voters_empty),
                Toast.LENGTH_SHORT,
            ).show()
        }
    }
}

internal fun TopicDetailActivity.showTopicVotersDialog(voters: List<VotedUserState>) {
    if (voters.isEmpty()) {
        AlertDialog.Builder(this)
            .setTitle(R.string.topic_detail_vote_voters_title)
            .setMessage(R.string.topic_detail_vote_voters_empty)
            .setPositiveButton(android.R.string.ok, null)
            .show()
        return
    }

    val labels = voters.map { topicVoterLabel(it) }.toTypedArray()
    AlertDialog.Builder(this)
        .setTitle(R.string.topic_detail_vote_voters_title)
        .setItems(labels) { _, which ->
            voters.getOrNull(which)?.username?.let { showUserInfoSheet(it) }
        }
        .setPositiveButton(android.R.string.ok, null)
        .show()
}

internal fun TopicDetailActivity.topicVoterLabel(voter: VotedUserState): String {
    val displayName = voter.name?.takeIf { it.isNotBlank() } ?: voter.username
    return "$displayName\n@${voter.username}"
}

internal data class TopicNotificationOption(
    val level: Int,
    val title: String,
)
