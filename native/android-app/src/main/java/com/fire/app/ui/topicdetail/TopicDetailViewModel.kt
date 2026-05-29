package com.fire.app.ui.topicdetail

import android.util.LruCache
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.fire.app.TopicPresentation
import com.fire.app.data.repository.SessionRepository
import com.fire.app.data.repository.TopicRepository
import com.fire.app.messagebus.FireMessageBusCoordinator
import com.fire.app.richtext.FireRichTextContent
import com.fire.app.richtext.FireRichTextParser
import com.fire.app.richtext.FireSpannableBuilder
import com.fire.app.session.FireSessionStore
import com.fire.app.cloudflare.CloudflareChallengeDetector
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asSharedFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import uniffi.fire_uniffi_topics.TopicDetailState
import uniffi.fire_uniffi_topics.TopicPostState
import uniffi.fire_uniffi_topics.TopicPostStreamState
import uniffi.fire_uniffi_topics.TopicResponseCursorState
import uniffi.fire_uniffi_topics.TopicResponsePageState
import uniffi.fire_uniffi_topics.TopicResponseRowState
import uniffi.fire_uniffi_topics.TopicScreenState

class TopicDetailViewModel(
    private val sessionRepository: SessionRepository,
    private val topicRepository: TopicRepository,
    private val sessionStore: FireSessionStore,
    private val messageBusCoordinator: FireMessageBusCoordinator,
) : ViewModel() {

    private val _detail = MutableStateFlow<TopicDetailState?>(null)
    val detail = _detail.asStateFlow()

    private val _isLoading = MutableStateFlow(false)
    val isLoading = _isLoading.asStateFlow()

    private val _isLoadingMore = MutableStateFlow(false)
    val isLoadingMore = _isLoadingMore.asStateFlow()

    private val _errorMessage = MutableStateFlow<String?>(null)
    val errorMessage = _errorMessage.asStateFlow()

    private val _postRows = MutableStateFlow<List<PostRow>>(emptyList())
    val postRows = _postRows.asStateFlow()

    private val _scrollTargetPostNumber = MutableSharedFlow<UInt>(extraBufferCapacity = 1)
    val scrollTargetPostNumber = _scrollTargetPostNumber.asSharedFlow()

    private val _cloudflareChallenge = MutableSharedFlow<Unit>(extraBufferCapacity = 1)
    val cloudflareChallenge = _cloudflareChallenge.asSharedFlow()

    private var cursor: TopicResponseCursorState? = null
    private var screen: TopicScreenState? = null
    private var responseRows: MutableList<TopicResponseRowState> = mutableListOf()
    private var messageBusJob: Job? = null
    private var pendingMessageBusRefreshJob: Job? = null
    private var subscribedTopicId: ULong? = null
    private var subscribedOwnerToken: String? = null

    val hasMorePosts: Boolean get() = cursor != null

    private val renderCache = LruCache<ULong, FireRichTextContent>(64)

    fun loadTopicDetail(topicId: ULong, targetPostNumber: UInt? = null) {
        if (_isLoading.value) return
        viewModelScope.launch {
            _isLoading.value = true
            _errorMessage.value = null
            try {
                val fetched = topicRepository.fetchTopicScreen(topicId, targetPostNumber)
                val allPosts = applyFetchedScreen(fetched)
                preloadRenderContent(allPosts)
                maintainTopicDetailMessageBus(topicId, fetched.header.messageBusLastId)
                targetPostNumber
                    ?.takeIf { it > 0u }
                    ?.let { scrollToPostWhenLoaded(it) }
            } catch (e: Exception) {
                if (CloudflareChallengeDetector.isChallenge(e)) {
                    _cloudflareChallenge.tryEmit(Unit)
                    _errorMessage.value = null
                } else {
                    _errorMessage.value = e.localizedMessage ?: "加载话题详情失败"
                }
            } finally {
                _isLoading.value = false
            }
        }
    }

    private fun applyFetchedScreen(fetched: TopicScreenState): List<TopicPostState> {
        val bodyPost = fetched.body.post
        val normalizedResponseRows = TopicDetailPostRows.uniqueResponseRows(
            rows = fetched.response.rows,
            bodyPostId = bodyPost.id,
        )
        val normalizedResponse = fetched.response.copy(rows = normalizedResponseRows)
        screen = fetched.copy(response = normalizedResponse)
        responseRows = normalizedResponseRows.toMutableList()
        cursor = fetched.response.nextCursor

        val header = fetched.header
        val allPosts = TopicDetailPostRows.postsForDetail(bodyPost, normalizedResponseRows)
        val rows = normalizedResponseRows.map(::postRow)

        _detail.value = TopicDetailState(
            id = header.topicId,
            messageBusLastId = header.messageBusLastId,
            title = header.title,
            slug = header.slug,
            postsCount = header.postsCount,
            categoryId = header.categoryId,
            tags = header.tags,
            views = header.views,
            likeCount = header.likeCount,
            createdAt = header.createdAt,
            lastReadPostNumber = header.lastReadPostNumber,
            bookmarks = header.bookmarks,
            bookmarked = header.bookmarked,
            bookmarkId = header.bookmarkId,
            bookmarkName = header.bookmarkName,
            bookmarkReminderAt = header.bookmarkReminderAt,
            acceptedAnswer = header.acceptedAnswer,
            hasAcceptedAnswer = header.hasAcceptedAnswer,
            canVote = header.canVote,
            voteCount = header.voteCount,
            userVoted = header.userVoted,
            summarizable = header.summarizable,
            hasCachedSummary = header.hasCachedSummary,
            hasSummary = header.hasSummary,
            archetype = header.archetype,
            postStream = TopicPostStreamState(
                posts = allPosts,
                stream = allPosts.map { it.id },
            ),
            details = header.details,
        )
        _postRows.value = rows
        return allPosts
    }

    private fun maintainTopicDetailMessageBus(topicId: ULong, lastMessageId: Long?) {
        if (subscribedTopicId == topicId && messageBusJob != null) return

        releaseTopicDetailMessageBus()
        val ownerToken = "android_topic_detail_$topicId"
        subscribedTopicId = topicId
        subscribedOwnerToken = ownerToken

        runCatching {
            sessionStore.subscribeTopicDetailChannel(topicId, ownerToken, lastMessageId)
            sessionStore.subscribeTopicReactionChannel(topicId, ownerToken)
            sessionStore.subscribeTopicPollsChannel(topicId, ownerToken)
        }.onFailure {
            releaseTopicDetailMessageBus()
            return
        }

        viewModelScope.launch {
            runCatching { sessionStore.bootstrapTopicReplyPresence(topicId, ownerToken) }
        }

        messageBusJob = viewModelScope.launch {
            messageBusCoordinator.topicDetailEvents(topicId).collect {
                scheduleTopicDetailRefresh(topicId)
            }
        }
    }

    private fun scheduleTopicDetailRefresh(topicId: ULong) {
        pendingMessageBusRefreshJob?.cancel()
        pendingMessageBusRefreshJob = viewModelScope.launch {
            delay(1_500L)
            refreshTopicDetailFromMessageBus(topicId)
        }
    }

    private suspend fun refreshTopicDetailFromMessageBus(topicId: ULong) {
        if (_isLoading.value) return
        try {
            val fetched = topicRepository.fetchTopicScreen(
                topicId = topicId,
                targetPostNumber = null,
                forceLoad = false,
                trackVisit = false,
            )
            val allPosts = applyFetchedScreen(fetched)
            preloadRenderContent(allPosts)
        } catch (e: Exception) {
            if (CloudflareChallengeDetector.isChallenge(e)) {
                _cloudflareChallenge.tryEmit(Unit)
                _errorMessage.value = null
            }
        }
    }

    private fun releaseTopicDetailMessageBus() {
        pendingMessageBusRefreshJob?.cancel()
        pendingMessageBusRefreshJob = null
        messageBusJob?.cancel()
        messageBusJob = null

        val topicId = subscribedTopicId
        val ownerToken = subscribedOwnerToken
        subscribedTopicId = null
        subscribedOwnerToken = null

        if (topicId != null && ownerToken != null) {
            runCatching {
                sessionStore.unsubscribeTopicDetailChannel(topicId, ownerToken)
                sessionStore.unsubscribeTopicReactionChannel(topicId, ownerToken)
                sessionStore.unsubscribeTopicPollsChannel(topicId, ownerToken)
                sessionStore.unsubscribeTopicReplyPresenceChannel(topicId, ownerToken)
            }
        }
    }

    fun loadMorePosts() {
        if (_isLoadingMore.value) return
        viewModelScope.launch {
            loadMorePostsPage()
        }
    }

    fun getRenderContent(post: TopicPostState): FireRichTextContent? {
        val cached = renderCache.get(post.id)
        if (cached != null) return cached

        val content = parsePostContent(post)
        if (content != null) {
            renderCache.put(post.id, content)
        }
        return content
    }

    fun likePost(postId: ULong) {
        viewModelScope.launch {
            try {
                sessionStore.likePost(postId)
                // Reload to get updated like count
                _detail.value?.let { current ->
                    _detail.value = current // trigger re-render
                }
            } catch (_: Exception) { }
        }
    }

    fun unlikePost(postId: ULong) {
        viewModelScope.launch {
            try {
                sessionStore.unlikePost(postId)
            } catch (_: Exception) { }
        }
    }

    fun bookmarkPost(postId: ULong, bookmarked: Boolean, bookmarkId: ULong?) {
        viewModelScope.launch {
            try {
                if (bookmarked && bookmarkId != null) {
                    sessionStore.deleteBookmark(bookmarkId)
                } else {
                    sessionStore.createBookmark(postId, "Post")
                }
            } catch (_: Exception) { }
        }
    }

    fun deletePost(postId: ULong) {
        viewModelScope.launch {
            try {
                sessionStore.deletePost(postId)
            } catch (_: Exception) { }
        }
    }

    private fun preloadRenderContent(posts: List<TopicPostState>) {
        viewModelScope.launch(Dispatchers.Default) {
            for (post in posts) {
                if (renderCache.get(post.id) == null) {
                    val content = parsePostContent(post)
                    if (content != null) {
                        renderCache.put(post.id, content)
                    }
                }
            }
        }
    }

    private suspend fun scrollToPostWhenLoaded(postNumber: UInt) {
        if (hasLoadedPostNumber(postNumber)) {
            _scrollTargetPostNumber.emit(postNumber)
            return
        }

        var remainingPages = TARGET_HYDRATION_PAGE_LIMIT
        while (remainingPages > 0 && cursor != null && !hasLoadedPostNumber(postNumber)) {
            remainingPages -= 1
            if (!loadMorePostsPage()) break
        }

        if (hasLoadedPostNumber(postNumber)) {
            _scrollTargetPostNumber.emit(postNumber)
        }
    }

    private fun hasLoadedPostNumber(postNumber: UInt): Boolean {
        if (screen?.body?.post?.postNumber == postNumber) return true
        return _postRows.value.any { row -> row.post.postNumber == postNumber }
    }

    private suspend fun loadMorePostsPage(): Boolean {
        val currentCursor = cursor ?: return false
        if (_isLoadingMore.value) return false
        _isLoadingMore.value = true
        return try {
            val page = topicRepository.fetchTopicResponsePage(currentCursor)
            if (cursor != currentCursor) return false

            val bodyPost = screen?.body?.post
            val previousResponseRows = responseRows.toList()
            val mergedResponseRows = TopicDetailPostRows.uniqueResponseRows(
                rows = previousResponseRows + page.rows,
                bodyPostId = bodyPost?.id,
            )
            responseRows = mergedResponseRows.toMutableList()
            cursor = page.nextCursor

            val rows = mergedResponseRows.map(::postRow)
            _postRows.value = rows

            _detail.value?.let { current ->
                val allPosts = bodyPost
                    ?.let { TopicDetailPostRows.postsForDetail(it, mergedResponseRows) }
                    ?: TopicDetailPostRows.uniquePosts(rows.map { it.post })
                _detail.value = current.copy(
                    postStream = current.postStream.copy(
                        posts = allPosts,
                        stream = allPosts.map { it.id },
                    ),
                )
            }
            preloadRenderContent(mergedResponseRows.map { it.post })
            page.rows.isNotEmpty()
        } catch (e: Exception) {
            if (CloudflareChallengeDetector.isChallenge(e)) {
                _cloudflareChallenge.tryEmit(Unit)
                _errorMessage.value = null
            } else {
                _errorMessage.value = e.localizedMessage ?: "加载更多帖子失败"
            }
            false
        } finally {
            _isLoadingMore.value = false
        }
    }

    private fun postRow(row: TopicResponseRowState): PostRow {
        return PostRow(
            post = row.post,
            depth = row.depth.toInt(),
            parentPostNumber = row.parentPostNumber,
            hasChildren = row.hasChildren,
        )
    }

    private fun parsePostContent(post: TopicPostState): FireRichTextContent? {
        val cooked = post.cooked.ifBlank { return null }
        return try {
            FireRichTextParser.parse(cooked, "https://linux.do")
        } catch (_: Exception) {
            null
        }
    }

    override fun onCleared() {
        releaseTopicDetailMessageBus()
        super.onCleared()
    }

    companion object {
        private const val TARGET_HYDRATION_PAGE_LIMIT = 20

        fun create(sessionStore: FireSessionStore): TopicDetailViewModel {
            val sessionRepo = SessionRepository(sessionStore)
            val topicRepo = TopicRepository(sessionStore)
            val messageBusCoordinator = FireMessageBusCoordinator(sessionStore)
            return TopicDetailViewModel(sessionRepo, topicRepo, sessionStore, messageBusCoordinator)
        }
    }
}

object TopicDetailPostRows {
    fun uniqueResponseRows(
        rows: List<TopicResponseRowState>,
        bodyPostId: ULong? = null,
    ): List<TopicResponseRowState> {
        val rowsByPostId = LinkedHashMap<ULong, TopicResponseRowState>(rows.size)
        for (row in rows) {
            if (row.post.id == bodyPostId) continue
            rowsByPostId[row.post.id] = row
        }
        return rowsByPostId.values.toList()
    }

    fun postsForDetail(
        bodyPost: TopicPostState,
        responseRows: List<TopicResponseRowState>,
    ): List<TopicPostState> {
        return uniquePosts(
            listOf(bodyPost) + responseRows
                .filter { it.post.id != bodyPost.id }
                .map { it.post },
        )
    }

    fun uniquePosts(posts: List<TopicPostState>): List<TopicPostState> {
        val postsById = LinkedHashMap<ULong, TopicPostState>(posts.size)
        for (post in posts) {
            postsById[post.id] = post
        }
        return postsById.values.toList()
    }
}
