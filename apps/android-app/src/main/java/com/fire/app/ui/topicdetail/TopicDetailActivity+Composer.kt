package com.fire.app.ui.topicdetail

import android.view.View
import android.widget.ArrayAdapter
import android.widget.EditText
import android.widget.LinearLayout
import android.widget.Spinner
import android.widget.Toast
import androidx.appcompat.app.AlertDialog
import androidx.lifecycle.lifecycleScope
import com.fire.app.R
import com.fire.app.core.ui.FireToast
import com.fire.app.displayName
import com.fire.app.ui.composer.ComposerTagAssist
import com.fire.app.ui.composer.QuoteMarkdown
import com.fire.app.ui.composer.ReplyComposerSheet
import kotlinx.coroutines.launch
import uniffi.fire_uniffi_session.TopicCategoryState
import uniffi.fire_uniffi_topics.TopicDetailState
import uniffi.fire_uniffi_topics.TopicPostState

internal fun TopicDetailActivity.showReplyComposerForPost(post: TopicPostState) {
    showReplyComposer(replyToPostNumber = post.postNumber.toInt())
}

internal fun TopicDetailActivity.showQuoteReplyComposerForPost(post: TopicPostState) {
    val currentRoute = route ?: return
    val quote = QuoteMarkdown.build(
        username = post.username,
        postNumber = post.postNumber,
        topicId = currentRoute.topicId.toULong(),
        plainText = post.presentation?.plainText().orEmpty(),
    )
    if (quote == null) {
        FireToast.show(binding.root, R.string.topic_detail_quote_empty, FireToast.Style.INFO)
        return
    }
    showReplyComposer(
        replyToPostNumber = post.postNumber.toInt(),
        initialBody = quote,
    )
}

internal fun TopicDetailActivity.showReplyComposer(replyToPostNumber: Int?, initialBody: String? = null) {
    val currentRoute = route ?: return
    val sheet = ReplyComposerSheet.newInstance(
        topicId = currentRoute.topicId,
        replyToPostNumber = replyToPostNumber,
        initialBody = initialBody,
    ) {
        viewModel?.loadTopicDetail(
            topicId = currentRoute.topicId.toULong(),
            targetPostNumber = replyToPostNumber?.toUInt(),
        )
    }
    sheet.show(supportFragmentManager, "reply_composer")
}

internal fun TopicDetailActivity.showTopicEditor(detail: TopicDetailState) {
    lifecycleScope.launch {
        try {
            val session = sessionStore.snapshot()
            val currentCategoryId = detail.categoryId
            val categories = session.bootstrap.categories.filter { category ->
                category.id == currentCategoryId ||
                    category.permission?.toInt()?.let { it <= 1 } ?: true
            }
            if (categories.isEmpty()) {
                Toast.makeText(
                    this@showTopicEditor,
                    R.string.topic_detail_edit_topic_no_categories,
                    Toast.LENGTH_SHORT,
                ).show()
                return@launch
            }
            showTopicEditorDialog(
                detail = detail,
                categories = categories,
                minTitleLength = session.bootstrap.minTopicTitleLength.toInt().coerceAtLeast(1),
            )
        } catch (e: Exception) {
            Toast.makeText(
                this@showTopicEditor,
                e.localizedMessage ?: getString(R.string.topic_detail_edit_topic_error),
                Toast.LENGTH_SHORT,
            ).show()
        }
    }
}

internal fun TopicDetailActivity.showTopicEditorDialog(
    detail: TopicDetailState,
    categories: List<TopicCategoryState>,
    minTitleLength: Int,
) {
    val titleInput = EditText(this).apply {
        setText(detail.title.trim())
        hint = getString(R.string.topic_detail_edit_topic_title_hint)
        setSingleLine(true)
    }
    val categorySpinner = Spinner(this).apply {
        adapter = ArrayAdapter(
            this@showTopicEditorDialog,
            android.R.layout.simple_spinner_item,
            categories.map { it.displayName() },
        ).apply {
            setDropDownViewResource(android.R.layout.simple_spinner_dropdown_item)
        }
        val selectedIndex = categories.indexOfFirst { it.id == detail.categoryId }
        if (selectedIndex >= 0) {
            setSelection(selectedIndex)
        }
    }
    val tagsInput = EditText(this).apply {
        setText(detail.tags.joinToString(" ") { it.name })
        hint = getString(R.string.topic_detail_edit_topic_tags_hint)
        setSingleLine(true)
    }
    val tagSuggestions = LinearLayout(this).apply {
        orientation = LinearLayout.VERTICAL
        visibility = View.GONE
    }
    val content = LinearLayout(this).apply {
        orientation = LinearLayout.VERTICAL
        setPadding(48, 8, 48, 0)
        addView(titleInput)
        addView(categorySpinner)
        addView(tagsInput)
        addView(tagSuggestions)
    }
    ComposerTagAssist(
        input = tagsInput,
        suggestions = tagSuggestions,
        sessionStore = sessionStore,
        scope = lifecycleScope,
        categoryIdProvider = { categories.getOrNull(categorySpinner.selectedItemPosition)?.id },
        selectedTagsProvider = {
            tagsInput.text.toString()
                .split("[,\\s]+".toRegex())
                .filter { it.isNotBlank() }
        },
    ).attach()

    val dialog = AlertDialog.Builder(this)
        .setTitle(R.string.topic_detail_edit_topic_title)
        .setView(content)
        .setPositiveButton(R.string.topic_detail_edit_save, null)
        .setNegativeButton(android.R.string.cancel, null)
        .create()
    dialog.setOnShowListener {
        dialog.getButton(AlertDialog.BUTTON_POSITIVE).setOnClickListener {
            val title = titleInput.text.toString().trim()
            val category = categories.getOrNull(categorySpinner.selectedItemPosition)
            val tags = tagsInput.text.toString()
                .split("[,\\s]+".toRegex())
                .filter { it.isNotBlank() }

            if (title.length < minTitleLength) {
                Toast.makeText(
                    this,
                    getString(
                        R.string.topic_detail_edit_topic_title_min_length,
                        minTitleLength.toString(),
                    ),
                    Toast.LENGTH_SHORT,
                ).show()
                return@setOnClickListener
            }
            if (category == null) {
                Toast.makeText(
                    this,
                    R.string.topic_detail_edit_topic_category_required,
                    Toast.LENGTH_SHORT,
                ).show()
                return@setOnClickListener
            }
            if (tags.size < category.minimumRequiredTags.toInt()) {
                Toast.makeText(
                    this,
                    getString(
                        R.string.topic_detail_edit_topic_tags_required,
                        category.minimumRequiredTags.toString(),
                    ),
                    Toast.LENGTH_SHORT,
                ).show()
                return@setOnClickListener
            }
            val disallowedTags = if (category.allowedTags.isEmpty()) {
                emptyList()
            } else {
                tags.filterNot { tag -> category.allowedTags.contains(tag) }
            }
            if (disallowedTags.isNotEmpty()) {
                Toast.makeText(
                    this,
                    getString(
                        R.string.topic_detail_edit_topic_tags_not_allowed,
                        disallowedTags.joinToString(", "),
                    ),
                    Toast.LENGTH_SHORT,
                ).show()
                return@setOnClickListener
            }
            viewModel?.updateTopic(title, category.id, tags)
            dialog.dismiss()
        }
    }
    dialog.show()
}
