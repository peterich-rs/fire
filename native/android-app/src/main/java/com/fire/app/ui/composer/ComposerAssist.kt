package com.fire.app.ui.composer

import android.content.Context
import android.net.Uri
import android.provider.OpenableColumns
import android.text.Editable
import android.text.TextWatcher
import android.view.View
import android.widget.EditText
import android.widget.LinearLayout
import android.widget.TextView
import com.fire.app.R
import com.fire.app.session.FireSessionStore
import com.google.android.material.chip.Chip
import com.google.android.material.chip.ChipGroup
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import uniffi.fire_uniffi_search.TagSearchQueryState
import uniffi.fire_uniffi_search.UserMentionQueryState
import uniffi.fire_uniffi_topics.UploadImageRequestState
import uniffi.fire_uniffi_topics.UploadResultState

class ComposerMentionAssist(
    private val input: EditText,
    private val suggestions: LinearLayout,
    private val sessionStore: FireSessionStore,
    private val scope: CoroutineScope,
    private val includeGroups: Boolean,
    private val topicId: ULong? = null,
    private val categoryIdProvider: () -> ULong? = { null },
) {
    private var searchJob: Job? = null
    private var applyingSuggestion = false

    fun attach() {
        input.addTextChangedListener(object : TextWatcher {
            override fun beforeTextChanged(s: CharSequence?, start: Int, count: Int, after: Int) = Unit
            override fun onTextChanged(s: CharSequence?, start: Int, before: Int, count: Int) = scheduleSearch()
            override fun afterTextChanged(s: Editable?) = Unit
        })
    }

    private fun scheduleSearch() {
        if (applyingSuggestion) return
        val context = mentionContext() ?: run {
            hideSuggestions()
            return
        }
        searchJob?.cancel()
        searchJob = scope.launch {
            delay(200)
            val result = runCatching {
                sessionStore.searchUsers(
                    UserMentionQueryState(
                        term = context.term,
                        includeGroups = includeGroups,
                        limit = 8u,
                        topicId = topicId,
                        categoryId = categoryIdProvider(),
                    ),
                )
            }.getOrNull()
            val items = buildList {
                result?.users.orEmpty().forEach { user ->
                    val display = user.name?.takeIf { it.isNotBlank() } ?: user.username
                    add(Suggestion(label = "$display @${user.username}", value = user.username))
                }
                result?.groups.orEmpty().forEach { group ->
                    val display = group.fullName?.takeIf { it.isNotBlank() } ?: group.name
                    add(Suggestion(label = "$display @${group.name}", value = group.name))
                }
            }.take(8)
            input.post {
                val latest = mentionContext()
                if (latest?.term == context.term) {
                    showSuggestions(items, latest)
                }
            }
        }
    }

    private fun showSuggestions(items: List<Suggestion>, context: TextContext) {
        suggestions.removeAllViews()
        suggestions.visibility = if (items.isEmpty()) View.GONE else View.VISIBLE
        items.forEach { item ->
            suggestions.addView(suggestionView(input.context, item.label) {
                applyingSuggestion = true
                input.text.replace(context.start, context.end, "@${item.value} ")
                input.setSelection((context.start + item.value.length + 2).coerceAtMost(input.text.length))
                applyingSuggestion = false
                hideSuggestions()
            })
        }
    }

    private fun hideSuggestions() {
        suggestions.removeAllViews()
        suggestions.visibility = View.GONE
    }

    private fun mentionContext(): TextContext? {
        val cursor = input.selectionStart.coerceAtLeast(0)
        val text = input.text.toString()
        if (cursor > text.length) return null
        val prefix = text.substring(0, cursor)
        val atIndex = prefix.lastIndexOf('@')
        if (atIndex < 0) return null
        if (atIndex > 0 && !prefix[atIndex - 1].isWhitespace()) return null
        val term = prefix.substring(atIndex + 1)
        if (term.length !in 1..30 || term.any { it.isWhitespace() }) return null
        return TextContext(start = atIndex, end = cursor, term = term)
    }
}

