package com.fire.app.ui.topicdetail

import android.view.ViewGroup
import androidx.recyclerview.widget.DiffUtil
import androidx.recyclerview.widget.ListAdapter

class PostListAdapter(
    private val callbacks: PostRowCallbacks,
) : ListAdapter<PostRow, PostViewHolder>(PostDiffCallback) {
    private val attachedHolders = mutableSetOf<PostViewHolder>()
    private var boostAnimationsEnabled = true

    var highlightedPostId: ULong? = null
        set(value) {
            if (field == value) return
            field = value
            refreshRows()
        }

    override fun onCreateViewHolder(parent: ViewGroup, viewType: Int): PostViewHolder {
        return PostViewHolder.create(parent)
    }

    override fun onBindViewHolder(holder: PostViewHolder, position: Int) {
        val row = getItem(position)
        holder.setBoostAnimationsEnabled(boostAnimationsEnabled)
        holder.bind(
            row = row,
            callbacks = callbacks,
            isSearchHighlighted = row.post.id == highlightedPostId,
        )
    }

    override fun onViewAttachedToWindow(holder: PostViewHolder) {
        super.onViewAttachedToWindow(holder)
        attachedHolders += holder
        holder.onAttachedToWindow()
        holder.setBoostAnimationsEnabled(boostAnimationsEnabled)
    }

    override fun onViewDetachedFromWindow(holder: PostViewHolder) {
        attachedHolders -= holder
        holder.onDetachedFromWindow()
        super.onViewDetachedFromWindow(holder)
    }

    fun setBoostAnimationsEnabled(enabled: Boolean) {
        if (boostAnimationsEnabled == enabled) return
        boostAnimationsEnabled = enabled
        attachedHolders.forEach { holder ->
            holder.setBoostAnimationsEnabled(enabled)
        }
    }

    fun refreshRows() {
        notifyDataSetChanged()
    }

    private object PostDiffCallback : DiffUtil.ItemCallback<PostRow>() {
        override fun areItemsTheSame(oldItem: PostRow, newItem: PostRow): Boolean =
            oldItem.post.id == newItem.post.id

        override fun areContentsTheSame(oldItem: PostRow, newItem: PostRow): Boolean =
            oldItem == newItem
    }
}
