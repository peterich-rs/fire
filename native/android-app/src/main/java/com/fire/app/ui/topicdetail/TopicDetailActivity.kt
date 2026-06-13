package com.fire.app.ui.topicdetail

import android.Manifest
import android.app.DatePickerDialog
import android.app.TimePickerDialog
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.view.Gravity
import android.view.MenuItem
import android.view.View
import android.widget.ArrayAdapter
import android.widget.EditText
import android.widget.ImageView
import android.widget.ListView
import android.widget.LinearLayout
import android.widget.ScrollView
import android.widget.Toast
import android.widget.ProgressBar
import android.widget.Spinner
import android.widget.TextView
import androidx.activity.result.contract.ActivityResultContracts
import androidx.activity.viewModels
import androidx.appcompat.app.AlertDialog
import androidx.appcompat.app.AppCompatActivity
import androidx.core.content.ContextCompat
import androidx.core.text.HtmlCompat
import androidx.core.view.ViewCompat
import androidx.core.view.WindowInsetsCompat
import androidx.core.view.updatePadding
import androidx.core.widget.doAfterTextChanged
import androidx.lifecycle.lifecycleScope
import androidx.recyclerview.widget.ConcatAdapter
import androidx.recyclerview.widget.LinearLayoutManager
import androidx.recyclerview.widget.RecyclerView
import com.fire.app.FireApplication
import com.fire.app.R
import com.fire.app.displayName
import com.fire.app.databinding.ActivityTopicDetailBinding
import com.fire.app.richtext.FireCookedImage
import com.fire.app.session.FireSessionStore
import com.fire.app.session.FireSessionStoreRepository
import com.fire.app.core.image.FireAvatarUrls
import com.fire.app.core.ui.FireToast
import com.fire.app.ui.composer.ComposerTagAssist
import com.fire.app.ui.composer.PrivateMessageComposerSheet
import com.fire.app.ui.composer.QuoteMarkdown
import com.fire.app.ui.composer.ReplyComposerSheet
import com.fire.app.ui.home.HomeTopicDetailPatchRepository
import com.fire.app.ui.webview.FireInAppWebViewActivity
import com.fire.app.core.ext.dp
import com.fire.app.core.image.FireImageLoader
import com.google.android.material.bottomsheet.BottomSheetDialog
import com.google.android.material.textfield.TextInputEditText
import com.google.android.material.textfield.TextInputLayout
import kotlinx.coroutines.flow.collectLatest
import kotlinx.coroutines.launch
import uniffi.fire_uniffi_session.TopicCategoryState
import uniffi.fire_uniffi_topics.PostActionTypeState
import uniffi.fire_uniffi_topics.PostFlagRequestState
import uniffi.fire_uniffi_topics.ReactionUsersGroupState
import uniffi.fire_uniffi_topics.TopicDetailState
import uniffi.fire_uniffi_topics.TopicPostState
import uniffi.fire_uniffi_topics.VotedUserState
import uniffi.fire_uniffi_user.UserProfileState
import uniffi.fire_uniffi_user.UserSummaryState
import java.time.Instant
import java.time.ZoneId
import java.time.ZonedDateTime
import java.time.format.DateTimeFormatter
import java.time.format.FormatStyle

class TopicDetailActivity : AppCompatActivity() {

    private lateinit var binding: ActivityTopicDetailBinding
    private lateinit var recyclerView: RecyclerView
    private lateinit var loadingView: ProgressBar
    private lateinit var errorView: View
    private lateinit var errorText: TextView
    private lateinit var retryButton: View
    private lateinit var replyFab: View
    private lateinit var searchOverlay: TopicSearchOverlay

    private var viewModel: TopicDetailViewModel? = null
    private var route: TopicDetailRoute? = null
    private lateinit var sessionStore: FireSessionStore

    private lateinit var headerAdapter: HeaderAdapter
    private lateinit var postListAdapter: PostListAdapter
    private val loadingFooterAdapter = LoadingFooterAdapter()
    private var loadMorePostsPosted = false
    private var pendingScrollTargetPostNumber: UInt? = null
    private var enabledReactionIds: List<String> = emptyList()
    private var timingTracker: TopicTimingTracker? = null
    private var searchMenuItem: MenuItem? = null
    private var notificationMenuItem: MenuItem? = null
    private var topicSearchQuery: String = ""
    private var topicSearchMatches: List<TopicDetailPostRows.SearchMatch> = emptyList()
    private var topicSearchIndex: Int = -1
    private val pendingBookmarkReminders = mutableMapOf<BookmarkReminderKey, BookmarkReminderRequest>()
    private var pendingNotificationPermissionRequest: BookmarkReminderRequest? = null
    private val notificationPermissionLauncher = registerForActivityResult(
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
        replyFab = binding.replyFab
        searchOverlay = binding.topicSearchOverlay

        binding.topicDetailToolbar.setNavigationOnClickListener {
            finish()
        }
        binding.topicDetailToolbar.title = parsedRoute.title
            ?: getString(R.string.topic_detail_title_fallback, parsedRoute.topicId.toString())
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
                viewModel?.detail?.value?.let(::showTopicNotificationOptions)
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
                onReplyClick = ::showReplyComposerForPost,
                onQuoteClick = ::showQuoteReplyComposerForPost,
                onHeartClick = { post -> viewModel?.toggleHeart(post) },
                onReactClick = ::showReactionPicker,
                onBookmarkClick = ::showPostBookmarkEditor,
                onVotePoll = { post, poll, options -> viewModel?.votePoll(post, poll, options) },
                onUnvotePoll = { post, poll -> viewModel?.unvotePoll(post, poll) },
                onReactionsClick = ::showReactionUsers,
                onReplyContextClick = ::showReplyContext,
                onMoreRepliesClick = { post -> viewModel?.expandReplyThread(post) },
                onDeletePostClick = ::confirmDeletePost,
                onRecoverPostClick = ::confirmRecoverPost,
                onFlagPostClick = ::showFlagPostOptions,
                onEditPostClick = ::showPostEditor,
                onImageClick = ::showImageViewer,
                onAuthorClick = ::showUserInfoSheet,
                onLinkClick = ::handleRichTextLink,
            )
            headerAdapter = HeaderAdapter(
                callbacks = postCallbacks,
                onReloadAiSummary = { viewModel?.reloadTopicAiSummary() },
                onToggleTopicVote = { viewModel?.toggleTopicVote() },
                onShowTopicVoters = ::showTopicVoters,
                onEditTopicClick = ::showTopicEditor,
            )
            postListAdapter = PostListAdapter(postCallbacks)

            val concatAdapter = ConcatAdapter(headerAdapter, postListAdapter, loadingFooterAdapter)
            recyclerView.layoutManager = LinearLayoutManager(this@TopicDetailActivity)
            recyclerView.adapter = concatAdapter
            loadEnabledReactionIds()
            searchOverlay.bind(
                onQueryChanged = ::updateTopicSearchQuery,
                onPrevious = { navigateTopicSearch(-1) },
                onNext = { navigateTopicSearch(1) },
                onClose = ::hideTopicSearch,
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
                loadRoute(parsedRoute)
            }

