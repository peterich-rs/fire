package com.fire.app

import android.graphics.Typeface
import android.content.Intent
import android.os.Bundle
import android.view.View
import android.view.ViewGroup
import android.widget.Button
import android.widget.LinearLayout
import android.widget.TextView
import androidx.activity.result.contract.ActivityResultContracts
import androidx.appcompat.app.AppCompatActivity
import androidx.core.text.HtmlCompat
import androidx.lifecycle.lifecycleScope
import com.fire.app.databinding.ActivityMainBinding
import com.fire.app.session.FireSessionStore
import kotlinx.coroutines.launch
import uniffi.fire_uniffi.BootstrapState
import uniffi.fire_uniffi.CookieState
import uniffi.fire_uniffi.SessionState
import uniffi.fire_uniffi.SessionReadinessState
import uniffi.fire_uniffi.TopicDetailQueryState
import uniffi.fire_uniffi.TopicDetailState
import uniffi.fire_uniffi.TopicListKindState
import uniffi.fire_uniffi.TopicListQueryState
import uniffi.fire_uniffi.TopicListState
import uniffi.fire_uniffi.TopicPostState
import uniffi.fire_uniffi.TopicSummaryState

class MainActivity : AppCompatActivity() {
    private lateinit var binding: ActivityMainBinding
    private lateinit var sessionStore: FireSessionStore

    private var currentFeedKind = TopicListKindState.LATEST
    private var currentFeedPage: UInt = 0u
    private var nextFeedPage: UInt? = null
    private var selectedTopicId: ULong? = null
    private var currentTopicList: TopicListState? = null
    private var currentTopicDetail: TopicDetailState? = null
    private var topicCategories: Map<ULong, TopicCategoryPresentation> = emptyMap()
    private var browserStatusMessage: String? = null
    private var isBrowserLoading = false
    private var isLoadingMoreFeed = false
    private var session: SessionState = placeholderSession()

    private val loginLauncher = registerForActivityResult(
        ActivityResultContracts.StartActivityForResult(),
    ) {
        refreshSessionAndFeed()
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        binding = ActivityMainBinding.inflate(layoutInflater)
        setContentView(binding.root)

        sessionStore = FireSessionStore(applicationContext)

        binding.restoreButton.setOnClickListener { refreshSessionAndFeed() }
        binding.openLoginButton.setOnClickListener {
            loginLauncher.launch(Intent(this, LoginActivity::class.java))
        }
        binding.refreshBootstrapButton.setOnClickListener { refreshBootstrap() }
        binding.logoutButton.setOnClickListener { logout() }
        binding.refreshFeedButton.setOnClickListener { reloadCurrentFeed() }
        binding.loadMoreButton.setOnClickListener { loadMoreFeed() }

        binding.latestButton.setOnClickListener { loadFeed(TopicListKindState.LATEST) }
        binding.newButton.setOnClickListener { loadFeed(TopicListKindState.NEW) }
        binding.unreadButton.setOnClickListener { loadFeed(TopicListKindState.UNREAD) }
        binding.unseenButton.setOnClickListener { loadFeed(TopicListKindState.UNSEEN) }
        binding.hotButton.setOnClickListener { loadFeed(TopicListKindState.HOT) }
        binding.topButton.setOnClickListener { loadFeed(TopicListKindState.TOP) }

        refreshSessionAndFeed()
    }

    private fun refreshSessionAndFeed() {
        lifecycleScope.launch {
            try {
                applySession(sessionStore.restorePersistedSessionIfAvailable() ?: sessionStore.snapshot())
                renderSession(session)
                reloadCurrentFeed()
            } catch (error: Exception) {
                browserStatusMessage = error.localizedMessage
                renderSession(session)
                renderBrowser()
            }
        }
    }

    private fun refreshBootstrap() {
        lifecycleScope.launch {
            try {
                applySession(sessionStore.refreshBootstrapIfNeeded())
                renderSession(session)
                reloadCurrentFeed()
            } catch (error: Exception) {
                browserStatusMessage = error.localizedMessage
                renderSession(session)
                renderBrowser()
            }
        }
    }

    private fun logout() {
        lifecycleScope.launch {
            try {
                applySession(sessionStore.logout())
                currentFeedKind = TopicListKindState.LATEST
                currentFeedPage = 0u
                nextFeedPage = null
                selectedTopicId = null
                currentTopicList = null
                currentTopicDetail = null
                renderSession(session)
                reloadCurrentFeed()
            } catch (error: Exception) {
                browserStatusMessage = error.localizedMessage
                renderSession(session)
                renderBrowser()
            }
        }
    }

    private fun reloadCurrentFeed() {
        loadFeed(currentFeedKind, selectedTopicId, reset = true, page = null)
    }