class ComposerTagAssist(
    private val input: EditText,
    private val suggestions: LinearLayout,
    private val sessionStore: FireSessionStore,
    private val scope: CoroutineScope,
    private val categoryIdProvider: () -> ULong?,
    private val selectedTagsProvider: () -> List<String>,
) {
    private var searchJob: Job? = null
    private var applyingSuggestion = false

    fun attach() {
        input.addTextChangedListener(object : TextWatcher {
            override fun beforeTextChanged(s: CharSequence?, start: Int, count: Int, after: Int) = Unit
            override fun onTextChanged(s: CharSequence?, start: Int, before: Int, count: Int) = scheduleSearch()
            override fun afterTextChanged(s: Editable?) = Unit
        })
    }

    private fun scheduleSearch() {
        if (applyingSuggestion) return
        val context = tagContext() ?: run {
            hideSuggestions()
            return
        }
        searchJob?.cancel()
        searchJob = scope.launch {
            delay(250)
            val result = runCatching {
                sessionStore.searchTags(
                    TagSearchQueryState(
                        q = context.term,
                        filterForInput = true,
                        limit = 8u,
                        categoryId = categoryIdProvider(),
                        selectedTags = selectedTagsProvider(),
                    ),
                )
            }.getOrNull()
            val items = result?.results.orEmpty()
                .map { item ->
                    val label = item.text.takeIf { it.isNotBlank() } ?: item.name
                    Suggestion(label = "$label (${item.count})", value = item.name)
                }
                .take(8)
            input.post {
                val latest = tagContext()
                if (latest?.term == context.term) {
                    showSuggestions(items, latest)
                }
            }
        }
    }

    private fun showSuggestions(items: List<Suggestion>, context: TextContext) {
        suggestions.removeAllViews()
        suggestions.visibility = if (items.isEmpty()) View.GONE else View.VISIBLE
        items.forEach { item ->
            suggestions.addView(suggestionView(input.context, item.label) {
                applyingSuggestion = true
                input.text.replace(context.start, context.end, item.value)
                input.text.insert((context.start + item.value.length).coerceAtMost(input.text.length), " ")
                applyingSuggestion = false
                hideSuggestions()
            })
        }
    }

    private fun hideSuggestions() {
        suggestions.removeAllViews()
        suggestions.visibility = View.GONE
    }

    private fun tagContext(): TextContext? {
        val cursor = input.selectionStart.coerceAtLeast(0)
        val text = input.text.toString()
        if (cursor > text.length) return null
        val prefix = text.substring(0, cursor)
        val separator = maxOf(prefix.lastIndexOf(' '), prefix.lastIndexOf(','), prefix.lastIndexOf('\n'))
        val start = separator + 1
        val term = prefix.substring(start).trim()
        if (term.length !in 1..30) return null
        return TextContext(start = start, end = cursor, term = term)
    }
}

class ComposerRecipientAssist(
    private val input: EditText,
    private val suggestions: LinearLayout,
    private val sessionStore: FireSessionStore,
    private val scope: CoroutineScope,
) {
    private var searchJob: Job? = null
    private var applyingSuggestion = false

    fun attach() {
        input.addTextChangedListener(object : TextWatcher {
            override fun beforeTextChanged(s: CharSequence?, start: Int, count: Int, after: Int) = Unit
            override fun onTextChanged(s: CharSequence?, start: Int, before: Int, count: Int) = scheduleSearch()
            override fun afterTextChanged(s: Editable?) = Unit
        })
    }

    private fun scheduleSearch() {
        if (applyingSuggestion) return
        val context = recipientContext() ?: run {
            hideSuggestions()
            return
        }
        searchJob?.cancel()
        searchJob = scope.launch {
            delay(200)
            val result = runCatching {
                sessionStore.searchUsers(
                    UserMentionQueryState(
                        term = context.term,
                        includeGroups = false,
                        limit = 8u,
                        topicId = null,
                        categoryId = null,
                    ),
                )
            }.getOrNull()
            val items = result?.users.orEmpty()
                .map { user ->
                    val display = user.name?.takeIf { it.isNotBlank() } ?: user.username
                    Suggestion(label = "$display @${user.username}", value = user.username)
                }
                .take(8)
            input.post {
                val latest = recipientContext()
                if (latest?.term == context.term) {
                    showSuggestions(items, latest)
                }
            }
        }
    }

    private fun showSuggestions(items: List<Suggestion>, context: TextContext) {
        suggestions.removeAllViews()
        suggestions.visibility = if (items.isEmpty()) View.GONE else View.VISIBLE
        items.forEach { item ->
            suggestions.addView(suggestionView(input.context, item.label) {
                applyingSuggestion = true
                input.text.replace(context.start, context.end, item.value)
                input.text.insert((context.start + item.value.length).coerceAtMost(input.text.length), " ")
                input.setSelection(input.text.length)
                applyingSuggestion = false
                hideSuggestions()
            })
        }
    }

    private fun hideSuggestions() {
        suggestions.removeAllViews()
        suggestions.visibility = View.GONE
    }

    private fun recipientContext(): TextContext? {
        val cursor = input.selectionStart.coerceAtLeast(0)
        val text = input.text.toString()
        if (cursor > text.length) return null
        val prefix = text.substring(0, cursor)
        val separator = maxOf(prefix.lastIndexOf(' '), prefix.lastIndexOf(','), prefix.lastIndexOf('\n'))
        val start = separator + 1
        val term = prefix.substring(start).trim().removePrefix("@")
        if (term.length !in 1..30 || term.any { it.isWhitespace() }) return null
        return TextContext(start = start, end = cursor, term = term)
    }
}

