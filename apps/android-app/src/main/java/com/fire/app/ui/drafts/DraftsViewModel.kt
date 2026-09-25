package com.fire.app.ui.drafts

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import androidx.paging.Pager
import androidx.paging.PagingConfig
import androidx.paging.PagingData
import androidx.paging.cachedIn
import com.fire.app.core.error.FireErrorReporter
import com.fire.app.data.paging.DraftsPagingSource
import com.fire.app.session.FireSessionStore
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import uniffi.fire_uniffi_types.DraftState

class DraftsViewModel(
    private val sessionStore: FireSessionStore,
) : ViewModel() {

    private val _error = MutableStateFlow<String?>(null)
    val error = _error.asStateFlow()

    val draftsPagingFlow: Flow<PagingData<DraftState>> = Pager(
        config = PagingConfig(
            pageSize = 30,
            prefetchDistance = 10,
            enablePlaceholders = false,
        ),
        pagingSourceFactory = { DraftsPagingSource(sessionStore) },
    ).flow.cachedIn(viewModelScope)

    fun clearError() {
        _error.value = null
    }

    fun deleteDraft(draft: DraftState, onDeleted: () -> Unit) {
        viewModelScope.launch {
            try {
                sessionStore.deleteDraft(draft.draftKey, draft.sequence)
                onDeleted()
            } catch (error: CancellationException) {
                throw error
            } catch (error: Exception) {
                val reported = FireErrorReporter.report(
                    operation = "drafts.delete",
                    error = error,
                    sessionStore = sessionStore,
                    fallbackMessage = "Unable to delete draft.",
                )
                _error.value = reported.displayMessage
            }
        }
    }

    companion object {
        fun create(sessionStore: FireSessionStore): DraftsViewModel {
            return DraftsViewModel(sessionStore)
        }
    }
}
