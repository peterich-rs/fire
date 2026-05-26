package com.fire.app

import android.content.Context
import android.content.Intent
import android.graphics.Color
import android.graphics.Rect
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.os.Bundle
import android.text.InputType
import android.view.View
import android.view.ViewGroup
import android.widget.Button
import android.widget.EditText
import android.widget.LinearLayout
import android.widget.ScrollView
import android.widget.TextView
import androidx.appcompat.app.AlertDialog
import androidx.appcompat.app.AppCompatActivity
import androidx.lifecycle.lifecycleScope
import com.fire.app.databinding.ActivityTopicDetailBinding
import com.fire.app.session.FireSessionStore
import com.fire.app.session.FireSessionStoreRepository
import kotlinx.coroutines.launch
import uniffi.fire_uniffi.plainTextFromHtml
import uniffi.fire_uniffi_session.TopicCategoryState
import uniffi.fire_uniffi_topics.PollOptionState
import uniffi.fire_uniffi_topics.PollState
import uniffi.fire_uniffi_topics.PostActionTypeState
import uniffi.fire_uniffi_topics.PostFlagRequestState
import uniffi.fire_uniffi_topics.PostReactionUpdateState
import uniffi.fire_uniffi_topics.PostUpdateRequestState
import uniffi.fire_uniffi_topics.ReactionUserState
import uniffi.fire_uniffi_topics.ReactionUsersGroupState
import uniffi.fire_uniffi_topics.TopicAiSummaryState
import uniffi.fire_uniffi_topics.TopicDetailQueryState
import uniffi.fire_uniffi_topics.TopicDetailState
import uniffi.fire_uniffi_topics.TopicPostState
import uniffi.fire_uniffi_topics.TopicReactionState
import uniffi.fire_uniffi_topics.TopicReplyRequestState
import uniffi.fire_uniffi_topics.TopicResponseCursorState
import uniffi.fire_uniffi_topics.TopicResponsePageQueryState
import uniffi.fire_uniffi_topics.TopicResponseRowState
import uniffi.fire_uniffi_topics.TopicScreenQueryState
import uniffi.fire_uniffi_topics.TopicScreenState
import uniffi.fire_uniffi_topics.TopicUpdateRequestState
import uniffi.fire_uniffi_topics.VotedUserState

class TopicDetailActivity : AppCompatActivity() {
    private enum class TopicNotificationLevelOption(
        val value: Int,
        val titleResId: Int,
        val descriptionResId: Int,
    ) {
        MUTED(
            value = 0,
            titleResId = R.string.topic_detail_notification_muted,
            descriptionResId = R.string.topic_detail_notification_muted_description,
        ),
        REGULAR(
            value = 1,
            titleResId = R.string.topic_detail_notification_regular,
            descriptionResId = R.string.topic_detail_notification_regular_description,
        ),
        TRACKING(
            value = 2,
            titleResId = R.string.topic_detail_notification_tracking,
            descriptionResId = R.string.topic_detail_notification_tracking_description,
        ),
        WATCHING(
            value = 3,
            titleResId = R.string.topic_detail_notification_watching,
            descriptionResId = R.string.topic_detail_notification_watching_description,
        );

        companion object {
            fun fromValue(value: Int?): TopicNotificationLevelOption =
                entries.firstOrNull { it.value == value } ?: REGULAR
        }
    }

    private data class BookmarkEditorTarget(
        val bookmarkId: ULong?,
        val bookmarkableId: ULong,
        val bookmarkableType: String,
        val title: String,
        val initialName: String?,
        val initialReminderAt: String?,
        val targetPostNumber: UInt?,
    )

    private data class TopicTimelineRow(
        val post: TopicPostState,
        val parentPostNumber: UInt?,
        val depth: Int,
        val isOriginalPost: Boolean,
    )

    private lateinit var binding: ActivityTopicDetailBinding
    private lateinit var sessionStore: FireSessionStore

    private var topicId: ULong = 0uL
    private var topicTitle: String = ""
    private var initialTargetPostNumber: UInt? = null
    private var topicCategories: Map<ULong, TopicCategoryState> = emptyMap()
    private var renderBaseUrl: String = "https://linux.do"
    private var enabledReactionIds: List<String> = listOf(HEART_REACTION_ID)
    private var minPostLength: UInt = 1u
    private var minTopicTitleLength: UInt = 1u
    private var canWriteAuthenticatedApi: Boolean = false
    private var currentScreen: TopicScreenState? = null
    private var currentDetail: TopicDetailState? = null
    private var currentResponseRows: MutableList<TopicResponseRowState> = mutableListOf()
    private var nextResponseCursor: TopicResponseCursorState? = null
    private var isLoadingMoreResponsePage: Boolean = false
    private var detailRenderGeneration: Int = 0
    private var topicAiSummaryView: View? = null
    private val postViewsByNumber: MutableMap<UInt, View> = mutableMapOf()

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        binding = ActivityTopicDetailBinding.inflate(layoutInflater)
        setContentView(binding.root)

        topicId = intent.getLongExtra(EXTRA_TOPIC_ID, -1L).takeIf { it > 0 }?.toULong() ?: 0uL
        topicTitle = intent.getStringExtra(EXTRA_TOPIC_TITLE).orEmpty()
        if (topicId == 0uL) {
            finish()
            return
        }

        sessionStore = FireSessionStoreRepository.get(applicationContext)
        initialTargetPostNumber = intent.getLongExtra(EXTRA_TARGET_POST_NUMBER, -1L)
            .takeIf { it > 0 }
            ?.toUInt()

        binding.backButton.setOnClickListener { finish() }
        binding.refreshButton.setOnClickListener { loadTopicDetail(force = true) }
        binding.editTopicButton.visibility = View.GONE
        binding.editTopicButton.isEnabled = false
        binding.editTopicButton.setOnClickListener {
            currentDetail?.let(::showTopicEditor)
        }
        binding.topicBookmarkButton.isEnabled = false
        binding.topicBookmarkButton.setOnClickListener {
            currentDetail?.let(::showTopicBookmarkEditor)
        }
        binding.topicNotificationButton.visibility = View.GONE
        binding.topicNotificationButton.isEnabled = false
        binding.topicNotificationButton.setOnClickListener {
            currentDetail?.let(::showTopicNotificationPicker)
        }
        binding.replyTopicButton.setOnClickListener { showReplyComposer(replyToPost = null) }
        binding.pageTitleText.text = topicTitle.ifBlank { getString(R.string.topic_detail_title_fallback, topicId.toString()) }

