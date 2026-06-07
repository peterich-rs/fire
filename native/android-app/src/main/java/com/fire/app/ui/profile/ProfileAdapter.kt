package com.fire.app.ui.profile

import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import android.widget.ImageView
import android.widget.TextView
import androidx.core.text.HtmlCompat
import androidx.recyclerview.widget.DiffUtil
import androidx.recyclerview.widget.ListAdapter
import androidx.recyclerview.widget.RecyclerView
import com.fire.app.R
import com.fire.app.TopicPresentation
import com.fire.app.core.image.FireAvatarUrls
import com.fire.app.core.image.FireImageLoader
import com.fire.app.richtext.FireRichTextView
import uniffi.fire_uniffi_user.BadgeState
import uniffi.fire_uniffi_user.ProfileSummaryTopicState
import uniffi.fire_uniffi_user.UserProfileState
import uniffi.fire_uniffi_user.UserSummaryStatsState

sealed class ProfileRow {
    data class HeaderRow(val profile: UserProfileState, val isOwnProfile: Boolean) : ProfileRow()
    data class StatsRow(val stats: UserSummaryStatsState) : ProfileRow()
    data class BadgeRow(val badges: List<BadgeState>) : ProfileRow()
    data class TopTopicRow(val topic: ProfileSummaryTopicState) : ProfileRow()
}

