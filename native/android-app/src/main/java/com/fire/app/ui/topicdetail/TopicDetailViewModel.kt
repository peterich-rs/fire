package com.fire.app.ui.topicdetail

import android.util.LruCache
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.fire.app.TopicPresentation
import com.fire.app.data.repository.SessionRepository
import com.fire.app.data.repository.TopicRepository
import com.fire.app.richtext.FireRichTextContent
import com.fire.app.richtext.FireRichTextParser
import com.fire.app.richtext.FireSpannableBuilder
import com.fire.app.session.FireSessionStore
import com.fire.app.cloudflare.CloudflareChallengeDetector
import kotlinx.coroutines.Dispatchers
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

    val hasMorePosts: Boolean get() = cursor != null

    private val renderCache = LruCache<ULong, FireRichTextContent>(64)

    fun loadTopicDetail(topicId: ULong, targetPostNumber: UInt? = null) {
        if (_isLoading.value) return
        viewModelScope.launch {
            _isLoading.value = true
            _errorMessage.value = null
            try {
                val fetched = topicRepository.fetchTopicScreen(topicId, targetPostNumber)
                screen = fetched
                responseRows = fetched.response.rows.toMutableList()
                cursor = fetched.response.nextCursor

                val header = fetched.header
                val bodyPost = fetched.body.post
                val allPosts = listOf(bodyPost) + fetched.response.rows.map { it.post }

                val rows = fetched.response.rows.map(::postRow)

                val detailState = TopicDetailState(
                    id = header.topicId,
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

                _detail.value = detailState
                _postRows.value = rows
                preloadRenderContent(allPosts)
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

            responseRows.addAll(page.rows)
            cursor = page.nextCursor

            val newRows = page.rows.map(::postRow)
            _postRows.value = _postRows.value + newRows

            _detail.value?.let { current ->
                val allPosts = buildList {
                    screen?.body?.post?.let { add(it) }
                    addAll(_postRows.value.map { it.post })
                }
                _detail.value = current.copy(
                    postStream = current.postStream.copy(
                        posts = allPosts,
                        stream = allPosts.map { it.id },
                    ),
                )
            }
            preloadRenderContent(page.rows.map { it.post })
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

    companion object {
        private const val TARGET_HYDRATION_PAGE_LIMIT = 20

        fun create(sessionStore: FireSessionStore): TopicDetailViewModel {
            val sessionRepo = SessionRepository(sessionStore)
            val topicRepo = TopicRepository(sessionStore)
            return TopicDetailViewModel(sessionRepo, topicRepo, sessionStore)
        }
    }
}
