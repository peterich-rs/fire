package com.fire.app.data.repository

import com.fire.app.session.FireSessionStore
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import uniffi.fire_uniffi_search.SearchQueryState
import uniffi.fire_uniffi_search.SearchResultState
import uniffi.fire_uniffi_search.SearchTypeFilterState

class SearchRepository(private val sessionStore: FireSessionStore) {

    suspend fun search(
        query: String,
        page: UInt? = null,
        typeFilter: SearchTypeFilterState? = null,
    ): SearchResultState = withContext(Dispatchers.IO) {
        sessionStore.search(
            SearchQueryState(
                q = query,
                page = page,
                typeFilter = typeFilter,
            ),
        )
    }
}
