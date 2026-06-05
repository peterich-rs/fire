package com.fire.app.ui.topicdetail

import android.util.LruCache
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.fire.app.TopicPresentation
import com.fire.app.core.error.FireErrorReporter
import com.fire.app.data.repository.TopicRepository
import com.fire.app.messagebus.FireMessageBusCoordinator
import com.fire.app.richtext.FireRichTextContent
import com.fire.app.richtext.FireRichTextParser
import com.fire.app.richtext.FireSpannableBuilder
import com.fire.app.session.FireSessionStore
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asSharedFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import uniffi.fire_uniffi_topics.PollState
import uniffi.fire_uniffi_topics.PostUpdateRequestState
import uniffi.fire_uniffi_topics.PostReactionUpdateState
import uniffi.fire_uniffi_topics.TopicAiSummaryState
import uniffi.fire_uniffi_topics.TopicDetailState
import uniffi.fire_uniffi_topics.TopicPostState
import uniffi.fire_uniffi_topics.TopicPostStreamState
import uniffi.fire_uniffi_topics.TopicResponseCursorState
import uniffi.fire_uniffi_topics.TopicResponsePageState
import uniffi.fire_uniffi_topics.TopicResponseRowState
import uniffi.fire_uniffi_topics.TopicScreenState
import uniffi.fire_uniffi_topics.TopicUpdateRequestState

