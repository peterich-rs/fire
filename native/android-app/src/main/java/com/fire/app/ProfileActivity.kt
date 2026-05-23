package com.fire.app

import android.content.Context
import android.content.Intent
import android.graphics.Color
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.os.Bundle
import android.text.InputType
import android.view.View
import android.view.ViewGroup
import android.widget.Button
import android.widget.EditText
import android.widget.LinearLayout
import android.widget.ProgressBar
import android.widget.ScrollView
import android.widget.TextView
import androidx.appcompat.app.AlertDialog
import androidx.appcompat.app.AppCompatActivity
import androidx.lifecycle.lifecycleScope
import com.fire.app.session.FireSessionStore
import com.fire.app.session.FireSessionStoreRepository
import kotlinx.coroutines.launch
import java.time.Duration
import java.time.Instant
import uniffi.fire_uniffi.plainTextFromHtml
import uniffi.fire_uniffi_topics.PrivateMessageCreateRequestState
import uniffi.fire_uniffi_user.FollowUserState
import uniffi.fire_uniffi_user.UserProfileState
import uniffi.fire_uniffi_user.UserReactionState
import uniffi.fire_uniffi_user.UserSummaryState

class ProfileActivity : AppCompatActivity() {
    private enum class UserNotificationLevelOption(
        val value: String,
        val titleResId: Int,
        val descriptionResId: Int,
    ) {
        NORMAL(
            value = "normal",
            titleResId = R.string.profile_notification_normal,
            descriptionResId = R.string.profile_notification_normal_description,
        ),
        MUTE(
            value = "mute",
            titleResId = R.string.profile_notification_mute,
            descriptionResId = R.string.profile_notification_mute_description,
        ),
        IGNORE(
            value = "ignore",
            titleResId = R.string.profile_notification_ignore,
            descriptionResId = R.string.profile_notification_ignore_description,
        );

        companion object {
            fun fromProfile(profile: UserProfileState): UserNotificationLevelOption =
                when {
                    profile.ignored -> IGNORE
                    profile.muted -> MUTE
                    else -> NORMAL
                }
        }
    }

    private enum class IgnoreDurationOption(
        val days: Long,
        val titleResId: Int,
    ) {
        TOMORROW(1, R.string.profile_notification_ignore_tomorrow),
        TWO_WEEKS(14, R.string.profile_notification_ignore_two_weeks),
        ONE_MONTH(30, R.string.profile_notification_ignore_one_month),
        THREE_MONTHS(90, R.string.profile_notification_ignore_three_months),
        ONE_YEAR(365, R.string.profile_notification_ignore_one_year),
        PERMANENT(365_000, R.string.profile_notification_ignore_permanent),
    }

    private lateinit var sessionStore: FireSessionStore
    private lateinit var loadingIndicator: ProgressBar
    private lateinit var titleText: TextView
    private lateinit var metaText: TextView
    private lateinit var errorText: TextView
    private lateinit var contentContainer: LinearLayout
    private lateinit var refreshButton: Button

    private var username: String = ""
    private var renderBaseUrl: String = "https://linux.do"
    private var currentProfile: UserProfileState? = null
    private var currentSummary: UserSummaryState? = null
    private var userReactions: List<UserReactionState>? = null
    private var reactionsHasMore: Boolean = true
    private var reactionsLoading: Boolean = false
    private var reactionsErrorMessage: String? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        username = intent.getStringExtra(EXTRA_USERNAME)?.trim().orEmpty()
        if (username.isBlank()) {
            finish()
            return
        }

