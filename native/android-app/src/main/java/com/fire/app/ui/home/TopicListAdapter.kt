package com.fire.app.ui.home

import android.view.ViewGroup
import androidx.paging.PagingDataAdapter
import androidx.recyclerview.widget.DiffUtil
import uniffi.fire_uniffi_session.TopicCategoryState
import uniffi.fire_uniffi_types.TopicRowState

class TopicListAdapter(
    private val onTagClick: (String) -> Unit = {},
    private val onLongClick: ((TopicRowState) -> Boolean)? = null,
    private val onTopicClick: (TopicRowState) -> Unit,
) : PagingDataAdapter<TopicRowState, TopicRowViewHolder>(TopicRowDiffCallback) {
    private val detailPatchesByTopicId = mutableMapOf<ULong, HomeTopicDetailPatch>()
    private var categoriesById: Map<ULong, TopicCategoryState> = emptyMap()

    override fun onCreateViewHolder(parent: ViewGroup, viewType: Int): TopicRowViewHolder {
        return TopicRowViewHolder.create(parent)
    }

    override fun onBindViewHolder(holder: TopicRowViewHolder, position: Int) {
        val row = getItem(position) ?: return
        val displayRow = detailPatchesByTopicId[row.topic.id]
            ?.let { HomeTopicDetailPatcher.patch(row, it) }
            ?: row
        val category = displayRow.topic.categoryId?.let { categoriesById[it] }
        holder.bind(displayRow, category, onTopicClick, onTagClick, onLongClick)
    }

    fun updateCategories(categories: List<TopicCategoryState>) {
        val next = categories.associateBy { it.id }
        if (categoriesById == next) return
        categoriesById = next
        notifyItemRangeChanged(0, itemCount)
    }

    fun applyDetailPatches(patches: Map<ULong, HomeTopicDetailPatch>): Boolean {
        if (detailPatchesByTopicId == patches) {
            return false
        }
        detailPatchesByTopicId.clear()
        detailPatchesByTopicId.putAll(patches)
        notifyItemRangeChanged(0, itemCount)
        return true
    }

    companion object {
        private val TopicRowDiffCallback = object : DiffUtil.ItemCallback<TopicRowState>() {
            override fun areItemsTheSame(oldItem: TopicRowState, newItem: TopicRowState): Boolean =
                oldItem.topic.id == newItem.topic.id

            override fun areContentsTheSame(oldItem: TopicRowState, newItem: TopicRowState): Boolean =
                oldItem == newItem
        }
    }
}
