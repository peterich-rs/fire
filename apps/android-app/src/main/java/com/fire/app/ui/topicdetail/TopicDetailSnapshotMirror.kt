package com.fire.app.ui.topicdetail

import uniffi.fire_uniffi_topics.TopicDetailReplyContextChangeState
import uniffi.fire_uniffi_topics.TopicDetailSnapshotChangeState
import uniffi.fire_uniffi_topics.TopicDetailUiRowState
import uniffi.fire_uniffi_topics.TopicDetailUiSnapshotState

fun interface TopicDetailFullSnapshotSource {
    fun full(): TopicDetailUiSnapshotState
}

class TopicDetailSnapshotMirror {
    private var snapshot: TopicDetailUiSnapshotState? = null
    private val rowsById = LinkedHashMap<ULong, TopicDetailUiRowState>()
    private var order: List<ULong> = emptyList()

    @Synchronized
    fun apply(
        change: TopicDetailSnapshotChangeState,
        source: TopicDetailFullSnapshotSource,
    ): TopicDetailUiSnapshotState? {
        val current = snapshot
        if (current != null && change.generation <= current.generation) {
            return null
        }
        if (current == null || change.baseGeneration != current.generation) {
            return replace(source.full(), change)
        }
        var next = requireNotNull(current)
        change.status?.let { status ->
            next = next.copy(
                phase = status.phase,
                loadError = status.loadError,
                notice = status.notice,
                hasMore = status.hasMore,
                isLoadingMore = status.isLoadingMore,
                loadMoreError = status.loadMoreError,
                scrollTargetPostNumber = status.scrollTargetPostNumber,
            )
        }
        change.chrome?.let { next = next.copy(chrome = it) }
        change.composer?.let { next = next.copy(composer = it) }
        change.sidecar?.let { next = next.copy(sidecar = it) }
        next = when (val reply = change.replyContext) {
            is TopicDetailReplyContextChangeState.Unchanged -> next
            is TopicDetailReplyContextChangeState.Cleared -> next.copy(focusedReplyContext = null)
            is TopicDetailReplyContextChangeState.Set -> next.copy(focusedReplyContext = reply.context)
        }
        change.flagTypes?.let { next = next.copy(flagTypes = it) }
        next = next.copy(homeRowPatch = change.homeRowPatch)
        for (row in change.upsertedRows) {
            rowsById[row.postId] = row
        }
        change.rowOrder?.let { rowOrder ->
            order = rowOrder
            val keep = rowOrder.toSet()
            rowsById.keys.retainAll(keep)
        }
        if (order.any { it !in rowsById }) {
            return replace(source.full(), change)
        }
        val rows = order.mapNotNull { rowsById[it] }
        snapshot = next.copy(
            generation = change.generation,
            collectionRevision = change.revisions.collection,
            chromeRevision = change.revisions.chrome,
            sidecarRevision = change.revisions.sidecar,
            interactionRevision = change.revisions.interaction,
            composerRevision = change.revisions.composer,
            rows = rows,
        )
        return snapshot
    }

    private fun replace(
        full: TopicDetailUiSnapshotState,
        change: TopicDetailSnapshotChangeState,
    ): TopicDetailUiSnapshotState {
        val next = full.copy(
            generation = change.generation,
            collectionRevision = change.revisions.collection,
            chromeRevision = change.revisions.chrome,
            sidecarRevision = change.revisions.sidecar,
            interactionRevision = change.revisions.interaction,
            composerRevision = change.revisions.composer,
        )
        rowsById.clear()
        for (row in next.rows) {
            rowsById[row.postId] = row
        }
        order = next.rows.map { it.postId }
        snapshot = next
        return next
    }
}
