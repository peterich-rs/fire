package com.fire.app

import android.graphics.Color
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.os.Bundle
import android.text.InputType
import android.view.View
import android.view.ViewGroup
import android.view.inputmethod.EditorInfo
import android.widget.Button
import android.widget.EditText
import android.widget.FrameLayout
import android.widget.LinearLayout
import android.widget.ProgressBar
import android.widget.TextView
import androidx.appcompat.app.AppCompatActivity
import androidx.lifecycle.lifecycleScope
import androidx.recyclerview.widget.DiffUtil
import androidx.recyclerview.widget.LinearLayoutManager
import androidx.recyclerview.widget.ListAdapter
import androidx.recyclerview.widget.RecyclerView
import com.fire.app.session.FireSessionStore
import com.fire.app.session.FireSessionStoreRepository
import kotlinx.coroutines.launch
import uniffi.fire_uniffi.plainTextFromHtml
import uniffi.fire_uniffi_search.GroupedSearchResultState
import uniffi.fire_uniffi_search.SearchPostState
import uniffi.fire_uniffi_search.SearchQueryState
import uniffi.fire_uniffi_search.SearchResultState
import uniffi.fire_uniffi_search.SearchTopicState
import uniffi.fire_uniffi_search.SearchTypeFilterState
import uniffi.fire_uniffi_search.SearchUserState

class SearchActivity : AppCompatActivity() {
    private enum class Filter(
        val typeFilter: SearchTypeFilterState?,
        val labelRes: Int,
    ) {
        ALL(null, R.string.search_filter_all),
        TOPICS(SearchTypeFilterState.TOPIC, R.string.search_filter_topics),
        POSTS(SearchTypeFilterState.POST, R.string.search_filter_posts),
        USERS(SearchTypeFilterState.USER, R.string.search_filter_users),
    }

    private data class SearchResultListItem(
        val key: String,
        val stableId: Long,
        val contentSignature: String,
        val buildView: () -> View,
    )

    private class SearchResultListAdapter :
        ListAdapter<SearchResultListItem, SearchResultListAdapter.DynamicViewHolder>(DiffCallback) {

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

        private object DiffCallback : DiffUtil.ItemCallback<SearchResultListItem>() {
            override fun areItemsTheSame(
                oldItem: SearchResultListItem,
                newItem: SearchResultListItem,
            ): Boolean = oldItem.key == newItem.key

            override fun areContentsTheSame(
                oldItem: SearchResultListItem,
                newItem: SearchResultListItem,
            ): Boolean = oldItem.contentSignature == newItem.contentSignature
        }
    }

    private lateinit var sessionStore: FireSessionStore
    private lateinit var queryEditText: EditText
    private lateinit var metaText: TextView
    private lateinit var errorText: TextView
    private lateinit var loadingIndicator: ProgressBar
    private lateinit var resultList: RecyclerView
    private lateinit var searchButton: Button
    private lateinit var loadMoreButton: Button
    private lateinit var filterButtons: Map<Filter, Button>
    private val resultListAdapter = SearchResultListAdapter()

    private var selectedFilter = Filter.ALL
    private var currentQuery = ""
    private var currentPage: UInt = 1u
    private var nextPage: UInt? = null
    private var groupedResult: GroupedSearchResultState? = null
    private var isLoading = false
    private val topics = mutableListOf<SearchTopicState>()
    private val posts = mutableListOf<SearchPostState>()
    private val users = mutableListOf<SearchUserState>()

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        sessionStore = FireSessionStoreRepository.get(applicationContext)
        setContentView(buildContentView())
        renderFilters()
        renderResults()
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