    private fun loadMoreFeed() {
        val page = nextFeedPage ?: return
        loadFeed(currentFeedKind, selectedTopicId, reset = false, page = page)
    }

    private fun loadFeed(
        kind: TopicListKindState,
        preferredTopicId: ULong? = selectedTopicId,
        reset: Boolean = true,
        page: UInt? = null,
    ) {
        lifecycleScope.launch {
            currentFeedKind = kind
            isLoadingMoreFeed = !reset
            setBrowserLoading(
                true,
                getString(if (reset) R.string.browser_loading else R.string.browser_loading_more),
            )
            renderSession(session)
            renderBrowser()

            try {
                val response = sessionStore.fetchTopicList(
                    TopicListQueryState(
                        kind = kind,
                        page = page,
                        topicIds = emptyList(),
                        order = null,
                        ascending = null,
                    ),
                )
                currentFeedPage = page ?: 0u
                nextFeedPage = TopicPresentation.nextPage(response.moreTopicsUrl)
                currentTopicList = if (reset || currentTopicList == null) {
                    response
                } else {
                    mergeTopicLists(currentTopicList!!, response)
                }
                val topicList = currentTopicList!!

                val nextTopicId = preferredTopicId?.takeIf { id ->
                    topicList.topics.any { it.id == id }
                } ?: topicList.topics.firstOrNull()?.id
                selectedTopicId = nextTopicId
                val shouldFetchDetail = nextTopicId != null && (
                    reset || currentTopicDetail?.id != nextTopicId
                )
                if (shouldFetchDetail) {
                    currentTopicDetail = null
                }
                renderSession(session)
                renderBrowser()

                if (nextTopicId == null) {
                    setBrowserLoading(false, getString(R.string.browser_empty))
                    isLoadingMoreFeed = false
                    renderBrowser()
                    return@launch
                }

                if (shouldFetchDetail) {
                    val detail = sessionStore.fetchTopicDetail(
                        TopicDetailQueryState(
                            topicId = nextTopicId,
                            postNumber = null,
                            trackVisit = true,
                            filter = null,
                            usernameFilters = null,
                            filterTopLevelReplies = false,
                        ),
                    )
                    currentTopicDetail = detail
                }
                setBrowserLoading(false, browserFeedSummary(topicList))
                isLoadingMoreFeed = false
                renderBrowser()
            } catch (error: Exception) {
                browserStatusMessage = error.localizedMessage
                setBrowserLoading(false, browserStatusMessage)
                isLoadingMoreFeed = false
                renderSession(session)
                renderBrowser()
            }
        }
    }

    private fun openTopic(topicId: ULong) {
        lifecycleScope.launch {
            selectedTopicId = topicId
            setBrowserLoading(true, getString(R.string.browser_loading))
            renderSession(session)
            renderBrowser()

            try {
                currentTopicDetail = sessionStore.fetchTopicDetail(
                    TopicDetailQueryState(
                        topicId = topicId,
                        postNumber = null,
                        trackVisit = true,
                        filter = null,
                        usernameFilters = null,
                        filterTopLevelReplies = false,
                    ),
                )
                setBrowserLoading(false, browserFeedSummary(currentTopicList))
                renderBrowser()
            } catch (error: Exception) {
                browserStatusMessage = error.localizedMessage
                setBrowserLoading(false, browserStatusMessage)
                renderSession(session)
                renderBrowser()
            }
        }
    }

    private fun renderSession(state: SessionState) {
        binding.sessionSummaryText.text = buildString {
            appendLine("Phase: ${state.loginPhase}")
            appendLine("Has Login: ${state.hasLoginSession}")
            appendLine("Username: ${state.bootstrap.currentUsername ?: "-"}")
            appendLine("Bootstrap Ready: ${state.bootstrap.hasPreloadedData}")
            appendLine("Categories: ${topicCategories.size}")
            appendLine("Has CSRF: ${state.cookies.csrfToken != null}")
            appendLine("Read API: ${state.readiness.canReadAuthenticatedApi}")
            appendLine("Write API: ${state.readiness.canWriteAuthenticatedApi}")
            appendLine("MessageBus: ${state.readiness.canOpenMessageBus}")
        }
    }