        sessionStore = FireSessionStoreRepository.get(applicationContext)
        setContentView(buildContentView())
        loadProfile()
    }

    private fun buildContentView(): View {
        return LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL

            addView(
                LinearLayout(context).apply {
                    gravity = android.view.Gravity.CENTER_VERTICAL
                    orientation = LinearLayout.HORIZONTAL
                    setPadding(dp(12), dp(12), dp(12), dp(12))

                    addView(
                        Button(context).apply {
                            text = getString(R.string.action_back)
                            setOnClickListener { finish() }
                        },
                    )

                    addView(
                        LinearLayout(context).apply {
                            orientation = LinearLayout.VERTICAL
                            layoutParams = LinearLayout.LayoutParams(
                                0,
                                ViewGroup.LayoutParams.WRAP_CONTENT,
                                1f,
                            ).apply {
                                marginStart = dp(12)
                                marginEnd = dp(12)
                            }

                            titleText = TextView(context).apply {
                                text = getString(R.string.profile_title, username)
                                textSize = 20f
                                setTypeface(typeface, Typeface.BOLD)
                                setTextColor(Color.parseColor("#FF111827"))
                                maxLines = 1
                                ellipsize = android.text.TextUtils.TruncateAt.END
                            }
                            addView(titleText)

                            metaText = TextView(context).apply {
                                text = getString(R.string.profile_loading)
                                textSize = 12f
                                setTextColor(Color.parseColor("#FF6B7280"))
                                setPadding(0, dp(4), 0, 0)
                            }
                            addView(metaText)
                        },
                    )

                    refreshButton = Button(context).apply {
                        text = getString(R.string.action_refresh)
                        setOnClickListener { loadProfile() }
                    }
                    addView(refreshButton)
                },
            )

            loadingIndicator = ProgressBar(context, null, android.R.attr.progressBarStyleHorizontal).apply {
                max = 100
                visibility = View.GONE
            }
            addView(loadingIndicator)

            errorText = TextView(context).apply {
                visibility = View.GONE
                setTextColor(Color.parseColor("#FFB91C1C"))
                textSize = 14f
                setPadding(dp(16), dp(12), dp(16), dp(4))
            }
            addView(errorText)

            addView(
                ScrollView(context).apply {
                    layoutParams = LinearLayout.LayoutParams(
                        ViewGroup.LayoutParams.MATCH_PARENT,
                        0,
                        1f,
                    )

                    contentContainer = LinearLayout(context).apply {
                        orientation = LinearLayout.VERTICAL
                        setPadding(dp(16), dp(16), dp(16), dp(24))
                    }
                    addView(contentContainer)
                },
            )
        }
    }

    private fun loadProfile() {
        lifecycleScope.launch {
            setLoading(true)
            errorText.visibility = View.GONE
            userReactions = null
            reactionsHasMore = true
            reactionsLoading = false
            reactionsErrorMessage = null
            currentSummary = null
            try {
                val session = sessionStore.restorePersistedSessionIfAvailable() ?: sessionStore.snapshot()
                renderBaseUrl = session.bootstrap.baseUrl.ifBlank { "https://linux.do" }
                val profile = sessionStore.fetchUserProfile(username)
                currentProfile = profile
                renderProfile(profile, summary = null)
                val summary = runCatching { sessionStore.fetchUserSummary(username) }.getOrNull()
                currentSummary = summary
                renderProfile(profile, summary)
                loadUserReactions(loadMore = false)
            } catch (error: Exception) {
                contentContainer.removeAllViews()
                errorText.text = error.localizedMessage ?: getString(R.string.profile_error)
                errorText.visibility = View.VISIBLE
                metaText.text = getString(R.string.profile_error)
            } finally {
                setLoading(false)
            }
        }
    }

    private fun renderProfile(profile: UserProfileState, summary: UserSummaryState?) {
        currentProfile = profile
        currentSummary = summary
        titleText.text = displayName(profile)
        metaText.text = buildList {
            add("@${profile.username}")
            add(profile.trustLevelLabel)
            profile.createdAt?.let { TopicPresentation.formatTimestamp(it) }?.let { add(getString(R.string.profile_joined_at, it)) }
            profile.gamificationScore?.let { add(getString(R.string.profile_score, it.toString())) }
        }.joinToString(" · ")

        contentContainer.removeAllViews()
        contentContainer.addView(headerCard(profile))
        profile.bioCooked?.takeIf { plainTextFromHtml(it).trim().isNotBlank() }?.let { bio ->
            contentContainer.addView(
                sectionCard(getString(R.string.profile_bio_title)) {
                    addView(FireCookedHtmlRenderer.render(context, bio, renderBaseUrl))
                },
            )
        }

        summary?.let {
            contentContainer.addView(summaryStatsCard(it))
            if (it.topTopics.isNotEmpty()) {
                contentContainer.addView(
                    sectionCard(getString(R.string.profile_top_topics_title)) {
                        it.topTopics.take(MAX_SUMMARY_ROWS).forEach { topic ->
                            addView(
                                summaryRow(
                                    title = topic.title,
                                    meta = buildList {
                                        add(getString(R.string.topic_detail_likes_count, topic.likeCount.toString()))
                                        TopicPresentation.formatTimestamp(topic.createdAt)?.let(::add)
                                    }.joinToString(" · "),
                                    onClick = { startActivity(TopicDetailActivity.intent(context, topic.id, topic.title)) },
                                ),
                            )
                        }
                    },
                )
            }
            if (it.topReplies.isNotEmpty()) {
                contentContainer.addView(
                    sectionCard(getString(R.string.profile_top_replies_title)) {
                        it.topReplies.take(MAX_SUMMARY_ROWS).forEach { reply ->
                            addView(
                                summaryRow(
                                    title = reply.title ?: getString(R.string.topic_detail_title_fallback, reply.topicId.toString()),
                                    meta = buildList {
                                        reply.postNumber?.let { postNumber -> add("#$postNumber") }
                                        add(getString(R.string.topic_detail_likes_count, reply.likeCount.toString()))
                                        TopicPresentation.formatTimestamp(reply.createdAt)?.let(::add)
                                    }.joinToString(" · "),
                                    onClick = {
                                        startActivity(
                                            TopicDetailActivity.intent(
                                                context = context,
                                                topicId = reply.topicId,
                                                topicTitle = reply.title.orEmpty(),
                                                targetPostNumber = reply.postNumber,
                                            ),
                                        )
                                    },
                                ),
                            )
                        }
                    },
                )
            }
            if (it.badges.isNotEmpty()) {
                contentContainer.addView(
                    sectionCard(getString(R.string.profile_badges_title)) {
                        it.badges.take(MAX_SUMMARY_ROWS).forEach { badge ->
                            addView(summaryRow(badge.name, badge.description ?: badge.longDescription.orEmpty()))
                        }
                    },
                )
            }
        } ?: contentContainer.addView(sectionBodyText(getString(R.string.profile_summary_loading)))

        contentContainer.addView(reactionsCard())
    }

    private fun headerCard(profile: UserProfileState): View {
        return sectionCard(getString(R.string.profile_overview_title)) {
            addView(
                TextView(context).apply {
                    text = displayName(profile)
                    textSize = 22f
                    setTypeface(typeface, Typeface.BOLD)
                    setTextColor(Color.parseColor("#FF111827"))
                },
            )
            addView(
                TextView(context).apply {
                    text = buildList {
                        add("@${profile.username}")
                        profile.name?.takeIf { it.isNotBlank() }?.let(::add)
                        add(profile.trustLevelLabel)
                    }.joinToString(" · ")
                    textSize = 13f
                    setTextColor(Color.parseColor("#FF6B7280"))
                    setPadding(0, dp(4), 0, dp(10))
                },
            )

            addView(
                LinearLayout(context).apply {
                    orientation = LinearLayout.HORIZONTAL
                    addView(metricButton(getString(R.string.profile_followers_count, profile.totalFollowers.toString())) {
                        showFollowUsers(getString(R.string.profile_followers_title), profile.username, followers = true)
                    })
                    addView(metricButton(getString(R.string.profile_following_count, profile.totalFollowing.toString())) {
                        showFollowUsers(getString(R.string.profile_following_title), profile.username, followers = false)
                    })
                },
            )

            val notificationLevel = UserNotificationLevelOption.fromProfile(profile)
            val canUpdateNotifications = profile.canMuteUser ||
                profile.canIgnoreUser ||
                notificationLevel != UserNotificationLevelOption.NORMAL
            if (canUpdateNotifications) {
                addView(
                    TextView(context).apply {
                        text = getString(
                            R.string.profile_notification_current,
                            userNotificationLevelTitle(notificationLevel),
                        )
                        textSize = 13f
                        setTextColor(Color.parseColor("#FF6B7280"))
                        setPadding(0, dp(10), 0, dp(4))
                    },
                )
                addView(
                    Button(context).apply {
                        isAllCaps = false
                        text = getString(R.string.profile_notification_action)
                        setOnClickListener { showUserNotificationLevelPicker(profile) }
                    },
                )
            }

            if (profile.canFollow) {
                addView(
                    Button(context).apply {
                        isAllCaps = false
                        text = if (profile.isFollowed) {
                            getString(R.string.profile_unfollow)
                        } else {
                            getString(R.string.profile_follow)
                        }
                        setOnClickListener { toggleFollow(profile) }
                    },
                )
            }
            if (profile.canSendPrivateMessageToUser) {
                addView(
                    Button(context).apply {
                        isAllCaps = false
                        text = getString(R.string.profile_send_private_message)
                        setOnClickListener { showPrivateMessageComposer(profile) }
                    },
                )
            }
        }
    }

    private fun showPrivateMessageComposer(profile: UserProfileState) {
        lifecycleScope.launch {
            setLoading(true)
            errorText.visibility = View.GONE
            try {
                val session = sessionStore.restorePersistedSessionIfAvailable() ?: sessionStore.snapshot()
                if (!session.readiness.canWriteAuthenticatedApi) {
                    showInlineError(getString(R.string.profile_private_message_login_required))
                    return@launch
                }
                showPrivateMessageDialog(
                    profile = profile,
                    minTitleLength = session.bootstrap.minPersonalMessageTitleLength,
                    minBodyLength = session.bootstrap.minPersonalMessagePostLength,
                )
            } catch (error: Exception) {
                showInlineError(error.localizedMessage ?: getString(R.string.profile_private_message_error))
            } finally {
                setLoading(false)
            }
        }
    }

    private fun showPrivateMessageDialog(
        profile: UserProfileState,
        minTitleLength: UInt,
        minBodyLength: UInt,
    ) {
        val titleInput = EditText(this).apply {
            hint = getString(R.string.profile_private_message_title_hint)
            setSingleLine(false)
            maxLines = 3
            inputType = InputType.TYPE_CLASS_TEXT or InputType.TYPE_TEXT_FLAG_CAP_SENTENCES
        }
        val bodyInput = EditText(this).apply {
            hint = getString(R.string.profile_private_message_body_hint)
            minLines = 7
            inputType = InputType.TYPE_CLASS_TEXT or
                InputType.TYPE_TEXT_FLAG_MULTI_LINE or
                InputType.TYPE_TEXT_FLAG_CAP_SENTENCES
        }
        val content = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(dp(20), dp(8), dp(20), dp(4))
            addView(sectionBodyText(getString(R.string.profile_private_message_recipient, profile.username)))
            addView(labelText(getString(R.string.profile_private_message_title_label)))
            addView(titleInput)
            addView(labelText(getString(R.string.profile_private_message_body_label)))
            addView(bodyInput)
        }

        val dialog = AlertDialog.Builder(this)
            .setTitle(getString(R.string.profile_private_message_title, displayName(profile)))
            .setView(ScrollView(this).apply { addView(content) })
            .setPositiveButton(R.string.profile_private_message_send, null)
            .setNegativeButton(R.string.action_cancel, null)
            .create()

        dialog.setOnShowListener {
            dialog.getButton(AlertDialog.BUTTON_POSITIVE).setOnClickListener {
                val title = titleInput.text?.toString()?.trim().orEmpty()
                val raw = bodyInput.text?.toString()?.trim().orEmpty()
                when {
                    title.length < minTitleLength.toInt() -> {
                        titleInput.error = getString(
                            R.string.profile_private_message_title_min_length,
                            minTitleLength.toString(),
                        )
                    }
                    raw.length < minBodyLength.toInt() -> {
                        bodyInput.error = getString(
                            R.string.profile_private_message_body_min_length,
                            minBodyLength.toString(),
                        )
                    }
                    else -> {
                        dialog.dismiss()
                        submitPrivateMessage(profile, title, raw)
                    }
                }
            }
        }
        dialog.show()
    }

    private fun submitPrivateMessage(
        profile: UserProfileState,
        title: String,
        raw: String,
    ) {
        lifecycleScope.launch {
            setLoading(true)
            errorText.visibility = View.GONE
            try {
                val topicId = sessionStore.createPrivateMessage(
                    PrivateMessageCreateRequestState(
                        title = title,
                        raw = raw,
                        targetRecipients = listOf(profile.username),
                    ),
                )
                startActivity(TopicDetailActivity.intent(this@ProfileActivity, topicId, title))
            } catch (error: Exception) {
                showInlineError(error.localizedMessage ?: getString(R.string.profile_private_message_error))
            } finally {
                setLoading(false)
            }
        }
    }

    private fun showUserNotificationLevelPicker(profile: UserProfileState) {
        val options = buildList {
            add(UserNotificationLevelOption.NORMAL)
            if (profile.canMuteUser || profile.muted) {
                add(UserNotificationLevelOption.MUTE)
            }
            if (profile.canIgnoreUser || profile.ignored) {
                add(UserNotificationLevelOption.IGNORE)
            }
        }
        val current = UserNotificationLevelOption.fromProfile(profile)
        val labels = options.map { option ->
            buildString {
                append(userNotificationLevelTitle(option))
                append(" - ")
                append(userNotificationLevelDescription(option))
                if (option == current) {
                    append(" ")
                    append(getString(R.string.profile_notification_selected))
                }
            }
        }.toTypedArray()

        AlertDialog.Builder(this)
            .setTitle(getString(R.string.profile_notification_title, displayName(profile)))
            .setItems(labels) { _, which ->
                val selected = options[which]
                if (selected == UserNotificationLevelOption.IGNORE) {
                    showIgnoreDurationPicker(profile)
                } else {
                    updateUserNotificationLevel(profile, selected, expiringAt = null)
                }
            }
            .setNegativeButton(R.string.action_cancel, null)
            .show()
    }

    private fun showIgnoreDurationPicker(profile: UserProfileState) {
        val options = IgnoreDurationOption.entries.toTypedArray()
        val labels = options.map { option ->
            if (option == IgnoreDurationOption.PERMANENT) {
                getString(option.titleResId)
            } else {
                getString(
                    R.string.profile_notification_ignore_until,
                    getString(option.titleResId),
                    TopicPresentation.formatTimestamp(ignoreExpiry(option)),
                )
            }
        }.toTypedArray()

        AlertDialog.Builder(this)
            .setTitle(getString(R.string.profile_notification_ignore_duration_title))
            .setItems(labels) { _, which ->
                updateUserNotificationLevel(
                    profile = profile,
                    option = UserNotificationLevelOption.IGNORE,
                    expiringAt = ignoreExpiry(options[which]),
                )
            }
            .setNegativeButton(R.string.action_cancel, null)
            .show()
    }

    private fun updateUserNotificationLevel(
        profile: UserProfileState,
        option: UserNotificationLevelOption,
        expiringAt: String?,
    ) {
        lifecycleScope.launch {
            setLoading(true)
            errorText.visibility = View.GONE
            try {
                val session = sessionStore.restorePersistedSessionIfAvailable() ?: sessionStore.snapshot()
                if (!session.readiness.canWriteAuthenticatedApi) {
                    showInlineError(getString(R.string.profile_notification_login_required))
                    return@launch
                }
                sessionStore.setUserNotificationLevel(
                    username = profile.username,
                    notificationLevel = option.value,
                    expiringAt = expiringAt,
                )
                val updatedProfile = sessionStore.fetchUserProfile(profile.username)
                currentProfile = updatedProfile
                currentSummary = runCatching { sessionStore.fetchUserSummary(profile.username) }.getOrNull()
                renderProfile(
                    updatedProfile,
                    currentSummary,
                )
            } catch (error: Exception) {
                showInlineError(error.localizedMessage ?: getString(R.string.profile_notification_error))
            } finally {
                setLoading(false)
            }
        }
    }

    private fun ignoreExpiry(option: IgnoreDurationOption): String {
        return Instant.now().plus(Duration.ofDays(option.days)).toString()
    }

    private fun userNotificationLevelTitle(option: UserNotificationLevelOption): String {
        return getString(option.titleResId)
    }

    private fun userNotificationLevelDescription(option: UserNotificationLevelOption): String {
        return getString(option.descriptionResId)
    }

    private fun summaryStatsCard(summary: UserSummaryState): View {
        val stats = summary.stats
        return sectionCard(getString(R.string.profile_summary_title)) {
            addView(
                TextView(context).apply {
                    text = buildList {
                        add(getString(R.string.profile_days_visited, stats.daysVisited.toString()))
                        add(getString(R.string.profile_topics_count, stats.topicCount.toString()))
                        add(getString(R.string.profile_posts_count, stats.postCount.toString()))
                        add(getString(R.string.profile_likes_received, stats.likesReceived.toString()))
                        add(getString(R.string.profile_likes_given, stats.likesGiven.toString()))
                        add(getString(R.string.profile_bookmarks_count, stats.bookmarkCount.toString()))
                    }.joinToString("\n")
                    textSize = 14f
                    setTextColor(Color.parseColor("#FF374151"))
                },
            )
        }
    }

    private fun toggleFollow(profile: UserProfileState) {
        lifecycleScope.launch {
            setLoading(true)
            try {
                if (profile.isFollowed) {
                    sessionStore.unfollowUser(profile.username)
                } else {
                    sessionStore.followUser(profile.username)
                }
                val updatedProfile = sessionStore.fetchUserProfile(profile.username)
                currentProfile = updatedProfile
                currentSummary = runCatching { sessionStore.fetchUserSummary(profile.username) }.getOrNull()
                renderProfile(updatedProfile, currentSummary)
            } catch (error: Exception) {
                errorText.text = error.localizedMessage ?: getString(R.string.profile_follow_error)
                errorText.visibility = View.VISIBLE
            } finally {
                setLoading(false)
            }
        }
    }

    private fun showFollowUsers(title: String, username: String, followers: Boolean) {
        val content = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(dp(20), dp(12), dp(20), dp(8))
            addView(sectionBodyText(getString(R.string.profile_follow_list_loading)))
        }
        val dialog = AlertDialog.Builder(this)
            .setTitle(title)
            .setView(ScrollView(this).apply { addView(content) })
            .setNegativeButton(R.string.action_close, null)
            .create()
        dialog.show()

        lifecycleScope.launch {
            try {
                val users = if (followers) {
                    sessionStore.fetchFollowers(username)
                } else {
                    sessionStore.fetchFollowing(username)
                }
                renderFollowUsers(content, dialog, users)
            } catch (error: Exception) {
                content.removeAllViews()
                content.addView(
                    sectionBodyText(error.localizedMessage ?: getString(R.string.profile_follow_list_error)).apply {
                        setTextColor(Color.parseColor("#FFB91C1C"))
                    },
                )
            }
        }
    }

    private fun renderFollowUsers(
        content: LinearLayout,
        dialog: AlertDialog,
        users: List<FollowUserState>,
    ) {
        content.removeAllViews()
        if (users.isEmpty()) {
            content.addView(sectionBodyText(getString(R.string.profile_follow_list_empty)))
            return
        }
        users.forEach { user ->
            content.addView(
                summaryRow(
                    title = displayName(user.username, user.name),
                    meta = "@${user.username}",
                    onClick = {
                        dialog.dismiss()
                        startActivity(intent(this, user.username))
                    },
                ),
            )
        }
    }

    private fun loadUserReactions(loadMore: Boolean) {
        if (reactionsLoading) {
            return
        }

        lifecycleScope.launch {
            reactionsLoading = true
            reactionsErrorMessage = null
            renderCurrentProfile()
            try {
                val beforeId = if (loadMore) {
                    userReactions.orEmpty().lastOrNull()?.id
                } else {
                    null
                }
                val response = sessionStore.fetchUserReactions(username, beforeId)
                val incoming = response.reactions
                userReactions = if (loadMore) {
                    (userReactions.orEmpty() + incoming).distinctBy { it.id }
                } else {
                    incoming
                }
                reactionsHasMore = incoming.size >= USER_REACTIONS_PAGE_SIZE
            } catch (error: Exception) {
                reactionsErrorMessage = error.localizedMessage ?: getString(R.string.profile_reactions_error)
            } finally {
                reactionsLoading = false
                renderCurrentProfile()
            }
        }
    }

    private fun renderCurrentProfile() {
        currentProfile?.let { profile ->
            renderProfile(profile, currentSummary)
        }
    }

    private fun reactionsCard(): View {
        return sectionCard(getString(R.string.profile_reactions_title)) {
            val error = reactionsErrorMessage
            val reactions = userReactions
            when {
                error != null -> {
                    addView(sectionBodyText(error).apply {
                        setTextColor(Color.parseColor("#FFB91C1C"))
                    })
                }
                reactionsLoading && reactions == null -> {
                    addView(sectionBodyText(getString(R.string.profile_reactions_loading)))
                }
                reactions == null -> {
                    addView(sectionBodyText(getString(R.string.profile_reactions_loading)))
                }
                reactions.isEmpty() -> {
                    addView(sectionBodyText(getString(R.string.profile_reactions_empty)))
                }
                else -> {
                    reactions.forEach { reaction ->
                        addView(
                            summaryRow(
                                title = reactionTitle(reaction),
                                meta = reactionMeta(reaction),
                                onClick = reactionClickHandler(reaction),
                            ),
                        )
                    }
                    if (reactionsLoading) {
                        addView(sectionBodyText(getString(R.string.profile_reactions_loading)))
                    }
                    if (reactionsHasMore) {
                        addView(
                            Button(context).apply {
                                isAllCaps = false
                                isEnabled = !reactionsLoading
                                text = getString(R.string.profile_reactions_load_more)
                                setOnClickListener { loadUserReactions(loadMore = true) }
                            },
                        )
                    }
                }
            }
        }
    }

    private fun reactionClickHandler(reaction: UserReactionState): (() -> Unit)? {
        if (reaction.topicId == 0uL) {
            return null
        }
        return {
            startActivity(
                TopicDetailActivity.intent(
                    context = this,
                    topicId = reaction.topicId,
                    topicTitle = reactionTitle(reaction),
                    targetPostNumber = reaction.postNumber,
                ),
            )
        }
    }

    private fun reactionTitle(reaction: UserReactionState): String {
        return reaction.topicTitle?.takeIf { it.isNotBlank() }
            ?: getString(R.string.topic_detail_title_fallback, reaction.topicId.toString())
    }

    private fun reactionMeta(reaction: UserReactionState): String {
        val preview = reaction.excerpt
            ?.let { plainTextFromHtml(it).trim() }
            ?.takeIf { it.isNotBlank() }
        return buildList {
            reaction.reactionValue?.takeIf { it.isNotBlank() }?.let {
                add(getString(R.string.profile_reaction_value, it))
            }
            reaction.postNumber?.let { add("#$it") }
            TopicPresentation.formatTimestamp(reaction.createdAt)?.let(::add)
            preview?.let(::add)
        }.joinToString("\n")
    }

    private fun sectionCard(
        title: String,
        contentBuilder: LinearLayout.() -> Unit,
    ): View {
        return LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(dp(16), dp(16), dp(16), dp(16))
            background = roundedBackground(Color.WHITE, Color.parseColor("#1F2F6FEB"))
            layoutParams = LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.WRAP_CONTENT,
            ).apply {
                bottomMargin = dp(12)
            }

            addView(
                TextView(context).apply {
                    text = title
                    textSize = 16f
                    setTypeface(typeface, Typeface.BOLD)
                    setTextColor(Color.parseColor("#FF111827"))
                    setPadding(0, 0, 0, dp(10))
                },
            )
            contentBuilder()
        }
    }

    private fun metricButton(text: String, onClick: () -> Unit): View {
        return Button(this).apply {
            isAllCaps = false
            this.text = text
            setOnClickListener { onClick() }
            layoutParams = LinearLayout.LayoutParams(
                0,
                ViewGroup.LayoutParams.WRAP_CONTENT,
                1f,
            ).apply {
                marginEnd = dp(8)
            }
        }
    }

    private fun summaryRow(
        title: String,
        meta: String,
        onClick: (() -> Unit)? = null,
    ): View {
        return LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(dp(12), dp(10), dp(12), dp(10))
            background = roundedBackground(Color.parseColor("#FFF9FAFB"), Color.parseColor("#1F6B7280"))
            layoutParams = LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.WRAP_CONTENT,
            ).apply {
                bottomMargin = dp(8)
            }
            if (onClick != null) {
                isClickable = true
                setOnClickListener { onClick() }
            }

            addView(
                TextView(context).apply {
                    text = title
                    textSize = 14f
                    setTypeface(typeface, Typeface.BOLD)
                    setTextColor(Color.parseColor("#FF111827"))
                    maxLines = 2
                    ellipsize = android.text.TextUtils.TruncateAt.END
                },
            )
            if (meta.isNotBlank()) {
                addView(
                    TextView(context).apply {
                        text = meta
                        textSize = 12f
                        setTextColor(Color.parseColor("#FF6B7280"))
                        setPadding(0, dp(3), 0, 0)
                    },
                )
            }
        }
    }

    private fun sectionBodyText(text: String): TextView {
        return TextView(this).apply {
            this.text = text
            textSize = 14f
            setTextColor(Color.parseColor("#FF374151"))
            setPadding(0, dp(4), 0, dp(6))
        }
    }

    private fun labelText(text: String): TextView {
        return TextView(this).apply {
            this.text = text
            textSize = 12f
            setTypeface(typeface, Typeface.BOLD)
            setTextColor(Color.parseColor("#FF6B7280"))
            setPadding(0, dp(10), 0, 0)
        }
    }

    private fun showInlineError(message: String) {
        errorText.text = message
        errorText.visibility = View.VISIBLE
    }

    private fun setLoading(loading: Boolean) {
        loadingIndicator.visibility = if (loading) View.VISIBLE else View.GONE
        refreshButton.isEnabled = !loading
    }

    private fun displayName(profile: UserProfileState): String {
        return displayName(profile.username, profile.name)
    }

    private fun displayName(username: String, name: String?): String {
        return name?.takeIf { it.isNotBlank() } ?: username
    }

    private fun roundedBackground(fillColor: Int, strokeColor: Int): GradientDrawable {
        return GradientDrawable().apply {
            shape = GradientDrawable.RECTANGLE
            cornerRadius = dp(12).toFloat()
            setColor(fillColor)
            setStroke(dp(1), strokeColor)
        }
    }

    private fun dp(value: Int): Int {
        return (value * resources.displayMetrics.density).toInt()
    }

    companion object {
        private const val EXTRA_USERNAME = "username"
        private const val MAX_SUMMARY_ROWS = 5
        private const val USER_REACTIONS_PAGE_SIZE = 20

        fun intent(context: Context, username: String): Intent {
            return Intent(context, ProfileActivity::class.java).apply {
                putExtra(EXTRA_USERNAME, username)
            }
        }
    }
}