            replyFab.setOnClickListener {
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

    private fun observeViewModel() {
        val vm = viewModel ?: return
        lifecycleScope.launch {
            vm.isLoading.collectLatest { loading ->
                loadingView.visibility = if (loading) View.VISIBLE else View.GONE
                recyclerView.visibility = if (loading && vm.postRows.value.isEmpty()) View.GONE else View.VISIBLE
            }
        }

        lifecycleScope.launch {
            vm.errorMessage.collectLatest { error ->
                if (error != null) {
                    errorView.visibility = View.VISIBLE
                    errorText.text = error
                    if (vm.postRows.value.isEmpty() && vm.detail.value == null) {
                        recyclerView.visibility = View.GONE
                    }
                } else {
                    errorView.visibility = View.GONE
                    recyclerView.visibility = if (vm.isLoading.value && vm.postRows.value.isEmpty()) {
                        View.GONE
                    } else {
                        View.VISIBLE
                    }
                }
            }
        }

        lifecycleScope.launch {
            vm.detail.collectLatest { detail ->
                headerAdapter.detail = detail
                if (detail != null) {
                    HomeTopicDetailPatchRepository.publish(detail)
                    binding.topicDetailToolbar.title = detail.title.trim()
                }
                updateTopicNotificationToolbar(detail)
                recomputeTopicSearch()
                updateVisiblePostTimings()
            }
        }

        lifecycleScope.launch {
            vm.topicAiSummary.collectLatest { summary ->
                headerAdapter.aiSummary = summary
            }
        }

        lifecycleScope.launch {
            vm.isLoadingTopicAiSummary.collectLatest { loading ->
                headerAdapter.isAiSummaryLoading = loading
            }
        }

        lifecycleScope.launch {
            vm.topicAiSummaryError.collectLatest { error ->
                headerAdapter.aiSummaryError = error
            }
        }

        lifecycleScope.launch {
            vm.postRows.collectLatest { rows ->
                postListAdapter.submitList(rows) {
                    updateVisiblePostTimings()
                    pendingScrollTargetPostNumber?.let { scrollToPostNumber(it) }
                }
                recomputeTopicSearch()
            }
        }

        lifecycleScope.launch {
            vm.scrollTargetPostNumber.collectLatest { postNumber ->
                scrollToPostNumber(postNumber)
            }
        }

        lifecycleScope.launch {
            vm.actionError.collectLatest { error ->
                FireToast.show(binding.root, error, FireToast.Style.ERROR)
            }
        }

        lifecycleScope.launch {
            vm.bookmarkEvents.collectLatest { event ->
                when (event) {
                    is BookmarkEvent.Saved -> {
                        FireToast.show(
                            binding.root,
                            R.string.topic_detail_bookmark_saved,
                            FireToast.Style.SUCCESS,
                        )
                        val key = BookmarkReminderKey(event.bookmarkableId, event.bookmarkableType)
                        pendingBookmarkReminders.remove(key)?.let { request ->
                            scheduleBookmarkReminderAfterSave(request.copy(reminderAt = event.reminderAt))
                        }
                    }
                    is BookmarkEvent.Deleted -> {
                        FireToast.show(
                            binding.root,
                            R.string.topic_detail_bookmark_deleted,
                            FireToast.Style.INFO,
                        )
                        val key = BookmarkReminderKey(event.bookmarkableId, event.bookmarkableType)
                        pendingBookmarkReminders.remove(key)
                        BookmarkReminderScheduler.cancel(
                            this@TopicDetailActivity,
                            event.bookmarkableId,
                            event.bookmarkableType,
                        )
                    }
                }
            }
        }

        lifecycleScope.launch {
            vm.isLoadingMore.collectLatest { loadingMore ->
                loadingFooterAdapter.isLoading = loadingMore
            }
        }
    }

    private fun showReplyComposerForPost(post: TopicPostState) {
        showReplyComposer(replyToPostNumber = post.postNumber.toInt())
    }

    private fun showQuoteReplyComposerForPost(post: TopicPostState) {
        val currentRoute = route ?: return
        val quote = QuoteMarkdown.build(
            username = post.username,
            postNumber = post.postNumber,
            topicId = currentRoute.topicId.toULong(),
            plainText = post.renderDocument?.plainText.orEmpty(),
        )
        if (quote == null) {
            FireToast.show(binding.root, R.string.topic_detail_quote_empty, FireToast.Style.INFO)
            return
        }
        showReplyComposer(
            replyToPostNumber = post.postNumber.toInt(),
            initialBody = quote,
        )
    }

    private fun updateTopicNotificationToolbar(detail: TopicDetailState?) {
        val item = notificationMenuItem ?: return
        val isPrivateMessageThread = detail?.archetype
            ?.trim()
            ?.equals("private_message", ignoreCase = true) == true
        item.isVisible = detail != null && !isPrivateMessageThread
        if (detail == null || isPrivateMessageThread) return

        val level = detail.details.notificationLevel ?: 1
        val title = topicNotificationTitle(level)
        item.title = getString(R.string.topic_detail_notification_button, title)
        item.setIcon(topicNotificationIcon(level))
        item.isEnabled = true
    }

    private fun topicNotificationTitle(level: Int): String {
        return when (level) {
            0 -> getString(R.string.topic_detail_notification_muted)
            2 -> getString(R.string.topic_detail_notification_tracking)
            3 -> getString(R.string.topic_detail_notification_watching)
            else -> getString(R.string.topic_detail_notification_regular)
        }
    }

    private fun topicNotificationIcon(level: Int): Int {
        return when (level) {
            0 -> R.drawable.ic_notifications_off
            2, 3 -> R.drawable.ic_notifications_active
            else -> R.drawable.ic_notifications
        }
    }

    private fun showTopicSearch() {
        searchOverlay.visibility = View.VISIBLE
        searchOverlay.focusSearch()
        recomputeTopicSearch()
    }

    private fun hideTopicSearch() {
        topicSearchQuery = ""
        topicSearchMatches = emptyList()
        topicSearchIndex = -1
        searchOverlay.reset()
        searchOverlay.visibility = View.GONE
        applyTopicSearchHighlight()
    }

    private fun updateTopicSearchQuery(query: String) {
        topicSearchQuery = query
        recomputeTopicSearch(scrollToActiveMatch = true)
    }

    private fun recomputeTopicSearch(scrollToActiveMatch: Boolean = false) {
        if (searchOverlay.visibility != View.VISIBLE && topicSearchQuery.isBlank()) {
            return
        }
        val posts = viewModel?.detail?.value?.postStream?.posts.orEmpty()
        val previousPostId = topicSearchMatches.getOrNull(topicSearchIndex)?.postId
        topicSearchMatches = TopicDetailPostRows.searchMatches(topicSearchQuery, posts)
        topicSearchIndex = when {
            topicSearchMatches.isEmpty() -> -1
            previousPostId != null -> topicSearchMatches
                .indexOfFirst { it.postId == previousPostId }
                .takeIf { it >= 0 }
                ?: 0
            else -> 0
        }
        searchOverlay.updateResult(topicSearchIndex, topicSearchMatches.size)
        applyTopicSearchHighlight()
        if (scrollToActiveMatch) {
            topicSearchMatches.getOrNull(topicSearchIndex)?.postNumber?.let(::scrollToPostNumber)
        }
    }

    private fun navigateTopicSearch(delta: Int) {
        if (topicSearchMatches.isEmpty()) return
        val size = topicSearchMatches.size
        topicSearchIndex = Math.floorMod(topicSearchIndex + delta, size)
        searchOverlay.updateResult(topicSearchIndex, size)
        applyTopicSearchHighlight()
        topicSearchMatches[topicSearchIndex].postNumber.let(::scrollToPostNumber)
    }

    private fun applyTopicSearchHighlight() {
        val highlightedPostId = topicSearchMatches.getOrNull(topicSearchIndex)?.postId
        headerAdapter.highlightedPostId = highlightedPostId
        postListAdapter.highlightedPostId = highlightedPostId
    }

    private fun showReplyComposer(replyToPostNumber: Int?, initialBody: String? = null) {
        val currentRoute = route ?: return
        val sheet = ReplyComposerSheet.newInstance(
            topicId = currentRoute.topicId,
            replyToPostNumber = replyToPostNumber,
            initialBody = initialBody,
        ) {
            viewModel?.loadTopicDetail(
                topicId = currentRoute.topicId.toULong(),
                targetPostNumber = replyToPostNumber?.toUInt(),
            )
        }
        sheet.show(supportFragmentManager, "reply_composer")
    }

    private fun confirmDeletePost(post: TopicPostState) {
        AlertDialog.Builder(this)
            .setTitle(
                getString(
                    R.string.topic_detail_delete_confirm_title,
                    post.postNumber.toString(),
                ),
            )
            .setMessage(R.string.topic_detail_delete_confirm_message)
            .setPositiveButton(R.string.topic_detail_delete_post) { _, _ ->
                viewModel?.deletePost(post)
            }
            .setNegativeButton(android.R.string.cancel, null)
            .show()
    }

    private fun confirmRecoverPost(post: TopicPostState) {
        AlertDialog.Builder(this)
            .setTitle(
                getString(
                    R.string.topic_detail_recover_confirm_title,
                    post.postNumber.toString(),
                ),
            )
            .setMessage(R.string.topic_detail_recover_confirm_message)
            .setPositiveButton(R.string.topic_detail_recover_post) { _, _ ->
                viewModel?.recoverPost(post)
            }
            .setNegativeButton(android.R.string.cancel, null)
            .show()
    }

    private fun showPostEditor(post: TopicPostState) {
        Toast.makeText(this, R.string.topic_detail_edit_post_loading, Toast.LENGTH_SHORT).show()
        lifecycleScope.launch {
            try {
                val editablePost = sessionStore.fetchPost(post.id)
                val raw = editablePost.raw
                    ?.takeIf { it.isNotBlank() }
                    ?: throw IllegalStateException(getString(R.string.topic_detail_edit_post_error))
                showPostEditorDialog(post, raw)
            } catch (e: Exception) {
                Toast.makeText(
                    this@TopicDetailActivity,
                    e.localizedMessage ?: getString(R.string.topic_detail_edit_post_error),
                    Toast.LENGTH_SHORT,
                ).show()
            }
        }
    }

    private fun showPostEditorDialog(post: TopicPostState, raw: String) {
        val bodyInput = EditText(this).apply {
            setText(raw)
            hint = getString(R.string.topic_detail_edit_post_body_hint)
            minLines = 8
            gravity = android.view.Gravity.TOP
        }
        val reasonInput = EditText(this).apply {
            hint = getString(R.string.topic_detail_edit_post_reason_hint)
            setSingleLine(true)
        }
        val content = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(48, 8, 48, 0)
            addView(bodyInput)
            addView(reasonInput)
        }

        val dialog = AlertDialog.Builder(this)
            .setTitle(getString(R.string.topic_detail_edit_post_title, post.postNumber.toString()))
            .setView(content)
            .setPositiveButton(R.string.topic_detail_edit_save, null)
            .setNegativeButton(android.R.string.cancel, null)
            .create()
        dialog.setOnShowListener {
            dialog.getButton(AlertDialog.BUTTON_POSITIVE).setOnClickListener {
                val nextRaw = bodyInput.text.toString()
                if (nextRaw.isBlank()) {
                    Toast.makeText(
                        this,
                        R.string.topic_detail_edit_post_error,
                        Toast.LENGTH_SHORT,
                    ).show()
                    return@setOnClickListener
                }
                viewModel?.updatePost(
                    post = post,
                    raw = nextRaw,
                    editReason = reasonInput.text.toString(),
                )
                dialog.dismiss()
            }
        }
        dialog.show()
    }

