package com.fire.app.ui.topicdetail

import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import android.widget.ProgressBar
import android.widget.TextView
import androidx.recyclerview.widget.DiffUtil
import androidx.recyclerview.widget.ListAdapter
import androidx.recyclerview.widget.RecyclerView
import com.fire.app.R
import com.fire.app.TopicPresentation
import com.fire.app.richtext.FireCookedImage
import com.google.android.material.chip.Chip
import com.google.android.material.chip.ChipGroup
import uniffi.fire_uniffi_topics.PollState
import uniffi.fire_uniffi_topics.TopicAiSummaryState
import uniffi.fire_uniffi_topics.TopicDetailState
import uniffi.fire_uniffi_topics.TopicPostState

data class PostRow(
    val post: TopicPostState,
    val depth: Int = 0,
    val parentPostNumber: UInt? = null,
    val hasChildren: Boolean = false,
    val usesTitleWidthBody: Boolean = false,
)

data class PostRowCallbacks(
    val reactionIds: () -> List<String> = { emptyList() },
    val onPostClick: (TopicPostState) -> Unit = {},
    val onReplyClick: (TopicPostState) -> Unit = {},
    val onHeartClick: (TopicPostState) -> Unit = {},
    val onReactClick: (TopicPostState) -> Unit = {},
    val onBookmarkClick: (TopicPostState) -> Unit = {},
    val onVotePoll: (TopicPostState, PollState, List<String>) -> Unit = { _, _, _ -> },
    val onUnvotePoll: (TopicPostState, PollState) -> Unit = { _, _ -> },
    val onReactionsClick: (TopicPostState) -> Unit = {},
    val onReplyContextClick: (TopicPostState) -> Unit = {},
    val onDeletePostClick: (TopicPostState) -> Unit = {},
    val onRecoverPostClick: (TopicPostState) -> Unit = {},
    val onFlagPostClick: (TopicPostState) -> Unit = {},
    val onEditPostClick: (TopicPostState) -> Unit = {},
    val onImageClick: (FireCookedImage) -> Unit = {},
    val onAuthorClick: (String) -> Unit = {},
    val onLinkClick: (String) -> Unit = {},
)

