package com.fire.app.ui.topicdetail

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Bundle
import android.view.MenuItem
import android.view.View
import android.widget.ProgressBar
import android.widget.TextView
import androidx.activity.result.contract.ActivityResultContracts
import androidx.activity.viewModels
import androidx.appcompat.app.AppCompatActivity
import androidx.lifecycle.lifecycleScope
import androidx.recyclerview.widget.ConcatAdapter
import androidx.recyclerview.widget.LinearLayoutManager
import androidx.recyclerview.widget.RecyclerView
import com.fire.app.FireApplication
import com.fire.app.R
import com.fire.app.core.ui.FireToast
import com.fire.app.databinding.ActivityTopicDetailBinding
import com.fire.app.session.FireSessionStore
import com.fire.app.session.FireSessionStoreRepository
import kotlinx.coroutines.launch

class TopicDetailActivity : AppCompatActivity() {

    internal lateinit var binding: ActivityTopicDetailBinding
    internal lateinit var recyclerView: RecyclerView
    internal lateinit var loadingView: ProgressBar
    internal lateinit var errorView: View
    internal lateinit var errorText: TextView
    internal lateinit var retryButton: View
    private lateinit var quickReplyBar: View
    internal lateinit var searchOverlay: TopicSearchOverlay
    internal var pinnedTopicTitle: String? = null
    internal var toolbarTitlePinned = false

    internal var viewModel: TopicDetailViewModel? = null
    internal var route: TopicDetailRoute? = null
    internal lateinit var sessionStore: FireSessionStore

