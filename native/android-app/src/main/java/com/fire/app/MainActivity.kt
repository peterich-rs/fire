package com.fire.app

import android.content.ClipData
import android.content.ClipboardManager
import android.content.Intent
import android.os.Bundle
import android.text.InputType
import android.view.View
import android.view.ViewGroup
import android.widget.Button
import android.widget.EditText
import android.widget.FrameLayout
import android.widget.HorizontalScrollView
import android.widget.LinearLayout
import android.widget.ScrollView
import android.widget.TextView
import android.widget.Toast
import androidx.activity.result.contract.ActivityResultContracts
import androidx.appcompat.app.AlertDialog
import androidx.appcompat.app.AppCompatActivity
import androidx.lifecycle.lifecycleScope
import androidx.recyclerview.widget.DiffUtil
import androidx.recyclerview.widget.LinearLayoutManager
import androidx.recyclerview.widget.ListAdapter
import androidx.recyclerview.widget.RecyclerView
import com.fire.app.databinding.ActivityMainBinding
import com.fire.app.session.FireSessionStore
import com.fire.app.session.FireSessionStoreRepository
import kotlinx.coroutines.launch
import uniffi.fire_uniffi_session.BootstrapState
import uniffi.fire_uniffi_session.CookieState
import uniffi.fire_uniffi_session.SessionState
import uniffi.fire_uniffi_session.SessionReadinessState
import uniffi.fire_uniffi_session.TopicCategoryState
import uniffi.fire_uniffi_topics.TopicCreateRequestState
import uniffi.fire_uniffi_topics.TopicListQueryState
import uniffi.fire_uniffi_types.TopicListKindState
import uniffi.fire_uniffi_types.TopicListState
import uniffi.fire_uniffi_types.TopicRowState
import uniffi.fire_uniffi_types.TopicSummaryState

class MainActivity : AppCompatActivity() {
    private enum class BrowserListSource {
        FEED,
        BOOKMARKS,
        READ_HISTORY,
    }

    private enum class CategoryNotificationLevelOption(
        val value: Int,
        val titleResId: Int,
        val descriptionResId: Int,
    ) {
        MUTED(
            value = 0,
            titleResId = R.string.category_notification_muted,
            descriptionResId = R.string.category_notification_muted_description,
        ),
        REGULAR(
            value = 1,
            titleResId = R.string.category_notification_regular,
            descriptionResId = R.string.category_notification_regular_description,
        ),
        TRACKING(
            value = 2,
            titleResId = R.string.category_notification_tracking,
            descriptionResId = R.string.category_notification_tracking_description,
        ),
        WATCHING(
            value = 3,
            titleResId = R.string.category_notification_watching,
            descriptionResId = R.string.category_notification_watching_description,
        ),
        WATCHING_FIRST_POST(
            value = 4,
            titleResId = R.string.category_notification_watching_first_post,
            descriptionResId = R.string.category_notification_watching_first_post_description,
        );

        companion object {
            fun fromValue(value: Int?): CategoryNotificationLevelOption =
                entries.firstOrNull { it.value == value } ?: REGULAR
        }
    }

    private data class BrowserScreenItem(
        val key: String,
        val stableId: Long,
        val contentSignature: String,
        val buildView: () -> View,
    )

    private class BrowserScreenAdapter :
        ListAdapter<BrowserScreenItem, BrowserScreenAdapter.DynamicViewHolder>(DiffCallback) {

        init {
            setHasStableIds(true)
        }

        override fun getItemId(position: Int): Long = getItem(position).stableId

        override fun onCreateViewHolder(parent: ViewGroup, viewType: Int): DynamicViewHolder {
            return DynamicViewHolder(FrameLayout(parent.context))
        }

        override fun onBindViewHolder(holder: DynamicViewHolder, position: Int) {
            holder.bind(getItem(position).buildView())
        }

        class DynamicViewHolder(private val container: FrameLayout) : RecyclerView.ViewHolder(container) {
            fun bind(view: View) {
                container.removeAllViews()
                if (view.parent != null) {
                    (view.parent as? ViewGroup)?.removeView(view)
                }
                container.addView(
                    view,
                    FrameLayout.LayoutParams(
                        ViewGroup.LayoutParams.MATCH_PARENT,
                        ViewGroup.LayoutParams.WRAP_CONTENT,
                    ),
                )
            }
        }

        private object DiffCallback : DiffUtil.ItemCallback<BrowserScreenItem>() {
            override fun areItemsTheSame(
                oldItem: BrowserScreenItem,
                newItem: BrowserScreenItem,
            ): Boolean = oldItem.key == newItem.key

            override fun areContentsTheSame(
                oldItem: BrowserScreenItem,
                newItem: BrowserScreenItem,
            ): Boolean = oldItem.contentSignature == newItem.contentSignature
        }
    }

    private lateinit var binding: ActivityMainBinding
    private lateinit var sessionStore: FireSessionStore
    private val browserScreenAdapter = BrowserScreenAdapter()

    private var currentListSource = BrowserListSource.FEED
    private var currentFeedKind = TopicListKindState.LATEST
    private var currentFeedPage: UInt = 0u
    private var nextFeedPage: UInt? = null
    private var selectedTopicId: ULong? = null
    private var currentTopicList: TopicListState? = null
    private var topicCategories: Map<ULong, TopicCategoryState> = emptyMap()
    private var browserStatusMessage: String? = null
    private var lastErrorMessage: String? = null
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

        sessionStore = FireSessionStoreRepository.get(applicationContext)
        binding.root.apply {
            layoutManager = LinearLayoutManager(this@MainActivity)
            adapter = browserScreenAdapter
            itemAnimator = null
            setItemViewCacheSize(10)
            recycledViewPool.setMaxRecycledViews(0, 24)
        }

