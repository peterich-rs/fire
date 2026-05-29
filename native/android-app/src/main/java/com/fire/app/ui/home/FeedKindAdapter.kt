package com.fire.app.ui.home

import android.view.View
import android.view.ViewGroup
import androidx.recyclerview.widget.RecyclerView
import com.google.android.material.chip.Chip
import uniffi.fire_uniffi_types.TopicListKindState

class FeedKindAdapter(
    private val kinds: List<TopicListKindState>,
    private var selectedKind: TopicListKindState,
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
            isCheckable = true
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
        chip.setOnClickListener {
            onKindSelected(kind)
            if (kind == selectedKind) {
                chip.isChecked = true
            }
        }
    }

    override fun getItemCount(): Int = kinds.size

    fun updateSelectedKind(kind: TopicListKindState) {
        if (selectedKind == kind) return

        val previousKind = selectedKind
        selectedKind = kind

        val previousIndex = kinds.indexOf(previousKind)
        if (previousIndex >= 0) {
            notifyItemChanged(previousIndex)
        }

        val nextIndex = kinds.indexOf(kind)
        if (nextIndex >= 0) {
            notifyItemChanged(nextIndex)
        }
    }

    class KindViewHolder(itemView: View) : RecyclerView.ViewHolder(itemView)
}
