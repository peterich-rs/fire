package com.fire.app.ui.topicdetail

import android.widget.EditText
import android.widget.LinearLayout
import android.widget.Toast
import androidx.appcompat.app.AlertDialog
import androidx.lifecycle.lifecycleScope
import com.fire.app.R
import kotlinx.coroutines.launch
import uniffi.fire_uniffi_topics.PostActionTypeState
import uniffi.fire_uniffi_topics.PostFlagRequestState
import uniffi.fire_uniffi_topics.TopicPostState

internal fun TopicDetailActivity.confirmDeletePost(post: TopicPostState) {
    AlertDialog.Builder(this)
        .setTitle(
            getString(
                R.string.topic_detail_delete_confirm_title,
                post.postNumber.toString(),
            ),
        )
        .setMessage(R.string.topic_detail_delete_confirm_message)
        .setPositiveButton(R.string.topic_detail_delete_post) { _, _ ->
            viewModel?.deletePost(post)
        }
        .setNegativeButton(android.R.string.cancel, null)
        .show()
}

internal fun TopicDetailActivity.confirmRecoverPost(post: TopicPostState) {
    AlertDialog.Builder(this)
        .setTitle(
            getString(
                R.string.topic_detail_recover_confirm_title,
                post.postNumber.toString(),
            ),
        )
        .setMessage(R.string.topic_detail_recover_confirm_message)
        .setPositiveButton(R.string.topic_detail_recover_post) { _, _ ->
            viewModel?.recoverPost(post)
        }
        .setNegativeButton(android.R.string.cancel, null)
        .show()
}

internal fun TopicDetailActivity.showPostEditor(post: TopicPostState) {
    Toast.makeText(this, R.string.topic_detail_edit_post_loading, Toast.LENGTH_SHORT).show()
    lifecycleScope.launch {
        try {
            val editablePost = sessionStore.fetchPost(post.id)
            val raw = editablePost.raw
                ?.takeIf { it.isNotBlank() }
                ?: throw IllegalStateException(getString(R.string.topic_detail_edit_post_error))
            showPostEditorDialog(post, raw)
        } catch (e: Exception) {
            Toast.makeText(
                this@showPostEditor,
                e.localizedMessage ?: getString(R.string.topic_detail_edit_post_error),
                Toast.LENGTH_SHORT,
            ).show()
        }
    }
}

internal fun TopicDetailActivity.showPostEditorDialog(post: TopicPostState, raw: String) {
    val bodyInput = EditText(this).apply {
        setText(raw)
        hint = getString(R.string.topic_detail_edit_post_body_hint)
        minLines = 8
        gravity = android.view.Gravity.TOP
    }
    val reasonInput = EditText(this).apply {
        hint = getString(R.string.topic_detail_edit_post_reason_hint)
        setSingleLine(true)
    }
    val content = LinearLayout(this).apply {
        orientation = LinearLayout.VERTICAL
        setPadding(48, 8, 48, 0)
        addView(bodyInput)
        addView(reasonInput)
    }

    val dialog = AlertDialog.Builder(this)
        .setTitle(getString(R.string.topic_detail_edit_post_title, post.postNumber.toString()))
        .setView(content)
        .setPositiveButton(R.string.topic_detail_edit_save, null)
        .setNegativeButton(android.R.string.cancel, null)
        .create()
    dialog.setOnShowListener {
        dialog.getButton(AlertDialog.BUTTON_POSITIVE).setOnClickListener {
            val nextRaw = bodyInput.text.toString()
            if (nextRaw.isBlank()) {
                Toast.makeText(
                    this,
                    R.string.topic_detail_edit_post_error,
                    Toast.LENGTH_SHORT,
                ).show()
                return@setOnClickListener
            }
            viewModel?.updatePost(
                post = post,
                raw = nextRaw,
                editReason = reasonInput.text.toString(),
            )
            dialog.dismiss()
        }
    }
    dialog.show()
}