        submitMainScreen()
        refreshSessionAndFeed()
    }

    private fun refreshSessionAndFeed() {
        lifecycleScope.launch {
            clearLastError()
            try {
                applySession(sessionStore.restorePersistedSessionIfAvailable() ?: sessionStore.snapshot())
                if (session.readiness.canReadAuthenticatedApi && !session.readiness.hasCsrfToken) {
                    applySession(sessionStore.refreshCsrfTokenIfNeeded())
                }
                renderSession(session)
                reloadCurrentFeed()
            } catch (error: Exception) {
                recordLastError(error)
                browserStatusMessage = lastErrorMessage
                renderSession(session)
                renderBrowser()
            }
        }
    }

    private fun refreshBootstrap() {
        lifecycleScope.launch {
            clearLastError()
            try {
                applySession(sessionStore.refreshBootstrapIfNeeded())
                if (session.readiness.canReadAuthenticatedApi && !session.readiness.hasCsrfToken) {
                    applySession(sessionStore.refreshCsrfTokenIfNeeded())
                }
                renderSession(session)
                reloadCurrentFeed()
            } catch (error: Exception) {
                recordLastError(error)
                browserStatusMessage = lastErrorMessage
                renderSession(session)
                renderBrowser()
            }
        }
    }

    private fun logout() {
        lifecycleScope.launch {
            clearLastError()
            try {
                applySession(sessionStore.logout())
                currentListSource = BrowserListSource.FEED
                currentFeedKind = TopicListKindState.LATEST
                currentFeedPage = 0u
                nextFeedPage = null
                selectedTopicId = null
                currentTopicList = null
                renderSession(session)
                reloadCurrentFeed()
            } catch (error: Exception) {
                recordLastError(error)
                browserStatusMessage = lastErrorMessage
                renderSession(session)
                renderBrowser()
            }
        }
    }

    private fun showCreateTopicComposer() {
        if (!session.readiness.canWriteAuthenticatedApi) {
            recordLastError(IllegalStateException(getString(R.string.create_topic_login_required)))
            renderSession(session)
            renderBrowser()
            return
        }

        val categories = topicCategoriesForComposer()
        if (categories.isEmpty()) {
            recordLastError(IllegalStateException(getString(R.string.create_topic_no_categories)))
            renderSession(session)
            renderBrowser()
            return
        }

        var selectedCategory = defaultComposerCategory(categories) ?: categories.first()
        val titleInput = EditText(this).apply {
            hint = getString(R.string.create_topic_title_hint)
            setSingleLine(false)
            maxLines = 3
            inputType = InputType.TYPE_CLASS_TEXT or InputType.TYPE_TEXT_FLAG_CAP_SENTENCES
        }
        val categoryText = TextView(this).apply {
            text = createTopicCategoryLabel(selectedCategory)
            textSize = 14f
            setPadding(0, dp(10), 0, 0)
        }
        val categoryButton = Button(this).apply {
            isAllCaps = false
            text = getString(R.string.create_topic_select_category)
            setOnClickListener {
                showTopicCategoryPicker(categories, selectedCategory) { category ->
                    selectedCategory = category
                    categoryText.text = createTopicCategoryLabel(category)
                }
            }
        }
        val bodyInput = EditText(this).apply {
            hint = getString(R.string.create_topic_body_hint)
            minLines = 8
            inputType = InputType.TYPE_CLASS_TEXT or
                InputType.TYPE_TEXT_FLAG_MULTI_LINE or
                InputType.TYPE_TEXT_FLAG_CAP_SENTENCES
        }
        val tagsInput = EditText(this).apply {
            hint = getString(R.string.create_topic_tags_hint)
            setSingleLine(false)
            maxLines = 2
            inputType = InputType.TYPE_CLASS_TEXT
        }

        val content = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(dp(20), dp(8), dp(20), dp(4))
            addView(labelText(getString(R.string.create_topic_title_label)))
            addView(titleInput)
            addView(labelText(getString(R.string.create_topic_category_label)))
            addView(categoryText)
            addView(categoryButton)
            addView(labelText(getString(R.string.create_topic_body_label)))
            addView(bodyInput)
            addView(labelText(getString(R.string.create_topic_tags_label)))
            addView(tagsInput)
        }

        val dialog = AlertDialog.Builder(this)
            .setTitle(R.string.create_topic_title)
            .setView(ScrollView(this).apply { addView(content) })
            .setPositiveButton(R.string.create_topic_submit, null)
            .setNegativeButton(R.string.action_cancel, null)
            .create()

        dialog.setOnShowListener {
            dialog.getButton(AlertDialog.BUTTON_POSITIVE).setOnClickListener {
                val title = titleInput.text?.toString()?.trim().orEmpty()
                val raw = bodyInput.text?.toString()?.trim().orEmpty()
                val tags = parseTopicTags(tagsInput.text?.toString().orEmpty())
                val disallowedTags = disallowedTopicTags(tags, selectedCategory)

                when {
                    title.length < session.bootstrap.minTopicTitleLength.toInt() -> {
                        titleInput.error = getString(
                            R.string.create_topic_title_min_length,
                            session.bootstrap.minTopicTitleLength.toString(),
                        )
                    }
                    raw.length < session.bootstrap.minFirstPostLength.toInt() -> {
                        bodyInput.error = getString(
                            R.string.create_topic_body_min_length,
                            session.bootstrap.minFirstPostLength.toString(),
                        )
                    }
                    tags.size < selectedCategory.minimumRequiredTags.toInt() -> {
                        tagsInput.error = getString(
                            R.string.create_topic_tags_required,
                            selectedCategory.minimumRequiredTags.toString(),
                        )
                    }
                    disallowedTags.isNotEmpty() -> {
                        tagsInput.error = getString(
                            R.string.create_topic_tags_not_allowed,
                            disallowedTags.joinToString(", "),
                        )
                    }
                    else -> {
                        dialog.dismiss()
                        submitCreateTopic(
                            title = title,
                            raw = raw,
                            categoryId = selectedCategory.id,
                            tags = tags,
                        )
                    }
                }
            }
        }
        dialog.show()
    }

    private fun showCategoryNotificationPicker() {
        if (!session.readiness.canWriteAuthenticatedApi) {
            recordLastError(IllegalStateException(getString(R.string.category_notification_login_required)))
            renderSession(session)
            renderBrowser()
            return
        }

        val categories = topicCategoriesForNotifications()
        if (categories.isEmpty()) {
            recordLastError(IllegalStateException(getString(R.string.category_notification_no_categories)))
            renderSession(session)
            renderBrowser()
            return
        }

        AlertDialog.Builder(this)
            .setTitle(R.string.category_notification_select_category)
            .setItems(categories.map(::categoryNotificationCategoryLabel).toTypedArray()) { dialog, which ->
                dialog.dismiss()
                showCategoryNotificationLevelPicker(categories[which])
            }
            .setNegativeButton(R.string.action_cancel, null)
            .show()
    }

    private fun showCategoryNotificationLevelPicker(category: TopicCategoryState) {
        val options = CategoryNotificationLevelOption.entries.toTypedArray()
        val current = CategoryNotificationLevelOption.fromValue(category.notificationLevel)
        val currentIndex = options.indexOf(current).coerceAtLeast(0)

        AlertDialog.Builder(this)
            .setTitle(getString(R.string.category_notification_title, category.displayName()))
            .setSingleChoiceItems(
                options.map(::categoryNotificationOptionLabel).toTypedArray(),
                currentIndex,
            ) { dialog, which ->
                dialog.dismiss()
                val selected = options[which]
                if (selected != current) {
                    updateCategoryNotificationLevel(category, selected)
                }
            }
            .setNegativeButton(R.string.action_cancel, null)
            .show()
    }

    private fun updateCategoryNotificationLevel(
        category: TopicCategoryState,
        option: CategoryNotificationLevelOption,
    ) {
        lifecycleScope.launch {
            clearLastError()
            setBrowserLoading(
                true,
                getString(R.string.category_notification_saving, category.displayName()),
            )
            renderSession(session)
            renderBrowser()

            try {
                sessionStore.setCategoryNotificationLevel(category.id, option.value)
                applySession(sessionStore.refreshBootstrap())
                setBrowserLoading(
                    false,
                    getString(
                        R.string.category_notification_saved,
                        category.displayName(),
                        getString(option.titleResId),
                    ),
                )
                renderSession(session)
                renderBrowser()
            } catch (error: Exception) {
                recordLastError(error)
                setBrowserLoading(false, lastErrorMessage ?: getString(R.string.category_notification_error))
                renderSession(session)
                renderBrowser()
            }
        }
    }

    private fun showTopicCategoryPicker(
        categories: List<TopicCategoryState>,
        selectedCategory: TopicCategoryState,
        onSelected: (TopicCategoryState) -> Unit,
    ) {
        val selectedIndex = categories.indexOfFirst { it.id == selectedCategory.id }.coerceAtLeast(0)
        AlertDialog.Builder(this)
            .setTitle(R.string.create_topic_select_category)
            .setSingleChoiceItems(
                categories.map(::createTopicCategoryLabel).toTypedArray(),
                selectedIndex,
            ) { dialog, which ->
                onSelected(categories[which])
                dialog.dismiss()
            }
            .setNegativeButton(R.string.action_cancel, null)
            .show()
    }

    private fun submitCreateTopic(
        title: String,
        raw: String,
        categoryId: ULong,
        tags: List<String>,
    ) {
        lifecycleScope.launch {
            clearLastError()
            setBrowserLoading(true, getString(R.string.create_topic_submitting))
            renderSession(session)
            renderBrowser()

            try {
                val topicId = sessionStore.createTopic(
                    TopicCreateRequestState(
                        title = title,
                        raw = raw,
                        categoryId = categoryId,
                        tags = tags,
                    ),
                )
                selectedTopicId = topicId
                setBrowserLoading(false, getString(R.string.create_topic_created, topicId.toString()))
                startActivity(TopicDetailActivity.intent(this@MainActivity, topicId, title))
                loadFeed(TopicListKindState.LATEST, preferredTopicId = topicId, reset = true, page = null)
            } catch (error: Exception) {
                recordLastError(error)
                setBrowserLoading(false, lastErrorMessage)
                renderSession(session)
                renderBrowser()
            }
        }
    }

    private fun reloadCurrentFeed() {
        when (currentListSource) {
            BrowserListSource.FEED -> loadFeed(currentFeedKind, selectedTopicId, reset = true, page = null)
            BrowserListSource.BOOKMARKS -> loadBookmarks(preferredTopicId = selectedTopicId)
            BrowserListSource.READ_HISTORY -> loadReadHistory(preferredTopicId = selectedTopicId)
        }
    }

    private fun loadMoreFeed() {
        val page = nextFeedPage ?: return
        when (currentListSource) {
            BrowserListSource.FEED -> loadFeed(currentFeedKind, selectedTopicId, reset = false, page = page)
            BrowserListSource.BOOKMARKS -> loadBookmarks(
                preferredTopicId = selectedTopicId,
                reset = false,
                page = page,
            )
            BrowserListSource.READ_HISTORY -> loadReadHistory(
                preferredTopicId = selectedTopicId,
                reset = false,
                page = page,
            )
        }
    }

    private fun loadFeed(
        kind: TopicListKindState,
        preferredTopicId: ULong? = selectedTopicId,
        reset: Boolean = true,
        page: UInt? = null,
    ) {
        lifecycleScope.launch {
            clearLastError()
            currentListSource = BrowserListSource.FEED
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
                        categorySlug = null,
                        categoryId = null,
                        parentCategorySlug = null,
                        tag = null,
                        additionalTags = emptyList(),
                        matchAllTags = false,
                    ),
                )
                currentFeedPage = page ?: 0u
                nextFeedPage = response.nextPage
                currentTopicList = if (reset || currentTopicList == null) {
                    response
                } else {
                    mergeTopicLists(currentTopicList!!, response)
                }
                val topicList = currentTopicList!!

                val nextTopicId = preferredTopicId?.takeIf { id ->
                    topicList.rows.any { it.topic.id == id }
                } ?: topicList.rows.firstOrNull()?.topic?.id
                selectedTopicId = nextTopicId
                renderSession(session)
                renderBrowser()

                if (nextTopicId == null) {
                    setBrowserLoading(false, getString(R.string.browser_empty))
                    isLoadingMoreFeed = false
                    renderBrowser()
                    return@launch
                }

                setBrowserLoading(false, browserFeedSummary(topicList))
                isLoadingMoreFeed = false
                renderBrowser()
            } catch (error: Exception) {
                recordLastError(error)
                browserStatusMessage = lastErrorMessage
                setBrowserLoading(false, browserStatusMessage)
                isLoadingMoreFeed = false
                renderSession(session)
                renderBrowser()
            }
        }
    }

    private fun loadBookmarks(
        preferredTopicId: ULong? = selectedTopicId,
        reset: Boolean = true,
        page: UInt? = null,
    ) {
        lifecycleScope.launch {
            clearLastError()
            currentListSource = BrowserListSource.BOOKMARKS
            isLoadingMoreFeed = !reset
            setBrowserLoading(
                true,
                getString(if (reset) R.string.browser_loading_bookmarks else R.string.browser_loading_more),
            )
            renderSession(session)
            renderBrowser()

            try {
                val username = session.bootstrap.currentUsername?.trim().orEmpty()
                if (username.isBlank()) {
                    throw IllegalStateException(getString(R.string.feed_bookmarks_login_required))
                }
                applyTopicListResponse(
                    response = sessionStore.fetchBookmarks(username, page),
                    preferredTopicId = preferredTopicId,
                    reset = reset,
                    page = page,
                    emptyMessage = getString(R.string.feed_bookmarks_empty),
                )
            } catch (error: Exception) {
                handleTopicListError(error)
            }
        }
    }

    private fun loadReadHistory(
        preferredTopicId: ULong? = selectedTopicId,
        reset: Boolean = true,
        page: UInt? = null,
    ) {
        lifecycleScope.launch {
            clearLastError()
            currentListSource = BrowserListSource.READ_HISTORY
            isLoadingMoreFeed = !reset
            setBrowserLoading(
                true,
                getString(if (reset) R.string.browser_loading_read_history else R.string.browser_loading_more),
            )
            renderSession(session)
            renderBrowser()

            try {
                applyTopicListResponse(
                    response = sessionStore.fetchReadHistory(page),
                    preferredTopicId = preferredTopicId,
                    reset = reset,
                    page = page,
                    emptyMessage = getString(R.string.feed_read_history_empty),
                )
            } catch (error: Exception) {
                handleTopicListError(error)
            }
        }
    }

    private fun applyTopicListResponse(
        response: TopicListState,
        preferredTopicId: ULong?,
        reset: Boolean,
        page: UInt?,
        emptyMessage: String,
    ) {
        currentFeedPage = page ?: 0u
        nextFeedPage = response.nextPage
        currentTopicList = if (reset || currentTopicList == null) {
            response
        } else {
            mergeTopicLists(currentTopicList!!, response)
        }
        val topicList = currentTopicList!!

        val nextTopicId = preferredTopicId?.takeIf { id ->
            topicList.rows.any { it.topic.id == id }
        } ?: topicList.rows.firstOrNull()?.topic?.id
        selectedTopicId = nextTopicId
        renderSession(session)
        renderBrowser()

        if (nextTopicId == null) {
            setBrowserLoading(false, emptyMessage)
            isLoadingMoreFeed = false
            renderBrowser()
            return
        }

        setBrowserLoading(false, browserFeedSummary(topicList))
        isLoadingMoreFeed = false
        renderBrowser()
    }

    private fun handleTopicListError(error: Exception) {
        recordLastError(error)
        browserStatusMessage = lastErrorMessage
        setBrowserLoading(false, browserStatusMessage)
        isLoadingMoreFeed = false
        renderSession(session)
        renderBrowser()
    }

    private fun openTopic(topicId: ULong) {
        selectedTopicId = topicId
        renderSession(session)
        renderBrowser()

        currentTopicList
            ?.rows
            ?.firstOrNull { it.topic.id == topicId }
            ?.let { row ->
                startActivity(
                    TopicDetailActivity.intent(
                        context = this,
                        topicId = row.topic.id,
                        topicTitle = row.topic.title,
                        targetPostNumber = targetPostNumberFor(row),
                    ),
                )
            }
    }

    private fun openSelectedTopic() {
        val selected = selectedTopicRow() ?: return
        openTopic(selected.topic.id)
    }

    private fun selectedTopicRow(): TopicRowState? {
        val selectedTopicId = selectedTopicId ?: return null
        return currentTopicList?.rows?.firstOrNull { it.topic.id == selectedTopicId }
    }

    private fun selectedTopicMeta(row: TopicRowState): String {
        return buildList {
            categoryLabelFor(row.topic.categoryId)?.let(::add)
            privateMessageParticipantLabel(row.topic)?.let {
                add(getString(R.string.feed_private_messages_participants, it))
            }
            bookmarkLabel(row.topic)?.let(::add)
            readHistoryLabel(row.topic)?.let(::add)
            row.lastPosterUsername?.let(::add)
            TopicPresentation.formatTimestamp(row.activityTimestampUnixMs ?: row.createdTimestampUnixMs)
                ?.let(::add)
            add("${row.topic.postsCount} posts")
            add("${row.topic.views} views")
            if (row.tagNames.isNotEmpty()) {
                add("#${row.tagNames.joinToString(" #")}")
            }
        }.joinToString(" · ")
    }

    private fun detailActionButton(): View {
        return Button(this).apply {
            text = getString(R.string.browser_open_detail)
            isAllCaps = false
            setOnClickListener { openSelectedTopic() }
            layoutParams = LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.WRAP_CONTENT,
            )
        }
    }

    private fun renderSession(state: SessionState) {
        submitMainScreen()
    }

    private fun renderLastError() {
        submitMainScreen()
    }

    private fun renderBrowser() {
        submitMainScreen()
    }

    private fun updateFeedButtonState() {
        submitMainScreen()
    }

    private fun setBrowserLoading(loading: Boolean, message: String? = null) {
        isBrowserLoading = loading
        browserStatusMessage = message
    }

    private fun submitMainScreen() {
        browserScreenAdapter.submitList(buildMainScreenItems())
    }

    private fun buildMainScreenItems(): List<BrowserScreenItem> {
        val items = mutableListOf<BrowserScreenItem>()
        items += browserItem("shell-header", "shell") { shellHeaderView() }
        items += browserItem("session-summary", sessionSummaryText()) { sessionSummaryView() }
        items += browserItem("actions", actionControlsSignature()) { actionControlsView() }
        lastErrorMessage?.let { errorMessage ->
            items += browserItem("last-error", errorMessage) { lastErrorView(errorMessage) }
        }
        items += browserItem("browser-title", currentListTitle()) { browserTitleView() }
        items += browserItem("feed-filters", feedFiltersSignature()) { feedFilterBarView() }
        items += browserItem("browser-status", browserStatusText()) { browserStatusView() }

        val topicList = currentTopicList
        if (topicList == null || topicList.rows.isEmpty()) {
            items += browserItem("topic-empty", topicEmptyText()) { sectionBodyText(topicEmptyText()) }
        } else {
            topicList.rows.forEachIndexed { index, row ->
                items += topicRowItem(row, index)
            }
        }

        if (nextFeedPage != null && topicList?.rows?.isNotEmpty() == true) {
            items += browserItem("load-more", loadMoreSignature()) { loadMoreButtonView() }
        }

        val selectedTopic = selectedTopicRow()
        val detailTitle = selectedTopic?.topic?.title ?: getString(R.string.browser_detail_empty)
        val detailMeta = selectedTopic?.let(::selectedTopicMeta) ?: getString(R.string.browser_detail_dedicated)
        items += browserItem("detail-title", detailTitle) { detailTitleView(detailTitle) }
        items += browserItem("detail-meta", detailMeta) { detailMetaView(detailMeta) }
        items += browserItem(
            key = "detail-action",
            contentSignature = selectedTopic?.topic?.id?.toString() ?: "empty",
        ) {
            if (selectedTopic == null) {
                sectionBodyText(getString(R.string.browser_detail_dedicated))
            } else {
                detailActionButton()
            }
        }

        return items
    }

    private fun browserItem(
        key: String,
        contentSignature: String,
        buildView: () -> View,
    ): BrowserScreenItem {
        return BrowserScreenItem(
            key = key,
            stableId = stableIdFor(key),
            contentSignature = contentSignature,
            buildView = buildView,
        )
    }

    private fun topicRowItem(row: TopicRowState, index: Int): BrowserScreenItem {
        val selected = row.topic.id == selectedTopicId
        return browserItem(
            key = "topic:${row.topic.id}",
            contentSignature = listOf(
                row.toString(),
                selected,
                currentListSource,
                currentFeedKind,
                topicCategories[row.topic.categoryId]?.displayName(),
            ).joinToString("|"),
        ) {
            topicButton(row, isFirst = index == 0)
        }
    }

    private fun stableIdFor(key: String): Long {
        var hash = 1125899906842597L
        key.forEach { character ->
            hash = (hash * 31) + character.code
        }
        return hash
    }

    private fun shellHeaderView(): View {
        return LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(0, 0, 0, dp(12))
            addView(
                TextView(context).apply {
                    text = getString(R.string.app_name)
                    textSize = 22f
                },
            )
            addView(
                TextView(context).apply {
                    text = getString(R.string.shell_subtitle)
                    textSize = 15f
                    setPadding(0, dp(8), 0, 0)
                },
            )
        }
    }

    private fun sessionSummaryView(): View {
        return TextView(this).apply {
            text = sessionSummaryText()
            textSize = 14f
            setPadding(0, dp(12), 0, dp(12))
        }
    }

    private fun sessionSummaryText(): String {
        return buildString {
            appendLine("Phase: ${session.loginPhase}")
            appendLine("Has Login: ${session.hasLoginSession}")
            appendLine("Username: ${session.bootstrap.currentUsername ?: "-"}")
            appendLine("Bootstrap Ready: ${session.bootstrap.hasPreloadedData}")
            appendLine("Categories: ${topicCategories.size}")
            appendLine("Has CSRF: ${session.cookies.csrfToken != null}")
            appendLine("Read API: ${session.readiness.canReadAuthenticatedApi}")
            appendLine("Write API: ${session.readiness.canWriteAuthenticatedApi}")
            appendLine("MessageBus: ${session.readiness.canOpenMessageBus}")
        }
    }

    private fun actionControlsSignature(): String {
        return listOf(
            isBrowserLoading,
            session.readiness.canWriteAuthenticatedApi,
            topicCategoriesForNotifications().size,
        ).joinToString("|")
    }

    private fun actionControlsView(): View {
        val actions = listOf(
            getString(R.string.action_restore_session) to Pair(true, { refreshSessionAndFeed() }),
            getString(R.string.action_open_login) to Pair(true, {
                loginLauncher.launch(Intent(this, LoginActivity::class.java))
            }),
            getString(R.string.action_refresh_bootstrap) to Pair(true, { refreshBootstrap() }),
            getString(R.string.action_refresh_topics) to Pair(!isBrowserLoading, { reloadCurrentFeed() }),
            getString(R.string.action_create_topic) to Pair(
                !isBrowserLoading && session.readiness.canWriteAuthenticatedApi,
                { showCreateTopicComposer() },
            ),
            getString(R.string.action_category_notifications) to Pair(
                !isBrowserLoading &&
                    session.readiness.canWriteAuthenticatedApi &&
                    topicCategoriesForNotifications().isNotEmpty(),
                { showCategoryNotificationPicker() },
            ),
            getString(R.string.action_logout) to Pair(true, { logout() }),
            getString(R.string.action_open_diagnostics) to Pair(true, {
                startActivity(Intent(this, DiagnosticsActivity::class.java))
            }),
            getString(R.string.action_open_notifications) to Pair(true, {
                startActivity(Intent(this, NotificationsActivity::class.java))
            }),
            getString(R.string.action_open_search) to Pair(true, {
                startActivity(Intent(this, SearchActivity::class.java))
            }),
        )

        return LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            actions.forEachIndexed { index, (title, enabledAndAction) ->
                addView(
                    browserButton(
                        text = title,
                        enabled = enabledAndAction.first,
                        topMargin = if (index == 0) 0 else dp(12),
                        onClick = enabledAndAction.second,
                    ),
                )
            }
        }
    }

    private fun lastErrorView(errorMessage: String): View {
        return LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(0, dp(16), 0, dp(12))
            addView(
                TextView(context).apply {
                    text = getString(R.string.last_error_title)
                    textSize = 18f
                },
            )
            addView(
                TextView(context).apply {
                    text = errorMessage
                    textSize = 14f
                    setPadding(0, dp(8), 0, 0)
                },
            )
            addView(
                browserButton(
                    text = getString(R.string.action_copy_last_error),
                    enabled = true,
                    topMargin = dp(8),
                ) {
                    copyLastError()
                },
            )
        }
    }

    private fun browserTitleView(): View {
        return TextView(this).apply {
            text = getString(R.string.browser_title)
            textSize = 18f
            setPadding(0, dp(16), 0, 0)
        }
    }

    private fun feedFiltersSignature(): String {
        return listOf(currentListSource, currentFeedKind, isBrowserLoading).joinToString("|")
    }

    private fun feedFilterBarView(): View {
        val filters = listOf(
            getString(R.string.feed_latest) to Pair(
                currentListSource == BrowserListSource.FEED && currentFeedKind == TopicListKindState.LATEST,
                { loadFeed(TopicListKindState.LATEST) },
            ),
            getString(R.string.feed_new) to Pair(
                currentListSource == BrowserListSource.FEED && currentFeedKind == TopicListKindState.NEW,
                { loadFeed(TopicListKindState.NEW) },
            ),
            getString(R.string.feed_unread) to Pair(
                currentListSource == BrowserListSource.FEED && currentFeedKind == TopicListKindState.UNREAD,
                { loadFeed(TopicListKindState.UNREAD) },
            ),
            getString(R.string.feed_unseen) to Pair(
                currentListSource == BrowserListSource.FEED && currentFeedKind == TopicListKindState.UNSEEN,
                { loadFeed(TopicListKindState.UNSEEN) },
            ),
            getString(R.string.feed_hot) to Pair(
                currentListSource == BrowserListSource.FEED && currentFeedKind == TopicListKindState.HOT,
                { loadFeed(TopicListKindState.HOT) },
            ),
            getString(R.string.feed_top) to Pair(
                currentListSource == BrowserListSource.FEED && currentFeedKind == TopicListKindState.TOP,
                { loadFeed(TopicListKindState.TOP) },
            ),
            getString(R.string.feed_private_messages_inbox) to Pair(
                currentListSource == BrowserListSource.FEED &&
                    currentFeedKind == TopicListKindState.PRIVATE_MESSAGES_INBOX,
                { loadFeed(TopicListKindState.PRIVATE_MESSAGES_INBOX) },
            ),
            getString(R.string.feed_private_messages_sent) to Pair(
                currentListSource == BrowserListSource.FEED &&
                    currentFeedKind == TopicListKindState.PRIVATE_MESSAGES_SENT,
                { loadFeed(TopicListKindState.PRIVATE_MESSAGES_SENT) },
            ),
            getString(R.string.feed_bookmarks) to Pair(
                currentListSource == BrowserListSource.BOOKMARKS,
                { loadBookmarks() },
            ),
            getString(R.string.feed_read_history) to Pair(
                currentListSource == BrowserListSource.READ_HISTORY,
                { loadReadHistory() },
            ),
        )

        return HorizontalScrollView(this).apply {
            isHorizontalScrollBarEnabled = false
            setPadding(0, dp(8), 0, 0)
            addView(
                LinearLayout(context).apply {
                    orientation = LinearLayout.HORIZONTAL
                    filters.forEachIndexed { index, (title, selectedAndAction) ->
                        addView(
                            filterButton(
                                text = title,
                                selected = selectedAndAction.first,
                                enabled = !isBrowserLoading,
                                startMargin = if (index == 0) 0 else dp(8),
                                onClick = selectedAndAction.second,
                            ),
                        )
                    }
                },
            )
        }
    }

    private fun browserStatusView(): View {
        return TextView(this).apply {
            text = browserStatusText()
            textSize = 14f
            setPadding(0, dp(12), 0, dp(4))
        }
    }

    private fun browserStatusText(): String {
        return browserStatusMessage ?: browserFeedSummary(currentTopicList)
    }

    private fun topicEmptyText(): String {
        return browserStatusMessage ?: getString(R.string.browser_empty)
    }

    private fun loadMoreSignature(): String {
        return listOf(nextFeedPage, isBrowserLoading, isLoadingMoreFeed).joinToString("|")
    }

    private fun loadMoreButtonView(): View {
        return browserButton(
            text = if (isLoadingMoreFeed) {
                getString(R.string.browser_loading_more)
            } else {
                getString(R.string.action_load_more)
            },
            enabled = !isBrowserLoading && nextFeedPage != null,
            topMargin = dp(12),
        ) {
            loadMoreFeed()
        }
    }

    private fun detailTitleView(title: String): View {
        return TextView(this).apply {
            text = title
            textSize = 18f
            setPadding(0, dp(28), 0, 0)
        }
    }

    private fun detailMetaView(meta: String): View {
        return TextView(this).apply {
            text = meta
            textSize = 12f
            setPadding(0, dp(8), 0, 0)
        }
    }

    private fun browserButton(
        text: String,
        enabled: Boolean,
        topMargin: Int,
        onClick: () -> Unit,
    ): Button {
        return Button(this).apply {
            this.text = text
            isAllCaps = false
            isEnabled = enabled
            setOnClickListener { onClick() }
            layoutParams = LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.WRAP_CONTENT,
            ).apply {
                this.topMargin = topMargin
            }
        }
    }

    private fun filterButton(
        text: String,
        selected: Boolean,
        enabled: Boolean,
        startMargin: Int,
        onClick: () -> Unit,
    ): Button {
        return Button(this).apply {
            this.text = text
            isAllCaps = false
            alpha = if (selected) 1f else 0.75f
            isEnabled = enabled
            setOnClickListener { onClick() }
            layoutParams = LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.WRAP_CONTENT,
                ViewGroup.LayoutParams.WRAP_CONTENT,
            ).apply {
                marginStart = startMargin
            }
        }
    }

    private fun recordLastError(error: Throwable) {
        lastErrorMessage = error.localizedMessage?.takeIf { it.isNotBlank() } ?: error.toString()
        renderLastError()
    }

    private fun clearLastError() {
        if (lastErrorMessage == null) {
            return
        }

        lastErrorMessage = null
        renderLastError()
    }

    private fun copyLastError() {
        val errorMessage = lastErrorMessage ?: return
        val clipboard = getSystemService(ClipboardManager::class.java) ?: return
        clipboard.setPrimaryClip(
            ClipData.newPlainText(getString(R.string.last_error_title), errorMessage),
        )
        Toast.makeText(this, R.string.last_error_copied, Toast.LENGTH_SHORT).show()
    }

    private fun browserFeedSummary(topicList: TopicListState?): String {
        val rows = topicList?.rows.orEmpty()
        if (rows.isEmpty()) {
            return getString(R.string.browser_empty)
        }
        val selected = selectedTopicId?.let { id ->
            rows.firstOrNull { it.topic.id == id }?.topic?.title
        }
        return buildString {
            append(currentListTitle())
            append(" · ${rows.size} topics")
            append(" · pages 1-${currentFeedPage.toInt() + 1}")
            if (!topicList?.moreTopicsUrl.isNullOrBlank()) {
                append(" · page ${(nextFeedPage?.toInt() ?: currentFeedPage.toInt()) + 1} ready")
            }
            if (!selected.isNullOrBlank()) {
                append(" · $selected")
            }
        }
    }

    private fun topicButton(row: TopicRowState, isFirst: Boolean): View {
        val topic = row.topic
        val category = categoryLabelFor(topic.categoryId)
        val lastActivity = listOfNotNull(
            row.lastPosterUsername,
            TopicPresentation.formatTimestamp(row.activityTimestampUnixMs ?: row.createdTimestampUnixMs),
        )
        val excerpt = row.excerptText?.takeIf { it.isNotBlank() }
        val tagNames = row.tagNames
        val participants = privateMessageParticipantLabel(topic)
        val bookmark = bookmarkLabel(topic)
        val readHistory = readHistoryLabel(topic)

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
                if (row.statusLabels.isNotEmpty()) {
                    append(" · ")
                    append(row.statusLabels.joinToString(" · "))
                }
                append("\n")
                append("${topic.postsCount} posts · ${topic.replyCount} replies · ${topic.views} views · ${topic.likeCount} likes")
                if (lastActivity.isNotEmpty()) {
                    append("\n")
                    append(lastActivity.joinToString(" · "))
                }
                if (!participants.isNullOrBlank()) {
                    append("\n")
                    append(getString(R.string.feed_private_messages_participants, participants))
                }
                if (!bookmark.isNullOrBlank()) {
                    append("\n")
                    append(bookmark)
                }
                if (!readHistory.isNullOrBlank()) {
                    append("\n")
                    append(readHistory)
                }
                if (tagNames.isNotEmpty()) {
                    append(" · #${tagNames.joinToString(" #")}")
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
                topMargin = if (isFirst) 0 else dp(8)
            }
        }
    }

    private fun privateMessageParticipantLabel(topic: TopicSummaryState): String? {
        if (currentListSource != BrowserListSource.FEED) {
            return null
        }
        if (currentFeedKind != TopicListKindState.PRIVATE_MESSAGES_INBOX &&
            currentFeedKind != TopicListKindState.PRIVATE_MESSAGES_SENT
        ) {
            return null
        }

        val currentUsername = session.bootstrap.currentUsername?.trim()
        val participants = topic.participants.mapNotNull { participant ->
            val username = participant.username?.trim().orEmpty()
            val name = participant.name?.trim().orEmpty()
            when {
                username.isEmpty() -> null
                username == currentUsername -> null
                name.isNotEmpty() -> "$name (@$username)"
                else -> "@$username"
            }
        }.distinct()

        return participants.takeIf { it.isNotEmpty() }?.take(4)?.joinToString(", ")
    }

    private fun bookmarkLabel(topic: TopicSummaryState): String? {
        if (currentListSource != BrowserListSource.BOOKMARKS) {
            return null
        }
        return buildList {
            topic.bookmarkedPostNumber?.let {
                add(getString(R.string.feed_bookmark_post_number, it.toString()))
            }
            topic.bookmarkName?.takeIf { it.isNotBlank() }?.let {
                add(getString(R.string.feed_bookmark_name, it))
            }
            TopicPresentation.formatTimestamp(topic.bookmarkReminderAt)?.let {
                add(getString(R.string.feed_bookmark_reminder, it))
            }
        }.takeIf { it.isNotEmpty() }?.joinToString(" · ")
    }

    private fun readHistoryLabel(topic: TopicSummaryState): String? {
        if (currentListSource != BrowserListSource.READ_HISTORY) {
            return null
        }
        return topic.lastReadPostNumber?.let {
            getString(R.string.feed_read_history_last_read, it.toString())
        }
    }

    private fun targetPostNumberFor(row: TopicRowState): UInt? {
        return when (currentListSource) {
            BrowserListSource.BOOKMARKS -> row.topic.bookmarkedPostNumber ?: row.topic.lastReadPostNumber
            BrowserListSource.READ_HISTORY -> row.topic.lastReadPostNumber
            BrowserListSource.FEED -> null
        }
    }

    private fun currentListTitle(): String {
        return when (currentListSource) {
            BrowserListSource.FEED -> getString(R.string.feed_title, currentFeedKind.displayName())
            BrowserListSource.BOOKMARKS -> getString(R.string.feed_bookmarks)
            BrowserListSource.READ_HISTORY -> getString(R.string.feed_read_history)
        }
    }

    private fun labelText(text: String): TextView {
        return TextView(this).apply {
            this.text = text
            textSize = 13f
            setPadding(0, dp(12), 0, dp(4))
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
            cookies = CookieState(
                tToken = null,
                forumSession = null,
                cfClearance = null,
                csrfToken = null,
                platformCookies = emptyList(),
            ),
            bootstrap = BootstrapState(
                baseUrl = "https://linux.do",
                discourseBaseUri = null,
                sharedSessionKey = null,
                currentUsername = null,
                currentUserId = null,
                notificationChannelPosition = null,
                longPollingBaseUrl = null,
                turnstileSitekey = null,
                topicTrackingStateMeta = null,
                preloadedJson = null,
                hasPreloadedData = false,
                hasSiteMetadata = false,
                topTags = emptyList(),
                canTagTopics = false,
                categories = emptyList(),
                hasSiteSettings = false,
                enabledReactionIds = listOf("heart"),
                minPostLength = 1u,
                minTopicTitleLength = 15u,
                minFirstPostLength = 20u,
                minPersonalMessageTitleLength = 2u,
                minPersonalMessagePostLength = 10u,
                defaultComposerCategory = null,
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
            loginPhase = uniffi.fire_uniffi_session.LoginPhaseState.ANONYMOUS,
            hasLoginSession = false,
            profileDisplayName = "未登录",
            loginPhaseLabel = "未登录",
            browserUserAgent = null,
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
            TopicListKindState.PRIVATE_MESSAGES_INBOX -> {
                getString(R.string.feed_private_messages_inbox)
            }
            TopicListKindState.PRIVATE_MESSAGES_SENT -> {
                getString(R.string.feed_private_messages_sent)
            }
        }
    }

    private fun dp(value: Int): Int {
        return (value * resources.displayMetrics.density).toInt()
    }

    private fun topicCategoriesForComposer(): List<TopicCategoryState> {
        return session.bootstrap.categories
            .filter { category -> category.id > 0uL && (category.permission ?: 1u) > 0u }
            .sortedWith(compareBy<TopicCategoryState> { it.name.lowercase() }.thenBy { it.id })
    }

    private fun topicCategoriesForNotifications(): List<TopicCategoryState> {
        return session.bootstrap.categories
            .filter { category -> category.id > 0uL }
            .sortedWith(compareBy<TopicCategoryState> { it.name.lowercase() }.thenBy { it.id })
    }

    private fun defaultComposerCategory(categories: List<TopicCategoryState>): TopicCategoryState? {
        val defaultId = session.bootstrap.defaultComposerCategory
        return categories.firstOrNull { it.id == defaultId } ?: categories.firstOrNull()
    }

    private fun createTopicCategoryLabel(category: TopicCategoryState): String {
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

    private fun categoryNotificationCategoryLabel(category: TopicCategoryState): String {
        val level = CategoryNotificationLevelOption.fromValue(category.notificationLevel)
        return getString(
            R.string.category_notification_category_choice,
            category.displayName(),
            getString(level.titleResId),
        )
    }

    private fun categoryNotificationOptionLabel(option: CategoryNotificationLevelOption): String {
        return getString(
            R.string.topic_detail_notification_option,
            getString(option.titleResId),
            getString(option.descriptionResId),
        )
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

    private fun applySession(state: SessionState) {
        session = state
        topicCategories = session.bootstrap.categories.associateBy { it.id }
    }

    private fun mergeTopicLists(
        existing: TopicListState,
        incoming: TopicListState,
    ): TopicListState {
        val topicsById = LinkedHashMap<ULong, TopicSummaryState>()
        existing.topics.forEach { topicsById[it.id] = it }
        incoming.topics.forEach { topicsById[it.id] = it }

        val usersById = LinkedHashMap<ULong, uniffi.fire_uniffi_types.TopicUserState>()
        existing.users.forEach { usersById[it.id] = it }
        incoming.users.forEach { usersById[it.id] = it }

        val rowsByTopicId = LinkedHashMap<ULong, uniffi.fire_uniffi_types.TopicRowState>()
        existing.rows.forEach { rowsByTopicId[it.topic.id] = it }
        incoming.rows.forEach { rowsByTopicId[it.topic.id] = it }

        return TopicListState(
            topics = topicsById.values.toList(),
            users = usersById.values.toList(),
            rows = rowsByTopicId.values.toList(),
            moreTopicsUrl = incoming.moreTopicsUrl,
            nextPage = incoming.nextPage,
        )
    }

    private fun categoryLabelFor(categoryId: ULong?): String? {
        val id = categoryId ?: return null
        return topicCategories[id]?.displayName() ?: "Category #$id"
    }
}
