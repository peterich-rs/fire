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
import uniffi.fire_uniffi_search.TagSearchQueryState

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