class ComposerRecipientTokenView(
    private val input: EditText,
    private val tokens: ChipGroup,
) {
    private var applyingTokenChange = false

    fun attach() {
        input.addTextChangedListener(object : TextWatcher {
            override fun beforeTextChanged(s: CharSequence?, start: Int, count: Int, after: Int) = Unit
            override fun onTextChanged(s: CharSequence?, start: Int, before: Int, count: Int) = render()
            override fun afterTextChanged(s: Editable?) = Unit
        })
        render()
    }

    private fun render() {
        if (applyingTokenChange) return
        val recipients = recipientValues()
        tokens.removeAllViews()
        tokens.visibility = if (recipients.isEmpty()) View.GONE else View.VISIBLE
        recipients.forEach { recipient ->
            tokens.addView(
                Chip(input.context).apply {
                    text = "@$recipient"
                    isCloseIconVisible = true
                    setOnCloseIconClickListener {
                        removeRecipient(recipient)
                    }
                },
            )
        }
    }

    private fun removeRecipient(username: String) {
        applyingTokenChange = true
        val remaining = recipientValues()
            .filterNot { it.equals(username, ignoreCase = true) }
        input.setText(remaining.joinToString(" "))
        input.setSelection(input.text.length)
        applyingTokenChange = false
        render()
    }

    private fun recipientValues(): List<String> =
        input.text.toString()
            .split("[,\\s]+".toRegex())
            .map { it.trim().removePrefix("@") }
            .filter { it.isNotBlank() }
            .distinctBy { it.lowercase() }
}

class ComposerDraftAutosave(
    private val scope: CoroutineScope,
    private val saveDraft: suspend () -> Unit,
    private val onSaveFailed: (Exception) -> Unit = {},
) {
    private var enabled = false
    private var saveJob: Job? = null

    fun attach(vararg inputs: EditText) {
        val watcher = object : TextWatcher {
            override fun beforeTextChanged(s: CharSequence?, start: Int, count: Int, after: Int) = Unit
            override fun onTextChanged(s: CharSequence?, start: Int, before: Int, count: Int) = schedule()
            override fun afterTextChanged(s: Editable?) = Unit
        }
        inputs.forEach { input -> input.addTextChangedListener(watcher) }
    }

    fun start() {
        enabled = true
    }

    fun schedule() {
        if (!enabled) return
        saveJob?.cancel()
        saveJob = scope.launch {
            delay(1_200)
            saveDraftSafely()
        }
    }

    fun flush() {
        if (!enabled) return
        saveJob?.cancel()
        saveJob = scope.launch {
            saveDraftSafely()
        }
    }

    fun cancel() {
        enabled = false
        saveJob?.cancel()
        saveJob = null
    }

    private suspend fun saveDraftSafely() {
        try {
            saveDraft()
        } catch (error: CancellationException) {
            throw error
        } catch (error: Exception) {
            onSaveFailed(error)
        }
    }
}

suspend fun uploadImageMarkdown(
    context: Context,
    sessionStore: FireSessionStore,
    uri: Uri,
): String {
    val resolver = context.contentResolver
    val bytes = resolver.openInputStream(uri)?.use { it.readBytes() }
        ?: error(context.getString(R.string.composer_upload_error))
    val mimeType = resolver.getType(uri)
    val fileName = displayName(context, uri) ?: "image-${System.currentTimeMillis()}"
    val result = sessionStore.uploadImage(
        UploadImageRequestState(
            fileName = fileName,
            mimeType = mimeType,
            bytes = bytes,
        ),
    )
    return markdownForUpload(result)
}

fun insertMarkdownAtCursor(input: EditText, markdown: String) {
    val start = input.selectionStart.coerceAtLeast(0)
    val end = input.selectionEnd.coerceAtLeast(start)
    val prefix = if (start == 0 || input.text.getOrNull(start - 1) == '\n') "" else "\n"
    val suffix = if (end >= input.text.length || input.text.getOrNull(end) == '\n') "\n" else "\n\n"
    input.text.replace(start, end, "$prefix$markdown$suffix")
    input.setSelection((start + prefix.length + markdown.length + suffix.length).coerceAtMost(input.text.length))
}

private fun markdownForUpload(result: UploadResultState): String {
    val alt = result.originalFilename?.takeIf { it.isNotBlank() } ?: "image"
    val width = result.thumbnailWidth ?: result.width
    val height = result.thumbnailHeight ?: result.height
    return if (width != null && height != null) {
        "![$alt|${width}x$height](${result.shortUrl})"
    } else {
        "![$alt](${result.shortUrl})"
    }
}

private fun displayName(context: Context, uri: Uri): String? {
    return context.contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)
        ?.use { cursor ->
            val index = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME)
            if (index >= 0 && cursor.moveToFirst()) cursor.getString(index) else null
        }
}

private fun suggestionView(context: Context, label: String, onClick: () -> Unit): TextView {
    return TextView(context).apply {
        text = label
        setTextAppearance(androidx.appcompat.R.style.TextAppearance_AppCompat_Caption)
        setTextColor(context.getColor(R.color.fire_accent))
        setPadding(0, 8, 0, 8)
        setOnClickListener { onClick() }
    }
}

private data class Suggestion(val label: String, val value: String)

private data class TextContext(val start: Int, val end: Int, val term: String)
