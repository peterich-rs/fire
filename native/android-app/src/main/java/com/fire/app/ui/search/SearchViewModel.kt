package com.fire.app.ui.search

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.fire.app.cloudflare.CloudflareChallengeDetector
import com.fire.app.data.repository.SearchRepository
import com.fire.app.session.FireSessionStore
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asSharedFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.debounce
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.launch
import uniffi.fire_uniffi_search.SearchResultState
import uniffi.fire_uniffi_search.SearchTypeFilterState

class SearchViewModel(
    private val repository: SearchRepository,
) : ViewModel() {

    private val _query = MutableStateFlow("")
    val query = _query.asStateFlow()

    private val _typeFilter = MutableStateFlow<SearchTypeFilterState?>(null)
    val typeFilter = _typeFilter.asStateFlow()

    private val _results = MutableStateFlow<SearchResultState?>(null)
    val results = _results.asStateFlow()

    private val _isLoading = MutableStateFlow(false)
    val isLoading = _isLoading.asStateFlow()

    private val _error = MutableStateFlow<String?>(null)
    val error = _error.asStateFlow()

    private val _cloudflareChallenge = MutableSharedFlow<Unit>(extraBufferCapacity = 1)
    val cloudflareChallenge = _cloudflareChallenge.asSharedFlow()

    init {
        viewModelScope.launch {
            _query
                .debounce(400)
                .distinctUntilChanged()
                .collect { q ->
                    if (q.isNotBlank()) {
                        performSearch(q, _typeFilter.value)
                    } else {
                        _results.value = null
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
        val grouped = current.groupedResult
        if (!grouped.moreFullPageResults) return
        val nextPage = (_results.value?.posts?.size?.div(30)?.plus(1))?.toUInt() ?: return
        viewModelScope.launch {
            try {
                val more = repository.search(_query.value, nextPage, _typeFilter.value)
                val merged = SearchResultState(
                    posts = current.posts + more.posts,
                    topics = current.topics + more.topics,
                    users = current.users + more.users,
                    groupedResult = more.groupedResult,
                )
                _results.value = merged
            } catch (e: Exception) {
                handleError(e, showMessage = false)
            }
        }
    }

    private fun performSearch(q: String, filter: SearchTypeFilterState?) {
        viewModelScope.launch {
            _isLoading.value = true
            _error.value = null
            try {
                val result = repository.search(q, null, filter)
                _results.value = result
            } catch (e: Exception) {
                handleError(e)
            } finally {
                _isLoading.value = false
            }
        }
    }

    private fun handleError(error: Exception, showMessage: Boolean = true) {
        if (CloudflareChallengeDetector.isChallenge(error)) {
            _cloudflareChallenge.tryEmit(Unit)
            if (showMessage) {
                _error.value = null
            }
        } else if (showMessage) {
            _error.value = error.message
        }
    }

    companion object {
        fun create(sessionStore: FireSessionStore): SearchViewModel {
            val repo = SearchRepository(sessionStore)
            return SearchViewModel(repo)
        }
    }
}