internal fun TopicDetailActivity.showFlagPostOptions(post: TopicPostState) {
    lifecycleScope.launch {
        try {
            val options = sessionStore.fetchPostActionTypes()
                .mapNotNull { postFlagOption(it) }
                .ifEmpty { fallbackPostFlagOptions() }
            val labels = options.map { option ->
                if (option.detail.isBlank()) {
                    option.title
                } else {
                    "${option.title}\n${option.detail}"
                }
            }.toTypedArray()
            AlertDialog.Builder(this@showFlagPostOptions)
                .setTitle(
                    getString(
                        R.string.topic_detail_flag_type_title,
                        post.postNumber.toString(),
                    ),
                )
                .setItems(labels) { _, which ->
                    promptFlagPost(post, options[which])
                }
                .setNegativeButton(android.R.string.cancel, null)
                .show()
        } catch (e: Exception) {
            Toast.makeText(
                this@showFlagPostOptions,
                e.localizedMessage ?: getString(R.string.topic_detail_flag_message_required),
                Toast.LENGTH_SHORT,
            ).show()
        }
    }
}

internal fun TopicDetailActivity.postFlagOption(type: PostActionTypeState): PostFlagOption? {
    if (!type.isFlag || !type.enabled) return null
    if (type.appliesTo.isNotEmpty() && !type.appliesTo.contains("Post")) return null

    val detail = type.description.ifBlank { type.shortDescription.orEmpty() }
    return PostFlagOption(
        id = type.id,
        title = type.name.ifBlank { fallbackFlagTitle(type.nameKey, type.id) },
        detail = plainText(detail),
        requireMessage = type.requireMessage,
    )
}

internal fun TopicDetailActivity.fallbackPostFlagOptions(): List<PostFlagOption> {
    return listOf(
        PostFlagOption(3u, "Off topic", "This post is off topic.", false),
        PostFlagOption(4u, "Inappropriate", "This post is inappropriate.", false),
        PostFlagOption(8u, "Spam", "This post looks like spam.", false),
        PostFlagOption(7u, "Notify moderators", "Add details for moderators.", true),
    )
}

internal fun TopicDetailActivity.fallbackFlagTitle(nameKey: String, id: UInt): String {
    return when (nameKey) {
        "off_topic" -> "Off topic"
        "inappropriate" -> "Inappropriate"
        "spam" -> "Spam"
        "notify_moderators" -> "Notify moderators"
        else -> nameKey.ifBlank { "#$id" }
    }
}

internal fun TopicDetailActivity.promptFlagPost(post: TopicPostState, option: PostFlagOption) {
    if (option.requireMessage) {
        val input = EditText(this).apply {
            hint = getString(R.string.topic_detail_flag_message_hint)
            minLines = 3
        }
        AlertDialog.Builder(this)
            .setTitle(getString(R.string.topic_detail_flag_message_title, option.title))
            .setView(input)
            .setPositiveButton(R.string.topic_detail_flag_submit) { _, _ ->
                val message = input.text.toString().trim()
                if (message.isBlank()) {
                    Toast.makeText(
                        this,
                        R.string.topic_detail_flag_message_required,
                        Toast.LENGTH_SHORT,
                    ).show()
                } else {
                    submitFlagPost(post, option, message)
                }
            }
            .setNegativeButton(android.R.string.cancel, null)
            .show()
    } else {
        AlertDialog.Builder(this)
            .setTitle(getString(R.string.topic_detail_flag_confirm_title, option.title))
            .setMessage(option.detail.ifBlank { getString(R.string.topic_detail_flag_confirm_message) })
            .setPositiveButton(R.string.topic_detail_flag_submit) { _, _ ->
                submitFlagPost(post, option, null)
            }
            .setNegativeButton(android.R.string.cancel, null)
            .show()
    }
}

internal fun TopicDetailActivity.submitFlagPost(
    post: TopicPostState,
    option: PostFlagOption,
    message: String?,
) {
    lifecycleScope.launch {
        try {
            sessionStore.flagPost(
                PostFlagRequestState(
                    postId = post.id,
                    flagTypeId = option.id,
                    message = message,
                ),
            )
            Toast.makeText(
                this@submitFlagPost,
                R.string.topic_detail_flag_submitted,
                Toast.LENGTH_SHORT,
            ).show()
        } catch (e: Exception) {
            Toast.makeText(
                this@submitFlagPost,
                e.localizedMessage ?: getString(R.string.topic_detail_action_error),
                Toast.LENGTH_SHORT,
            ).show()
        }
    }
}

internal data class PostFlagOption(
    val id: UInt,
    val title: String,
    val detail: String,
    val requireMessage: Boolean,
)