class PostListAdapter(
    private val callbacks: PostRowCallbacks,
) : ListAdapter<PostRow, PostViewHolder>(PostDiffCallback) {
    private val attachedHolders = mutableSetOf<PostViewHolder>()
    private var boostAnimationsEnabled = true

    override fun onCreateViewHolder(parent: ViewGroup, viewType: Int): PostViewHolder {
        return PostViewHolder.create(parent)
    }

    override fun onBindViewHolder(holder: PostViewHolder, position: Int) {
        holder.setBoostAnimationsEnabled(boostAnimationsEnabled)
        holder.bind(getItem(position), callbacks)
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

class HeaderAdapter(
    private val callbacks: PostRowCallbacks,
    private val onReloadAiSummary: () -> Unit,
    private val onToggleTopicVote: () -> Unit,
    private val onShowTopicVoters: (TopicDetailState) -> Unit,
    private val onEditTopicClick: (TopicDetailState) -> Unit,
    private val onTopicBookmarkClick: (TopicDetailState) -> Unit,
    private val onTopicNotificationClick: (TopicDetailState) -> Unit,
) : RecyclerView.Adapter<HeaderAdapter.HeaderViewHolder>() {
    private val attachedHolders = mutableSetOf<HeaderViewHolder>()
    private var boostAnimationsEnabled = true

    var detail: TopicDetailState? = null
        set(value) {
            val oldValue = field
            if (oldValue != null && value != null && oldValue.hasSameHeaderContent(value)) {
                field = value
                return
            }
            field = value
            when {
                oldValue == null && value != null -> notifyItemInserted(0)
                oldValue != null && value == null -> notifyItemRemoved(0)
                oldValue != null && value != null -> notifyItemChanged(0)
            }
        }

    var aiSummary: TopicAiSummaryState? = null
        set(value) {
            if (field == value) return
            field = value
            notifyHeaderChanged()
        }

    var isAiSummaryLoading: Boolean = false
        set(value) {
            if (field == value) return
            field = value
            notifyHeaderChanged()
        }

    var aiSummaryError: String? = null
        set(value) {
            if (field == value) return
            field = value
            notifyHeaderChanged()
        }

    override fun onCreateViewHolder(parent: ViewGroup, viewType: Int): HeaderViewHolder {
        val view = LayoutInflater.from(parent.context)
            .inflate(R.layout.item_topic_header, parent, false)
        return HeaderViewHolder(
            itemView = view,
            callbacks = callbacks,
            onReloadAiSummary = onReloadAiSummary,
            onToggleTopicVote = onToggleTopicVote,
            onShowTopicVoters = onShowTopicVoters,
            onEditTopicClick = onEditTopicClick,
            onTopicBookmarkClick = onTopicBookmarkClick,
            onTopicNotificationClick = onTopicNotificationClick,
        )
    }

    override fun onBindViewHolder(holder: HeaderViewHolder, position: Int) {
        holder.setBoostAnimationsEnabled(boostAnimationsEnabled)
        detail?.let { holder.bind(it, aiSummary, isAiSummaryLoading, aiSummaryError) }
    }

    override fun onViewAttachedToWindow(holder: HeaderViewHolder) {
        super.onViewAttachedToWindow(holder)
        attachedHolders += holder
        holder.onAttachedToWindow()
        holder.setBoostAnimationsEnabled(boostAnimationsEnabled)
    }

    override fun onViewDetachedFromWindow(holder: HeaderViewHolder) {
        attachedHolders -= holder
        holder.onDetachedFromWindow()
        super.onViewDetachedFromWindow(holder)
    }

    override fun getItemCount(): Int = if (detail != null) 1 else 0

    private fun TopicDetailState.hasSameHeaderContent(other: TopicDetailState): Boolean {
        return title == other.title &&
            tags == other.tags &&
            categoryId == other.categoryId &&
            postsCount == other.postsCount &&
            replyCount == other.replyCount &&
            highestPostNumber == other.highestPostNumber &&
            views == other.views &&
            likeCount == other.likeCount &&
            bookmarked == other.bookmarked &&
            bookmarkId == other.bookmarkId &&
            bookmarkName == other.bookmarkName &&
            bookmarkReminderAt == other.bookmarkReminderAt &&
            canVote == other.canVote &&
            voteCount == other.voteCount &&
            userVoted == other.userVoted &&
            summarizable == other.summarizable &&
            hasCachedSummary == other.hasCachedSummary &&
            hasSummary == other.hasSummary &&
            originalPost() == other.originalPost()
    }

    private fun notifyHeaderChanged() {
        if (detail != null) {
            notifyItemChanged(0)
        }
    }

    fun refreshRows() {
        notifyHeaderChanged()
    }

    fun setBoostAnimationsEnabled(enabled: Boolean) {
        if (boostAnimationsEnabled == enabled) return
        boostAnimationsEnabled = enabled
        attachedHolders.forEach { holder ->
            holder.setBoostAnimationsEnabled(enabled)
        }
    }

    private fun TopicDetailState.originalPost(): TopicPostState? {
        return postStream.posts.minByOrNull { it.postNumber }
    }

    class HeaderViewHolder(
        itemView: View,
        private val callbacks: PostRowCallbacks,
        private val onReloadAiSummary: () -> Unit,
        private val onToggleTopicVote: () -> Unit,
        private val onShowTopicVoters: (TopicDetailState) -> Unit,
        private val onEditTopicClick: (TopicDetailState) -> Unit,
        private val onTopicBookmarkClick: (TopicDetailState) -> Unit,
        private val onTopicNotificationClick: (TopicDetailState) -> Unit,
    ) : RecyclerView.ViewHolder(itemView) {
        private val titleText: TextView = itemView.findViewById(R.id.topic_title)
        private val chips: ChipGroup = itemView.findViewById(R.id.topic_chips)
        private val topicNotificationButton: TextView = itemView.findViewById(R.id.topic_notification_button)
        private val topicEditButton: TextView = itemView.findViewById(R.id.topic_edit_button)
        private val topicBookmarkButton: TextView = itemView.findViewById(R.id.topic_bookmark_button)
        private val aiSummaryContainer: View = itemView.findViewById(R.id.ai_summary_container)
        private val aiSummaryProgress: ProgressBar = itemView.findViewById(R.id.ai_summary_progress)
        private val aiSummaryBody: TextView = itemView.findViewById(R.id.ai_summary_body)
        private val aiSummaryMeta: TextView = itemView.findViewById(R.id.ai_summary_meta)
        private val aiSummaryRetry: TextView = itemView.findViewById(R.id.ai_summary_retry)
        private val statReplies: TextView = itemView.findViewById(R.id.stat_replies)
        private val statViews: TextView = itemView.findViewById(R.id.stat_views)
        private val statLikes: TextView = itemView.findViewById(R.id.stat_likes)
        private val topicVoteContainer: View = itemView.findViewById(R.id.topic_vote_container)
        private val topicVoteCount: TextView = itemView.findViewById(R.id.topic_vote_count)
        private val topicVoteStatus: TextView = itemView.findViewById(R.id.topic_vote_status)
        private val topicVoteVotersButton: TextView = itemView.findViewById(R.id.topic_vote_voters_button)
        private val topicVoteButton: TextView = itemView.findViewById(R.id.topic_vote_button)
        private val originalPostContainer: View = itemView.findViewById(R.id.original_post_container)
        private val originalPostHolder = PostViewHolder(originalPostContainer)

        fun onAttachedToWindow() {
            originalPostHolder.onAttachedToWindow()
        }

        fun onDetachedFromWindow() {
            originalPostHolder.onDetachedFromWindow()
        }

        fun setBoostAnimationsEnabled(enabled: Boolean) {
            originalPostHolder.setBoostAnimationsEnabled(enabled)
        }

        fun bind(
            detail: TopicDetailState,
            aiSummary: TopicAiSummaryState?,
            isAiSummaryLoading: Boolean,
            aiSummaryError: String?,
        ) {
            titleText.text = detail.title.trim()
            val tagNames = TopicPresentation.tagNames(detail.tags)
            if (tagNames.isNotEmpty() || detail.categoryId != null) {
                chips.visibility = View.VISIBLE
                chips.removeAllViews()
                detail.categoryId?.let { cid ->
                    val chip = Chip(itemView.context).apply {
                        text = "分类 $cid"
                        isClickable = false
                        isCheckable = false
                        setChipBackgroundColorResource(R.color.fire_accent_soft)
                        setTextColor(itemView.context.getColor(R.color.fire_accent))
                    }
                    chips.addView(chip)
                }
                for (tagName in tagNames) {
                    val chip = Chip(itemView.context).apply {
                        text = "#$tagName"
                        isClickable = false
                        isCheckable = false
                        setChipBackgroundColorResource(R.color.fire_accent_soft)
                        setTextColor(itemView.context.getColor(R.color.fire_accent))
                    }
                    chips.addView(chip)
                }
            } else {
                chips.visibility = View.GONE
            }
            bindTopicNotification(detail)
            bindTopicEdit(detail)
            bindTopicBookmark(detail)
            bindAiSummary(aiSummary, isAiSummaryLoading, aiSummaryError)
            statReplies.text = "${detail.replyCount}"
            statViews.text = "${detail.views}"
            statLikes.text = "${detail.likeCount}"
            bindTopicVote(detail)

            val originalPost = detail.postStream.posts.minByOrNull { it.postNumber }
            if (originalPost != null) {
                originalPostContainer.visibility = View.VISIBLE
                originalPostContainer.setPadding(
                    0,
                    originalPostContainer.paddingTop,
                    0,
                    originalPostContainer.paddingBottom,
                )
                originalPostHolder.bind(
                    PostRow(post = originalPost, depth = 0, usesTitleWidthBody = true),
                    callbacks,
                )
            } else {
                originalPostContainer.visibility = View.GONE
            }
        }

        private fun bindTopicNotification(detail: TopicDetailState) {
            val isPrivateMessageThread = detail.archetype
                ?.trim()
                ?.equals("private_message", ignoreCase = true) == true
            topicNotificationButton.visibility = if (isPrivateMessageThread) View.GONE else View.VISIBLE
            if (isPrivateMessageThread) {
                topicNotificationButton.setOnClickListener(null)
                return
            }

            val title = topicNotificationTitle(detail.details.notificationLevel ?: 1)
            topicNotificationButton.text = itemView.context.getString(
                R.string.topic_detail_notification_button,
                title,
            )
            topicNotificationButton.setOnClickListener {
                onTopicNotificationClick(detail)
            }
        }

        private fun bindTopicEdit(detail: TopicDetailState) {
            val isPrivateMessageThread = detail.archetype
                ?.trim()
                ?.equals("private_message", ignoreCase = true) == true
            val visible = detail.details.canEdit && !isPrivateMessageThread
            topicEditButton.visibility = if (visible) View.VISIBLE else View.GONE
            if (visible) {
                topicEditButton.setOnClickListener { onEditTopicClick(detail) }
            } else {
                topicEditButton.setOnClickListener(null)
            }
        }

        private fun bindTopicBookmark(detail: TopicDetailState) {
            topicBookmarkButton.text = itemView.context.getString(
                if (detail.bookmarked) {
                    R.string.topic_detail_bookmark_topic_active
                } else {
                    R.string.topic_detail_bookmark_topic
                },
            )
            topicBookmarkButton.setOnClickListener {
                onTopicBookmarkClick(detail)
            }
        }

        private fun topicNotificationTitle(level: Int): String {
            val context = itemView.context
            return when (level) {
                0 -> context.getString(R.string.topic_detail_notification_muted)
                2 -> context.getString(R.string.topic_detail_notification_tracking)
                3 -> context.getString(R.string.topic_detail_notification_watching)
                else -> context.getString(R.string.topic_detail_notification_regular)
            }
        }

        private fun bindTopicVote(detail: TopicDetailState) {
            val visible = detail.canVote || detail.userVoted || detail.voteCount > 0
            topicVoteContainer.visibility = if (visible) View.VISIBLE else View.GONE
            if (!visible) return

            val context = itemView.context
            topicVoteCount.text = context.getString(
                R.string.topic_detail_vote_count,
                detail.voteCount.coerceAtLeast(0).toString(),
            )
            topicVoteStatus.text = if (detail.userVoted) {
                context.getString(R.string.topic_detail_vote_you_voted)
            } else {
                ""
            }
            topicVoteButton.text = context.getString(
                if (detail.userVoted) {
                    R.string.topic_detail_unvote_topic
                } else {
                    R.string.topic_detail_vote_topic
                },
            )
            topicVoteButton.isEnabled = detail.canVote || detail.userVoted
            topicVoteButton.setTextColor(
                context.getColor(
                    if (detail.userVoted) R.color.fire_text_secondary else R.color.fire_accent,
                ),
            )
            topicVoteButton.setOnClickListener {
                onToggleTopicVote()
            }
            topicVoteVotersButton.visibility = if (detail.voteCount > 0) View.VISIBLE else View.GONE
            topicVoteVotersButton.setOnClickListener {
                onShowTopicVoters(detail)
            }
        }

        private fun bindAiSummary(
            summary: TopicAiSummaryState?,
            isLoading: Boolean,
            error: String?,
        ) {
            val visible = summary != null || isLoading || !error.isNullOrBlank()
            aiSummaryContainer.visibility = if (visible) View.VISIBLE else View.GONE
            if (!visible) return

            aiSummaryProgress.visibility = if (isLoading) View.VISIBLE else View.GONE
            aiSummaryRetry.visibility = if (!isLoading && !error.isNullOrBlank()) View.VISIBLE else View.GONE
            aiSummaryRetry.setOnClickListener {
                onReloadAiSummary()
            }

            when {
                summary != null -> {
                    aiSummaryBody.text = summary.summarizedText.trim()
                    aiSummaryBody.visibility = View.VISIBLE
                    val metadata = topicAiSummaryMetadata(summary)
                    aiSummaryMeta.text = metadata.joinToString(" · ")
                    aiSummaryMeta.visibility = if (metadata.isNotEmpty()) View.VISIBLE else View.GONE
                }
                isLoading -> {
                    aiSummaryBody.text = itemView.context.getString(R.string.topic_detail_ai_summary_loading)
                    aiSummaryBody.visibility = View.VISIBLE
                    aiSummaryMeta.visibility = View.GONE
                }
                else -> {
                    aiSummaryBody.text = error ?: itemView.context.getString(R.string.topic_detail_ai_summary_error)
                    aiSummaryBody.visibility = View.VISIBLE
                    aiSummaryMeta.visibility = View.GONE
                }
            }
        }

        private fun topicAiSummaryMetadata(summary: TopicAiSummaryState): List<String> {
            val context = itemView.context
            val metadata = mutableListOf<String>()
            TopicPresentation.formatTimestamp(summary.updatedAt)?.let { updatedAt ->
                metadata.add(context.getString(R.string.topic_detail_ai_summary_updated, updatedAt))
            }
            if (summary.outdated && summary.newPostsSinceSummary > 0u) {
                metadata.add(
                    context.getString(
                        R.string.topic_detail_ai_summary_new_posts,
                        summary.newPostsSinceSummary.toString(),
                    ),
                )
            }
            val algorithm = summary.algorithm?.trim()
            if (!algorithm.isNullOrEmpty()) {
                metadata.add(algorithm)
            }
            if (summary.canRegenerate) {
                metadata.add(context.getString(R.string.topic_detail_ai_summary_can_regenerate))
            }
            return metadata
        }
    }
}

class LoadingFooterAdapter : RecyclerView.Adapter<LoadingFooterAdapter.FooterViewHolder>() {

    var isLoading: Boolean = false
        set(value) {
            val oldValue = field
            if (oldValue == value) return
            field = value
            if (value) {
                notifyItemInserted(0)
            } else {
                notifyItemRemoved(0)
            }
        }

    override fun onCreateViewHolder(parent: ViewGroup, viewType: Int): FooterViewHolder {
        val view = LayoutInflater.from(parent.context)
            .inflate(R.layout.item_loading_footer, parent, false)
        return FooterViewHolder(view)
    }

    override fun onBindViewHolder(holder: FooterViewHolder, position: Int) {}

    override fun getItemCount(): Int = if (isLoading) 1 else 0

    class FooterViewHolder(itemView: View) : RecyclerView.ViewHolder(itemView)
}
