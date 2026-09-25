package com.fire.app.ui.composer

import android.text.Editable
import android.text.TextWatcher
import android.view.View
import android.widget.EditText
import android.widget.LinearLayout
import com.fire.app.session.FireSessionStore
import com.google.android.material.chip.Chip
import com.google.android.material.chip.ChipGroup
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import uniffi.fire_uniffi_search.UserMentionQueryState

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