    private fun renderBrowser() {
        updateFeedButtonState()
        binding.browserStatusText.text = browserStatusMessage ?: browserFeedSummary(currentTopicList)

        binding.topicListContainer.removeAllViews()
        val topicList = currentTopicList
        if (topicList == null || topicList.topics.isEmpty()) {
            binding.topicListContainer.addView(
                sectionBodyText(
                    if (browserStatusMessage == null) getString(R.string.browser_empty) else browserStatusMessage!!,
                ),
            )
        } else {
            topicList.topics.forEach { topic ->
                binding.topicListContainer.addView(topicButton(topic))
            }
        }
        binding.loadMoreButton.visibility = if (
            nextFeedPage != null && topicList?.topics?.isNotEmpty() == true
        ) {
            View.VISIBLE
        } else {
            View.GONE
        }
        binding.loadMoreButton.text = if (isLoadingMoreFeed) {
            getString(R.string.browser_loading_more)
        } else {
            getString(R.string.action_load_more)
        }

        binding.topicDetailTitleText.text = currentTopicDetail?.title ?: getString(R.string.browser_detail_empty)
        binding.topicDetailMetaText.text = currentTopicDetail?.let { topic ->
            buildList {
                add("Topic #${topic.id}")
                categoryLabelFor(topic.categoryId)?.let(::add)
                topic.details.createdBy?.username?.let(::add)
                TopicPresentation.formatTimestamp(topic.createdAt)?.let(::add)
                add("${topic.postsCount} posts")
                add("${topic.views} views")
                add("${topic.likeCount} likes")
                topic.lastReadPostNumber?.let { add("last read #$it") }
                if (topic.tags.isNotEmpty()) {
                    add("#${topic.tags.joinToString(" #")}")
                }
            }.joinToString(" · ")
        }.orEmpty()

        binding.topicDetailContainer.removeAllViews()
        val detail = currentTopicDetail
        if (detail == null) {
            binding.topicDetailContainer.addView(sectionBodyText(getString(R.string.browser_detail_empty)))
        } else {
            detail.postStream.posts.forEachIndexed { index, post ->
                binding.topicDetailContainer.addView(postView(post, index == 0))
            }
        }
    }

    private fun updateFeedButtonState() {
        listOf(
            binding.latestButton to TopicListKindState.LATEST,
            binding.newButton to TopicListKindState.NEW,
            binding.unreadButton to TopicListKindState.UNREAD,
            binding.unseenButton to TopicListKindState.UNSEEN,
            binding.hotButton to TopicListKindState.HOT,
            binding.topButton to TopicListKindState.TOP,
        ).forEach { (button, kind) ->
            val selected = currentFeedKind == kind
            button.alpha = if (selected) 1f else 0.75f
            button.isEnabled = !isBrowserLoading
        }
        binding.refreshFeedButton.isEnabled = !isBrowserLoading
        binding.loadMoreButton.isEnabled = !isBrowserLoading && nextFeedPage != null
    }

    private fun setBrowserLoading(loading: Boolean, message: String? = null) {
        isBrowserLoading = loading
        browserStatusMessage = message
        updateFeedButtonState()
    }

    private fun browserFeedSummary(topicList: TopicListState?): String {
        val topics = topicList?.topics.orEmpty()
        if (topics.isEmpty()) {
            return getString(R.string.browser_empty)
        }
        val selected = selectedTopicId?.let { id ->
            topics.firstOrNull { it.id == id }?.title
        }
        return buildString {
            append("${currentFeedKind.displayName()} feed")
            append(" · ${topics.size} topics")
            append(" · pages 1-${currentFeedPage.toInt() + 1}")
            if (!topicList?.moreTopicsUrl.isNullOrBlank()) {
                append(" · page ${(nextFeedPage?.toInt() ?: currentFeedPage.toInt()) + 1} ready")
            }
            if (!selected.isNullOrBlank()) {
                append(" · $selected")
            }
        }
    }

    private fun topicButton(topic: TopicSummaryState): View {
        val category = categoryLabelFor(topic.categoryId)
        val statusLabels = TopicPresentation.topicStatusLabels(topic)
        val lastActivity = listOfNotNull(
            topic.lastPosterUsername,
            TopicPresentation.formatTimestamp(topic.lastPostedAt ?: topic.createdAt),
        )
        val excerpt = topic.excerpt
            ?.takeIf { it.isNotBlank() }
            ?.let { HtmlCompat.fromHtml(it, HtmlCompat.FROM_HTML_MODE_LEGACY).toString().trim() }

        return Button(this).apply {
            isAllCaps = false
            textAlignment = View.TEXT_ALIGNMENT_VIEW_START
            text = buildString {
                if (topic.id == selectedTopicId) {
                    append("▶ ")
                }
                if (category != null) {
                    append("[$category] ")
                }
                append(topic.title)
                if (statusLabels.isNotEmpty()) {
                    append(" · ")
                    append(statusLabels.joinToString(" · "))
                }
                append("\n")
                append("${topic.postsCount} posts · ${topic.replyCount} replies · ${topic.views} views · ${topic.likeCount} likes")
                if (lastActivity.isNotEmpty()) {
                    append("\n")
                    append(lastActivity.joinToString(" · "))
                }
                if (topic.tags.isNotEmpty()) {
                    append(" · #${topic.tags.joinToString(" #")}")
                }
                if (!excerpt.isNullOrBlank()) {
                    append("\n")
                    append(excerpt)
                }
            }
            setOnClickListener { openTopic(topic.id) }
            layoutParams = LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.WRAP_CONTENT,
            ).apply {
                topMargin = if (binding.topicListContainer.childCount == 0) 0 else dp(8)
            }
        }
    }

    private fun postView(post: TopicPostState, isFirstPost: Boolean): View {
        return LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(dp(12), dp(if (isFirstPost) 0 else 12), dp(12), dp(12))
            layoutParams = LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.WRAP_CONTENT,
            ).apply {
                topMargin = if (isFirstPost) 0 else dp(10)
            }

            addView(
                TextView(context).apply {
                    setTypeface(typeface, Typeface.BOLD)
                    text = postHeader(post)
                    textSize = 14f
                },
            )
            TopicPresentation.formatTimestamp(post.createdAt)?.let { createdAt ->
                addView(
                    TextView(context).apply {
                        text = createdAt
                        textSize = 12f
                        setPadding(0, dp(4), 0, 0)
                    },
                )
            }
            addView(
                TextView(context).apply {
                    text = HtmlCompat.fromHtml(post.cooked, HtmlCompat.FROM_HTML_MODE_LEGACY)
                    textSize = 14f
                    setPadding(0, dp(6), 0, 0)
                },
            )
        }
    }

    private fun postHeader(post: TopicPostState): String {
        return buildString {
            append("#${post.postNumber} ")
            append(post.username)
            if (!post.name.isNullOrBlank()) {
                append(" (${post.name})")
            }
            append(" · ${post.likeCount} likes")
            if (post.replyToPostNumber != null) {
                append(" · reply to #${post.replyToPostNumber}")
            }
            if (post.replyCount > 0u) {
                append(" · ${post.replyCount} replies")
            }
        }
    }

    private fun sectionBodyText(text: String): TextView {
        return TextView(this).apply {
            this.text = text
            textSize = 14f
            setPadding(0, dp(4), 0, 0)
        }
    }

    private fun placeholderSession(): SessionState {
        return SessionState(
            cookies = CookieState(null, null, null, null),
            bootstrap = BootstrapState(
                baseUrl = "https://linux.do",
                discourseBaseUri = null,
                sharedSessionKey = null,
                currentUsername = null,
                longPollingBaseUrl = null,
                turnstileSitekey = null,
                topicTrackingStateMeta = null,
                preloadedJson = null,
                hasPreloadedData = false,
            ),
            readiness = SessionReadinessState(
                hasLoginCookie = false,
                hasForumSession = false,
                hasCloudflareClearance = false,
                hasCsrfToken = false,
                hasCurrentUser = false,
                hasPreloadedData = false,
                hasSharedSessionKey = false,
                canReadAuthenticatedApi = false,
                canWriteAuthenticatedApi = false,
                canOpenMessageBus = false,
            ),
            loginPhase = uniffi.fire_uniffi.LoginPhaseState.ANONYMOUS,
            hasLoginSession = false,
        )
    }

    private fun TopicListKindState.displayName(): String {
        return when (this) {
            TopicListKindState.LATEST -> getString(R.string.feed_latest)
            TopicListKindState.NEW -> getString(R.string.feed_new)
            TopicListKindState.UNREAD -> getString(R.string.feed_unread)
            TopicListKindState.UNSEEN -> getString(R.string.feed_unseen)
            TopicListKindState.HOT -> getString(R.string.feed_hot)
            TopicListKindState.TOP -> getString(R.string.feed_top)
        }
    }

    private fun dp(value: Int): Int {
        return (value * resources.displayMetrics.density).toInt()
    }

    private fun applySession(state: SessionState) {
        session = state
        topicCategories = TopicPresentation.parseCategories(session.bootstrap.preloadedJson)
    }

    private fun mergeTopicLists(
        existing: TopicListState,
        incoming: TopicListState,
    ): TopicListState {
        val topicsById = LinkedHashMap<ULong, TopicSummaryState>()
        existing.topics.forEach { topicsById[it.id] = it }
        incoming.topics.forEach { topicsById[it.id] = it }

        val usersById = LinkedHashMap<ULong, uniffi.fire_uniffi.TopicUserState>()
        existing.users.forEach { usersById[it.id] = it }
        incoming.users.forEach { usersById[it.id] = it }

        return TopicListState(
            topics = topicsById.values.toList(),
            users = usersById.values.toList(),
            moreTopicsUrl = incoming.moreTopicsUrl,
        )
    }

    private fun categoryLabelFor(categoryId: ULong?): String? {
        val id = categoryId ?: return null
        return topicCategories[id]?.displayName ?: "Category #$id"
    }
}