    private fun showPostBookmarkEditor(post: TopicPostState) {
        showBookmarkEditor(
            bookmarkableId = post.id,
            bookmarkableType = "Post",
            bookmarkId = post.bookmarkId,
            bookmarkName = post.bookmarkName,
            bookmarkReminderAt = post.bookmarkReminderAt,
            targetPostNumber = post.postNumber,
        )
    }

    private fun showBookmarkEditor(
        bookmarkableId: ULong,
        bookmarkableType: String,
        bookmarkId: ULong?,
        bookmarkName: String?,
        bookmarkReminderAt: String?,
        targetPostNumber: UInt?,
    ) {
        val nameInput = EditText(this).apply {
            setText(bookmarkName.orEmpty())
            hint = getString(R.string.topic_detail_bookmark_name_hint)
            setSingleLine(true)
        }
        val reminderSelection = BookmarkReminderSelection.from(bookmarkReminderAt)
        val reminderToggle = androidx.appcompat.widget.SwitchCompat(this).apply {
            text = getString(R.string.topic_detail_bookmark_reminder_label)
            isChecked = reminderSelection.hasReminder
        }
        val reminderButton = TextView(this).apply {
            setPadding(0, dp(12), 0, dp(4))
            text = reminderSelection.displayText(this@TopicDetailActivity)
            setTextColor(getColor(R.color.fire_accent))
            setOnClickListener {
                showBookmarkReminderDatePicker(reminderSelection, this)
            }
        }
        reminderButton.visibility = if (reminderSelection.hasReminder) View.VISIBLE else View.GONE
        reminderToggle.setOnCheckedChangeListener { _, isChecked ->
            reminderSelection.hasReminder = isChecked
            if (isChecked && reminderSelection.dateTime == null) {
                reminderSelection.dateTime = ZonedDateTime.now().plusHours(1)
            }
            reminderButton.text = reminderSelection.displayText(this)
            reminderButton.visibility = if (isChecked) View.VISIBLE else View.GONE
        }
        val content = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(dp(24), dp(8), dp(24), 0)
            addView(nameInput)
            addView(reminderToggle)
            addView(reminderButton)
        }