    internal lateinit var headerAdapter: HeaderAdapter
    internal lateinit var postListAdapter: PostListAdapter
    internal val loadingFooterAdapter = LoadingFooterAdapter()
    internal var loadMorePostsPosted = false
    internal var pendingScrollTargetPostNumber: UInt? = null
    internal var enabledReactionIds: List<String> = emptyList()
    internal var timingTracker: TopicTimingTracker? = null
    private var searchMenuItem: MenuItem? = null
    internal var notificationMenuItem: MenuItem? = null
    internal var topicSearchQuery: String = ""
    internal var topicSearchMatches: List<TopicDetailPostRows.SearchMatch> = emptyList()
    internal var topicSearchIndex: Int = -1
    internal val pendingBookmarkReminders = mutableMapOf<BookmarkReminderKey, BookmarkReminderRequest>()
    internal var pendingNotificationPermissionRequest: BookmarkReminderRequest? = null
    internal val notificationPermissionLauncher = registerForActivityResult(
        ActivityResultContracts.RequestPermission(),
    ) { granted ->
        val request = pendingNotificationPermissionRequest
        pendingNotificationPermissionRequest = null
        if (granted && request != null) {
            BookmarkReminderScheduler.sync(this, request)
        }
    }
    private val appScope by lazy { FireApplication.applicationScope() }
    private val viewModelDelegate: TopicDetailViewModel by viewModels {
        TopicDetailViewModelFactory(sessionStore)
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        binding = ActivityTopicDetailBinding.inflate(layoutInflater)
        setContentView(binding.root)
        applySystemBarInsets()

        val parsedRoute = TopicDetailRoute.from(intent)
        if (parsedRoute == null) {
            finish()
            return
        }
        route = parsedRoute

        recyclerView = binding.postList
        loadingView = binding.loadingView
        errorView = binding.errorView
        errorText = binding.errorText
        retryButton = binding.retryButton
        quickReplyBar = binding.quickReplyBar
        searchOverlay = binding.topicSearchOverlay

        binding.topicDetailToolbar.setNavigationOnClickListener {
            finish()
        }
        pinnedTopicTitle = parsedRoute.title
        binding.topicDetailToolbar.title = ""
        searchMenuItem = binding.topicDetailToolbar.menu.add(
            R.string.topic_detail_search_topic,
        ).apply {
            setIcon(R.drawable.ic_search)
            setShowAsAction(MenuItem.SHOW_AS_ACTION_ALWAYS)
            setOnMenuItemClickListener {
                showTopicSearch()
                true
            }
        }
        notificationMenuItem = binding.topicDetailToolbar.menu.add(
            R.string.topic_detail_notification_topic,
        ).apply {
            setIcon(R.drawable.ic_notifications)
            setShowAsAction(MenuItem.SHOW_AS_ACTION_ALWAYS)
            setOnMenuItemClickListener {
                viewModel?.detail?.value?.let { showTopicNotificationOptions(it) }
                true
            }
            isVisible = false
        }

        lifecycleScope.launch {
            sessionStore = FireSessionStoreRepository.get(this@TopicDetailActivity)
            viewModel = viewModelDelegate
            timingTracker = TopicTimingTracker(
                topicId = parsedRoute.topicId.toULong(),
                scope = appScope,
                reporter = { topicId, topicTimeMs, timings ->
                    sessionStore.reportTopicTimings(topicId, topicTimeMs, timings)
                },
            ).also { tracker ->
                tracker.start()
            }

            val postCallbacks = PostRowCallbacks(
                reactionIds = { enabledReactionIds },
                onReplyClick = { showReplyComposerForPost(it) },
                onQuoteClick = { showQuoteReplyComposerForPost(it) },
                onHeartClick = { post -> viewModel?.toggleHeart(post) },
                onReactClick = { showReactionPicker(it) },
                onBookmarkClick = { showPostBookmarkEditor(it) },
                onVotePoll = { post, poll, options -> viewModel?.votePoll(post, poll, options) },
                onUnvotePoll = { post, poll -> viewModel?.unvotePoll(post, poll) },
                onReactionsClick = { showReactionUsers(it) },
                onReplyContextClick = { showReplyContext(it) },
                onMoreRepliesClick = { post -> viewModel?.expandReplyThread(post) },
                onDeletePostClick = { confirmDeletePost(it) },
                onRecoverPostClick = { confirmRecoverPost(it) },
                onFlagPostClick = { showFlagPostOptions(it) },
                onAcceptSolutionClick = { viewModel?.acceptSolution(it) },
                onBoostClick = { showBoostComposerForPost(it) },
                onEditPostClick = { showPostEditor(it) },
                onImageClick = { showImageViewer(it) },
                onAuthorClick = { showUserInfoSheet(it) },
                onLinkClick = { handleRichTextLink(it) },
            )
            headerAdapter = HeaderAdapter(
                callbacks = postCallbacks,
                onToggleTopicVote = { viewModel?.toggleTopicVote() },
                onShowTopicVoters = { showTopicVoters(it) },
                onEditTopicClick = { showTopicEditor(it) },
            )
            postListAdapter = PostListAdapter(postCallbacks)

            val concatAdapter = ConcatAdapter(headerAdapter, postListAdapter, loadingFooterAdapter)
            recyclerView.layoutManager = LinearLayoutManager(this@TopicDetailActivity)
            recyclerView.adapter = concatAdapter
            loadEnabledReactionIds()
            searchOverlay.bind(
                onQueryChanged = { updateTopicSearchQuery(it) },
                onPrevious = { navigateTopicSearch(-1) },
                onNext = { navigateTopicSearch(1) },
                onClose = { hideTopicSearch() },
            )

            recyclerView.addOnScrollListener(object : RecyclerView.OnScrollListener() {
                override fun onScrolled(rv: RecyclerView, dx: Int, dy: Int) {
                    timingTracker?.recordInteraction()
                    updateVisiblePostTimings()

                    val layoutManager = rv.layoutManager as? LinearLayoutManager ?: return
                    val totalItemCount = layoutManager.itemCount
                    val lastVisible = layoutManager.findLastVisibleItemPosition()
                    if (lastVisible >= totalItemCount - 5) {
                        scheduleLoadMorePosts(rv)
                    }
                    updatePinnedToolbarTitle(layoutManager.findFirstVisibleItemPosition())
                }

                override fun onScrollStateChanged(rv: RecyclerView, newState: Int) {
                    super.onScrollStateChanged(rv, newState)
                    val isIdle = newState == RecyclerView.SCROLL_STATE_IDLE
                    headerAdapter.setBoostAnimationsEnabled(isIdle)
                    postListAdapter.setBoostAnimationsEnabled(isIdle)
                    if (!isIdle) {
                        timingTracker?.recordInteraction()
                    }
                    viewModel?.setTopicDetailScrollInteractionActive(
                        !isIdle
                    )
                }
            })

            observeViewModel()

            retryButton.setOnClickListener {
                val vm = viewModel
                if (vm?.isCloudflareError?.value == true) {
                    lifecycleScope.launch {
                        val ok = com.fire.app.session.FireCloudflareRecovery.completeManualVerification(
                            context = this@TopicDetailActivity,
                            sessionStore = sessionStore,
                            operation = "topic_detail.manual_verify",
                            originUrl = "https://linux.do/t/${parsedRoute.topicId}",
                        )
                        if (ok) {
                            loadRoute(parsedRoute)
                        } else {
                            FireToast.show(
                                binding.root,
                                getString(R.string.login_cloudflare_retry_failed),
                                FireToast.Style.ERROR,
                            )
                        }
                    }
                } else {
                    loadRoute(parsedRoute)
                }
            }

            binding.quickReplyInput.setOnClickListener {
                showReplyComposer(replyToPostNumber = null)
            }
            binding.quickReplySend.setOnClickListener {
                showReplyComposer(replyToPostNumber = null)
            }

            loadRoute(parsedRoute)
        }
    }

