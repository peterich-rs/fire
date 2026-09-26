package com.fire.app.ui.home

import android.view.ViewGroup
import androidx.recyclerview.widget.RecyclerView
import uniffi.fire_uniffi_session.TopicCategoryState
import uniffi.fire_uniffi_types.TopicRowState

class HomeRealtimeRowsAdapter(
    private val onTagClick: (String) -> Unit = {},
    private val onLongClick: ((TopicRowState) -> Boolean)? = null,
    private val onTopicClick: (TopicRowState) -> Unit,
) : RecyclerView.Adapter<TopicRowViewHolder>() {
    private val store = HomeRealtimeRowsStore()
    private var categoriesById: Map<ULong, TopicCategoryState> = emptyMap()

    val pendingCount: Int
        get() = store.pendingCount

    fun snapshotIds(): Set<ULong> = store.snapshotIds()

    fun updateCategories(categories: List<TopicCategoryState>) {
        val next = categories.associateBy { it.id }
        if (categoriesById == next) return
        categoriesById = next
        notifyItemRangeChanged(0, itemCount)
    }

    fun upsertRealtimeRows(incoming: List<TopicRowState>, prependNow: Boolean): Int {
        val mutation = store.upsertRealtimeRows(incoming, prependNow)
        mutation.changedIndexes.forEach(::notifyItemChanged)
        if (mutation.insertedCount > 0) {
            notifyItemRangeInserted(0, mutation.insertedCount)
        }
        return pendingCount
    }

    fun flushPendingRows(): Int {
        val inserted = store.flushPendingRows()
        if (inserted > 0) {
            notifyItemRangeInserted(0, inserted)
        }
        return pendingCount
    }

    fun clear() {
        val count = store.clear()
        if (count > 0) {
            notifyItemRangeRemoved(0, count)
        }
    }

    override fun onCreateViewHolder(parent: ViewGroup, viewType: Int): TopicRowViewHolder {
        return TopicRowViewHolder.create(parent)
    }

    override fun onBindViewHolder(holder: TopicRowViewHolder, position: Int) {
        val row = store.rowAt(position)
        val category = row.topic.categoryId?.let { categoriesById[it] }
        holder.bind(row, category, onTopicClick, onTagClick, onLongClick)
    }

    override fun getItemCount(): Int = store.itemCount
}
