package com.fire.app.ui.home

import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import android.widget.TextView
import androidx.recyclerview.widget.RecyclerView
import com.fire.app.R
import com.google.android.material.chip.Chip
import uniffi.fire_uniffi_types.TopicListKindState

class FeedKindAdapter(
    private val kinds: List<TopicListKindState>,
    private val selectedKind: TopicListKindState,
    private val onKindSelected: (TopicListKindState) -> Unit,
) : RecyclerView.Adapter<FeedKindAdapter.KindViewHolder>() {

    private val displayNames = mapOf(
        TopicListKindState.LATEST to "最新",
        TopicListKindState.NEW to "最新发布",
        TopicListKindState.UNREAD to "未读",
        TopicListKindState.UNSEEN to "未看",
        TopicListKindState.HOT to "热门",
        TopicListKindState.TOP to "精华",
        TopicListKindState.PRIVATE_MESSAGES_INBOX to "私信",
        TopicListKindState.PRIVATE_MESSAGES_SENT to "已发",
    )

    override fun onCreateViewHolder(parent: ViewGroup, viewType: Int): KindViewHolder {
        val chip = Chip(parent.context).apply {
            isClickable = true
            isCheckable = false
        }
        chip.layoutParams = ViewGroup.LayoutParams(
            ViewGroup.LayoutParams.WRAP_CONTENT,
            ViewGroup.LayoutParams.WRAP_CONTENT,
        )
        return KindViewHolder(chip)
    }

    override fun onBindViewHolder(holder: KindViewHolder, position: Int) {
        val kind = kinds[position]
        val chip = holder.itemView as Chip
        chip.text = displayNames[kind] ?: kind.name
        chip.isChecked = kind == selectedKind
        chip.setOnClickListener { onKindSelected(kind) }
    }

    override fun getItemCount(): Int = kinds.size

    class KindViewHolder(itemView: View) : RecyclerView.ViewHolder(itemView)
}