    override fun onResume() {
        super.onResume()
        timingTracker?.setSceneActive(true)
        updateVisiblePostTimings()
    }

    override fun onPause() {
        updateVisiblePostTimings()
        timingTracker?.setSceneActive(false)
        super.onPause()
    }

    override fun onDestroy() {
        timingTracker?.stop()
        timingTracker = null
        viewModel = null
        super.onDestroy()
    }

    internal data class TopicDetailRoute(
        val topicId: Long,
        val title: String?,
        val targetPostNumber: Int,
    ) {
        companion object {
            fun from(intent: Intent): TopicDetailRoute? {
                val extraTopicId = intent.getLongExtra(EXTRA_TOPIC_ID, -1L)
                if (extraTopicId > 0L) {
                    return TopicDetailRoute(
                        topicId = extraTopicId,
                        title = intent.getStringExtra(EXTRA_TOPIC_TITLE),
                        targetPostNumber = intent.getIntExtra(EXTRA_TARGET_POST_NUMBER, -1),
                    )
                }

                return fromUri(intent.data)
            }

            private fun fromUri(uri: Uri?): TopicDetailRoute? {
                if (uri?.scheme != "fire" || uri.host != "topic") {
                    return null
                }
                val segments = uri.pathSegments
                val topicId = segments.getOrNull(0)?.toLongOrNull()?.takeIf { it > 0L } ?: return null
                val postNumber = segments.getOrNull(1)?.toIntOrNull() ?: -1
                return TopicDetailRoute(
                    topicId = topicId,
                    title = null,
                    targetPostNumber = postNumber,
                )
            }
        }
    }

    companion object {
        private const val EXTRA_TOPIC_ID = "com.fire.app.extra.TOPIC_ID"
        private const val EXTRA_TOPIC_TITLE = "com.fire.app.extra.TOPIC_TITLE"
        private const val EXTRA_TARGET_POST_NUMBER = "com.fire.app.extra.TARGET_POST_NUMBER"
        internal const val REPLY_CONTEXT_POST_BATCH_SIZE = 20

        fun createIntent(
            context: Context,
            topicId: Long,
            topicTitle: String? = null,
            targetPostNumber: Int = -1,
        ): Intent {
            return Intent(context, TopicDetailActivity::class.java).apply {
                putExtra(EXTRA_TOPIC_ID, topicId)
                putExtra(EXTRA_TARGET_POST_NUMBER, targetPostNumber)
                topicTitle?.let { putExtra(EXTRA_TOPIC_TITLE, it) }
            }
        }

        fun start(
            context: Context,
            topicId: Long,
            topicTitle: String? = null,
            targetPostNumber: Int = -1,
        ) {
            context.startActivity(
                createIntent(
                    context = context,
                    topicId = topicId,
                    topicTitle = topicTitle,
                    targetPostNumber = targetPostNumber,
                ),
            )
        }
    }
}
