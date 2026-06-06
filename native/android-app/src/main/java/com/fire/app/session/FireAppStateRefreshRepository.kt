package com.fire.app.session

import kotlinx.coroutines.channels.BufferOverflow
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.SharedFlow
import kotlinx.coroutines.flow.asSharedFlow
import uniffi.fire_uniffi_session.AppStateRefreshEventState
import uniffi.fire_uniffi_session.AppStateRefreshHandler

object FireAppStateRefreshRepository : AppStateRefreshHandler {
    private val _events = MutableSharedFlow<AppStateRefreshEventState>(
        replay = 1,
        extraBufferCapacity = 8,
        onBufferOverflow = BufferOverflow.DROP_OLDEST,
    )

    val events: SharedFlow<AppStateRefreshEventState> = _events.asSharedFlow()

    override fun onAppStateRefreshEvent(event: AppStateRefreshEventState) {
        _events.tryEmit(event)
    }
}
