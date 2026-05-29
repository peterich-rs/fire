package com.fire.app.ui.profile

import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import android.widget.ImageView
import android.widget.TextView
import androidx.recyclerview.widget.RecyclerView
import coil.ImageLoader
import coil.request.ImageRequest
import com.fire.app.R
import uniffi.fire_uniffi_user.BadgeState
import uniffi.fire_uniffi_user.ProfileSummaryTopicState
import uniffi.fire_uniffi_user.UserProfileState
import uniffi.fire_uniffi_user.UserSummaryStatsState

sealed class ProfileRow {
    data class HeaderRow(val profile: UserProfileState) : ProfileRow()
    data class StatsRow(val stats: UserSummaryStatsState) : ProfileRow()
    data class BadgeRow(val badges: List<BadgeState>) : ProfileRow()
    data class TopTopicRow(val topic: ProfileSummaryTopicState) : ProfileRow()
}

class ProfileAdapter : RecyclerView.Adapter<RecyclerView.ViewHolder>() {

    private val items = mutableListOf<ProfileRow>()

    companion object {
        private const val TYPE_HEADER = 0
        private const val TYPE_STATS = 1
        private const val TYPE_BADGES = 2
        private const val TYPE_TOP_TOPIC = 3
    }

    fun submitList(rows: List<ProfileRow>) {
        items.clear()
        items.addAll(rows)
        notifyDataSetChanged()
    }

    override fun getItemCount(): Int = items.size

    override fun getItemViewType(position: Int): Int = when (items[position]) {
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
        when (val row = items[position]) {
            is ProfileRow.HeaderRow -> (holder as HeaderViewHolder).bind(row.profile)
            is ProfileRow.StatsRow -> (holder as StatsViewHolder).bind(row.stats)
            is ProfileRow.BadgeRow -> (holder as BadgesViewHolder).bind(row.badges)
            is ProfileRow.TopTopicRow -> (holder as TopTopicViewHolder).bind(row.topic)
        }
    }

    class HeaderViewHolder(itemView: View) : RecyclerView.ViewHolder(itemView) {
        private val avatar: ImageView = itemView.findViewById(R.id.profile_avatar)
        private val username: TextView = itemView.findViewById(R.id.profile_username)
        private val trustLevel: TextView = itemView.findViewById(R.id.profile_trust_level)
        private val bio: TextView = itemView.findViewById(R.id.profile_bio)
        private val followBtn: TextView = itemView.findViewById(R.id.profile_follow_btn)

        fun bind(profile: UserProfileState) {
            username.text = profile.username
            trustLevel.text = profile.trustLevelLabel

            if (!profile.bioCooked.isNullOrBlank()) {
                bio.text = profile.bioCooked
                bio.visibility = View.VISIBLE
            } else {
                bio.visibility = View.GONE
            }

            followBtn.text = if (profile.isFollowed) {
                itemView.context.getString(R.string.profile_unfollow)
            } else {
                itemView.context.getString(R.string.profile_follow)
            }

            val avatarTemplate = profile.avatarTemplate
            if (!avatarTemplate.isNullOrBlank()) {
                val url = buildAvatarUrl(avatarTemplate, 120)
                val request = ImageRequest.Builder(avatar.context)
                    .data(url)
                    .crossfade(true)
                    .target(avatar)
                    .build()
                ImageLoader.Builder(avatar.context).build().enqueue(request)
            }
        }

        private fun buildAvatarUrl(template: String, size: Int): String {
            if (template.startsWith("http")) return template.replace("{size}", size.toString())
            return "https://linux.do/${template.trimStart('/').replace("{size}", size.toString())}"
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

        fun bind(topic: ProfileSummaryTopicState) {
            title.text = topic.title
            meta.text = itemView.context.getString(
                R.string.search_topic_meta,
                topic.likeCount.toString(),
                "0",
            )
        }
    }
}
