package com.fire.app.session

import kotlinx.coroutines.channels.BufferOverflow
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.SharedFlow
import kotlinx.coroutines.flow.asSharedFlow
import uniffi.fire_uniffi.StateObserver
import uniffi.fire_uniffi_notifications.NotificationCenterState
import uniffi.fire_uniffi_session.SessionState
import uniffi.fire_uniffi_types.TopicListState

object FireStateObserverRepository : StateObserver {
    private val _sessionSnapshots = MutableSharedFlow<SessionState>(
        replay = 1,
        extraBufferCapacity = 4,
        onBufferOverflow = BufferOverflow.DROP_OLDEST,
    )
    val sessionSnapshots: SharedFlow<SessionState> = _sessionSnapshots.asSharedFlow()

    private val _topicListSnapshots = MutableSharedFlow<TopicListState>(
        replay = 1,
        extraBufferCapacity = 4,
        onBufferOverflow = BufferOverflow.DROP_OLDEST,
    )
    val topicListSnapshots: SharedFlow<TopicListState> = _topicListSnapshots.asSharedFlow()

    private val _notificationCenterSnapshots = MutableSharedFlow<NotificationCenterState>(
        replay = 1,
        extraBufferCapacity = 4,
        onBufferOverflow = BufferOverflow.DROP_OLDEST,
    )
    val notificationCenterSnapshots: SharedFlow<NotificationCenterState> =
        _notificationCenterSnapshots.asSharedFlow()

    override fun onSessionSnapshot(snapshot: SessionState) {
        _sessionSnapshots.tryEmit(snapshot)
    }

    override fun onTopicListSnapshot(snapshot: TopicListState) {
        _topicListSnapshots.tryEmit(snapshot)
    }

    override fun onNotificationCenterSnapshot(snapshot: NotificationCenterState) {
        _notificationCenterSnapshots.tryEmit(snapshot)
    }
}
