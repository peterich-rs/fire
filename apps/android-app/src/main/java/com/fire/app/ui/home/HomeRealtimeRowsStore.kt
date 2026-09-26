package com.fire.app.ui.home

import uniffi.fire_uniffi_types.TopicRowState

class HomeRealtimeRowsStore {
    private val rows = mutableListOf<TopicRowState>()
    private val pendingRows = mutableListOf<TopicRowState>()

    val snapshot: List<TopicRowState>
        get() = rows.toList()

    val pendingCount: Int
        get() = pendingRows.size

    fun snapshotIds(): Set<ULong> = rows.map { it.topic.id }.toSet()

    fun upsertRealtimeRows(incoming: List<TopicRowState>, prependNow: Boolean): HomeRealtimeRowsMutation {
        if (incoming.isEmpty()) {
            return HomeRealtimeRowsMutation()
        }
        val existingIds = rows.map { it.topic.id }.toSet()
        val replacements = incoming.filter { existingIds.contains(it.topic.id) }
        val inserts = incoming.filterNot { existingIds.contains(it.topic.id) }
        val changedIndexes = mutableListOf<Int>()
        replacements.forEach { replacement ->
            val index = rows.indexOfFirst { it.topic.id == replacement.topic.id }
            if (index >= 0) {
                rows[index] = replacement
                changedIndexes += index
            }
        }
        var insertedCount = 0
        if (inserts.isNotEmpty()) {
            if (prependNow) {
                rows.addAll(0, inserts)
                insertedCount = inserts.size
            } else {
                pendingRows.removeAll { pending -> inserts.any { it.topic.id == pending.topic.id } }
                pendingRows.addAll(0, inserts)
            }
        }
        return HomeRealtimeRowsMutation(
            changedIndexes = changedIndexes,
            insertedCount = insertedCount,
        )
    }

    fun flushPendingRows(): Int {
        if (pendingRows.isEmpty()) {
            return 0
        }
        val inserted = pendingRows.toList()
        pendingRows.clear()
        rows.addAll(0, inserted)
        return inserted.size
    }

    fun clear(): Int {
        val count = rows.size
        rows.clear()
        pendingRows.clear()
        return count
    }

    fun rowAt(index: Int): TopicRowState = rows[index]

    val itemCount: Int
        get() = rows.size
}

data class HomeRealtimeRowsMutation(
    val changedIndexes: List<Int> = emptyList(),
    val insertedCount: Int = 0,
)