class ProfileAdapter(
    private val onFollowClick: () -> Unit,
    private val onMessageClick: (UserProfileState) -> Unit,
    private val onTopicClick: (ProfileSummaryTopicState) -> Unit,
) : ListAdapter<ProfileRow, RecyclerView.ViewHolder>(DiffCallback) {

    companion object {
        private const val TYPE_HEADER = 0
        private const val TYPE_STATS = 1
        private const val TYPE_BADGES = 2
        private const val TYPE_TOP_TOPIC = 3
    }

    override fun getItemViewType(position: Int): Int = when (getItem(position)) {
        is ProfileRow.HeaderRow -> TYPE_HEADER
        is ProfileRow.StatsRow -> TYPE_STATS
        is ProfileRow.BadgeRow -> TYPE_BADGES
        is ProfileRow.TopTopicRow -> TYPE_TOP_TOPIC
    }

    override fun onCreateViewHolder(parent: ViewGroup, viewType: Int): RecyclerView.ViewHolder {
        val inflater = LayoutInflater.from(parent.context)
        return when (viewType) {
            TYPE_HEADER -> HeaderViewHolder(
                inflater.inflate(R.layout.item_profile_header, parent, false),
            )
            TYPE_STATS -> StatsViewHolder(
                inflater.inflate(R.layout.item_profile_stats, parent, false),
            )
            TYPE_BADGES -> BadgesViewHolder(
                inflater.inflate(R.layout.item_profile_badges, parent, false),
            )
            TYPE_TOP_TOPIC -> TopTopicViewHolder(
                inflater.inflate(R.layout.item_profile_topic, parent, false),
            )
            else -> throw IllegalArgumentException("Unknown view type: $viewType")
        }
    }

    override fun onBindViewHolder(holder: RecyclerView.ViewHolder, position: Int) {
        when (val row = getItem(position)) {
            is ProfileRow.HeaderRow -> (holder as HeaderViewHolder).bind(
                profile = row.profile,
                isOwnProfile = row.isOwnProfile,
                onFollowClick = onFollowClick,
                onMessageClick = onMessageClick,
            )
            is ProfileRow.StatsRow -> (holder as StatsViewHolder).bind(row.stats)
            is ProfileRow.BadgeRow -> (holder as BadgesViewHolder).bind(row.badges)
            is ProfileRow.TopTopicRow -> (holder as TopTopicViewHolder).bind(row.topic, onTopicClick)
        }
    }

    private object DiffCallback : DiffUtil.ItemCallback<ProfileRow>() {
        override fun areItemsTheSame(oldItem: ProfileRow, newItem: ProfileRow): Boolean {
            return when {
                oldItem is ProfileRow.HeaderRow && newItem is ProfileRow.HeaderRow ->
                    oldItem.profile.id == newItem.profile.id
                oldItem is ProfileRow.StatsRow && newItem is ProfileRow.StatsRow -> true
                oldItem is ProfileRow.BadgeRow && newItem is ProfileRow.BadgeRow -> true
                oldItem is ProfileRow.TopTopicRow && newItem is ProfileRow.TopTopicRow ->
                    oldItem.topic.id == newItem.topic.id
                else -> false
            }
        }

        override fun areContentsTheSame(oldItem: ProfileRow, newItem: ProfileRow): Boolean =
            oldItem == newItem
    }

    class HeaderViewHolder(itemView: View) : RecyclerView.ViewHolder(itemView) {
        private val avatar: ImageView = itemView.findViewById(R.id.profile_avatar)
        private val username: TextView = itemView.findViewById(R.id.profile_username)
        private val trustLevel: TextView = itemView.findViewById(R.id.profile_trust_level)
        private val bio: FireRichTextView = itemView.findViewById(R.id.profile_bio)
        private val followBtn: TextView = itemView.findViewById(R.id.profile_follow_btn)
        private val messageBtn: TextView = itemView.findViewById(R.id.profile_message_btn)

        fun bind(
            profile: UserProfileState,
            isOwnProfile: Boolean,
            onFollowClick: () -> Unit,
            onMessageClick: (UserProfileState) -> Unit,
        ) {
            username.text = profile.username
            trustLevel.text = profile.trustLevelLabel

            val bioCooked = profile.bioCooked?.trim()?.takeIf { it.isNotEmpty() }
            if (bioCooked != null) {
                bio.text = HtmlCompat.fromHtml(bioCooked, HtmlCompat.FROM_HTML_MODE_LEGACY)
                    .toString()
                    .trim()
                bio.visibility = View.VISIBLE
            } else {
                bio.visibility = View.GONE
            }

            if (profile.canFollow) {
                followBtn.visibility = View.VISIBLE
                followBtn.text = if (profile.isFollowed) {
                    itemView.context.getString(R.string.profile_unfollow)
                } else {
                    itemView.context.getString(R.string.profile_follow)
                }
                followBtn.setOnClickListener { onFollowClick() }
            } else {
                followBtn.visibility = View.GONE
                followBtn.setOnClickListener(null)
            }

            if (!isOwnProfile && profile.canSendPrivateMessageToUser) {
                messageBtn.visibility = View.VISIBLE
                messageBtn.setOnClickListener { onMessageClick(profile) }
            } else {
                messageBtn.visibility = View.GONE
                messageBtn.setOnClickListener(null)
            }

            val avatarTemplate = profile.avatarTemplate
            if (!avatarTemplate.isNullOrBlank()) {
                FireAvatarUrls.build(avatarTemplate)?.let { url ->
                    FireImageLoader.load(url, avatar)
                }
            } else {
                avatar.setImageDrawable(null)
            }
        }
    }

    class StatsViewHolder(itemView: View) : RecyclerView.ViewHolder(itemView) {
        private val daysVisited: TextView = itemView.findViewById(R.id.stats_days_visited)
        private val topicsCount: TextView = itemView.findViewById(R.id.stats_topics)
        private val postsCount: TextView = itemView.findViewById(R.id.stats_posts)
        private val likesGiven: TextView = itemView.findViewById(R.id.stats_likes_given)
        private val likesReceived: TextView = itemView.findViewById(R.id.stats_likes_received)

        fun bind(stats: UserSummaryStatsState) {
            daysVisited.text = itemView.context.getString(R.string.profile_days_visited, stats.daysVisited.toString())
            topicsCount.text = itemView.context.getString(R.string.profile_topics_count, stats.topicCount.toString())
            postsCount.text = itemView.context.getString(R.string.profile_posts_count, stats.postCount.toString())
            likesGiven.text = itemView.context.getString(R.string.profile_likes_given, stats.likesGiven.toString())
            likesReceived.text = itemView.context.getString(R.string.profile_likes_received, stats.likesReceived.toString())
        }
    }

    class BadgesViewHolder(itemView: View) : RecyclerView.ViewHolder(itemView) {
        private val badgesText: TextView = itemView.findViewById(R.id.badges_text)

        fun bind(badges: List<BadgeState>) {
            badgesText.text = badges.take(10).joinToString(" · ") { it.name }
        }
    }

    class TopTopicViewHolder(itemView: View) : RecyclerView.ViewHolder(itemView) {
        private val title: TextView = itemView.findViewById(R.id.topic_title)
        private val meta: TextView = itemView.findViewById(R.id.topic_meta)

        fun bind(topic: ProfileSummaryTopicState, onClick: (ProfileSummaryTopicState) -> Unit) {
            title.text = topic.title
            meta.text = buildList {
                add(itemView.context.getString(R.string.topic_detail_likes_count, topic.likeCount.toString()))
                TopicPresentation.formatTimestamp(topic.createdAt)?.let { add(it) }
            }.joinToString(" · ")
            itemView.setOnClickListener { onClick(topic) }
        }
    }
}