        loadTopicDetail(targetPostNumber = initialTargetPostNumber)
    }

    private fun loadTopicDetail(force: Boolean = false, targetPostNumber: UInt? = null) {
        lifecycleScope.launch {
            setLoading(true)
            binding.errorText.visibility = View.GONE

            try {
                fetchAndRenderTopicDetail(force = force, targetPostNumber = targetPostNumber)
                targetPostNumber?.let(::scrollToPostNumber)
            } catch (error: Exception) {
                currentScreen = null
                currentDetail = null
                currentResponseRows.clear()
                nextResponseCursor = null
                binding.editTopicButton.visibility = View.GONE
                binding.editTopicButton.isEnabled = false
                binding.topicNotificationButton.visibility = View.GONE
                binding.topicNotificationButton.isEnabled = false
                binding.topicBookmarkButton.isEnabled = false
                binding.pageMetaText.text = getString(R.string.topic_detail_error)
                binding.postsContainer.removeAllViews()
                binding.errorText.text = error.localizedMessage ?: getString(R.string.topic_detail_error)
                binding.errorText.visibility = View.VISIBLE
            } finally {
                setLoading(false)
            }
        }
    }

    private suspend fun fetchAndRenderTopicDetail(force: Boolean = false, targetPostNumber: UInt? = null) {
        val restored = sessionStore.restorePersistedSessionIfAvailable() ?: sessionStore.snapshot()
        topicCategories = restored.bootstrap.categories.associateBy { it.id }
        renderBaseUrl = restored.bootstrap.baseUrl.ifBlank { "https://linux.do" }
        enabledReactionIds = normalizedReactionIds(restored.bootstrap.enabledReactionIds)
        minPostLength = restored.bootstrap.minPostLength.takeIf { it > 0u } ?: 1u
        minTopicTitleLength = restored.bootstrap.minTopicTitleLength.takeIf { it > 0u } ?: 1u
        canWriteAuthenticatedApi = restored.readiness.canWriteAuthenticatedApi

        val screen = sessionStore.fetchTopicScreen(
            TopicScreenQueryState(
                topicId = topicId,
                targetPostNumber = targetPostNumber,
                rootPageSize = 10.toUShort(),
                trackVisit = !force,
            ),
        )
        currentScreen = screen
        currentResponseRows = screen.response.rows.toMutableList()
        nextResponseCursor = screen.response.nextCursor
        renderDetail(screen)
    }

    private fun renderDetail(screen: TopicScreenState) {
        val detail = synthesizeTopicDetail(screen, currentResponseRows)
        currentDetail = detail
        val renderGeneration = ++detailRenderGeneration
        topicAiSummaryView = null
        updateTopicEditButton(detail)
        updateTopicBookmarkButton(detail)
        updateTopicNotificationButton(detail)
        val timelineRows = buildTimelineRows(screen.body.post, currentResponseRows)
        val tagNames = TopicPresentation.tagNames(detail.tags)
        binding.pageTitleText.text = detail.title
        binding.pageMetaText.text = buildList {
            add(getString(R.string.topic_detail_topic_number, detail.id.toString()))
            categoryLabelFor(detail.categoryId)?.let(::add)
            detail.details.createdBy?.username?.let(::add)
            TopicPresentation.formatTimestamp(detail.createdAt)?.let(::add)
            add(getString(R.string.topic_detail_posts_count, detail.postsCount.toString()))
            add(getString(R.string.topic_detail_views_count, detail.views.toString()))
            add(getString(R.string.topic_detail_likes_count, detail.likeCount.toString()))
            detail.lastReadPostNumber?.let { add(getString(R.string.topic_detail_last_read, it.toString())) }
            bookmarkSummary(detail.bookmarked, detail.bookmarkName, detail.bookmarkReminderAt)?.let(::add)
            if (tagNames.isNotEmpty()) {
                add("#${tagNames.joinToString(" #")}")
            }
        }.joinToString(" · ")

        binding.postsContainer.removeAllViews()
        postViewsByNumber.clear()
        if (showsTopicVote(detail)) {
            binding.postsContainer.addView(topicVotePanelView(detail))
        }
        if (showsTopicAiSummary(detail)) {
            val loadingView = topicAiSummaryLoadingView()
            topicAiSummaryView = loadingView
            binding.postsContainer.addView(loadingView)
            loadAndRenderTopicAiSummary(detail, renderGeneration)
        }
        if (timelineRows.isEmpty()) {
            binding.postsContainer.addView(sectionBodyText(getString(R.string.topic_detail_empty_posts)))
            return
        }

        timelineRows.firstOrNull { it.isOriginalPost }?.post?.let { originalPost ->
            binding.postsContainer.addView(
                sectionCard(
                    title = getString(R.string.topic_detail_original_post),
                    subtitle = null,
                    accentColor = sectionAccentColor(),
                ) {
                    addView(
                        postCardView(
                            post = originalPost,
                            roleLabel = getString(R.string.topic_detail_original_post_badge),
                            depth = 0,
                            emphasized = true,
                        ),
                    )
                },
            )
        }

        val replyPosts = timelineRows.filterNot { it.isOriginalPost }
        if (replyPosts.isEmpty()) {
            binding.postsContainer.addView(
                sectionBodyText(getString(R.string.topic_detail_no_replies)),
            )
            return
        }

        binding.postsContainer.addView(
            sectionCard(
                title = getString(R.string.topic_detail_replies_section),
                subtitle = getString(
                    R.string.topic_detail_replies_count,
                    screen.response.totalResponseCount.toString(),
                ),
                accentColor = sectionAccentColor(alpha = 0x66),
            ) {
                replyPosts.forEach { row ->
                    addView(
                        postCardView(
                            post = row.post,
                            roleLabel = replyContextLabel(row.post, row.parentPostNumber)
                                ?: getString(R.string.topic_detail_reply_to_topic),
                            depth = row.depth,
                            emphasized = row.depth == 0,
                            replyTargetPostNumber = row.parentPostNumber,
                        ),
                    )
                }
                if (nextResponseCursor != null) {
                    addView(
                        Button(context).apply {
                            text = getString(
                                if (isLoadingMoreResponsePage) {
                                    R.string.topic_detail_loading_more_replies
                                } else {
                                    R.string.topic_detail_load_more_replies
                                },
                            )
                            isEnabled = !isLoadingMoreResponsePage
                            setOnClickListener { loadMoreResponsePage() }
                        },
                    )
                }
            },
        )
    }

    private fun showsTopicAiSummary(detail: TopicDetailState): Boolean {
        return detail.summarizable || detail.hasCachedSummary || detail.hasSummary
    }

    private fun loadAndRenderTopicAiSummary(detail: TopicDetailState, renderGeneration: Int) {
        lifecycleScope.launch {
            val result = runCatching {
                sessionStore.fetchTopicAiSummary(detail.id, skipAgeCheck = false)
            }
            if (renderGeneration != detailRenderGeneration || currentDetail?.id != detail.id) {
                return@launch
            }

            result.onSuccess { summary ->
                val trimmedSummary = summary?.summarizedText?.trim().orEmpty()
                if (summary == null || trimmedSummary.isEmpty()) {
                    replaceTopicAiSummaryView(null)
                } else {
                    replaceTopicAiSummaryView(topicAiSummaryCardView(summary))
                }
            }.onFailure { error ->
                replaceTopicAiSummaryView(
                    topicAiSummaryErrorView(
                        message = error.localizedMessage ?: getString(R.string.topic_detail_ai_summary_error),
                        detail = detail,
                        renderGeneration = renderGeneration,
                    ),
                )
            }
        }
    }

    private fun replaceTopicAiSummaryView(nextView: View?) {
        val previous = topicAiSummaryView
        val previousIndex = previous?.let { binding.postsContainer.indexOfChild(it) } ?: -1
        if (previousIndex >= 0) {
            binding.postsContainer.removeViewAt(previousIndex)
            if (nextView != null) {
                binding.postsContainer.addView(nextView, previousIndex)
            }
        }
        topicAiSummaryView = nextView
    }

    private fun topicAiSummaryLoadingView(): View {
        return sectionCard(
            title = getString(R.string.topic_detail_ai_summary_title),
            subtitle = getString(R.string.topic_detail_ai_summary_loading),
            accentColor = sectionAccentColor(alpha = 0x99),
        ) {
            addView(sectionBodyText(getString(R.string.topic_detail_ai_summary_loading)))
        }
    }

    private fun topicAiSummaryErrorView(
        message: String,
        detail: TopicDetailState,
        renderGeneration: Int,
    ): View {
        return sectionCard(
            title = getString(R.string.topic_detail_ai_summary_title),
            subtitle = getString(R.string.topic_detail_ai_summary_error),
            accentColor = Color.parseColor("#FFB91C1C"),
        ) {
            addView(
                sectionBodyText(message).apply {
                    setTextColor(Color.parseColor("#FFB91C1C"))
                },
            )
            addView(
                Button(context).apply {
                    text = getString(R.string.topic_detail_ai_summary_retry)
                    setOnClickListener {
                        val loadingView = topicAiSummaryLoadingView()
                        replaceTopicAiSummaryView(loadingView)
                        loadAndRenderTopicAiSummary(detail, renderGeneration)
                    }
                },
            )
        }
    }

    private fun topicAiSummaryCardView(summary: TopicAiSummaryState): View {
        return sectionCard(
            title = getString(R.string.topic_detail_ai_summary_title),
            subtitle = topicAiSummarySubtitle(summary),
            accentColor = sectionAccentColor(alpha = 0x99),
        ) {
            addView(
                sectionBodyText(summary.summarizedText.trim()).apply {
                    setTextColor(Color.parseColor("#FF111827"))
                },
            )
        }
    }

    private fun topicAiSummarySubtitle(summary: TopicAiSummaryState): String? {
        val parts = buildList {
            TopicPresentation.formatTimestamp(summary.updatedAt)?.let {
                add(getString(R.string.topic_detail_ai_summary_updated, it))
            }
            if (summary.outdated && summary.newPostsSinceSummary > 0u) {
                add(getString(R.string.topic_detail_ai_summary_new_posts, summary.newPostsSinceSummary.toString()))
            }
            summary.algorithm?.trim()?.takeIf { it.isNotEmpty() }?.let(::add)
            if (summary.canRegenerate) {
                add(getString(R.string.topic_detail_ai_summary_can_regenerate))
            }
        }
        return parts.takeIf { it.isNotEmpty() }?.joinToString(" · ")
    }

    private fun synthesizeTopicDetail(
        screen: TopicScreenState,
        responseRows: List<TopicResponseRowState>,
    ): TopicDetailState {
        val posts = buildList {
            add(screen.body.post)
            addAll(responseRows.map { it.post })
        }
        return TopicDetailState(
            id = screen.header.topicId,
            title = screen.header.title,
            slug = screen.header.slug,
            postsCount = screen.header.postsCount,
            categoryId = screen.header.categoryId,
            tags = screen.header.tags,
            views = screen.header.views,
            likeCount = screen.header.likeCount,
            createdAt = screen.header.createdAt,
            lastReadPostNumber = screen.header.lastReadPostNumber,
            bookmarks = screen.header.bookmarks,
            bookmarked = screen.header.bookmarked,
            bookmarkId = screen.header.bookmarkId,
            bookmarkName = screen.header.bookmarkName,
            bookmarkReminderAt = screen.header.bookmarkReminderAt,
            acceptedAnswer = screen.header.acceptedAnswer,
            hasAcceptedAnswer = screen.header.hasAcceptedAnswer,
            canVote = screen.header.canVote,
            voteCount = screen.header.voteCount,
            userVoted = screen.header.userVoted,
            summarizable = screen.header.summarizable,
            hasCachedSummary = screen.header.hasCachedSummary,
            hasSummary = screen.header.hasSummary,
            archetype = screen.header.archetype,
            postStream = uniffi.fire_uniffi_topics.TopicPostStreamState(
                posts = posts,
                stream = posts.map { it.id },
            ),
            details = screen.header.details,
        )
    }

    private fun buildTimelineRows(
        bodyPost: TopicPostState,
        responseRows: List<TopicResponseRowState>,
    ): List<TopicTimelineRow> {
        val rows = ArrayList<TopicTimelineRow>(responseRows.size + 1)
        rows += TopicTimelineRow(
            post = bodyPost,
            parentPostNumber = null,
            depth = 0,
            isOriginalPost = true,
        )
        responseRows.forEach { row ->
            rows += TopicTimelineRow(
                post = row.post,
                parentPostNumber = row.parentPostNumber,
                depth = row.depth.toInt(),
                isOriginalPost = false,
            )
        }
        return rows
    }

    private fun loadMoreResponsePage() {
        val cursor = nextResponseCursor ?: return
        if (isLoadingMoreResponsePage) {
            return
        }
        lifecycleScope.launch {
            isLoadingMoreResponsePage = true
            try {
                val page = sessionStore.fetchTopicResponsePage(
                    TopicResponsePageQueryState(cursor = cursor),
                )
                currentResponseRows.addAll(page.rows)
                nextResponseCursor = page.nextCursor
                currentScreen?.let(::renderDetail)
            } catch (error: Exception) {
                binding.errorText.text = error.localizedMessage ?: getString(R.string.topic_detail_error)
                binding.errorText.visibility = View.VISIBLE
            } finally {
                isLoadingMoreResponsePage = false
            }
        }
    }

    private fun sectionCard(
        title: String,
        subtitle: String?,
        accentColor: Int,
        contentBuilder: LinearLayout.() -> Unit,
    ): View {
        return LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(dp(16), dp(16), dp(16), dp(16))
            layoutParams = LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.WRAP_CONTENT,
            ).apply {
                leftMargin = dp(16)
                rightMargin = dp(16)
                topMargin = dp(12)
            }
            background = roundedBackground(
                fillColor = Color.parseColor("#FFF6F7FB"),
                strokeColor = accentColor,
            )

            addView(
                TextView(context).apply {
                    text = title
                    textSize = 18f
                    setTypeface(typeface, Typeface.BOLD)
                    setTextColor(Color.parseColor("#FF111827"))
                },
            )

            subtitle?.let {
                addView(
                    TextView(context).apply {
                        text = it
                        textSize = 12f
                        setTextColor(Color.parseColor("#FF6B7280"))
                        setPadding(0, dp(4), 0, 0)
                    },
                )
            }

            contentBuilder()
        }
    }

    private fun postCardView(
        post: TopicPostState,
        roleLabel: String?,
        depth: Int,
        emphasized: Boolean,
        replyTargetPostNumber: UInt? = null,
    ): View {
        val accentColor = if (emphasized) sectionAccentColor() else Color.parseColor("#FF6B91FF")
        val fillColor = if (emphasized) Color.WHITE else Color.parseColor("#FFF9FAFB")
        val strokeColor = if (emphasized) Color.parseColor("#1F2F6FEB") else Color.parseColor("#1F6B91FF")

        return LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            layoutParams = LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.WRAP_CONTENT,
            ).apply {
                topMargin = dp(12)
                marginStart = dp(minOf(depth, 3) * 18)
            }
            postViewsByNumber[post.postNumber] = this

            addView(
                View(context).apply {
                    layoutParams = LinearLayout.LayoutParams(dp(3), ViewGroup.LayoutParams.MATCH_PARENT)
                    background = GradientDrawable().apply {
                        shape = GradientDrawable.RECTANGLE
                        cornerRadius = dp(3).toFloat()
                        setColor(accentColor)
                    }
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
                        marginStart = dp(10)
                    }
                    setPadding(dp(12), dp(12), dp(12), dp(12))
                    background = roundedBackground(fillColor = fillColor, strokeColor = strokeColor)

                    roleLabel?.let {
                        addView(
                            chipView(
                                text = it,
                                accentColor = accentColor,
                                onClick = replyTargetPostNumber?.let { target ->
                                    { openPostNumber(target) }
                                },
                            ),
                        )
                    }

                    addView(
                        TextView(context).apply {
                            text = post.username.ifBlank { "Unknown" }
                            textSize = 16f
                            setTypeface(typeface, Typeface.BOLD)
                            setTextColor(Color.parseColor("#FF2F6FEB"))
                            if (roleLabel != null) {
                                setPadding(0, dp(8), 0, 0)
                            }
                            setOnClickListener { openProfile(post.username) }
                            isClickable = true
                        },
                    )

                    addView(
                        TextView(context).apply {
                            text = buildList {
                                add("#${post.postNumber}")
                                TopicPresentation.formatTimestamp(post.createdAt)?.let(::add)
                                add(getString(R.string.topic_detail_likes_count, post.likeCount.toString()))
                                if (post.replyCount > 0u) {
                                    add(getString(R.string.topic_detail_replies_count, post.replyCount.toString()))
                                }
                                replyContextLabel(
                                    post = post,
                                    fallbackPostNumber = replyTargetPostNumber
                                        ?: post.replyToPostNumber?.takeIf { it != 0u && it != post.postNumber },
                                )?.let(::add)
                            }.joinToString(" · ")
                            textSize = 12f
                            setTextColor(Color.parseColor("#FF6B7280"))
                            setPadding(0, dp(4), 0, 0)
                        },
                    )

                    addView(
                        FireCookedHtmlRenderer.render(
                            context = context,
                            rawHtml = post.cooked,
                            baseUrl = renderBaseUrl,
                        ),
                    )

                    if (post.polls.isNotEmpty()) {
                        addView(pollCardsView(post))
                    }

                    addView(postInteractionRow(post))

                    if (post.replyCount > 0u || post.replyToPostNumber != null) {
                        addView(
                            Button(context).apply {
                                text = if (post.replyCount > 0u) {
                                    getString(R.string.topic_detail_replies_count, post.replyCount.toString())
                                } else {
                                    getString(R.string.topic_detail_reply_context_history)
                                }
                                setOnClickListener { showReplyContext(post) }
                                setPadding(0, dp(6), 0, 0)
                            },
                        )
                    }
                },
            )
        }
    }

    private fun postInteractionRow(post: TopicPostState): View {
        return LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(0, dp(10), 0, 0)

            addView(
                LinearLayout(context).apply {
                    orientation = LinearLayout.HORIZONTAL
                    gravity = android.view.Gravity.CENTER_VERTICAL

                    addView(
                        Button(context).apply {
                            isAllCaps = false
                            text = heartButtonTitle(post)
                            isEnabled = canToggleHeart(post)
                            setOnClickListener { toggleHeart(post) }
                            layoutParams = LinearLayout.LayoutParams(
                                ViewGroup.LayoutParams.WRAP_CONTENT,
                                ViewGroup.LayoutParams.WRAP_CONTENT,
                            )
                        },
                    )

                    addView(
                        Button(context).apply {
                            isAllCaps = false
                            text = getString(R.string.topic_detail_reply_post)
                            setOnClickListener { showReplyComposer(post) }
                            layoutParams = LinearLayout.LayoutParams(
                                ViewGroup.LayoutParams.WRAP_CONTENT,
                                ViewGroup.LayoutParams.WRAP_CONTENT,
                            ).apply {
                                marginStart = dp(8)
                            }
                        },
                    )

                    if (availableCustomReactionIds(post).isNotEmpty()) {
                        addView(
                            Button(context).apply {
                                isAllCaps = false
                                text = getString(R.string.topic_detail_react_post)
                                isEnabled = canToggleReaction(post)
                                setOnClickListener { showReactionPicker(post) }
                                layoutParams = LinearLayout.LayoutParams(
                                    ViewGroup.LayoutParams.WRAP_CONTENT,
                                    ViewGroup.LayoutParams.WRAP_CONTENT,
                                ).apply {
                                    marginStart = dp(8)
                                }
                            },
                        )
                    }

                    if (canManagePost(post)) {
                        addView(
                            Button(context).apply {
                                isAllCaps = false
                                text = getString(R.string.topic_detail_post_actions)
                                setOnClickListener { showPostActions(post) }
                                layoutParams = LinearLayout.LayoutParams(
                                    ViewGroup.LayoutParams.WRAP_CONTENT,
                                    ViewGroup.LayoutParams.WRAP_CONTENT,
                                ).apply {
                                    marginStart = dp(8)
                                }
                            },
                        )
                    }
                },
            )

            reactionSummary(post)?.let { summary ->
                addView(
                    TextView(context).apply {
                        text = summary
                        textSize = 12f
                        setTextColor(Color.parseColor("#FF2F6FEB"))
                        setPadding(0, dp(4), 0, 0)
                        maxLines = 2
                        isClickable = true
                        setOnClickListener { showReactionUsers(post, initialReactionId = null) }
                    },
                )
            }
        }
    }

    private fun pollCardsView(post: TopicPostState): View {
        return LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(0, dp(10), 0, 0)
            post.polls.forEach { poll ->
                addView(pollCardView(post, poll))
            }
        }
    }

    private fun pollCardView(post: TopicPostState, poll: PollState): View {
        val isClosed = isPollClosed(poll)
        val canVote = canWriteAuthenticatedApi && !isClosed
        val isMultiple = isMultiplePoll(poll)
        val selectedOptions = poll.userVotes.toSet()

        return LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(dp(12), dp(12), dp(12), dp(12))
            background = roundedBackground(
                fillColor = Color.parseColor("#FFF6F7FB"),
                strokeColor = Color.parseColor("#1F2F6FEB"),
                cornerRadiusDp = 12,
            )
            layoutParams = LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.WRAP_CONTENT,
            ).apply {
                topMargin = dp(8)
            }

            addView(
                TextView(context).apply {
                    text = pollHeaderTitle(poll, isMultiple, isClosed)
                    textSize = 14f
                    setTypeface(typeface, Typeface.BOLD)
                    setTextColor(Color.parseColor("#FF111827"))
                },
            )

            poll.options.forEach { option ->
                addView(
                    pollOptionButton(
                        post = post,
                        poll = poll,
                        option = option,
                        selected = option.id in selectedOptions,
                        canVote = canVote && !isMultiple,
                    ),
                )
            }

            addView(
                LinearLayout(context).apply {
                    orientation = LinearLayout.HORIZONTAL
                    gravity = android.view.Gravity.CENTER_VERTICAL
                    setPadding(0, dp(8), 0, 0)

                    addView(
                        TextView(context).apply {
                            text = getString(R.string.topic_detail_poll_voters_count, poll.voters.toString())
                            textSize = 12f
                            setTextColor(Color.parseColor("#FF6B7280"))
                            layoutParams = LinearLayout.LayoutParams(
                                0,
                                ViewGroup.LayoutParams.WRAP_CONTENT,
                                1f,
                            )
                        },
                    )

                    if (selectedOptions.isNotEmpty()) {
                        addView(
                            Button(context).apply {
                                isAllCaps = false
                                text = getString(R.string.topic_detail_poll_unvote)
                                isEnabled = canVote
                                setOnClickListener { unvotePoll(post, poll) }
                            },
                        )
                    }

                    if (isMultiple) {
                        addView(
                            Button(context).apply {
                                isAllCaps = false
                                text = getString(R.string.topic_detail_poll_choose)
                                isEnabled = canVote
                                setOnClickListener { showMultiplePollPicker(post, poll) }
                                layoutParams = LinearLayout.LayoutParams(
                                    ViewGroup.LayoutParams.WRAP_CONTENT,
                                    ViewGroup.LayoutParams.WRAP_CONTENT,
                                ).apply {
                                    if (selectedOptions.isNotEmpty()) {
                                        marginStart = dp(8)
                                    }
                                }
                            },
                        )
                    }
                },
            )
        }
    }

    private fun pollOptionButton(
        post: TopicPostState,
        poll: PollState,
        option: PollOptionState,
        selected: Boolean,
        canVote: Boolean,
    ): View {
        return Button(this).apply {
            isAllCaps = false
            textAlignment = View.TEXT_ALIGNMENT_VIEW_START
            text = pollOptionTitle(option, selected)
            isEnabled = canVote
            setOnClickListener { votePoll(post, poll, listOf(option.id)) }
            layoutParams = LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.WRAP_CONTENT,
            ).apply {
                topMargin = dp(6)
            }
        }
    }

    private fun showMultiplePollPicker(post: TopicPostState, poll: PollState) {
        val selectedIds = poll.userVotes.toMutableSet()
        val checkedItems = poll.options.map { it.id in selectedIds }.toBooleanArray()
        val dialog = AlertDialog.Builder(this)
            .setTitle(getString(R.string.topic_detail_poll_choose_title, pollDisplayName(poll)))
            .setMultiChoiceItems(
                poll.options.map { pollOptionLabel(it) }.toTypedArray(),
                checkedItems,
            ) { _, index, checked ->
                val optionId = poll.options[index].id
                if (checked) {
                    selectedIds.add(optionId)
                } else {
                    selectedIds.remove(optionId)
                }
            }
            .setPositiveButton(R.string.topic_detail_poll_submit, null)
            .setNegativeButton(R.string.action_cancel, null)
            .create()
        dialog.setOnShowListener {
            dialog.getButton(AlertDialog.BUTTON_POSITIVE).setOnClickListener {
                val selected = poll.options.map { it.id }.filter { it in selectedIds }
                if (selected.isEmpty()) {
                    binding.errorText.text = getString(R.string.topic_detail_poll_select_required)
                    binding.errorText.visibility = View.VISIBLE
                    return@setOnClickListener
                }
                dialog.dismiss()
                votePoll(post, poll, selected)
            }
        }
        dialog.show()
    }

    private fun votePoll(post: TopicPostState, poll: PollState, options: List<String>) {
        lifecycleScope.launch {
            setLoading(true)
            binding.errorText.visibility = View.GONE
            try {
                sessionStore.votePoll(post.id, poll.name, options)
                fetchAndRenderTopicDetail(force = true, targetPostNumber = post.postNumber)
                scrollToPostNumber(post.postNumber)
            } catch (error: Exception) {
                binding.errorText.text = error.localizedMessage ?: getString(R.string.topic_detail_poll_error)
                binding.errorText.visibility = View.VISIBLE
            } finally {
                setLoading(false)
            }
        }
    }

    private fun unvotePoll(post: TopicPostState, poll: PollState) {
        lifecycleScope.launch {
            setLoading(true)
            binding.errorText.visibility = View.GONE
            try {
                sessionStore.unvotePoll(post.id, poll.name)
                fetchAndRenderTopicDetail(force = true, targetPostNumber = post.postNumber)
                scrollToPostNumber(post.postNumber)
            } catch (error: Exception) {
                binding.errorText.text = error.localizedMessage ?: getString(R.string.topic_detail_poll_error)
                binding.errorText.visibility = View.VISIBLE
            } finally {
                setLoading(false)
            }
        }
    }

    private fun pollHeaderTitle(poll: PollState, isMultiple: Boolean, isClosed: Boolean): String {
        return buildList {
            add(pollDisplayName(poll))
            if (isMultiple) {
                add(getString(R.string.topic_detail_poll_multiple))
            }
            if (isClosed) {
                add(getString(R.string.topic_detail_poll_closed))
            }
        }.joinToString(" · ")
    }

    private fun pollDisplayName(poll: PollState): String {
        return poll.name.trim().ifBlank { getString(R.string.topic_detail_poll_title) }
    }

    private fun pollOptionTitle(option: PollOptionState, selected: Boolean): String {
        return buildString {
            append(if (selected) "[x] " else "[ ] ")
            append(pollOptionLabel(option))
            append(" · ")
            append(getString(R.string.topic_detail_poll_votes_count, option.votes.toString()))
        }
    }

    private fun pollOptionLabel(option: PollOptionState): String {
        return plainTextFromHtml(rawHtml = option.html).trim().ifBlank { option.id }
    }

    private fun isMultiplePoll(poll: PollState): Boolean {
        return poll.kind.contains("multiple", ignoreCase = true)
    }

    private fun isPollClosed(poll: PollState): Boolean {
        return poll.status.contains("closed", ignoreCase = true)
    }

    private fun showReplyComposer(replyToPost: TopicPostState?) {
        val input = EditText(this).apply {
            hint = getString(R.string.topic_detail_reply_hint)
            minLines = 5
            inputType = InputType.TYPE_CLASS_TEXT or
                InputType.TYPE_TEXT_FLAG_MULTI_LINE or
                InputType.TYPE_TEXT_FLAG_CAP_SENTENCES
            setPadding(dp(16), dp(8), dp(16), dp(8))
        }

        val title = replyToPost?.let {
            getString(R.string.topic_detail_reply_post_title, it.postNumber.toString())
        } ?: getString(R.string.topic_detail_reply_topic_title)

        val dialog = AlertDialog.Builder(this)
            .setTitle(title)
            .setView(input)
            .setPositiveButton(R.string.topic_detail_reply_submit, null)
            .setNegativeButton(R.string.action_cancel, null)
            .create()
        dialog.setOnShowListener {
            dialog.getButton(AlertDialog.BUTTON_POSITIVE).setOnClickListener {
                val raw = input.text?.toString()?.trim().orEmpty()
                if (raw.length < minPostLength.toInt()) {
                    input.error = getString(R.string.topic_detail_reply_min_length, minPostLength.toString())
                    return@setOnClickListener
                }
                dialog.dismiss()
                submitReply(raw = raw, replyToPostNumber = replyToPost?.postNumber)
            }
        }
        dialog.show()
    }

    private fun submitReply(raw: String, replyToPostNumber: UInt?) {
        lifecycleScope.launch {
            setLoading(true)
            binding.errorText.visibility = View.GONE
            try {
                val created = sessionStore.createReply(
                    TopicReplyRequestState(
                        topicId = topicId,
                        raw = raw,
                        replyToPostNumber = replyToPostNumber,
                    ),
                )
                fetchAndRenderTopicDetail(force = true, targetPostNumber = created.postNumber)
                scrollToPostNumber(created.postNumber)
            } catch (error: Exception) {
                binding.errorText.text = error.localizedMessage ?: getString(R.string.topic_detail_reply_error)
                binding.errorText.visibility = View.VISIBLE
            } finally {
                setLoading(false)
            }
        }
    }

    private fun showReactionPicker(post: TopicPostState) {
        val reactionIds = availableCustomReactionIds(post)
        if (reactionIds.isEmpty()) {
            return
        }

        AlertDialog.Builder(this)
            .setTitle(getString(R.string.topic_detail_reaction_title, post.postNumber.toString()))
            .setItems(reactionIds.map { reactionPickerTitle(post, it) }.toTypedArray()) { _, index ->
                toggleReaction(post, reactionIds[index])
            }
            .setNegativeButton(R.string.action_cancel, null)
            .show()
    }

    private fun toggleReaction(post: TopicPostState, reactionId: String) {
        val normalized = reactionId.trim()
        if (normalized.isEmpty()) {
            return
        }
        lifecycleScope.launch {
            setLoading(true)
            binding.errorText.visibility = View.GONE
            try {
                val update = sessionStore.togglePostReaction(post.id, normalized)
                applyReactionUpdate(post, update)
                fetchAndRenderTopicDetail(force = true, targetPostNumber = post.postNumber)
                scrollToPostNumber(post.postNumber)
            } catch (error: Exception) {
                binding.errorText.text = error.localizedMessage ?: getString(R.string.topic_detail_reaction_error)
                binding.errorText.visibility = View.VISIBLE
            } finally {
                setLoading(false)
            }
        }
    }

    private fun toggleHeart(post: TopicPostState) {
        lifecycleScope.launch {
            setLoading(true)
            binding.errorText.visibility = View.GONE
            try {
                val liked = hasHeartReaction(post)
                val update = if (liked) {
                    sessionStore.unlikePost(post.id)
                } else {
                    sessionStore.likePost(post.id)
                }
                update?.let { applyReactionUpdate(post, it) }
                fetchAndRenderTopicDetail(force = true, targetPostNumber = post.postNumber)
                scrollToPostNumber(post.postNumber)
            } catch (error: Exception) {
                binding.errorText.text = error.localizedMessage ?: getString(R.string.topic_detail_like_error)
                binding.errorText.visibility = View.VISIBLE
            } finally {
                setLoading(false)
            }
        }
    }

    private fun canToggleReaction(post: TopicPostState): Boolean {
        val currentReaction = post.currentUserReaction ?: return true
        return currentReaction.canUndo ?: true
    }

    private fun canManagePost(post: TopicPostState): Boolean {
        return (post.canEdit && !post.hidden) || (post.canDelete && !post.hidden) || post.canRecover || !post.hidden
    }

    private fun showPostActions(post: TopicPostState) {
        val actions = buildList<Pair<String, () -> Unit>> {
            if (post.canEdit && !post.hidden) {
                add(getString(R.string.topic_detail_edit_post) to { showPostEditor(post) })
            }
            if (!post.hidden) {
                add(bookmarkActionTitle(post.bookmarkId) to { showPostBookmarkEditor(post) })
            }
            if (post.canDelete && !post.hidden) {
                add(getString(R.string.topic_detail_delete_post) to { confirmDeletePost(post) })
            }
            if (post.canRecover) {
                add(getString(R.string.topic_detail_recover_post) to { confirmRecoverPost(post) })
            }
            if (!post.hidden) {
                add(getString(R.string.topic_detail_flag_post) to { showFlagTypePicker(post) })
            }
        }

        if (actions.isEmpty()) {
            return
        }

        AlertDialog.Builder(this)
            .setTitle(getString(R.string.topic_detail_post_actions_title, post.postNumber.toString()))
            .setItems(actions.map { it.first }.toTypedArray()) { _, index ->
                actions[index].second.invoke()
            }
            .setNegativeButton(R.string.action_cancel, null)
            .show()
    }

    private fun showTopicEditor(detail: TopicDetailState) {
        val categories = topicCategoriesForEditor(detail.categoryId)
        var selectedCategory = detail.categoryId?.let { currentCategoryId ->
            categories.firstOrNull { it.id == currentCategoryId }
        } ?: categories.firstOrNull()

        if (selectedCategory == null) {
            binding.errorText.text = getString(R.string.topic_detail_edit_topic_no_categories)
            binding.errorText.visibility = View.VISIBLE
            return
        }

        val titleInput = EditText(this).apply {
            hint = getString(R.string.topic_detail_edit_topic_title_hint)
            setSingleLine(false)
            maxLines = 3
            inputType = InputType.TYPE_CLASS_TEXT or InputType.TYPE_TEXT_FLAG_CAP_SENTENCES
            setText(detail.title)
        }
        val categoryText = TextView(this).apply {
            text = topicCategoryEditorLabel(selectedCategory!!)
            textSize = 14f
            setPadding(0, dp(10), 0, 0)
        }
        val categoryButton = Button(this).apply {
            isAllCaps = false
            text = getString(R.string.topic_detail_edit_topic_select_category)
            setOnClickListener {
                showTopicCategoryPicker(categories, selectedCategory!!) { category ->
                    selectedCategory = category
                    categoryText.text = topicCategoryEditorLabel(category)
                }
            }
        }
        val tagsInput = EditText(this).apply {
            hint = getString(R.string.topic_detail_edit_topic_tags_hint)
            setSingleLine(false)
            maxLines = 2
            inputType = InputType.TYPE_CLASS_TEXT
            setText(TopicPresentation.tagNames(detail.tags).joinToString(" "))
        }
        val content = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(dp(20), dp(8), dp(20), dp(4))
            addView(labelText(getString(R.string.topic_detail_edit_topic_title_label)))
            addView(titleInput)
            addView(labelText(getString(R.string.topic_detail_edit_topic_category_label)))
            addView(categoryText)
            addView(categoryButton)
            addView(labelText(getString(R.string.topic_detail_edit_topic_tags_label)))
            addView(tagsInput)
        }

        val dialog = AlertDialog.Builder(this)
            .setTitle(R.string.topic_detail_edit_topic_title)
            .setView(ScrollView(this).apply { addView(content) })
            .setPositiveButton(R.string.topic_detail_edit_save, null)
            .setNegativeButton(R.string.action_cancel, null)
            .create()

        dialog.setOnShowListener {
            dialog.getButton(AlertDialog.BUTTON_POSITIVE).setOnClickListener {
                val title = titleInput.text?.toString()?.trim().orEmpty()
                val category = selectedCategory
                val tags = parseTopicTags(tagsInput.text?.toString().orEmpty())
                val disallowedTags = category?.let { disallowedTopicTags(tags, it) }.orEmpty()

                when {
                    title.length < minTopicTitleLength.toInt() -> {
                        titleInput.error = getString(
                            R.string.topic_detail_edit_topic_title_min_length,
                            minTopicTitleLength.toString(),
                        )
                    }
                    category == null -> {
                        categoryText.error = getString(R.string.topic_detail_edit_topic_category_required)
                    }
                    tags.size < category.minimumRequiredTags.toInt() -> {
                        tagsInput.error = getString(
                            R.string.topic_detail_edit_topic_tags_required,
                            category.minimumRequiredTags.toString(),
                        )
                    }
                    disallowedTags.isNotEmpty() -> {
                        tagsInput.error = getString(
                            R.string.topic_detail_edit_topic_tags_not_allowed,
                            disallowedTags.joinToString(", "),
                        )
                    }
                    else -> {
                        dialog.dismiss()
                        submitTopicEdit(title, category.id, tags)
                    }
                }
            }
        }
        dialog.show()
    }

    private fun showPostEditor(post: TopicPostState) {
        val rawInput = EditText(this).apply {
            hint = getString(R.string.topic_detail_edit_post_body_hint)
            minLines = 8
            inputType = InputType.TYPE_CLASS_TEXT or
                InputType.TYPE_TEXT_FLAG_MULTI_LINE or
                InputType.TYPE_TEXT_FLAG_CAP_SENTENCES
            setPadding(dp(16), dp(8), dp(16), dp(8))
            setText(post.raw ?: plainTextFromHtml(post.cooked))
        }
        val reasonInput = EditText(this).apply {
            hint = getString(R.string.topic_detail_edit_post_reason_hint)
            setSingleLine(false)
            maxLines = 2
            inputType = InputType.TYPE_CLASS_TEXT or InputType.TYPE_TEXT_FLAG_CAP_SENTENCES
        }
        val content = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(dp(20), dp(8), dp(20), dp(4))
            addView(labelText(getString(R.string.topic_detail_edit_post_body_label)))
            addView(rawInput)
            addView(labelText(getString(R.string.topic_detail_edit_post_reason_label)))
            addView(reasonInput)
        }

        val dialog = AlertDialog.Builder(this)
            .setTitle(getString(R.string.topic_detail_edit_post_title, post.postNumber.toString()))
            .setView(ScrollView(this).apply { addView(content) })
            .setPositiveButton(R.string.topic_detail_edit_save, null)
            .setNegativeButton(R.string.action_cancel, null)
            .create()

        dialog.setOnShowListener {
            dialog.getButton(AlertDialog.BUTTON_POSITIVE).setOnClickListener {
                val raw = rawInput.text?.toString()?.trim().orEmpty()
                val editReason = reasonInput.text?.toString()?.trim()?.takeIf { it.isNotEmpty() }
                if (raw.length < minPostLength.toInt()) {
                    rawInput.error = getString(R.string.topic_detail_edit_post_min_length, minPostLength.toString())
                    return@setOnClickListener
                }
                dialog.dismiss()
                submitPostEdit(post, raw, editReason)
            }
        }
        dialog.show()
    }

    private fun submitTopicEdit(title: String, categoryId: ULong, tags: List<String>) {
        lifecycleScope.launch {
            setLoading(true)
            binding.errorText.visibility = View.GONE
            try {
                sessionStore.updateTopic(
                    TopicUpdateRequestState(
                        topicId = topicId,
                        title = title,
                        categoryId = categoryId,
                        tags = tags,
                    ),
                )
                fetchAndRenderTopicDetail(force = true)
            } catch (error: Exception) {
                binding.errorText.text = error.localizedMessage ?: getString(R.string.topic_detail_edit_topic_error)
                binding.errorText.visibility = View.VISIBLE
            } finally {
                setLoading(false)
            }
        }
    }

    private fun submitPostEdit(post: TopicPostState, raw: String, editReason: String?) {
        lifecycleScope.launch {
            setLoading(true)
            binding.errorText.visibility = View.GONE
            try {
                sessionStore.updatePost(
                    PostUpdateRequestState(
                        postId = post.id,
                        raw = raw,
                        editReason = editReason,
                    ),
                )
                fetchAndRenderTopicDetail(force = true, targetPostNumber = post.postNumber)
                scrollToPostNumber(post.postNumber)
            } catch (error: Exception) {
                binding.errorText.text = error.localizedMessage ?: getString(R.string.topic_detail_edit_post_error)
                binding.errorText.visibility = View.VISIBLE
            } finally {
                setLoading(false)
            }
        }
    }

    private fun showTopicBookmarkEditor(detail: TopicDetailState) {
        showBookmarkEditor(
            BookmarkEditorTarget(
                bookmarkId = detail.bookmarkId,
                bookmarkableId = detail.id,
                bookmarkableType = BOOKMARK_TYPE_TOPIC,
                title = detail.title,
                initialName = detail.bookmarkName,
                initialReminderAt = detail.bookmarkReminderAt,
                targetPostNumber = null,
            ),
        )
    }

    private fun showPostBookmarkEditor(post: TopicPostState) {
        showBookmarkEditor(
            BookmarkEditorTarget(
                bookmarkId = post.bookmarkId,
                bookmarkableId = post.id,
                bookmarkableType = BOOKMARK_TYPE_POST,
                title = buildList {
                    add(getString(R.string.topic_detail_floor_title, post.postNumber.toString()))
                    post.username.takeIf { it.isNotBlank() }?.let(::add)
                }.joinToString(" · "),
                initialName = post.bookmarkName,
                initialReminderAt = post.bookmarkReminderAt,
                targetPostNumber = post.postNumber,
            ),
        )
    }

    private fun showBookmarkEditor(target: BookmarkEditorTarget) {
        val nameInput = EditText(this).apply {
            hint = getString(R.string.topic_detail_bookmark_name_hint)
            setSingleLine(false)
            maxLines = 2
            inputType = InputType.TYPE_CLASS_TEXT or InputType.TYPE_TEXT_FLAG_CAP_SENTENCES
            setText(target.initialName.orEmpty())
        }
        val reminderInput = EditText(this).apply {
            hint = getString(R.string.topic_detail_bookmark_reminder_hint)
            setSingleLine(true)
            inputType = InputType.TYPE_CLASS_TEXT
            setText(target.initialReminderAt.orEmpty())
        }
        val content = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(dp(20), dp(8), dp(20), dp(4))
            addView(sectionBodyText(target.title))
            addView(labelText(getString(R.string.topic_detail_bookmark_name_label)))
            addView(nameInput)
            addView(labelText(getString(R.string.topic_detail_bookmark_reminder_label)))
            addView(reminderInput)
        }

        val builder = AlertDialog.Builder(this)
            .setTitle(
                if (target.bookmarkId == null) {
                    R.string.topic_detail_bookmark_add_title
                } else {
                    R.string.topic_detail_bookmark_edit_title
                },
            )
            .setView(ScrollView(this).apply { addView(content) })
            .setPositiveButton(R.string.topic_detail_bookmark_save, null)
            .setNegativeButton(R.string.action_cancel, null)
        if (target.bookmarkId != null) {
            builder.setNeutralButton(R.string.topic_detail_bookmark_delete, null)
        }
        val dialog = builder.create()

        dialog.setOnShowListener {
            dialog.getButton(AlertDialog.BUTTON_POSITIVE).setOnClickListener {
                val name = nameInput.text?.toString()?.trim()?.takeIf { it.isNotEmpty() }
                val reminderAt = reminderInput.text?.toString()?.trim()?.takeIf { it.isNotEmpty() }
                dialog.dismiss()
                submitBookmark(target, name, reminderAt)
            }
            target.bookmarkId?.let { bookmarkId ->
                dialog.getButton(AlertDialog.BUTTON_NEUTRAL).setOnClickListener {
                    dialog.dismiss()
                    deleteBookmark(target, bookmarkId)
                }
            }
        }
        dialog.show()
    }

    private fun submitBookmark(
        target: BookmarkEditorTarget,
        name: String?,
        reminderAt: String?,
    ) {
        lifecycleScope.launch {
            setLoading(true)
            binding.errorText.visibility = View.GONE
            try {
                val bookmarkId = target.bookmarkId
                if (bookmarkId == null) {
                    sessionStore.createBookmark(
                        bookmarkableId = target.bookmarkableId,
                        bookmarkableType = target.bookmarkableType,
                        name = name,
                        reminderAt = reminderAt,
                    )
                } else {
                    sessionStore.updateBookmark(
                        bookmarkId = bookmarkId,
                        name = name,
                        reminderAt = reminderAt,
                    )
                }
                refreshAfterBookmarkChange(target)
            } catch (error: Exception) {
                binding.errorText.text = error.localizedMessage ?: getString(R.string.topic_detail_bookmark_error)
                binding.errorText.visibility = View.VISIBLE
            } finally {
                setLoading(false)
            }
        }
    }

    private fun deleteBookmark(target: BookmarkEditorTarget, bookmarkId: ULong) {
        lifecycleScope.launch {
            setLoading(true)
            binding.errorText.visibility = View.GONE
            try {
                sessionStore.deleteBookmark(bookmarkId)
                refreshAfterBookmarkChange(target)
            } catch (error: Exception) {
                binding.errorText.text = error.localizedMessage ?: getString(R.string.topic_detail_bookmark_error)
                binding.errorText.visibility = View.VISIBLE
            } finally {
                setLoading(false)
            }
        }
    }

    private fun showsTopicVote(detail: TopicDetailState): Boolean {
        return detail.canVote || detail.userVoted || detail.voteCount > 0
    }

    private fun topicVotePanelView(detail: TopicDetailState): View {
        return LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(dp(16), dp(14), dp(16), dp(14))
            layoutParams = LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.WRAP_CONTENT,
            ).apply {
                leftMargin = dp(16)
                rightMargin = dp(16)
                topMargin = dp(12)
            }
            background = roundedBackground(
                fillColor = Color.parseColor("#FFF6F7FB"),
                strokeColor = Color.parseColor("#1F2F6FEB"),
                cornerRadiusDp = 16,
            )

            addView(
                TextView(context).apply {
                    text = buildList {
                        add(getString(R.string.topic_detail_vote_count, detail.voteCount.toString()))
                        if (detail.userVoted) {
                            add(getString(R.string.topic_detail_vote_you_voted))
                        }
                    }.joinToString(" · ")
                    textSize = 14f
                    setTypeface(typeface, Typeface.BOLD)
                    setTextColor(Color.parseColor("#FF2F6FEB"))
                },
            )

            addView(
                LinearLayout(context).apply {
                    orientation = LinearLayout.HORIZONTAL
                    gravity = android.view.Gravity.CENTER_VERTICAL
                    setPadding(0, dp(10), 0, 0)

                    addView(
                        Button(context).apply {
                            isAllCaps = false
                            text = if (detail.userVoted) {
                                getString(R.string.topic_detail_unvote_topic)
                            } else {
                                getString(R.string.topic_detail_vote_topic)
                            }
                            isEnabled = canWriteAuthenticatedApi
                            setOnClickListener { toggleTopicVote(detail) }
                        },
                    )

                    addView(
                        Button(context).apply {
                            isAllCaps = false
                            text = getString(R.string.topic_detail_vote_voters)
                            setOnClickListener { showTopicVotersDialog() }
                            layoutParams = LinearLayout.LayoutParams(
                                ViewGroup.LayoutParams.WRAP_CONTENT,
                                ViewGroup.LayoutParams.WRAP_CONTENT,
                            ).apply {
                                marginStart = dp(8)
                            }
                        },
                    )
                },
            )
        }
    }

    private fun toggleTopicVote(detail: TopicDetailState) {
        lifecycleScope.launch {
            setLoading(true)
            binding.errorText.visibility = View.GONE
            try {
                if (detail.userVoted) {
                    sessionStore.unvoteTopic(detail.id)
                } else {
                    sessionStore.voteTopic(detail.id)
                }
                fetchAndRenderTopicDetail(force = true)
            } catch (error: Exception) {
                binding.errorText.text = error.localizedMessage ?: getString(R.string.topic_detail_vote_error)
                binding.errorText.visibility = View.VISIBLE
            } finally {
                setLoading(false)
            }
        }
    }

    private fun showTopicVotersDialog() {
        val content = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(dp(20), dp(12), dp(20), dp(8))
            addView(sectionBodyText(getString(R.string.topic_detail_vote_voters_loading)))
        }
        val dialog = AlertDialog.Builder(this)
            .setTitle(R.string.topic_detail_vote_voters_title)
            .setView(ScrollView(this).apply { addView(content) })
            .setNegativeButton(R.string.action_close, null)
            .create()
        dialog.show()

        lifecycleScope.launch {
            try {
                val voters = sessionStore.fetchTopicVoters(topicId)
                renderTopicVoters(content, voters)
            } catch (error: Exception) {
                content.removeAllViews()
                content.addView(
                    sectionBodyText(error.localizedMessage ?: getString(R.string.topic_detail_vote_error)).apply {
                        setTextColor(Color.parseColor("#FFB91C1C"))
                    },
                )
            }
        }
    }

    private fun renderTopicVoters(content: LinearLayout, voters: List<VotedUserState>) {
        content.removeAllViews()
        if (voters.isEmpty()) {
            content.addView(sectionBodyText(getString(R.string.topic_detail_vote_voters_empty)))
            return
        }

        voters.forEach { voter ->
            content.addView(
                TextView(this).apply {
                    text = buildList {
                        val displayName = voter.name?.takeIf { it.isNotBlank() } ?: voter.username
                        add(displayName)
                        voter.username.takeIf { it.isNotBlank() }?.let { add("@$it") }
                    }.joinToString(" · ")
                    textSize = 14f
                    setTextColor(Color.parseColor("#FF111827"))
                    setPadding(0, dp(8), 0, dp(8))
                    setOnClickListener { openProfile(voter.username) }
                    isClickable = voter.username.isNotBlank()
                },
            )
        }
    }

    private fun showReactionUsers(post: TopicPostState, initialReactionId: String? = null) {
        val content = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(dp(20), dp(12), dp(20), dp(8))
            addView(sectionBodyText(getString(R.string.topic_detail_reaction_users_loading)))
        }
        val dialog = AlertDialog.Builder(this)
            .setTitle(R.string.topic_detail_reaction_users_title)
            .setView(ScrollView(this).apply { addView(content) })
            .setNegativeButton(R.string.action_close, null)
            .create()
        dialog.show()

        lifecycleScope.launch {
            try {
                val groups = sessionStore.fetchReactionUsers(post.id)
                renderReactionUsers(content, groups, initialReactionId)
            } catch (error: Exception) {
                content.removeAllViews()
                content.addView(
                    sectionBodyText(error.localizedMessage ?: getString(R.string.topic_detail_reaction_users_error)).apply {
                        setTextColor(Color.parseColor("#FFB91C1C"))
                    },
                )
            }
        }
    }

    private fun renderReactionUsers(
        content: LinearLayout,
        groups: List<ReactionUsersGroupState>,
        selectedReactionId: String? = null,
    ) {
        content.removeAllViews()
        val orderedGroups = orderedReactionUsersGroups(groups, selectedReactionId)
        if (orderedGroups.isEmpty()) {
            content.addView(sectionBodyText(getString(R.string.topic_detail_reaction_users_empty)))
            return
        }

        orderedGroups.forEach { group ->
            content.addView(
                labelText(getString(R.string.topic_detail_reaction_users_group, group.id, group.count.toString())),
            )
            if (group.users.isEmpty()) {
                content.addView(sectionBodyText(getString(R.string.topic_detail_reaction_users_empty)))
            } else {
                group.users.forEach { user ->
                    content.addView(reactionUserRow(user))
                }
            }
        }
    }

    private fun orderedReactionUsersGroups(
        groups: List<ReactionUsersGroupState>,
        selectedReactionId: String?,
    ): List<ReactionUsersGroupState> {
        val selected = selectedReactionId?.trim()?.takeIf { it.isNotEmpty() } ?: return groups
        return groups.sortedBy { group ->
            if (group.id.equals(selected, ignoreCase = true)) 0 else 1
        }
    }

    private fun reactionUserRow(user: ReactionUserState): TextView {
        return TextView(this).apply {
            text = buildList {
                val displayName = user.name?.takeIf { it.isNotBlank() } ?: user.username
                add(displayName)
                user.username.takeIf { it.isNotBlank() }?.let { add("@$it") }
            }.joinToString(" · ")
            textSize = 14f
            setTextColor(Color.parseColor("#FF111827"))
            setPadding(0, dp(8), 0, dp(8))
            if (user.username.isNotBlank()) {
                isClickable = true
                setOnClickListener { openProfile(user.username) }
            }
        }
    }

    private suspend fun refreshAfterBookmarkChange(target: BookmarkEditorTarget) {
        fetchAndRenderTopicDetail(force = true, targetPostNumber = target.targetPostNumber)
        target.targetPostNumber?.let(::scrollToPostNumber)
    }

    private fun confirmDeletePost(post: TopicPostState) {
        AlertDialog.Builder(this)
            .setTitle(getString(R.string.topic_detail_delete_confirm_title, post.postNumber.toString()))
            .setMessage(R.string.topic_detail_delete_confirm_message)
            .setPositiveButton(R.string.topic_detail_delete_post) { _, _ ->
                runPostManagementOperation(post, getString(R.string.topic_detail_action_error)) {
                    sessionStore.deletePost(post.id)
                }
            }
            .setNegativeButton(R.string.action_cancel, null)
            .show()
    }

    private fun confirmRecoverPost(post: TopicPostState) {
        AlertDialog.Builder(this)
            .setTitle(getString(R.string.topic_detail_recover_confirm_title, post.postNumber.toString()))
            .setMessage(R.string.topic_detail_recover_confirm_message)
            .setPositiveButton(R.string.topic_detail_recover_post) { _, _ ->
                runPostManagementOperation(post, getString(R.string.topic_detail_action_error)) {
                    sessionStore.recoverPost(post.id)
                }
            }
            .setNegativeButton(R.string.action_cancel, null)
            .show()
    }

    private fun showFlagTypePicker(post: TopicPostState) {
        lifecycleScope.launch {
            setLoading(true)
            binding.errorText.visibility = View.GONE
            try {
                val flagTypes = sessionStore.fetchPostActionTypes()
                    .filter(::isPostFlagAction)
                    .sortedWith(compareBy<PostActionTypeState> { it.position }.thenBy { it.id })

                if (flagTypes.isEmpty()) {
                    binding.errorText.text = getString(R.string.topic_detail_flag_empty)
                    binding.errorText.visibility = View.VISIBLE
                    return@launch
                }

                AlertDialog.Builder(this@TopicDetailActivity)
                    .setTitle(getString(R.string.topic_detail_flag_type_title, post.postNumber.toString()))
                    .setItems(flagTypes.map(::flagActionTitle).toTypedArray()) { _, index ->
                        showFlagSubmissionDialog(post, flagTypes[index])
                    }
                    .setNegativeButton(R.string.action_cancel, null)
                    .show()
            } catch (error: Exception) {
                binding.errorText.text = error.localizedMessage ?: getString(R.string.topic_detail_flag_error)
                binding.errorText.visibility = View.VISIBLE
            } finally {
                setLoading(false)
            }
        }
    }

    private fun showFlagSubmissionDialog(post: TopicPostState, flagType: PostActionTypeState) {
        if (!flagType.requireMessage) {
            AlertDialog.Builder(this)
                .setTitle(getString(R.string.topic_detail_flag_confirm_title, flagActionTitle(flagType)))
                .setMessage(flagType.description.ifBlank { getString(R.string.topic_detail_flag_confirm_message) })
                .setPositiveButton(R.string.topic_detail_flag_submit) { _, _ ->
                    submitFlagPost(post, flagType, null)
                }
                .setNegativeButton(R.string.action_cancel, null)
                .show()
            return
        }

        val input = EditText(this).apply {
            hint = getString(R.string.topic_detail_flag_message_hint)
            minLines = 3
            inputType = InputType.TYPE_CLASS_TEXT or InputType.TYPE_TEXT_FLAG_MULTI_LINE
            setPadding(dp(16), dp(8), dp(16), dp(8))
        }

        val dialog = AlertDialog.Builder(this)
            .setTitle(getString(R.string.topic_detail_flag_message_title, flagActionTitle(flagType)))
            .setView(input)
            .setPositiveButton(R.string.topic_detail_flag_submit, null)
            .setNegativeButton(R.string.action_cancel, null)
            .create()
        dialog.setOnShowListener {
            dialog.getButton(AlertDialog.BUTTON_POSITIVE).setOnClickListener {
                val message = input.text?.toString()?.trim().orEmpty()
                if (message.isEmpty()) {
                    input.error = getString(R.string.topic_detail_flag_message_required)
                    return@setOnClickListener
                }
                dialog.dismiss()
                submitFlagPost(post, flagType, message)
            }
        }
        dialog.show()
    }

    private fun submitFlagPost(post: TopicPostState, flagType: PostActionTypeState, message: String?) {
        runPostManagementOperation(post, getString(R.string.topic_detail_flag_error)) {
            sessionStore.flagPost(
                PostFlagRequestState(
                    postId = post.id,
                    flagTypeId = flagType.id,
                    message = message?.trim()?.takeIf { it.isNotEmpty() },
                ),
            )
        }
    }

    private fun runPostManagementOperation(
        post: TopicPostState,
        fallbackError: String,
        operation: suspend () -> Unit,
    ) {
        lifecycleScope.launch {
            setLoading(true)
            binding.errorText.visibility = View.GONE
            try {
                operation()
                fetchAndRenderTopicDetail(force = true, targetPostNumber = post.postNumber)
                scrollToPostNumber(post.postNumber)
            } catch (error: Exception) {
                binding.errorText.text = error.localizedMessage ?: fallbackError
                binding.errorText.visibility = View.VISIBLE
            } finally {
                setLoading(false)
            }
        }
    }

    private fun isPostFlagAction(actionType: PostActionTypeState): Boolean {
        if (!actionType.enabled || !actionType.isFlag) {
            return false
        }
        return actionType.appliesTo.isEmpty() ||
            actionType.appliesTo.any { it.equals("Post", ignoreCase = true) }
    }

    private fun flagActionTitle(actionType: PostActionTypeState): String {
        return actionType.name.ifBlank {
            actionType.shortDescription?.takeIf { it.isNotBlank() }
                ?: actionType.nameKey.ifBlank { getString(R.string.topic_detail_flag_type_fallback, actionType.id.toString()) }
        }
    }

    private fun applyReactionUpdate(post: TopicPostState, update: PostReactionUpdateState) {
        post.reactions = update.reactions
        post.currentUserReaction = update.currentUserReaction
        post.likeCount = heartReactionCount(update.reactions)
    }

    private fun heartButtonTitle(post: TopicPostState): String {
        val count = heartReactionCount(post).toString()
        return if (hasHeartReaction(post)) {
            getString(R.string.topic_detail_unlike_post, count)
        } else {
            getString(R.string.topic_detail_like_post, count)
        }
    }

    private fun updateTopicEditButton(detail: TopicDetailState) {
        binding.editTopicButton.visibility = if (detail.details.canEdit) View.VISIBLE else View.GONE
        binding.editTopicButton.isEnabled = detail.details.canEdit
    }

    private fun updateTopicBookmarkButton(detail: TopicDetailState) {
        binding.topicBookmarkButton.isEnabled = true
        binding.topicBookmarkButton.text = if (detail.bookmarkId != null || detail.bookmarked) {
            getString(R.string.topic_detail_bookmark_topic_active)
        } else {
            getString(R.string.topic_detail_bookmark_topic)
        }
    }

    private fun updateTopicNotificationButton(detail: TopicDetailState) {
        if (isPrivateMessageThread(detail)) {
            binding.topicNotificationButton.visibility = View.GONE
            binding.topicNotificationButton.isEnabled = false
            return
        }

        val option = TopicNotificationLevelOption.fromValue(detail.details.notificationLevel)
        binding.topicNotificationButton.visibility = View.VISIBLE
        binding.topicNotificationButton.isEnabled = canWriteAuthenticatedApi
        binding.topicNotificationButton.text = getString(
            R.string.topic_detail_notification_button,
            getString(option.titleResId),
        )
    }

    private fun showTopicNotificationPicker(detail: TopicDetailState) {
        if (isPrivateMessageThread(detail)) {
            return
        }
        val options = TopicNotificationLevelOption.entries.toTypedArray()
        val current = TopicNotificationLevelOption.fromValue(detail.details.notificationLevel)
        val currentIndex = options.indexOf(current).coerceAtLeast(0)

        AlertDialog.Builder(this)
            .setTitle(R.string.topic_detail_notification_title)
            .setSingleChoiceItems(
                options.map(::topicNotificationOptionLabel).toTypedArray(),
                currentIndex,
            ) { dialog, which ->
                dialog.dismiss()
                val selected = options[which]
                if (selected != current) {
                    updateTopicNotificationLevel(detail, selected)
                }
            }
            .setNegativeButton(R.string.action_cancel, null)
            .show()
    }

    private fun topicNotificationOptionLabel(option: TopicNotificationLevelOption): String {
        return getString(
            R.string.topic_detail_notification_option,
            getString(option.titleResId),
            getString(option.descriptionResId),
        )
    }

    private fun updateTopicNotificationLevel(
        detail: TopicDetailState,
        option: TopicNotificationLevelOption,
    ) {
        lifecycleScope.launch {
            setLoading(true)
            binding.errorText.visibility = View.GONE
            try {
                sessionStore.setTopicNotificationLevel(detail.id, option.value)
                fetchAndRenderTopicDetail(force = true)
            } catch (error: Exception) {
                binding.errorText.text = error.localizedMessage ?: getString(R.string.topic_detail_notification_error)
                binding.errorText.visibility = View.VISIBLE
            } finally {
                setLoading(false)
            }
        }
    }

    private fun isPrivateMessageThread(detail: TopicDetailState): Boolean {
        return detail.archetype?.equals("private_message", ignoreCase = true) == true
    }

    private fun bookmarkActionTitle(bookmarkId: ULong?): String {
        return if (bookmarkId == null) {
            getString(R.string.topic_detail_bookmark_post)
        } else {
            getString(R.string.topic_detail_bookmark_post_active)
        }
    }

    private fun bookmarkSummary(
        bookmarked: Boolean,
        bookmarkName: String?,
        bookmarkReminderAt: String?,
    ): String? {
        if (!bookmarked && bookmarkName.isNullOrBlank() && bookmarkReminderAt.isNullOrBlank()) {
            return null
        }
        return buildList {
            add(getString(R.string.topic_detail_bookmarked))
            bookmarkName?.takeIf { it.isNotBlank() }?.let {
                add(getString(R.string.feed_bookmark_name, it))
            }
            TopicPresentation.formatTimestamp(bookmarkReminderAt)?.let {
                add(getString(R.string.feed_bookmark_reminder, it))
            }
        }.joinToString(" · ")
    }

    private fun hasHeartReaction(post: TopicPostState): Boolean {
        return post.currentUserReaction?.id?.equals(HEART_REACTION_ID, ignoreCase = true) == true
    }

    private fun canToggleHeart(post: TopicPostState): Boolean {
        val currentReaction = post.currentUserReaction ?: return true
        return currentReaction.id.equals(HEART_REACTION_ID, ignoreCase = true) &&
            (currentReaction.canUndo ?: true)
    }

    private fun heartReactionCount(post: TopicPostState): UInt {
        return post.reactions
            .firstOrNull { it.id.equals(HEART_REACTION_ID, ignoreCase = true) }
            ?.count
            ?: post.likeCount
    }

    private fun heartReactionCount(reactions: List<TopicReactionState>): UInt {
        return reactions
            .firstOrNull { it.id.equals(HEART_REACTION_ID, ignoreCase = true) }
            ?.count
            ?: 0u
    }

    private fun availableReactionIds(post: TopicPostState): List<String> {
        return normalizedReactionIds(
            enabledReactionIds +
                post.reactions.map { it.id } +
                listOfNotNull(post.currentUserReaction?.id),
        )
    }

    private fun availableCustomReactionIds(post: TopicPostState): List<String> {
        return availableReactionIds(post)
            .filterNot { it.equals(HEART_REACTION_ID, ignoreCase = true) }
    }

    private fun normalizedReactionIds(ids: List<String>): List<String> {
        val seen = mutableSetOf<String>()
        val normalized = ids.mapNotNull { id ->
            val trimmed = id.trim()
            if (trimmed.isEmpty()) {
                null
            } else {
                trimmed.takeIf { seen.add(it.lowercase()) }
            }
        }
        return normalized.ifEmpty { listOf(HEART_REACTION_ID) }
    }

    private fun reactionPickerTitle(post: TopicPostState, reactionId: String): String {
        val count = post.reactions
            .firstOrNull { it.id.equals(reactionId, ignoreCase = true) }
            ?.count
            ?: 0u
        val selected = post.currentUserReaction?.id?.equals(reactionId, ignoreCase = true) == true
        val title = getString(R.string.topic_detail_reaction_choice, reactionId, count.toString())
        return if (selected) {
            getString(R.string.topic_detail_reaction_choice_selected, title)
        } else {
            title
        }
    }

    private fun reactionSummary(post: TopicPostState): String? {
        val parts = post.reactions.mapNotNull { reaction ->
            val id = reaction.id.trim().takeIf { it.isNotEmpty() } ?: return@mapNotNull null
            "$id ${reaction.count}"
        }
        return parts.takeIf { it.isNotEmpty() }?.joinToString(" · ")
    }

    private fun replyContextLabel(post: TopicPostState, fallbackPostNumber: UInt?): String? {
        val targetPostNumber = post.replyToPostNumber ?: fallbackPostNumber
        if (targetPostNumber == null || targetPostNumber == 0u) {
            return null
        }

        val username = post.replyToUser?.username?.trim().orEmpty()
        return if (username.isNotEmpty()) {
            getString(R.string.topic_detail_reply_to_user, username)
        } else {
            getString(R.string.topic_detail_reply_to, targetPostNumber.toString())
        }
    }

    private fun openPostNumber(postNumber: UInt) {
        if (postNumber == 0u) {
            return
        }
        if (postViewsByNumber.containsKey(postNumber)) {
            scrollToPostNumber(postNumber)
            return
        }
        loadTopicDetail(targetPostNumber = postNumber)
    }

    private fun openProfile(username: String) {
        val trimmed = username.trim()
        if (trimmed.isEmpty()) {
            return
        }
        startActivity(ProfileActivity.intent(this, trimmed))
    }

    private fun scrollToPostNumber(postNumber: UInt) {
        val target = postViewsByNumber[postNumber] ?: return
        binding.postsScrollView.post {
            val rect = Rect()
            target.getDrawingRect(rect)
            binding.postsScrollView.offsetDescendantRectToMyCoords(target, rect)
            binding.postsScrollView.smoothScrollTo(0, maxOf(rect.top - dp(12), 0))
        }
    }

    private fun showReplyContext(post: TopicPostState) {
        val content = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(dp(20), dp(12), dp(20), dp(8))
            addView(sectionBodyText(getString(R.string.topic_detail_reply_context_loading)))
        }
        val dialog = AlertDialog.Builder(this)
            .setTitle(getString(R.string.topic_detail_reply_context_title, post.postNumber.toString()))
            .setView(
                ScrollView(this).apply {
                    addView(content)
                },
            )
            .setNegativeButton(R.string.action_close, null)
            .create()
        dialog.show()

        lifecycleScope.launch {
            try {
                val (replyHistory, replies) = loadReplyContextPosts(post)
                renderReplyContextDialog(content, dialog, replyHistory, replies)
            } catch (error: Exception) {
                renderReplyContextError(content, dialog, post, error)
            }
        }
    }

    private suspend fun loadReplyContextPosts(
        post: TopicPostState,
    ): Pair<List<TopicPostState>, List<TopicPostState>> {
        val replies = loadDirectReplyPosts(post)
        val replyHistory = if (post.replyToPostNumber != null) {
            sessionStore.fetchPostReplyHistory(post.id)
        } else {
            emptyList()
        }
        return replyHistory to replies
    }

    private suspend fun loadDirectReplyPosts(post: TopicPostState): List<TopicPostState> {
        if (post.replyCount == 0u) {
            return emptyList()
        }

        val replyIds = orderedUniquePostIds(sessionStore.fetchPostReplyIds(post.id))
        if (replyIds.isEmpty()) {
            return sessionStore.fetchPostReplies(post.id, 1u)
        }

        return replyIds.chunked(REPLY_CONTEXT_POST_BATCH_SIZE).flatMap { batch ->
            sessionStore.fetchTopicPosts(topicId, batch)
        }
    }

    private fun orderedUniquePostIds(ids: List<ULong>): List<ULong> {
        val seen = mutableSetOf<ULong>()
        return ids.filter { id -> id > 0uL && seen.add(id) }
    }

    private fun renderReplyContextDialog(
        content: LinearLayout,
        dialog: AlertDialog,
        replyHistory: List<TopicPostState>,
        replies: List<TopicPostState>,
    ) {
        content.removeAllViews()

        if (replyHistory.isEmpty() && replies.isEmpty()) {
            content.addView(sectionBodyText(getString(R.string.topic_detail_reply_context_empty)))
            return
        }

        if (replyHistory.isNotEmpty()) {
            addReplyContextSection(
                content = content,
                dialog = dialog,
                title = getString(R.string.topic_detail_reply_context_history),
                posts = replyHistory,
            )
        }

        if (replies.isNotEmpty()) {
            addReplyContextSection(
                content = content,
                dialog = dialog,
                title = getString(R.string.topic_detail_reply_context_direct),
                posts = replies,
            )
        }
    }

    private fun renderReplyContextError(
        content: LinearLayout,
        dialog: AlertDialog,
        post: TopicPostState,
        error: Exception,
    ) {
        content.removeAllViews()
        content.addView(
            sectionBodyText(error.localizedMessage ?: getString(R.string.topic_detail_error)).apply {
                setTextColor(Color.parseColor("#FFB91C1C"))
            },
        )
        content.addView(
            Button(this).apply {
                text = getString(R.string.topic_detail_reply_context_retry)
                setOnClickListener {
                    content.removeAllViews()
                    content.addView(sectionBodyText(getString(R.string.topic_detail_reply_context_loading)))
                    lifecycleScope.launch {
                        try {
                            val (replyHistory, replies) = loadReplyContextPosts(post)
                            renderReplyContextDialog(content, dialog, replyHistory, replies)
                        } catch (nextError: Exception) {
                            renderReplyContextError(content, dialog, post, nextError)
                        }
                    }
                }
            },
        )
    }

    private fun addReplyContextSection(
        content: LinearLayout,
        dialog: AlertDialog,
        title: String,
        posts: List<TopicPostState>,
    ) {
        content.addView(
            TextView(this).apply {
                text = title
                textSize = 14f
                setTypeface(typeface, Typeface.BOLD)
                setTextColor(Color.parseColor("#FF111827"))
                setPadding(0, dp(10), 0, dp(6))
            },
        )
        posts.forEach { contextPost ->
            content.addView(
                replyContextRow(contextPost) {
                    dialog.dismiss()
                    openPostNumber(contextPost.postNumber)
                },
            )
        }
    }

    private fun replyContextRow(post: TopicPostState, onClick: () -> Unit): View {
        return LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(dp(12), dp(10), dp(12), dp(10))
            background = roundedBackground(
                fillColor = Color.parseColor("#FFF9FAFB"),
                strokeColor = Color.parseColor("#1F6B7280"),
                cornerRadiusDp = 12,
            )
            layoutParams = LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.WRAP_CONTENT,
            ).apply {
                bottomMargin = dp(8)
            }
            setOnClickListener { onClick() }

            addView(
                TextView(context).apply {
                    text = buildList {
                        add(post.username.ifBlank { "Unknown" })
                        add("#${post.postNumber}")
                        TopicPresentation.formatTimestamp(post.createdAt)?.let(::add)
                    }.joinToString(" · ")
                    textSize = 13f
                    setTypeface(typeface, Typeface.BOLD)
                    setTextColor(Color.parseColor("#FF2F6FEB"))
                    setOnClickListener { openProfile(post.username) }
                    isClickable = true
                },
            )
            addView(
                TextView(context).apply {
                    text = plainTextFromHtml(rawHtml = post.cooked).trim()
                        .ifBlank { getString(R.string.topic_detail_reply_context_empty) }
                    textSize = 13f
                    setTextColor(Color.parseColor("#FF4B5563"))
                    setPadding(0, dp(4), 0, 0)
                    maxLines = 3
                },
            )
        }
    }

    private fun chipView(
        text: String,
        accentColor: Int,
        onClick: (() -> Unit)? = null,
    ): View {
        return TextView(this).apply {
            this.text = text
            textSize = 11f
            setTypeface(typeface, Typeface.BOLD)
            setTextColor(accentColor)
            setPadding(dp(8), dp(4), dp(8), dp(4))
            if (onClick != null) {
                setOnClickListener { onClick() }
                isClickable = true
            }
            background = roundedBackground(
                fillColor = sectionAccentColor(alpha = 0x18),
                strokeColor = Color.TRANSPARENT,
                cornerRadiusDp = 999,
            )
        }
    }

    private fun sectionBodyText(text: String): TextView {
        return TextView(this).apply {
            this.text = text
            textSize = 14f
            setPadding(dp(16), dp(6), dp(16), dp(16))
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

    private fun topicCategoriesForEditor(currentCategoryId: ULong?): List<TopicCategoryState> {
        val writable = topicCategories.values
            .filter { category -> category.id > 0uL && (category.permission ?: 1u) > 0u }
        val current = currentCategoryId?.let(topicCategories::get)
        return (writable + listOfNotNull(current))
            .distinctBy { it.id }
            .sortedWith(compareBy<TopicCategoryState> { it.name.lowercase() }.thenBy { it.id })
    }

    private fun showTopicCategoryPicker(
        categories: List<TopicCategoryState>,
        selectedCategory: TopicCategoryState,
        onSelected: (TopicCategoryState) -> Unit,
    ) {
        val selectedIndex = categories.indexOfFirst { it.id == selectedCategory.id }.coerceAtLeast(0)
        AlertDialog.Builder(this)
            .setTitle(R.string.topic_detail_edit_topic_select_category)
            .setSingleChoiceItems(
                categories.map(::topicCategoryEditorLabel).toTypedArray(),
                selectedIndex,
            ) { dialog, which ->
                onSelected(categories[which])
                dialog.dismiss()
            }
            .setNegativeButton(R.string.action_cancel, null)
            .show()
    }

    private fun topicCategoryEditorLabel(category: TopicCategoryState): String {
        return buildList {
            add(category.displayName())
            if (category.minimumRequiredTags > 0u) {
                add(getString(R.string.create_topic_category_required_tags, category.minimumRequiredTags.toString()))
            }
            if (category.allowedTags.isNotEmpty()) {
                add(getString(R.string.create_topic_category_allowed_tags, category.allowedTags.take(6).joinToString(", ")))
            }
        }.joinToString(" · ")
    }

    private fun parseTopicTags(input: String): List<String> {
        val seen = mutableSetOf<String>()
        return input
            .split(',', '#', ' ', '\n', '\t')
            .mapNotNull { value ->
                val tag = value.trim()
                tag.takeIf { it.isNotEmpty() && seen.add(it.lowercase()) }
            }
    }

    private fun disallowedTopicTags(
        tags: List<String>,
        category: TopicCategoryState,
    ): List<String> {
        if (tags.isEmpty() || category.allowedTags.isEmpty()) {
            return emptyList()
        }
        val allowed = category.allowedTags
            .map { it.trim().lowercase() }
            .filter { it.isNotEmpty() }
            .toSet()
        if (allowed.isEmpty()) {
            return emptyList()
        }
        return tags.filter { it.trim().lowercase() !in allowed }
    }

    private fun categoryLabelFor(categoryId: ULong?): String? {
        val id = categoryId ?: return null
        return topicCategories[id]?.displayName()
            ?: getString(R.string.topic_detail_category_fallback, id.toString())
    }

    private fun setLoading(loading: Boolean) {
        binding.loadingIndicator.visibility = if (loading) View.VISIBLE else View.GONE
        binding.refreshButton.isEnabled = !loading
        binding.replyTopicButton.isEnabled = !loading
        val detail = currentDetail
        binding.editTopicButton.isEnabled = !loading && detail?.details?.canEdit == true
        binding.topicBookmarkButton.isEnabled = !loading && detail != null
        binding.topicNotificationButton.isEnabled = !loading && detail != null &&
            !isPrivateMessageThread(detail) &&
            canWriteAuthenticatedApi
    }

    private fun dp(value: Int): Int {
        return (value * resources.displayMetrics.density).toInt()
    }

    private fun roundedBackground(
        fillColor: Int,
        strokeColor: Int,
        cornerRadiusDp: Int = 18,
    ): GradientDrawable {
        return GradientDrawable().apply {
            shape = GradientDrawable.RECTANGLE
            cornerRadius = dp(cornerRadiusDp).toFloat()
            setColor(fillColor)
            if (strokeColor != Color.TRANSPARENT) {
                setStroke(dp(1), strokeColor)
            }
        }
    }

    private fun sectionAccentColor(alpha: Int = 0xFF): Int {
        return Color.argb(alpha, 0x2F, 0x6F, 0xEB)
    }

    companion object {
        private const val EXTRA_TOPIC_ID = "topic_id"
        private const val EXTRA_TOPIC_TITLE = "topic_title"
        private const val EXTRA_TARGET_POST_NUMBER = "target_post_number"
        private const val REPLY_CONTEXT_POST_BATCH_SIZE = 20
        private const val HEART_REACTION_ID = "heart"
        private const val BOOKMARK_TYPE_TOPIC = "Topic"
        private const val BOOKMARK_TYPE_POST = "Post"

        fun intent(
            context: Context,
            topicId: ULong,
            topicTitle: String,
            targetPostNumber: UInt? = null,
        ): Intent {
            return Intent(context, TopicDetailActivity::class.java).apply {
                putExtra(EXTRA_TOPIC_ID, topicId.toLong())
                putExtra(EXTRA_TOPIC_TITLE, topicTitle)
                targetPostNumber?.let {
                    putExtra(EXTRA_TARGET_POST_NUMBER, it.toLong())
                }
            }
        }
    }
}