        val dialog = AlertDialog.Builder(this)
            .setTitle(
                if (bookmarkId == null) {
                    R.string.topic_detail_bookmark_add_title
                } else {
                    R.string.topic_detail_bookmark_edit_title
                },
            )
            .setView(content)
            .setPositiveButton(R.string.topic_detail_bookmark_save, null)
            .setNegativeButton(android.R.string.cancel, null)
            .apply {
                if (bookmarkId != null) {
                    setNeutralButton(R.string.topic_detail_bookmark_delete, null)
                }
            }
            .create()
        dialog.setOnShowListener {
            dialog.getButton(AlertDialog.BUTTON_POSITIVE).setOnClickListener {
                val reminderAt = reminderSelection.reminderAt()
                val key = BookmarkReminderKey(bookmarkableId, bookmarkableType)
                pendingBookmarkReminders[key] = BookmarkReminderRequest(
                    bookmarkableId = bookmarkableId,
                    bookmarkableType = bookmarkableType,
                    topicId = route?.topicId ?: -1L,
                    postNumber = targetPostNumber?.toInt() ?: -1,
                    title = bookmarkReminderTitle(bookmarkableType, targetPostNumber),
                    reminderAt = reminderAt,
                )
                viewModel?.saveBookmark(
                    bookmarkableId = bookmarkableId,
                    bookmarkableType = bookmarkableType,
                    bookmarkId = bookmarkId,
                    name = nameInput.text.toString(),
                    reminderAt = reminderAt,
                    targetPostNumber = targetPostNumber,
                )
                dialog.dismiss()
            }
            if (bookmarkId != null) {
                dialog.getButton(AlertDialog.BUTTON_NEUTRAL).setOnClickListener {
                    viewModel?.deleteBookmark(
                        bookmarkId = bookmarkId,
                        bookmarkableId = bookmarkableId,
                        bookmarkableType = bookmarkableType,
                        targetPostNumber = targetPostNumber,
                    )
                    dialog.dismiss()
                }
            }
        }
        dialog.show()
    }

    private fun showBookmarkReminderDatePicker(
        selection: BookmarkReminderSelection,
        target: TextView,
    ) {
        val current = selection.dateTime ?: ZonedDateTime.now().plusHours(1)
        DatePickerDialog(
            this,
            { _, year, month, dayOfMonth ->
                TimePickerDialog(
                    this,
                    { _, hourOfDay, minute ->
                        val selectedDateTime = current
                            .withYear(year)
                            .withMonth(month + 1)
                            .withDayOfMonth(dayOfMonth)
                            .withHour(hourOfDay)
                            .withMinute(minute)
                            .withSecond(0)
                            .withNano(0)
                        selection.dateTime = selectedDateTime.takeIf { it.isAfter(ZonedDateTime.now()) }
                            ?: ZonedDateTime.now().plusMinutes(1).withSecond(0).withNano(0)
                        target.text = selection.displayText(this)
                    },
                    current.hour,
                    current.minute,
                    true,
                ).show()
            },
            current.year,
            current.monthValue - 1,
            current.dayOfMonth,
        ).apply {
            datePicker.minDate = System.currentTimeMillis()
        }.show()
    }

    private fun scheduleBookmarkReminderAfterSave(request: BookmarkReminderRequest) {
        if (request.reminderAt.isNullOrBlank()) {
            BookmarkReminderScheduler.sync(this, request)
            return
        }
        if (
            Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
            ContextCompat.checkSelfPermission(this, Manifest.permission.POST_NOTIFICATIONS) !=
                PackageManager.PERMISSION_GRANTED
        ) {
            pendingNotificationPermissionRequest = request
            notificationPermissionLauncher.launch(Manifest.permission.POST_NOTIFICATIONS)
            return
        }
        BookmarkReminderScheduler.sync(this, request)
    }

    private fun bookmarkReminderTitle(bookmarkableType: String, targetPostNumber: UInt?): String {
        val detail = viewModel?.detail?.value
        val title = detail?.title?.trim()?.takeIf { it.isNotEmpty() }
            ?: route?.title?.trim()?.takeIf { it.isNotEmpty() }
            ?: getString(R.string.topic_detail_title_fallback, route?.topicId?.toString().orEmpty())
        return if (bookmarkableType.equals("Post", ignoreCase = true) && targetPostNumber != null) {
            "$title #$targetPostNumber"
        } else {
            title
        }
    }

    private fun showFlagPostOptions(post: TopicPostState) {
        lifecycleScope.launch {
            try {
                val options = sessionStore.fetchPostActionTypes()
                    .mapNotNull(::postFlagOption)
                    .ifEmpty { fallbackPostFlagOptions() }
                val labels = options.map { option ->
                    if (option.detail.isBlank()) {
                        option.title
                    } else {
                        "${option.title}\n${option.detail}"
                    }
                }.toTypedArray()
                AlertDialog.Builder(this@TopicDetailActivity)
                    .setTitle(
                        getString(
                            R.string.topic_detail_flag_type_title,
                            post.postNumber.toString(),
                        ),
                    )
                    .setItems(labels) { _, which ->
                        promptFlagPost(post, options[which])
                    }
                    .setNegativeButton(android.R.string.cancel, null)
                    .show()
            } catch (e: Exception) {
                Toast.makeText(
                    this@TopicDetailActivity,
                    e.localizedMessage ?: getString(R.string.topic_detail_flag_message_required),
                    Toast.LENGTH_SHORT,
                ).show()
            }
        }
    }

    private fun postFlagOption(type: PostActionTypeState): PostFlagOption? {
        if (!type.isFlag || !type.enabled) return null
        if (type.appliesTo.isNotEmpty() && !type.appliesTo.contains("Post")) return null

        val detail = type.description.ifBlank { type.shortDescription.orEmpty() }
        return PostFlagOption(
            id = type.id,
            title = type.name.ifBlank { fallbackFlagTitle(type.nameKey, type.id) },
            detail = plainText(detail),
            requireMessage = type.requireMessage,
        )
    }

    private fun fallbackPostFlagOptions(): List<PostFlagOption> {
        return listOf(
            PostFlagOption(3u, "Off topic", "This post is off topic.", false),
            PostFlagOption(4u, "Inappropriate", "This post is inappropriate.", false),
            PostFlagOption(8u, "Spam", "This post looks like spam.", false),
            PostFlagOption(7u, "Notify moderators", "Add details for moderators.", true),
        )
    }

    private fun fallbackFlagTitle(nameKey: String, id: UInt): String {
        return when (nameKey) {
            "off_topic" -> "Off topic"
            "inappropriate" -> "Inappropriate"
            "spam" -> "Spam"
            "notify_moderators" -> "Notify moderators"
            else -> nameKey.ifBlank { "#$id" }
        }
    }

    private fun promptFlagPost(post: TopicPostState, option: PostFlagOption) {
        if (option.requireMessage) {
            val input = EditText(this).apply {
                hint = getString(R.string.topic_detail_flag_message_hint)
                minLines = 3
            }
            AlertDialog.Builder(this)
                .setTitle(getString(R.string.topic_detail_flag_message_title, option.title))
                .setView(input)
                .setPositiveButton(R.string.topic_detail_flag_submit) { _, _ ->
                    val message = input.text.toString().trim()
                    if (message.isBlank()) {
                        Toast.makeText(
                            this,
                            R.string.topic_detail_flag_message_required,
                            Toast.LENGTH_SHORT,
                        ).show()
                    } else {
                        submitFlagPost(post, option, message)
                    }
                }
                .setNegativeButton(android.R.string.cancel, null)
                .show()
        } else {
            AlertDialog.Builder(this)
                .setTitle(getString(R.string.topic_detail_flag_confirm_title, option.title))
                .setMessage(option.detail.ifBlank { getString(R.string.topic_detail_flag_confirm_message) })
                .setPositiveButton(R.string.topic_detail_flag_submit) { _, _ ->
                    submitFlagPost(post, option, null)
                }
                .setNegativeButton(android.R.string.cancel, null)
                .show()
        }
    }

    private fun submitFlagPost(
        post: TopicPostState,
        option: PostFlagOption,
        message: String?,
    ) {
        lifecycleScope.launch {
            try {
                sessionStore.flagPost(
                    PostFlagRequestState(
                        postId = post.id,
                        flagTypeId = option.id,
                        message = message,
                    ),
                )
                Toast.makeText(
                    this@TopicDetailActivity,
                    R.string.topic_detail_flag_submitted,
                    Toast.LENGTH_SHORT,
                ).show()
            } catch (e: Exception) {
                Toast.makeText(
                    this@TopicDetailActivity,
                    e.localizedMessage ?: getString(R.string.topic_detail_action_error),
                    Toast.LENGTH_SHORT,
                ).show()
            }
        }
    }

    private fun plainText(html: String): String {
        return HtmlCompat.fromHtml(html, HtmlCompat.FROM_HTML_MODE_LEGACY)
            .toString()
            .trim()
    }

    private fun handleRichTextLink(rawUrl: String) {
        val uri = runCatching { Uri.parse(rawUrl) }.getOrNull() ?: return
        profileUsernameFromUri(uri)?.let { username ->
            showUserInfoSheet(username)
            return
        }
        topicRouteFromUri(uri)?.let { route ->
            TopicDetailActivity.start(
                context = this,
                topicId = route.first,
                targetPostNumber = route.second,
            )
            return
        }
        val url = uri.toString()
        if (url.startsWith("http://") || url.startsWith("https://")) {
            FireInAppWebViewActivity.start(this, url)
            return
        }
        runCatching {
            startActivity(Intent(Intent.ACTION_VIEW, uri))
        }
    }

    private fun showUserInfoSheet(username: String) {
        val normalized = username.trim().removePrefix("@").takeIf { it.isNotEmpty() } ?: return
        val dialog = BottomSheetDialog(this)
        val content = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(dp(20), dp(18), dp(20), dp(24))
        }
        val loading = TextView(this).apply {
            text = getString(R.string.profile_loading)
            setTextAppearance(androidx.appcompat.R.style.TextAppearance_AppCompat_Body1)
            setTextColor(getColor(R.color.fire_text_secondary))
        }
        content.addView(loading)
        dialog.setContentView(ScrollView(this).apply { addView(content) })
        dialog.show()

        lifecycleScope.launch {
            try {
                val profile = sessionStore.fetchUserProfile(normalized)
                val summary = runCatching { sessionStore.fetchUserSummary(normalized) }.getOrNull()
                val currentUsername = runCatching {
                    sessionStore.snapshot().bootstrap.currentUsername
                }.getOrNull()?.trim()
                if (!dialog.isShowing) return@launch
                renderUserInfoSheet(
                    content = content,
                    dialog = dialog,
                    profile = profile,
                    summary = summary,
                    isOwnProfile = currentUsername.equals(profile.username.trim(), ignoreCase = true),
                )
            } catch (e: Exception) {
                if (!dialog.isShowing) return@launch
                content.removeAllViews()
                content.addView(TextView(this@TopicDetailActivity).apply {
                    text = e.localizedMessage ?: getString(R.string.profile_error)
                    setTextAppearance(androidx.appcompat.R.style.TextAppearance_AppCompat_Body1)
                    setTextColor(getColor(R.color.fire_text_secondary))
                })
            }
        }
    }

    private fun renderUserInfoSheet(
        content: LinearLayout,
        dialog: BottomSheetDialog,
        profile: UserProfileState,
        summary: UserSummaryState?,
        isOwnProfile: Boolean,
    ) {
        content.removeAllViews()
        val header = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
        }
        val avatar = ImageView(this).apply {
            layoutParams = LinearLayout.LayoutParams(dp(64), dp(64))
            scaleType = ImageView.ScaleType.CENTER_CROP
            contentDescription = getString(R.string.content_desc_avatar)
        }
        profile.avatarTemplate?.takeIf { it.isNotBlank() }?.let { template ->
            FireAvatarUrls.build(template)?.let { url ->
                FireImageLoader.load(url, avatar)
            }
        }
        val titleStack = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(dp(14), 0, 0, 0)
        }
        titleStack.addView(TextView(this).apply {
            text = profile.name?.takeIf { it.isNotBlank() } ?: profile.username
            setTextAppearance(androidx.appcompat.R.style.TextAppearance_AppCompat_Title)
            setTextColor(getColor(R.color.fire_text_primary))
        })
        titleStack.addView(TextView(this).apply {
            text = "@${profile.username} · ${profile.trustLevelLabel}"
            setTextAppearance(androidx.appcompat.R.style.TextAppearance_AppCompat_Caption)
            setTextColor(getColor(R.color.fire_text_secondary))
        })
        header.addView(avatar)
        header.addView(titleStack)
        content.addView(header)

        val stats = summary?.stats
        val statText = buildList {
            add(getString(R.string.profile_topics_count, (stats?.topicCount ?: 0u).toString()))
            add(getString(R.string.profile_posts_count, (stats?.postCount ?: 0u).toString()))
            add(getString(R.string.profile_likes_received, (stats?.likesReceived ?: 0u).toString()))
            add(getString(R.string.profile_followers_count, profile.totalFollowers.toString()))
        }.joinToString("\n")
        content.addView(TextView(this).apply {
            text = statText
            setPadding(0, dp(16), 0, 0)
            setTextAppearance(androidx.appcompat.R.style.TextAppearance_AppCompat_Body1)
            setTextColor(getColor(R.color.fire_text_primary))
        })

        profile.bioCooked?.trim()?.takeIf { it.isNotEmpty() }?.let { bio ->
            content.addView(TextView(this).apply {
                text = plainText(bio)
                setPadding(0, dp(14), 0, 0)
                setTextIsSelectable(true)
                setTextAppearance(androidx.appcompat.R.style.TextAppearance_AppCompat_Body2)
                setTextColor(getColor(R.color.fire_text_secondary))
            })
        }

        if (!isOwnProfile && profile.canSendPrivateMessageToUser) {
            content.addView(TextView(this).apply {
                text = getString(R.string.profile_send_private_message)
                gravity = Gravity.CENTER
                setPadding(dp(12), dp(10), dp(12), dp(10))
                setTextAppearance(androidx.appcompat.R.style.TextAppearance_AppCompat_Button)
                setTextColor(getColor(R.color.fire_accent))
                setOnClickListener {
                    dialog.dismiss()
                    PrivateMessageComposerSheet.newInstance(
                        targetUsername = profile.username,
                        displayName = profile.name?.takeIf { it.isNotBlank() } ?: profile.username,
                        onPrivateMessageCreated = { topicId, title ->
                            TopicDetailActivity.start(
                                context = this@TopicDetailActivity,
                                topicId = topicId.toLong(),
                                topicTitle = title,
                            )
                        },
                    ).show(supportFragmentManager, "private_message_composer")
                }
            })
        }
    }

    private fun profileUsernameFromUri(uri: Uri): String? {
        if (uri.scheme == "fire" && (uri.host == "profile" || uri.host == "user")) {
            return uri.pathSegments.firstOrNull()
        }
        if ((uri.scheme == "http" || uri.scheme == "https") &&
            uri.host?.endsWith("linux.do") == true &&
            uri.pathSegments.firstOrNull() == "u"
        ) {
            return uri.pathSegments.getOrNull(1)
        }
        return null
    }

    private fun topicRouteFromUri(uri: Uri): Pair<Long, Int>? {
        if (uri.scheme == "fire" && uri.host == "topic") {
            val topicId = uri.pathSegments.getOrNull(0)?.toLongOrNull()?.takeIf { it > 0 } ?: return null
            val postNumber = uri.pathSegments.getOrNull(1)?.toIntOrNull() ?: -1
            return topicId to postNumber
        }
        if ((uri.scheme != "http" && uri.scheme != "https") ||
            uri.host?.endsWith("linux.do") != true ||
            uri.pathSegments.firstOrNull() != "t"
        ) {
            return null
        }
        val tail = uri.pathSegments.drop(1)
        if (tail.size == 2) {
            val topicId = tail[0].toLongOrNull()?.takeIf { it > 0 }
            val postNumber = tail[1].toIntOrNull()
            if (topicId != null && postNumber != null) {
                return topicId to postNumber
            }
        }
        if (tail.size >= 3) {
            val postNumber = tail.last().toIntOrNull()
            val topicId = tail.getOrNull(tail.size - 2)?.toLongOrNull()?.takeIf { it > 0 }
            if (topicId != null && postNumber != null) {
                return topicId to postNumber
            }
        }
        val topicId = tail.lastOrNull()?.toLongOrNull()?.takeIf { it > 0 } ?: return null
        return topicId to -1
    }

    private fun showImageViewer(image: FireCookedImage) {
        TopicImagePreviewDialogFragment
            .newInstance(image)
            .show(supportFragmentManager, "topic_image_preview")
    }

    private fun showReactionUsers(post: TopicPostState) {
        showReactionUsers(post, reactionId = null)
    }

    private fun showReactionUsers(post: TopicPostState, reactionId: String?) {
        lifecycleScope.launch {
            try {
                val groups = sessionStore.fetchReactionUsers(post.id)
                    .filterForReaction(reactionId)
                val message = if (groups.isEmpty()) {
                    getString(R.string.topic_detail_reaction_users_empty)
                } else {
                    groups.joinToString("\n\n", transform = ::formatReactionUsersGroup)
                }
                AlertDialog.Builder(this@TopicDetailActivity)
                    .setTitle(
                        reactionId
                            ?.let { ReactionPresentation.optionFor(it) }
                            ?.let { getString(R.string.topic_detail_reaction_users_title_for_reaction, it.symbol, it.label) }
                            ?: getString(R.string.topic_detail_reaction_users_title),
                    )
                    .setMessage(message)
                    .setPositiveButton(android.R.string.ok, null)
                    .show()
            } catch (e: Exception) {
                FireToast.show(
                    binding.root,
                    e.localizedMessage ?: getString(R.string.topic_detail_reaction_users_error),
                    FireToast.Style.ERROR,
                )
            }
        }
    }

    private fun List<ReactionUsersGroupState>.filterForReaction(reactionId: String?): List<ReactionUsersGroupState> {
        val trimmedReactionId = reactionId?.trim()?.takeIf { it.isNotEmpty() } ?: return this
        return filter { group -> group.id.equals(trimmedReactionId, ignoreCase = true) }
    }

    private fun formatReactionUsersGroup(group: ReactionUsersGroupState): String {
        val users = group.users
            .joinToString(", ") { user ->
                user.name?.takeIf { it.isNotBlank() } ?: "@${user.username}"
            }
            .ifBlank { getString(R.string.topic_detail_reaction_users_empty) }
        return getString(
            R.string.topic_detail_reaction_users_group,
            group.id,
            group.count.toString(),
        ) + "\n" + users
    }

    private fun showReactionPicker(post: TopicPostState) {
        val currentReaction = post.currentUserReaction
        if (currentReaction?.canUndo == false) {
            FireToast.show(
                binding.root,
                R.string.topic_detail_reaction_locked,
                FireToast.Style.WARNING,
            )
            return
        }

        lifecycleScope.launch {
            val options = fullReactionOptionsForPost(post)
            if (options.isEmpty()) {
                FireToast.show(
                    binding.root,
                    R.string.topic_detail_reaction_empty,
                    FireToast.Style.INFO,
                )
                return@launch
            }

            val content = LinearLayout(this@TopicDetailActivity).apply {
                orientation = LinearLayout.VERTICAL
                setPadding(dp(20), dp(8), dp(20), 0)
            }
            val searchLayout = TextInputLayout(this@TopicDetailActivity).apply {
                hint = getString(R.string.topic_detail_reaction_search_hint)
            }
            val searchInput = TextInputEditText(searchLayout.context).apply {
                isSingleLine = true
            }
            searchLayout.addView(
                searchInput,
                LinearLayout.LayoutParams(
                    LinearLayout.LayoutParams.MATCH_PARENT,
                    LinearLayout.LayoutParams.WRAP_CONTENT,
                ),
            )
            val listView = ListView(this@TopicDetailActivity).apply {
                divider = null
                choiceMode = ListView.CHOICE_MODE_NONE
            }
            content.addView(
                searchLayout,
                LinearLayout.LayoutParams(
                    LinearLayout.LayoutParams.MATCH_PARENT,
                    LinearLayout.LayoutParams.WRAP_CONTENT,
                ),
            )
            content.addView(
                listView,
                LinearLayout.LayoutParams(
                    LinearLayout.LayoutParams.MATCH_PARENT,
                    dp(360),
                ),
            )

            var visibleOptions = options
            val adapter = ArrayAdapter(
                this@TopicDetailActivity,
                android.R.layout.simple_list_item_1,
                visibleOptions.map { option -> reactionChoiceLabel(post, option) }.toMutableList(),
            )
            fun submitVisibleOptions(query: String) {
                visibleOptions = ReactionPresentation.filteredOptions(options, query)
                adapter.clear()
                adapter.addAll(visibleOptions.map { option -> reactionChoiceLabel(post, option) })
                adapter.notifyDataSetChanged()
            }
            listView.adapter = adapter
            listView.setOnItemLongClickListener { _, _, position, _ ->
                visibleOptions.getOrNull(position)?.let { option ->
                    showReactionUsers(post, option.id)
                }
                true
            }
            searchInput.doAfterTextChanged { text ->
                submitVisibleOptions(text?.toString().orEmpty())
            }

            val dialog = AlertDialog.Builder(this@TopicDetailActivity)
                .setTitle(
                    getString(
                        R.string.topic_detail_reaction_title,
                        post.postNumber.toString(),
                    ),
                )
                .setView(content)
                .setNegativeButton(android.R.string.cancel, null)
                .create()
            listView.setOnItemClickListener { _, _, position, _ ->
                visibleOptions.getOrNull(position)?.let { option ->
                    viewModel?.toggleReaction(post, option.id)
                    dialog.dismiss()
                }
            }
            dialog.show()
        }
    }

    private fun reactionChoiceLabel(post: TopicPostState, option: ReactionOption): String {
        val count = post.reactions
            .firstOrNull { it.id.equals(option.id, ignoreCase = true) }
            ?.count
            ?: 0u
        val label = getString(
            R.string.topic_detail_reaction_choice,
            "${option.symbol} ${option.label}",
            count.toString(),
        )
        return if (post.currentUserReaction?.id?.equals(option.id, ignoreCase = true) == true) {
            getString(R.string.topic_detail_reaction_choice_selected, label)
        } else {
            label
        }
    }

    private suspend fun fullReactionOptionsForPost(post: TopicPostState): List<ReactionOption> {
        if (enabledReactionIds.isEmpty()) {
            enabledReactionIds = runCatching {
                sessionStore.snapshot().bootstrap.enabledReactionIds
            }.getOrDefault(emptyList())
            refreshReactionRows()
        }
        return ReactionPresentation.fullOptions(
            reactionIds = enabledReactionIds,
            currentReactionId = post.currentUserReaction?.id,
        )
    }

    private fun loadEnabledReactionIds() {
        lifecycleScope.launch {
            enabledReactionIds = runCatching {
                sessionStore.snapshot().bootstrap.enabledReactionIds
            }.getOrDefault(emptyList())
            refreshReactionRows()
        }
    }

    private fun refreshReactionRows() {
        headerAdapter.refreshRows()
        postListAdapter.refreshRows()
    }

    private fun showTopicNotificationOptions(detail: TopicDetailState) {
        val options = listOf(
            TopicNotificationOption(
                level = 0,
                title = getString(R.string.topic_detail_notification_muted),
            ),
            TopicNotificationOption(
                level = 1,
                title = getString(R.string.topic_detail_notification_regular),
            ),
            TopicNotificationOption(
                level = 2,
                title = getString(R.string.topic_detail_notification_tracking),
            ),
            TopicNotificationOption(
                level = 3,
                title = getString(R.string.topic_detail_notification_watching),
            ),
        )
        val labels = options.map { option ->
            option.title
        }.toTypedArray()
        val selectedIndex = options.indexOfFirst {
            it.level == (detail.details.notificationLevel ?: 1)
        }.coerceAtLeast(0)

        AlertDialog.Builder(this)
            .setTitle(R.string.topic_detail_notification_title)
            .setSingleChoiceItems(labels, selectedIndex) { dialog, which ->
                viewModel?.setTopicNotificationLevel(options[which].level)
                dialog.dismiss()
            }
            .setNegativeButton(android.R.string.cancel, null)
            .show()
    }

    private fun showTopicEditor(detail: TopicDetailState) {
        lifecycleScope.launch {
            try {
                val session = sessionStore.snapshot()
                val currentCategoryId = detail.categoryId
                val categories = session.bootstrap.categories.filter { category ->
                    category.id == currentCategoryId ||
                        category.permission?.toInt()?.let { it <= 1 } ?: true
                }
                if (categories.isEmpty()) {
                    Toast.makeText(
                        this@TopicDetailActivity,
                        R.string.topic_detail_edit_topic_no_categories,
                        Toast.LENGTH_SHORT,
                    ).show()
                    return@launch
                }
                showTopicEditorDialog(
                    detail = detail,
                    categories = categories,
                    minTitleLength = session.bootstrap.minTopicTitleLength.toInt().coerceAtLeast(1),
                )
            } catch (e: Exception) {
                Toast.makeText(
                    this@TopicDetailActivity,
                    e.localizedMessage ?: getString(R.string.topic_detail_edit_topic_error),
                    Toast.LENGTH_SHORT,
                ).show()
            }
        }
    }

    private fun showTopicEditorDialog(
        detail: TopicDetailState,
        categories: List<TopicCategoryState>,
        minTitleLength: Int,
    ) {
        val titleInput = EditText(this).apply {
            setText(detail.title.trim())
            hint = getString(R.string.topic_detail_edit_topic_title_hint)
            setSingleLine(true)
        }
        val categorySpinner = Spinner(this).apply {
            adapter = ArrayAdapter(
                this@TopicDetailActivity,
                android.R.layout.simple_spinner_item,
                categories.map { it.displayName() },
            ).apply {
                setDropDownViewResource(android.R.layout.simple_spinner_dropdown_item)
            }
            val selectedIndex = categories.indexOfFirst { it.id == detail.categoryId }
            if (selectedIndex >= 0) {
                setSelection(selectedIndex)
            }
        }
        val tagsInput = EditText(this).apply {
            setText(detail.tags.joinToString(" ") { it.name })
            hint = getString(R.string.topic_detail_edit_topic_tags_hint)
            setSingleLine(true)
        }
        val tagSuggestions = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            visibility = View.GONE
        }
        val content = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(48, 8, 48, 0)
            addView(titleInput)
            addView(categorySpinner)
            addView(tagsInput)
            addView(tagSuggestions)
        }
        ComposerTagAssist(
            input = tagsInput,
            suggestions = tagSuggestions,
            sessionStore = sessionStore,
            scope = lifecycleScope,
            categoryIdProvider = { categories.getOrNull(categorySpinner.selectedItemPosition)?.id },
            selectedTagsProvider = {
                tagsInput.text.toString()
                    .split("[,\\s]+".toRegex())
                    .filter { it.isNotBlank() }
            },
        ).attach()

        val dialog = AlertDialog.Builder(this)
            .setTitle(R.string.topic_detail_edit_topic_title)
            .setView(content)
            .setPositiveButton(R.string.topic_detail_edit_save, null)
            .setNegativeButton(android.R.string.cancel, null)
            .create()
        dialog.setOnShowListener {
            dialog.getButton(AlertDialog.BUTTON_POSITIVE).setOnClickListener {
                val title = titleInput.text.toString().trim()
                val category = categories.getOrNull(categorySpinner.selectedItemPosition)
                val tags = tagsInput.text.toString()
                    .split("[,\\s]+".toRegex())
                    .filter { it.isNotBlank() }

                if (title.length < minTitleLength) {
                    Toast.makeText(
                        this,
                        getString(
                            R.string.topic_detail_edit_topic_title_min_length,
                            minTitleLength.toString(),
                        ),
                        Toast.LENGTH_SHORT,
                    ).show()
                    return@setOnClickListener
                }
                if (category == null) {
                    Toast.makeText(
                        this,
                        R.string.topic_detail_edit_topic_category_required,
                        Toast.LENGTH_SHORT,
                    ).show()
                    return@setOnClickListener
                }
                if (tags.size < category.minimumRequiredTags.toInt()) {
                    Toast.makeText(
                        this,
                        getString(
                            R.string.topic_detail_edit_topic_tags_required,
                            category.minimumRequiredTags.toString(),
                        ),
                        Toast.LENGTH_SHORT,
                    ).show()
                    return@setOnClickListener
                }
                val disallowedTags = if (category.allowedTags.isEmpty()) {
                    emptyList()
                } else {
                    tags.filterNot { tag -> category.allowedTags.contains(tag) }
                }
                if (disallowedTags.isNotEmpty()) {
                    Toast.makeText(
                        this,
                        getString(
                            R.string.topic_detail_edit_topic_tags_not_allowed,
                            disallowedTags.joinToString(", "),
                        ),
                        Toast.LENGTH_SHORT,
                    ).show()
                    return@setOnClickListener
                }
                viewModel?.updateTopic(title, category.id, tags)
                dialog.dismiss()
            }
        }
        dialog.show()
    }

    private fun showTopicVoters(detail: TopicDetailState) {
        Toast.makeText(
            this,
            R.string.topic_detail_vote_voters_loading,
            Toast.LENGTH_SHORT,
        ).show()
        lifecycleScope.launch {
            try {
                val voters = sessionStore.fetchTopicVoters(detail.id)
                showTopicVotersDialog(voters)
            } catch (e: Exception) {
                Toast.makeText(
                    this@TopicDetailActivity,
                    e.localizedMessage ?: getString(R.string.topic_detail_vote_voters_empty),
                    Toast.LENGTH_SHORT,
                ).show()
            }
        }
    }

    private fun showTopicVotersDialog(voters: List<VotedUserState>) {
        if (voters.isEmpty()) {
            AlertDialog.Builder(this)
                .setTitle(R.string.topic_detail_vote_voters_title)
                .setMessage(R.string.topic_detail_vote_voters_empty)
                .setPositiveButton(android.R.string.ok, null)
                .show()
            return
        }

        val labels = voters.map(::topicVoterLabel).toTypedArray()
        AlertDialog.Builder(this)
            .setTitle(R.string.topic_detail_vote_voters_title)
            .setItems(labels) { _, which ->
                voters.getOrNull(which)?.username?.let(::showUserInfoSheet)
            }
            .setPositiveButton(android.R.string.ok, null)
            .show()
    }

    private fun topicVoterLabel(voter: VotedUserState): String {
        val displayName = voter.name?.takeIf { it.isNotBlank() } ?: voter.username
        return "$displayName\n@${voter.username}"
    }

    private fun showReplyContext(post: TopicPostState) {
        val currentRoute = route ?: return
        Toast.makeText(
            this,
            R.string.topic_detail_reply_context_loading,
            Toast.LENGTH_SHORT,
        ).show()
        lifecycleScope.launch {
            try {
                val history = if (post.replyToPostNumber != null) {
                    sessionStore.fetchPostReplyHistory(post.id)
                } else {
                    emptyList()
                }
                val directReplies = fetchDirectReplies(currentRoute.topicId.toULong(), post)
                val message = replyContextMessage(history, directReplies)
                AlertDialog.Builder(this@TopicDetailActivity)
                    .setTitle(
                        getString(
                            R.string.topic_detail_reply_context_title,
                            post.postNumber.toString(),
                        ),
                    )
                    .setMessage(message)
                    .setPositiveButton(android.R.string.ok, null)
                    .show()
            } catch (e: Exception) {
                Toast.makeText(
                    this@TopicDetailActivity,
                    e.localizedMessage ?: getString(R.string.topic_detail_reply_context_empty),
                    Toast.LENGTH_SHORT,
                ).show()
            }
        }
    }

    private suspend fun fetchDirectReplies(
        topicId: ULong,
        post: TopicPostState,
    ): List<TopicPostState> {
        if (post.replyCount == 0u) {
            return emptyList()
        }
        val replyIds = sessionStore.fetchPostReplyIds(post.id)
            .filter { it > 0u }
            .distinct()
        if (replyIds.isEmpty()) {
            return emptyList()
        }

        return replyIds.chunked(REPLY_CONTEXT_POST_BATCH_SIZE).flatMap { batch ->
            sessionStore.fetchTopicPosts(topicId, batch)
        }
    }

    private fun replyContextMessage(
        history: List<TopicPostState>,
        directReplies: List<TopicPostState>,
    ): String {
        if (history.isEmpty() && directReplies.isEmpty()) {
            return getString(R.string.topic_detail_reply_context_empty)
        }

        return buildString {
            if (history.isNotEmpty()) {
                appendLine(getString(R.string.topic_detail_reply_context_history))
                appendLine(history.joinToString("\n\n", transform = ::replyContextPostLine))
            }
            if (directReplies.isNotEmpty()) {
                if (isNotEmpty()) appendLine()
                appendLine(getString(R.string.topic_detail_reply_context_direct))
                appendLine(directReplies.joinToString("\n\n", transform = ::replyContextPostLine))
            }
        }.trim()
    }

    private fun replyContextPostLine(post: TopicPostState): String {
        val author = post.name?.takeIf { it.isNotBlank() } ?: "@${post.username}"
        val body = post.renderDocument?.plainText.orEmpty()
            .lineSequence()
            .map { it.trim() }
            .filter { it.isNotEmpty() }
            .joinToString(" ")
            .take(180)
        return "#${post.postNumber} $author\n$body"
    }

    private fun loadRoute(route: TopicDetailRoute) {
        val targetPostNumber = route.targetPostNumber.takeIf { it > 0 }?.toUInt()
        viewModel?.loadTopicDetail(route.topicId.toULong(), targetPostNumber)
    }

    private fun scheduleLoadMorePosts(rv: RecyclerView) {
        if (loadMorePostsPosted) return
        loadMorePostsPosted = true
        rv.post {
            loadMorePostsPosted = false
            viewModel?.loadMorePosts()
        }
    }

    private fun updateVisiblePostTimings() {
        val tracker = timingTracker ?: return
        val layoutManager = recyclerView.layoutManager as? LinearLayoutManager ?: return
        val firstVisible = layoutManager.findFirstVisibleItemPosition()
        val lastVisible = layoutManager.findLastVisibleItemPosition()
        if (firstVisible == RecyclerView.NO_POSITION || lastVisible == RecyclerView.NO_POSITION) {
            tracker.updateVisiblePostNumbers(emptySet())
            return
        }

        val visiblePostNumbers = buildSet {
            for (adapterPosition in firstVisible..lastVisible) {
                visiblePostNumberForAdapterPosition(adapterPosition)?.let(::add)
            }
        }
        if (visiblePostNumbers.isNotEmpty()) {
            tracker.recordInteraction()
        }
        tracker.updateVisiblePostNumbers(visiblePostNumbers)
    }

    private fun visiblePostNumberForAdapterPosition(adapterPosition: Int): UInt? {
        if (adapterPosition < 0) return null
        if (adapterPosition < headerAdapter.itemCount) {
            return viewModel?.detail?.value?.postStream?.posts
                ?.minByOrNull { it.postNumber }
                ?.postNumber
        }

        val rowIndex = adapterPosition - headerAdapter.itemCount
        return postListAdapter.currentList.getOrNull(rowIndex)?.post?.postNumber
    }

    private fun scrollToPostNumber(postNumber: UInt) {
        pendingScrollTargetPostNumber = postNumber
        val adapterPosition = if (postNumber <= 1u) {
            0
        } else {
            val rowIndex = postListAdapter.currentList.indexOfFirst {
                it.post.postNumber == postNumber
            }
            if (rowIndex < 0) return
            headerAdapter.itemCount + rowIndex
        }
        pendingScrollTargetPostNumber = null

        recyclerView.post {
            val layoutManager = recyclerView.layoutManager as? LinearLayoutManager
            if (layoutManager != null) {
                layoutManager.scrollToPositionWithOffset(adapterPosition, 0)
            } else {
                recyclerView.scrollToPosition(adapterPosition)
            }
        }
    }

    private fun applySystemBarInsets() {
        val root = binding.root
        val initialLeft = root.paddingLeft
        val initialTop = root.paddingTop
        val initialRight = root.paddingRight
        val initialBottom = root.paddingBottom
        ViewCompat.setOnApplyWindowInsetsListener(root) { view, insets ->
            val systemBars = insets.getInsets(WindowInsetsCompat.Type.systemBars())
            view.updatePadding(
                left = initialLeft + systemBars.left,
                top = initialTop + systemBars.top,
                right = initialRight + systemBars.right,
                bottom = initialBottom + systemBars.bottom,
            )
            insets
        }
        ViewCompat.requestApplyInsets(root)
    }

    private data class TopicDetailRoute(
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
        private const val REPLY_CONTEXT_POST_BATCH_SIZE = 20

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

private data class TopicNotificationOption(
    val level: Int,
    val title: String,
)

private data class BookmarkReminderKey(
    val bookmarkableId: ULong,
    val bookmarkableType: String,
)

private class BookmarkReminderSelection(
    var hasReminder: Boolean,
    var dateTime: ZonedDateTime?,
) {
    fun reminderAt(): String? {
        if (!hasReminder) return null
        val normalizedDateTime = dateTime
            ?.takeIf { it.isAfter(ZonedDateTime.now()) }
            ?: ZonedDateTime.now().plusMinutes(1)
        return normalizedDateTime
            ?.withSecond(0)
            ?.withNano(0)
            ?.toInstant()
            ?.toString()
    }

    fun displayText(context: Context): String {
        val dateTime = dateTime ?: return context.getString(R.string.topic_detail_bookmark_reminder_pick)
        return DateTimeFormatter
            .ofLocalizedDateTime(FormatStyle.MEDIUM, FormatStyle.SHORT)
            .format(dateTime.withZoneSameInstant(ZoneId.systemDefault()))
    }

    companion object {
        fun from(rawValue: String?): BookmarkReminderSelection {
            val parsed = rawValue
                ?.trim()
                ?.takeIf { it.isNotEmpty() }
                ?.let { runCatching { Instant.parse(it).atZone(ZoneId.systemDefault()) }.getOrNull() }
            return BookmarkReminderSelection(
                hasReminder = parsed != null,
                dateTime = parsed,
            )
        }
    }
}

private data class PostFlagOption(
    val id: UInt,
    val title: String,
    val detail: String,
    val requireMessage: Boolean,
)
