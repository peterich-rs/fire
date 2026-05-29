package com.fire.app.ui.home

import android.view.ViewGroup
import androidx.paging.PagingDataAdapter
import androidx.recyclerview.widget.DiffUtil
import uniffi.fire_uniffi_types.TopicRowState

class TopicListAdapter(
    private val onTagClick: (String) -> Unit = {},
    private val onTopicClick: (TopicRowState) -> Unit,
) : PagingDataAdapter<TopicRowState, TopicRowViewHolder>(TopicRowDiffCallback) {

    override fun onCreateViewHolder(parent: ViewGroup, viewType: Int): TopicRowViewHolder {
        return TopicRowViewHolder.create(parent)
    }

    override fun onBindViewHolder(holder: TopicRowViewHolder, position: Int) {
        val row = getItem(position) ?: return
        holder.bind(row, onTopicClick, onTagClick)
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
