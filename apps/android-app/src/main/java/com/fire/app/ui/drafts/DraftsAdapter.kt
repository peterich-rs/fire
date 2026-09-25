package com.fire.app.ui.drafts

import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import android.widget.ImageButton
import android.widget.TextView
import androidx.paging.PagingDataAdapter
import androidx.recyclerview.widget.DiffUtil
import androidx.recyclerview.widget.RecyclerView
import com.fire.app.R
import com.fire.app.TopicPresentation
import uniffi.fire_uniffi_types.DraftState

class DraftsAdapter(
    private val onDraftClick: (DraftState) -> Unit,
    private val onDraftDelete: (DraftState) -> Unit,
) : PagingDataAdapter<DraftState, DraftsAdapter.DraftViewHolder>(DiffCallback) {

    override fun onCreateViewHolder(parent: ViewGroup, viewType: Int): DraftViewHolder {
        val view = LayoutInflater.from(parent.context)
            .inflate(R.layout.item_draft, parent, false)
        return DraftViewHolder(view)
    }

    override fun onBindViewHolder(holder: DraftViewHolder, position: Int) {
        getItem(position)?.let { draft ->
            holder.bind(draft, onDraftClick, onDraftDelete)
        }
    }

    class DraftViewHolder(itemView: View) : RecyclerView.ViewHolder(itemView) {
        private val titleView: TextView = itemView.findViewById(R.id.draft_title)
        private val excerptView: TextView = itemView.findViewById(R.id.draft_excerpt)
        private val metaView: TextView = itemView.findViewById(R.id.draft_meta)
        private val deleteButton: ImageButton = itemView.findViewById(R.id.draft_delete_button)

        fun bind(
            draft: DraftState,
            onClick: (DraftState) -> Unit,
            onDelete: (DraftState) -> Unit,
        ) {
            titleView.text = draft.displayTitle()
            excerptView.text = draft.displayExcerpt()
            excerptView.visibility = if (excerptView.text.isNullOrBlank()) View.GONE else View.VISIBLE
            metaView.text = draft.displayMetadata(itemView.context)

            itemView.setOnClickListener { onClick(draft) }
            deleteButton.setOnClickListener { onDelete(draft) }
        }

        private fun DraftState.displayTitle(): String {
            return title?.takeIf { it.isNotBlank() }
                ?: data.title?.takeIf { it.isNotBlank() }
                ?: itemView.context.getString(R.string.feed_drafts_untitled)
        }

        private fun DraftState.displayExcerpt(): String {
            return excerpt?.takeIf { it.isNotBlank() }
                ?: data.reply?.takeIf { it.isNotBlank() }
                ?: ""
        }

        private fun DraftState.displayMetadata(context: android.content.Context): String {
            return buildList {
                add(context.getString(typeLabelRes()))
                TopicPresentation.formatTimestamp(updatedAt)?.let { add(it) }
                username?.takeIf { it.isNotBlank() }?.let { add("@$it") }
            }.joinToString(" · ")
        }

        private fun DraftState.typeLabelRes(): Int {
            return when {
                draftKey == "new_topic" -> R.string.feed_drafts_type_topic
                draftKey == "new_private_message" || data.archetypeId == "private_message" ->
                    R.string.feed_drafts_type_private_message
                topicId != null || draftKey.startsWith("topic_") -> R.string.feed_drafts_type_reply
                else -> R.string.feed_drafts_type_unknown
            }
        }
    }

    private object DiffCallback : DiffUtil.ItemCallback<DraftState>() {
        override fun areItemsTheSame(oldItem: DraftState, newItem: DraftState): Boolean =
            oldItem.draftKey == newItem.draftKey

        override fun areContentsTheSame(oldItem: DraftState, newItem: DraftState): Boolean =
            oldItem == newItem
    }
}