                            addView(
                                TextView(context).apply {
                                    text = getString(R.string.search_title)
                                    textSize = 20f
                                    setTypeface(typeface, Typeface.BOLD)
                                    setTextColor(Color.parseColor("#FF111827"))
                                },
                            )
                            metaText = TextView(context).apply {
                                text = getString(R.string.search_enter_query)
                                textSize = 12f
                                setTextColor(Color.parseColor("#FF6B7280"))
                                setPadding(0, dp(4), 0, 0)
                            }
                            addView(metaText)
                        },
                    )
                },
            )

            loadingIndicator = ProgressBar(context, null, android.R.attr.progressBarStyleHorizontal).apply {
                max = 100
                visibility = View.GONE
            }
            addView(loadingIndicator)

            addView(
                LinearLayout(context).apply {
                    orientation = LinearLayout.HORIZONTAL
                    setPadding(dp(16), dp(10), dp(16), dp(4))

                    queryEditText = EditText(context).apply {
                        hint = getString(R.string.search_hint)
                        setSingleLine(true)
                        imeOptions = EditorInfo.IME_ACTION_SEARCH
                        inputType = InputType.TYPE_CLASS_TEXT
                        setOnEditorActionListener { _, actionId, _ ->
                            if (actionId == EditorInfo.IME_ACTION_SEARCH) {
                                performSearch(reset = true)
                                true
                            } else {
                                false
                            }
                        }
                        layoutParams = LinearLayout.LayoutParams(
                            0,
                            ViewGroup.LayoutParams.WRAP_CONTENT,
                            1f,
                        ).apply {
                            marginEnd = dp(8)
                        }
                    }
                    addView(queryEditText)

                    searchButton = Button(context).apply {
                        text = getString(R.string.search_action)
                        setOnClickListener { performSearch(reset = true) }
                    }
                    addView(searchButton)
                },
            )

            addView(
                LinearLayout(context).apply {
                    orientation = LinearLayout.HORIZONTAL
                    setPadding(dp(16), dp(4), dp(16), dp(4))

                    filterButtons = Filter.entries.associateWith { filter ->
                        Button(context).apply {
                            isAllCaps = false
                            text = getString(filter.labelRes)
                            setOnClickListener {
                                selectedFilter = filter
                                renderFilters()
                                performSearch(reset = true)
                            }
                            layoutParams = LinearLayout.LayoutParams(
                                0,
                                ViewGroup.LayoutParams.WRAP_CONTENT,
                                1f,
                            ).apply {
                                marginEnd = if (filter == Filter.entries.last()) 0 else dp(6)
                            }
                        }.also(::addView)
                    }
                },
            )

            errorText = TextView(context).apply {
                visibility = View.GONE
                setTextColor(Color.parseColor("#FFB91C1C"))
                textSize = 14f
                setPadding(dp(16), dp(8), dp(16), dp(4))
            }
            addView(errorText)

            resultList = RecyclerView(context).apply {
                layoutParams = LinearLayout.LayoutParams(
                    ViewGroup.LayoutParams.MATCH_PARENT,
                    0,
                    1f,
                )
                clipToPadding = false
                setPadding(dp(16), dp(12), dp(16), dp(16))
                layoutManager = LinearLayoutManager(this@SearchActivity)
                adapter = resultListAdapter
                itemAnimator = null
                setItemViewCacheSize(8)
                recycledViewPool.setMaxRecycledViews(0, 18)
            }
            addView(resultList)

            loadMoreButton = Button(context).apply {
                isAllCaps = false
                text = getString(R.string.action_load_more)
                setOnClickListener { performSearch(reset = false) }
                visibility = View.GONE
                layoutParams = LinearLayout.LayoutParams(
                    ViewGroup.LayoutParams.MATCH_PARENT,
                    ViewGroup.LayoutParams.WRAP_CONTENT,
                ).apply {
                    leftMargin = dp(16)
                    rightMargin = dp(16)
                    bottomMargin = dp(16)
                }
            }
            addView(loadMoreButton)
        }
    }

    private fun performSearch(reset: Boolean) {
        if (isLoading) {
            return
        }

        val nextQuery = queryEditText.text?.toString()?.trim().orEmpty()
        if (nextQuery.isBlank()) {
            currentQuery = ""
            clearResults()
            renderResults()
            return
        }
        if (!reset && nextPage == null) {
            return
        }

        lifecycleScope.launch {
            setLoading(true)
            errorText.visibility = View.GONE
            try {
                if (reset) {
                    clearResults()
                    currentPage = 1u
                    currentQuery = nextQuery
                } else {
                    currentPage = nextPage ?: currentPage
                }
                val result = sessionStore.search(
                    SearchQueryState(
                        q = currentQuery,
                        page = currentPage,
                        typeFilter = selectedFilter.typeFilter,
                    ),
                )
                applyResult(result, reset)
                renderResults()
            } catch (error: Exception) {
                errorText.text = error.localizedMessage ?: getString(R.string.search_error)
                errorText.visibility = View.VISIBLE
            } finally {
                setLoading(false)
                renderFilters()
            }
        }
    }

    private fun applyResult(result: SearchResultState, reset: Boolean) {
        if (reset) {
            clearResults()
        }
        mergeTopics(result.topics)
        mergePosts(result.posts)
        mergeUsers(result.users)
        groupedResult = result.groupedResult
        nextPage = if (hasMore(result.groupedResult)) currentPage + 1u else null
    }

    private fun mergeTopics(incoming: List<SearchTopicState>) {
        val existing = topics.map { it.id }.toMutableSet()
        incoming.forEach { topic ->
            if (existing.add(topic.id)) {
                topics.add(topic)
            }
        }
    }

    private fun mergePosts(incoming: List<SearchPostState>) {
        val existing = posts.map { it.id }.toMutableSet()
        incoming.forEach { post ->
            if (existing.add(post.id)) {
                posts.add(post)
            }
        }
    }

    private fun mergeUsers(incoming: List<SearchUserState>) {
        val existing = users.map { it.id }.toMutableSet()
        incoming.forEach { user ->
            if (existing.add(user.id)) {
                users.add(user)
            }
        }
    }

    private fun hasMore(grouped: GroupedSearchResultState): Boolean {
        return when (selectedFilter) {
            Filter.ALL -> grouped.moreFullPageResults
            Filter.TOPICS -> grouped.moreFullPageResults
            Filter.POSTS -> grouped.morePosts || grouped.moreFullPageResults
            Filter.USERS -> grouped.moreUsers || grouped.moreFullPageResults
        }
    }

    private fun clearResults() {
        topics.clear()
        posts.clear()
        users.clear()
        groupedResult = null
        nextPage = null
        currentPage = 1u
    }

    private fun renderResults() {
        renderMeta()
        renderFilters()
        resultListAdapter.submitList(searchResultItems())
        renderLoadMore()
    }

    private fun searchResultItems(): List<SearchResultListItem> {
        if (currentQuery.isBlank()) {
            return listOf(
                searchResultItem("empty-query", getString(R.string.search_enter_query)) {
                    sectionBodyText(getString(R.string.search_enter_query))
                },
            )
        }
        if (topics.isEmpty() && posts.isEmpty() && users.isEmpty()) {
            return listOf(
                searchResultItem("empty-results", getString(R.string.search_empty)) {
                    sectionBodyText(getString(R.string.search_empty))
                },
            )
        }

        val items = mutableListOf<SearchResultListItem>()
        if (topics.isNotEmpty()) {
            items += sectionItem("section:topics", getString(R.string.search_topics_section))
            topics.forEach { topic ->
                items += searchResultItem(
                    key = "topic:${topic.id}",
                    contentSignature = topic.toString(),
                ) {
                    topicRow(topic)
                }
            }
        }
        if (posts.isNotEmpty()) {
            items += sectionItem("section:posts", getString(R.string.search_posts_section))
            posts.forEach { post ->
                items += searchResultItem(
                    key = "post:${post.id}",
                    contentSignature = post.toString(),
                ) {
                    postRow(post)
                }
            }
        }
        if (users.isNotEmpty()) {
            items += sectionItem("section:users", getString(R.string.search_users_section))
            users.forEach { user ->
                items += searchResultItem(
                    key = "user:${user.id}",
                    contentSignature = user.toString(),
                ) {
                    userRow(user)
                }
            }
        }
        return items
    }

    private fun sectionItem(key: String, title: String): SearchResultListItem {
        return searchResultItem(key, title) {
            sectionTitle(title)
        }
    }

    private fun searchResultItem(
        key: String,
        contentSignature: String,
        buildView: () -> View,
    ): SearchResultListItem {
        return SearchResultListItem(
            key = key,
            stableId = stableIdFor(key),
            contentSignature = contentSignature,
            buildView = buildView,
        )
    }

    private fun stableIdFor(key: String): Long {
        return key.fold(1125899906842597L) { hash, character ->
            (hash * 31) + character.code
        }
    }

    private fun renderMeta() {
        metaText.text = if (currentQuery.isBlank()) {
            getString(R.string.search_enter_query)
        } else {
            buildList {
                add(getString(R.string.search_summary, topics.size.toString(), posts.size.toString(), users.size.toString()))
                groupedResult?.takeIf { hasMore(it) }?.let {
                    add(getString(R.string.search_more_available))
                }
            }.joinToString(" · ")
        }
    }

    private fun renderFilters() {
        filterButtons.forEach { (filter, button) ->
            val selected = filter == selectedFilter
            button.alpha = if (selected) 1f else 0.72f
            button.isEnabled = !isLoading || !selected
        }
        searchButton.isEnabled = !isLoading
    }

    private fun renderLoadMore() {
        loadMoreButton.visibility = if (nextPage != null || isLoading) View.VISIBLE else View.GONE
        loadMoreButton.isEnabled = !isLoading && nextPage != null
        loadMoreButton.text = if (isLoading) {
            getString(R.string.browser_loading_more)
        } else {
            getString(R.string.action_load_more)
        }
    }

    private fun topicRow(topic: SearchTopicState): View {
        val tags = topic.tags.takeIf { it.isNotEmpty() }?.joinToString(" #", prefix = "#")
        val meta = buildList {
            add(getString(R.string.search_topic_meta, topic.postsCount.toString(), topic.views.toString()))
            tags?.let(::add)
            if (topic.closed) {
                add("closed")
            }
            if (topic.archived) {
                add("archived")
            }
        }.joinToString(" · ")

        return resultRow(
            title = topic.title,
            meta = meta,
            body = null,
            onClick = {
                startActivity(TopicDetailActivity.intent(this, topic.id, topic.title))
            },
        )
    }

    private fun postRow(post: SearchPostState): View {
        val title = post.topicTitleHeadline
            ?.let { plainTextFromHtml(it).trim() }
            ?.takeIf { it.isNotBlank() }
            ?: getString(R.string.topic_detail_title_fallback, post.topicId?.toString() ?: post.id.toString())
        val meta = buildList {
            add(getString(R.string.search_post_meta, post.username, post.postNumber.toString(), post.likeCount.toString()))
            (
                TopicPresentation.formatTimestamp(post.createdTimestampUnixMs)
                    ?: TopicPresentation.formatTimestamp(post.createdAt)
                )?.let(::add)
        }.joinToString(" · ")
        val blurb = plainTextFromHtml(post.blurb).trim().takeIf { it.isNotBlank() }

        return resultRow(
            title = title,
            meta = meta,
            body = blurb,
            onClick = {
                val topicId = post.topicId ?: return@resultRow
                startActivity(
                    TopicDetailActivity.intent(
                        context = this,
                        topicId = topicId,
                        topicTitle = title,
                        targetPostNumber = post.postNumber,
                    ),
                )
            },
        )
    }

    private fun userRow(user: SearchUserState): View {
        val title = user.name?.takeIf { it.isNotBlank() } ?: user.username
        return resultRow(
            title = title,
            meta = getString(R.string.search_user_meta, user.username),
            body = null,
            onClick = {
                startActivity(ProfileActivity.intent(this, user.username))
            },
        )
    }

    private fun resultRow(
        title: String,
        meta: String,
        body: String?,
        onClick: () -> Unit,
    ): View {
        return LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            isClickable = true
            setOnClickListener { onClick() }
            setPadding(dp(14), dp(12), dp(14), dp(12))
            background = roundedBackground(Color.WHITE, Color.parseColor("#1F2563EB"))
            layoutParams = LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.WRAP_CONTENT,
            ).apply {
                bottomMargin = dp(10)
            }

            addView(
                TextView(context).apply {
                    text = title
                    textSize = 15f
                    setTypeface(typeface, Typeface.BOLD)
                    setTextColor(Color.parseColor("#FF111827"))
                    maxLines = 2
                    ellipsize = android.text.TextUtils.TruncateAt.END
                },
            )
            addView(
                TextView(context).apply {
                    text = meta
                    textSize = 12f
                    setTextColor(Color.parseColor("#FF6B7280"))
                    setPadding(0, dp(4), 0, 0)
                },
            )
            if (!body.isNullOrBlank()) {
                addView(
                    TextView(context).apply {
                        text = body
                        textSize = 13f
                        setTextColor(Color.parseColor("#FF374151"))
                        setPadding(0, dp(8), 0, 0)
                        maxLines = 3
                        ellipsize = android.text.TextUtils.TruncateAt.END
                    },
                )
            }
        }
    }

    private fun sectionTitle(title: String): View {
        return TextView(this).apply {
            text = title
            textSize = 16f
            setTypeface(typeface, Typeface.BOLD)
            setTextColor(Color.parseColor("#FF111827"))
            setPadding(0, dp(10), 0, dp(8))
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

    private fun setLoading(loading: Boolean) {
        isLoading = loading
        loadingIndicator.visibility = if (loading) View.VISIBLE else View.GONE
        renderMeta()
        renderFilters()
        renderLoadMore()
    }

    private fun roundedBackground(fillColor: Int, strokeColor: Int): GradientDrawable {
        return GradientDrawable().apply {
            shape = GradientDrawable.RECTANGLE
            cornerRadius = dp(10).toFloat()
            setColor(fillColor)
            setStroke(dp(1), strokeColor)
        }
    }

    private fun dp(value: Int): Int {
        return (value * resources.displayMetrics.density).toInt()
    }
}