class TopicDetailViewModel(
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

    private val _topicAiSummary = MutableStateFlow<TopicAiSummaryState?>(null)
    val topicAiSummary = _topicAiSummary.asStateFlow()

    private val _isLoadingTopicAiSummary = MutableStateFlow(false)
    val isLoadingTopicAiSummary = _isLoadingTopicAiSummary.asStateFlow()

    private val _topicAiSummaryError = MutableStateFlow<String?>(null)
    val topicAiSummaryError = _topicAiSummaryError.asStateFlow()

    private val _scrollTargetPostNumber = MutableSharedFlow<UInt>(extraBufferCapacity = 1)
    val scrollTargetPostNumber = _scrollTargetPostNumber.asSharedFlow()

    private val _actionError = MutableSharedFlow<String>(extraBufferCapacity = 1)
    val actionError = _actionError.asSharedFlow()

    private var cursor: TopicResponseCursorState? = null
    private var screen: TopicScreenState? = null
    private var responseRows: MutableList<TopicResponseRowState> = mutableListOf()
    private var messageBusJob: Job? = null
    private var pendingMessageBusRefreshJob: Job? = null
    private var topicAiSummaryJob: Job? = null
    private var topicAiSummaryTopicId: ULong? = null
    private var topicAiSummaryUnavailable: Boolean = false
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
                loadTopicAiSummaryIfNeeded(topicId, _detail.value)
                maintainTopicDetailMessageBus(topicId, fetched.header.messageBusLastId)
                targetPostNumber
                    ?.takeIf { it > 0u }
                    ?.let { scrollToPostWhenLoaded(it) }
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                val reported = FireErrorReporter.report(
                    operation = "topic_detail.load",
                    error = e,
                    sessionStore = sessionStore,
                    fallbackMessage = "加载话题详情失败",
                )
                _errorMessage.value = reported.displayMessage
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
            FireErrorReporter.report(
                operation = "topic_detail.messagebus.subscribe",
                error = it,
                sessionStore = sessionStore,
            )
            releaseTopicDetailMessageBus()
            return
        }

        viewModelScope.launch {
            runCatching { sessionStore.bootstrapTopicReplyPresence(topicId, ownerToken) }
                .onFailure {
                    FireErrorReporter.report(
                        operation = "topic_detail.presence.bootstrap",
                        error = it,
                        sessionStore = sessionStore,
                    )
                }
        }

        messageBusJob = viewModelScope.launch {
            try {
                messageBusCoordinator.topicDetailEvents(topicId).collect {
                    scheduleTopicDetailRefresh(topicId)
                }
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                messageBusJob = null
                val reported = FireErrorReporter.report(
                    operation = "topic_detail.messagebus.collect",
                    error = e,
                    sessionStore = sessionStore,
                )
                _errorMessage.value = reported.displayMessage
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
            loadTopicAiSummaryIfNeeded(topicId, _detail.value)
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            val reported = FireErrorReporter.report(
                operation = "topic_detail.messagebus.refresh",
                error = e,
                sessionStore = sessionStore,
            )
            _errorMessage.value = reported.displayMessage
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

    fun reloadTopicAiSummary() {
        val topicId = screen?.header?.topicId ?: _detail.value?.id ?: return
        loadTopicAiSummaryIfNeeded(topicId, _detail.value, force = true)
    }

    fun toggleTopicVote() {
        val detail = _detail.value ?: return
        if (!detail.canVote && !detail.userVoted) return
        viewModelScope.launch {
            try {
                val response = if (detail.userVoted) {
                    sessionStore.unvoteTopic(detail.id)
                } else {
                    sessionStore.voteTopic(detail.id)
                }
                _detail.value = detail.copy(
                    canVote = response.canVote,
                    voteCount = response.voteCount,
                    userVoted = !detail.userVoted,
                )
            } catch (e: Exception) {
                handleActionError(e, "投票状态更新失败")
            }
        }
    }

    fun setTopicNotificationLevel(notificationLevel: Int) {
        val detail = _detail.value ?: return
        viewModelScope.launch {
            try {
                sessionStore.setTopicNotificationLevel(detail.id, notificationLevel)
                refreshCurrentTopic()
            } catch (e: Exception) {
                handleActionError(e, "话题通知更新失败")
            }
        }
    }

    fun updateTopic(title: String, categoryId: ULong, tags: List<String>) {
        val detail = _detail.value ?: return
        val trimmedTitle = title.trim()
        if (trimmedTitle.isEmpty()) return
        viewModelScope.launch {
            try {
                sessionStore.updateTopic(
                    TopicUpdateRequestState(
                        topicId = detail.id,
                        title = trimmedTitle,
                        categoryId = categoryId,
                        tags = tags.map { it.trim() }.filter { it.isNotEmpty() },
                    ),
                )
                refreshCurrentTopic()
            } catch (e: Exception) {
                handleActionError(e, "话题编辑失败")
            }
        }
    }

    fun votePoll(post: TopicPostState, poll: PollState, options: List<String>) {
        if (options.isEmpty()) return
        viewModelScope.launch {
            try {
                val updated = sessionStore.votePoll(post.id, poll.name, options)
                applyPollUpdate(post.id, updated)
            } catch (e: Exception) {
                handleActionError(e, "投票更新失败")
            }
        }
    }

    fun unvotePoll(post: TopicPostState, poll: PollState) {
        viewModelScope.launch {
            try {
                val updated = sessionStore.unvotePoll(post.id, poll.name)
                applyPollUpdate(post.id, updated)
            } catch (e: Exception) {
                handleActionError(e, "投票更新失败")
            }
        }
    }

    private fun loadTopicAiSummaryIfNeeded(
        topicId: ULong,
        detail: TopicDetailState?,
        force: Boolean = false,
    ) {
        if (topicAiSummaryTopicId != topicId) {
            _topicAiSummary.value = null
            _topicAiSummaryError.value = null
            topicAiSummaryUnavailable = false
        }
        if (detail == null || !(detail.summarizable || detail.hasCachedSummary || detail.hasSummary)) {
            return
        }
        if (!force &&
            topicAiSummaryTopicId == topicId &&
            (_topicAiSummary.value != null || _isLoadingTopicAiSummary.value || topicAiSummaryUnavailable)
        ) {
            return
        }

        topicAiSummaryJob?.cancel()
        topicAiSummaryTopicId = topicId
        topicAiSummaryUnavailable = false
        _topicAiSummaryError.value = null
        _isLoadingTopicAiSummary.value = true

        topicAiSummaryJob = viewModelScope.launch {
            try {
                val summary = topicRepository.fetchTopicAiSummary(topicId, skipAgeCheck = false)
                if (summary != null && summary.summarizedText.trim().isNotEmpty()) {
                    _topicAiSummary.value = summary
                    topicAiSummaryUnavailable = false
                } else {
                    _topicAiSummary.value = null
                    topicAiSummaryUnavailable = true
                }
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                val reported = FireErrorReporter.report(
                    operation = "topic_detail.ai_summary",
                    error = e,
                    sessionStore = sessionStore,
                    fallbackMessage = "AI 摘要加载失败",
                )
                _topicAiSummaryError.value = reported.displayMessage
            } finally {
                _isLoadingTopicAiSummary.value = false
            }
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

    fun toggleHeart(post: TopicPostState) {
        viewModelScope.launch {
            try {
                val update = if (post.currentUserReaction?.id == HEART_REACTION_ID) {
                    sessionStore.unlikePost(post.id)
                } else {
                    sessionStore.likePost(post.id)
                }
                if (update != null) {
                    applyReactionUpdate(post.id, update)
                } else {
                    refreshCurrentTopic(post.postNumber)
                }
            } catch (e: Exception) {
                handleActionError(e, "点赞状态更新失败")
            }
        }
    }

    fun toggleReaction(post: TopicPostState, reactionId: String) {
        val trimmedReactionId = reactionId.trim()
        if (trimmedReactionId.isEmpty()) return
        val currentReaction = post.currentUserReaction
        if (currentReaction?.canUndo == false) {
            _actionError.tryEmit("当前表情回应暂时不能修改")
            return
        }
        if (trimmedReactionId.equals(HEART_REACTION_ID, ignoreCase = true)) {
            toggleHeart(post)
            return
        }

        viewModelScope.launch {
            try {
                val update = sessionStore.togglePostReaction(post.id, trimmedReactionId)
                applyReactionUpdate(post.id, update)
            } catch (e: Exception) {
                handleActionError(e, "表情回应更新失败")
            }
        }
    }

    fun toggleBookmark(post: TopicPostState) {
        viewModelScope.launch {
            try {
                if (post.bookmarked) {
                    val bookmarkId = post.bookmarkId
                    if (bookmarkId != null) {
                        sessionStore.deleteBookmark(bookmarkId)
                    }
                } else {
                    sessionStore.createBookmark(post.id, "Post")
                }
                refreshCurrentTopic(post.postNumber)
            } catch (e: Exception) {
                handleActionError(e, "书签更新失败")
            }
        }
    }

    fun saveBookmark(
        bookmarkableId: ULong,
        bookmarkableType: String,
        bookmarkId: ULong?,
        name: String?,
        reminderAt: String?,
        targetPostNumber: UInt?,
    ) {
        viewModelScope.launch {
            try {
                val normalizedName = name?.trim()?.takeIf { it.isNotEmpty() }
                val normalizedReminder = reminderAt?.trim()?.takeIf { it.isNotEmpty() }
                if (bookmarkId != null) {
                    sessionStore.updateBookmark(
                        bookmarkId = bookmarkId,
                        name = normalizedName,
                        reminderAt = normalizedReminder,
                    )
                } else {
                    sessionStore.createBookmark(
                        bookmarkableId = bookmarkableId,
                        bookmarkableType = bookmarkableType,
                        name = normalizedName,
                        reminderAt = normalizedReminder,
                    )
                }
                refreshCurrentTopic(targetPostNumber)
            } catch (e: Exception) {
                handleActionError(e, "书签更新失败")
            }
        }
    }

    fun deleteBookmark(bookmarkId: ULong, targetPostNumber: UInt?) {
        viewModelScope.launch {
            try {
                sessionStore.deleteBookmark(bookmarkId)
                refreshCurrentTopic(targetPostNumber)
            } catch (e: Exception) {
                handleActionError(e, "书签删除失败")
            }
        }
    }

    fun deletePost(post: TopicPostState) {
        viewModelScope.launch {
            try {
                sessionStore.deletePost(post.id)
                refreshCurrentTopic(post.postNumber)
            } catch (e: Exception) {
                handleActionError(e, "帖子删除失败")
            }
        }
    }

    fun recoverPost(post: TopicPostState) {
        viewModelScope.launch {
            try {
                sessionStore.recoverPost(post.id)
                refreshCurrentTopic(post.postNumber)
            } catch (e: Exception) {
                handleActionError(e, "帖子恢复失败")
            }
        }
    }

    fun updatePost(post: TopicPostState, raw: String, editReason: String?) {
        val trimmedRaw = raw.trim()
        if (trimmedRaw.isEmpty()) return
        viewModelScope.launch {
            try {
                val updated = sessionStore.updatePost(
                    PostUpdateRequestState(
                        postId = post.id,
                        raw = trimmedRaw,
                        editReason = editReason?.trim()?.takeIf { it.isNotEmpty() },
                    ),
                )
                renderCache.remove(post.id)
                replacePost(post.id) { updated }
            } catch (e: Exception) {
                handleActionError(e, "帖子编辑失败")
            }
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
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            val reported = FireErrorReporter.report(
                operation = "topic_detail.load_more",
                error = e,
                sessionStore = sessionStore,
                fallbackMessage = "加载更多帖子失败",
            )
            _errorMessage.value = reported.displayMessage
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
        if (post.cooked.isBlank() && post.renderDocument == null) return null
        return try {
            FireRichTextParser.parse(post, "https://linux.do")
        } catch (_: Exception) {
            null
        }
    }

    private fun applyReactionUpdate(postId: ULong, update: PostReactionUpdateState) {
        replacePost(postId) { post ->
            val nextLikeCount = update.reactions
                .firstOrNull { it.id == HEART_REACTION_ID }
                ?.count
                ?: 0u
            post.copy(
                likeCount = nextLikeCount,
                reactions = update.reactions,
                currentUserReaction = update.currentUserReaction,
            )
        }
    }

    private fun applyPollUpdate(postId: ULong, updatedPoll: PollState) {
        replacePost(postId) { post ->
            post.copy(
                polls = post.polls.map { poll ->
                    if (poll.name == updatedPoll.name) updatedPoll else poll
                },
            )
        }
    }

    private suspend fun refreshCurrentTopic(targetPostNumber: UInt? = null) {
        val topicId = _detail.value?.id ?: return
        val fetched = topicRepository.fetchTopicScreen(
            topicId = topicId,
            targetPostNumber = targetPostNumber,
            forceLoad = false,
            trackVisit = false,
        )
        val allPosts = applyFetchedScreen(fetched)
        preloadRenderContent(allPosts)
    }

    private fun replacePost(
        postId: ULong,
        transform: (TopicPostState) -> TopicPostState,
    ) {
        val previousScreen = screen
        val nextBodyPost = previousScreen?.body?.post?.let { post ->
            if (post.id == postId) transform(post) else post
        }

        responseRows = responseRows.map { row ->
            if (row.post.id == postId) {
                row.copy(post = transform(row.post))
            } else {
                row
            }
        }.toMutableList()

        previousScreen?.let { current ->
            screen = current.copy(
                body = nextBodyPost?.let { current.body.copy(post = it) } ?: current.body,
                response = current.response.copy(rows = responseRows),
            )
        }

        _postRows.value = responseRows.map(::postRow)
        _detail.value = _detail.value?.let { current ->
            val updatedPosts = current.postStream.posts.map { post ->
                if (post.id == postId) transform(post) else post
            }
            current.copy(
                postStream = current.postStream.copy(
                    posts = updatedPosts,
                    stream = updatedPosts.map { it.id },
                ),
            )
        }
    }

    private fun handleActionError(error: Exception, fallbackMessage: String) {
        val reported = FireErrorReporter.report(
            operation = "topic_detail.action",
            error = error,
            sessionStore = sessionStore,
            fallbackMessage = fallbackMessage,
        )
        _actionError.tryEmit(reported.displayMessage)
    }

    override fun onCleared() {
        topicAiSummaryJob?.cancel()
        releaseTopicDetailMessageBus()
        super.onCleared()
    }

    companion object {
        private const val TARGET_HYDRATION_PAGE_LIMIT = 20
        private const val HEART_REACTION_ID = "heart"

        fun create(sessionStore: FireSessionStore): TopicDetailViewModel {
            val topicRepo = TopicRepository(sessionStore)
            val messageBusCoordinator = FireMessageBusCoordinator(sessionStore)
            return TopicDetailViewModel(topicRepo, sessionStore, messageBusCoordinator)
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
