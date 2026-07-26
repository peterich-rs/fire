package com.fire.app.session

import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.SharedFlow
import kotlinx.coroutines.flow.asSharedFlow
import uniffi.fire_uniffi_session.CloudflareClearanceResolvedEventState
import uniffi.fire_uniffi_session.CloudflareClearanceResolvedHandler

/**
 * Process-wide bus for Rust Cloudflare clearance-resolved events.
 * Home / MessageBus / CF banners subscribe here after challenge success.
 */
object FireClearanceResolvedRepository : CloudflareClearanceResolvedHandler {
    private val _events = MutableSharedFlow<CloudflareClearanceResolvedEventState>(
        extraBufferCapacity = 8,
    )
    val events: SharedFlow<CloudflareClearanceResolvedEventState> = _events.asSharedFlow()

    override fun onClearanceResolved(event: CloudflareClearanceResolvedEventState) {
        _events.tryEmit(event)
    }
}
