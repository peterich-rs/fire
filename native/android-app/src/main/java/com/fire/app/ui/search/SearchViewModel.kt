package com.fire.app.ui.search

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.fire.app.core.error.FireErrorReporter
import com.fire.app.data.repository.SearchRepository
import com.fire.app.session.FireSessionStore
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Job
import kotlinx.coroutines.FlowPreview
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.debounce
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.launch
import uniffi.fire_uniffi_search.SearchResultState
import uniffi.fire_uniffi_search.SearchTypeFilterState

@OptIn(FlowPreview::class)
class SearchViewModel(
    private val repository: SearchRepository,
    private val sessionStore: FireSessionStore,
) : ViewModel() {

    private val _query = MutableStateFlow("")
    val query = _query.asStateFlow()

    private val _typeFilter = MutableStateFlow<SearchTypeFilterState?>(null)
    val typeFilter = _typeFilter.asStateFlow()

    private val _results = MutableStateFlow<SearchResultState?>(null)
    val results = _results.asStateFlow()

    private val _isLoading = MutableStateFlow(false)
    val isLoading = _isLoading.asStateFlow()

    private val _isLoadingMore = MutableStateFlow(false)
    val isLoadingMore = _isLoadingMore.asStateFlow()

    private val _error = MutableStateFlow<String?>(null)
    val error = _error.asStateFlow()

    private var searchJob: Job? = null
    private var activeGeneration = 0
    private var loadedPage = 1u

    init {
        viewModelScope.launch {
            _query
                .debounce(400)
                .distinctUntilChanged()
                .collect { q ->
                    if (q.isNotBlank()) {
                        performSearch(q, _typeFilter.value)
                    } else {
                        clearResults()
                    }
                }
        }
    }

    fun setQuery(q: String) {
        _query.value = q
    }

    fun setTypeFilter(filter: SearchTypeFilterState?) {
        _typeFilter.value = filter
        if (_query.value.isNotBlank()) {
            performSearch(_query.value, filter)
        }
    }

    fun loadMore() {
        val current = _results.value ?: return
        val query = _query.value.trim().takeIf { it.isNotEmpty() } ?: return
        if (_isLoading.value || _isLoadingMore.value || !current.groupedResult.moreFullPageResults) {
            return
        }
        val generation = activeGeneration
        val nextPage = loadedPage + 1u
        viewModelScope.launch {
            _isLoadingMore.value = true
            _error.value = null
            try {
                val more = repository.search(query, nextPage, _typeFilter.value)
                if (generation == activeGeneration) {
                    _results.value = mergeResults(current, more)
                    loadedPage = nextPage
                }
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                handleError(e)
            } finally {
                _isLoadingMore.value = false
            }
        }
    }

    private fun performSearch(q: String, filter: SearchTypeFilterState?) {
        val normalizedQuery = q.trim()
        if (normalizedQuery.isEmpty()) {
            clearResults()
            return
        }

        activeGeneration += 1
        val generation = activeGeneration
        searchJob?.cancel()
        searchJob = viewModelScope.launch {
            _isLoading.value = true
            _isLoadingMore.value = false
            _error.value = null
            try {
                val result = repository.search(normalizedQuery, null, filter)
                if (generation == activeGeneration) {
                    loadedPage = 1u
                    _results.value = result
                }
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                handleError(e)
            } finally {
                if (generation == activeGeneration) {
                    _isLoading.value = false
                }
            }
        }
    }

    private fun clearResults() {
        activeGeneration += 1
        searchJob?.cancel()
        loadedPage = 1u
        _isLoading.value = false
        _isLoadingMore.value = false
        _error.value = null
        _results.value = null
    }

    private fun mergeResults(
        current: SearchResultState,
        more: SearchResultState,
    ): SearchResultState {
        return SearchResultState(
            posts = (current.posts + more.posts).distinctBy { it.id },
            topics = (current.topics + more.topics).distinctBy { it.id },
            users = (current.users + more.users).distinctBy { it.id },
            groupedResult = more.groupedResult,
        )
    }

    private fun handleError(error: Exception, showMessage: Boolean = true) {
        val reported = FireErrorReporter.report(
            operation = "search.query",
            error = error,
            sessionStore = sessionStore,
        )
        if (showMessage) {
            _error.value = reported.displayMessage
        }
    }

    companion object {
        fun create(sessionStore: FireSessionStore): SearchViewModel {
            val repo = SearchRepository(sessionStore)
            return SearchViewModel(repo, sessionStore)
        }
    }
}
