package com.fire.app.ui.composer

import android.text.Editable
import android.text.TextWatcher
import android.view.View
import android.widget.EditText
import android.widget.LinearLayout
import com.fire.app.session.FireSessionStore
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import uniffi.fire_uniffi_search.UserMentionQueryState

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
