package com.fire.app.ui.topicdetail

import android.util.LruCache
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.fire.app.TopicPresentation
import com.fire.app.core.error.FireErrorReporter
import com.fire.app.data.repository.TopicRepository
import com.fire.app.messagebus.FireMessageBusCoordinator
import com.fire.app.richtext.FireRichTextContent
import com.fire.app.richtext.FireRenderBlockBuilder
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
import uniffi.fire_uniffi_topics.TopicBodyState
import uniffi.fire_uniffi_topics.TopicDetailPageState
import uniffi.fire_uniffi_topics.TopicDetailState
import uniffi.fire_uniffi_topics.TopicDetailSourceSnapshotState
import uniffi.fire_uniffi_topics.TopicPostState
import uniffi.fire_uniffi_topics.TopicPostStreamState
import uniffi.fire_uniffi_topics.TopicSourceCursorState
import uniffi.fire_uniffi_topics.TopicTreePresentationState
import uniffi.fire_uniffi_topics.TopicTreeRowState
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

    private var sourceCursor: TopicSourceCursorState? = null
    private var sourceSnapshot: TopicDetailSourceSnapshotState? = null
    private var treePresentation: TopicTreePresentationState? = null
    private var messageBusJob: Job? = null
    private var pendingMessageBusRefreshJob: Job? = null
    private var isScrollInteractionActive = false
    private var deferredMessageBusRefreshTopicId: ULong? = null
    private var deferredMessageBusPayloadTopicId: ULong? = null
    private var deferredMessageBusPayload: TopicDetailPageState? = null
    private var topicAiSummaryJob: Job? = null
    private var topicAiSummaryTopicId: ULong? = null
    private var topicAiSummaryUnavailable: Boolean = false
    private var subscribedTopicId: ULong? = null
    private var subscribedOwnerToken: String? = null

    val hasMorePosts: Boolean get() = sourceCursor != null

    private val renderCache = LruCache<ULong, FireRichTextContent>(64)

    fun loadTopicDetail(topicId: ULong, targetPostNumber: UInt? = null) {
        if (_isLoading.value) return
        viewModelScope.launch {
            _isLoading.value = true
            _errorMessage.value = null
            try {
                val shouldUseSuggestedUnreadRootTarget = targetPostNumber == null && _detail.value == null
                val payload = fetchTopicDetailPagePayload(
                    topicId = topicId,
                    targetPostNumber = targetPostNumber,
                    forceLoad = true,
                    trackVisit = true,
                    allowSuggestedUnreadRoot = shouldUseSuggestedUnreadRootTarget,
                )
                val allPosts = applyFetchedPayload(payload)
                preloadRenderContent(allPosts)
                loadTopicAiSummaryIfNeeded(topicId, _detail.value)
                maintainTopicDetailMessageBus(topicId, payload.sourceSnapshot.header.messageBusLastId)
                val scrollTargetPostNumber = TopicDetailPostRows.initialScrollTargetPostNumber(
                    explicitTargetPostNumber = targetPostNumber,
                    suggestedUnreadRootPostNumber = payload.treePresentation.firstUnreadRootPostNumber,
                    shouldUseSuggestedUnreadRootTarget = shouldUseSuggestedUnreadRootTarget,
                )
                scrollTargetPostNumber?.let { scrollToPostWhenLoaded(it) }
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

    fun setTopicDetailScrollInteractionActive(active: Boolean) {
        val changed = isScrollInteractionActive != active
        isScrollInteractionActive = active
        if (changed && !active) {
            drainDeferredMessageBusRefreshIfNeeded()
        }
    }

    private suspend fun fetchTopicDetailPagePayload(
        topicId: ULong,
        targetPostNumber: UInt? = null,
        forceLoad: Boolean,
        trackVisit: Boolean,
        allowSuggestedUnreadRoot: Boolean = false,
    ): TopicDetailPageState {
        return topicRepository.fetchTopicDetailPage(
            topicId = topicId,
            targetPostNumber = targetPostNumber,
            forceLoad = forceLoad,
            trackVisit = trackVisit,
            allowSuggestedUnreadRoot = allowSuggestedUnreadRoot,
        )
    }

    private fun applyFetchedPayload(payload: TopicDetailPageState): List<TopicPostState> {
        val bodyPost = payload.sourceSnapshot.body.post
        val normalizedReplyRows = TopicDetailPostRows.uniqueTreeRows(
            rows = payload.treePresentation.replyRows,
            bodyPostId = bodyPost.id,
        )
        sourceSnapshot = payload.sourceSnapshot
        treePresentation = payload.treePresentation.copy(replyRows = normalizedReplyRows)
        sourceCursor = payload.sourceSnapshot.sourceCursor

        val header = payload.sourceSnapshot.header
        val allPosts = TopicDetailPostRows.postsForDetail(
            bodyPost = bodyPost,
            loadedPosts = payload.sourceSnapshot.loadedPosts,
            replyRows = normalizedReplyRows,
        )
        val postsById = TopicDetailPostRows.postsById(allPosts)
        val rows = normalizedReplyRows.mapNotNull { row -> postRow(row, postsById) }

        val nextDetail = TopicDetailState(
            id = header.topicId,
            messageBusLastId = header.messageBusLastId,
            title = header.title,
            slug = header.slug,
            postsCount = header.postsCount,
            replyCount = header.replyCount,
            categoryId = header.categoryId,
            tags = header.tags,
            views = header.views,
            likeCount = header.likeCount,
            createdAt = header.createdAt,
            highestPostNumber = header.highestPostNumber,
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
        if (_detail.value != nextDetail) {
            _detail.value = nextDetail
        }
        if (_postRows.value != rows) {
            _postRows.value = rows
        }
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
        if (isScrollInteractionActive) {
            deferredMessageBusRefreshTopicId = topicId
            return
        }
        try {
            val payload = fetchTopicDetailPagePayload(
                topicId = topicId,
                targetPostNumber = null,
                forceLoad = false,
                trackVisit = false,
            )
            if (isScrollInteractionActive) {
                deferredMessageBusRefreshTopicId = topicId
                deferredMessageBusPayloadTopicId = topicId
                deferredMessageBusPayload = payload
                return
            }
            deferredMessageBusRefreshTopicId = null
            deferredMessageBusPayloadTopicId = null
            deferredMessageBusPayload = null
            val allPosts = applyFetchedPayload(payload)
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

    private fun drainDeferredMessageBusRefreshIfNeeded() {
        val deferredPayload = deferredMessageBusPayload
        val deferredPayloadTopicId = deferredMessageBusPayloadTopicId
        if (deferredPayload != null && deferredPayloadTopicId != null) {
            deferredMessageBusPayload = null
            deferredMessageBusPayloadTopicId = null
            deferredMessageBusRefreshTopicId = null
            val allPosts = applyFetchedPayload(deferredPayload)
            preloadRenderContent(allPosts)
            loadTopicAiSummaryIfNeeded(deferredPayloadTopicId, _detail.value)
            return
        }

        val deferredTopicId = deferredMessageBusRefreshTopicId ?: return
        deferredMessageBusRefreshTopicId = null
        pendingMessageBusRefreshJob?.cancel()
        pendingMessageBusRefreshJob = viewModelScope.launch {
            refreshTopicDetailFromMessageBus(deferredTopicId)
        }
    }

    private fun releaseTopicDetailMessageBus() {
        pendingMessageBusRefreshJob?.cancel()
        pendingMessageBusRefreshJob = null
        deferredMessageBusRefreshTopicId = null
        deferredMessageBusPayloadTopicId = null
        deferredMessageBusPayload = null
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
        val topicId = sourceSnapshot?.header?.topicId ?: _detail.value?.id ?: return
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
        while (remainingPages > 0 && sourceCursor != null && !hasLoadedPostNumber(postNumber)) {
            remainingPages -= 1
            if (!loadMorePostsPage()) break
        }

        if (hasLoadedPostNumber(postNumber)) {
            _scrollTargetPostNumber.emit(postNumber)
        }
    }

    private fun hasLoadedPostNumber(postNumber: UInt): Boolean {
        if (sourceSnapshot?.body?.post?.postNumber == postNumber) return true
        return _postRows.value.any { row -> row.post.postNumber == postNumber }
    }

    private suspend fun loadMorePostsPage(): Boolean {
        val currentCursor = sourceCursor ?: return false
        if (_isLoadingMore.value) return false
        _isLoadingMore.value = true
        return try {
            val outcome = topicRepository.loadMoreTopicPosts(currentCursor)
            if (sourceCursor != currentCursor) return false

            val previousLoadedPostIds = sourceSnapshot
                ?.loadedPosts
                ?.mapTo(LinkedHashSet()) { it.id }
                ?: linkedSetOf()
            val allPosts = applyFetchedPayload(
                TopicDetailPageState(
                    sourceSnapshot = outcome.sourceSnapshot,
                    treePresentation = outcome.treePresentation,
                ),
            )
            preloadRenderContent(allPosts)
            outcome.sourceSnapshot.loadedPosts.any { !previousLoadedPostIds.contains(it.id) }
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

    private fun postRow(
        row: TopicTreeRowState,
        postsById: Map<ULong, TopicPostState>,
    ): PostRow? {
        val post = postsById[row.postId] ?: return null
        return PostRow(
            post = post,
            depth = row.depth.toInt(),
            parentPostNumber = row.parentPostNumber,
            hasChildren = row.hasChildren,
        )
    }

    private fun parsePostContent(post: TopicPostState): FireRichTextContent? {
        val document = post.renderDocument ?: return null
        return try {
            FireRenderBlockBuilder.build(document)
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
        val payload = fetchTopicDetailPagePayload(
            topicId = topicId,
            targetPostNumber = targetPostNumber,
            forceLoad = false,
            trackVisit = false,
        )
        val allPosts = applyFetchedPayload(payload)
        preloadRenderContent(allPosts)
    }

    private fun replacePost(
        postId: ULong,
        transform: (TopicPostState) -> TopicPostState,
    ) {
        sourceSnapshot = sourceSnapshot?.let { current ->
            val nextBodyPost = current.body.post.let { post ->
                if (post.id == postId) transform(post) else post
            }
            current.copy(
                body = TopicBodyState(post = nextBodyPost),
                loadedPosts = current.loadedPosts.map { post ->
                    if (post.id == postId) transform(post) else post
                },
            )
        }

        val updatedDetail = _detail.value?.let { current ->
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
        _detail.value = updatedDetail

        val postsById = updatedDetail
            ?.postStream
            ?.posts
            ?.let(TopicDetailPostRows::postsById)
            ?: emptyMap()
        _postRows.value = treePresentation
            ?.replyRows
            ?.mapNotNull { row -> postRow(row, postsById) }
            .orEmpty()
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
    fun uniqueTreeRows(
        rows: List<TopicTreeRowState>,
        bodyPostId: ULong? = null,
    ): List<TopicTreeRowState> {
        val rowsByPostId = LinkedHashMap<ULong, TopicTreeRowState>(rows.size)
        for (row in rows) {
            if (row.postId == bodyPostId) continue
            rowsByPostId[row.postId] = row
        }
        return rowsByPostId.values.toList()
    }

    fun initialScrollTargetPostNumber(
        explicitTargetPostNumber: UInt?,
        suggestedUnreadRootPostNumber: UInt?,
        shouldUseSuggestedUnreadRootTarget: Boolean,
    ): UInt? {
        explicitTargetPostNumber?.takeIf { it > 0u }?.let { return it }
        if (!shouldUseSuggestedUnreadRootTarget) return null
        return suggestedUnreadRootPostNumber?.takeIf { it > 1u }
    }

    fun usesBoostBarrage(row: PostRow): Boolean {
        return row.depth == 0 && row.post.boosts.isNotEmpty()
    }

    fun postsForDetail(
        bodyPost: TopicPostState,
        loadedPosts: List<TopicPostState>,
        replyRows: List<TopicTreeRowState>,
    ): List<TopicPostState> {
        val postsById = postsById(listOf(bodyPost) + loadedPosts)
        return uniquePosts(
            listOf(bodyPost) + replyRows.mapNotNull { row ->
                if (row.postId == bodyPost.id) null else postsById[row.postId]
            },
        )
    }

    fun postsById(posts: List<TopicPostState>): Map<ULong, TopicPostState> {
        return posts.associateBy { it.id }
    }

    fun uniquePosts(posts: List<TopicPostState>): List<TopicPostState> {
        val postsById = LinkedHashMap<ULong, TopicPostState>(posts.size)
        for (post in posts) {
            postsById[post.id] = post
        }
        return postsById.values.toList()
    }
}

object TopicDetailBoostPresentation {
    const val BODY_BARRAGE_VISIBLE_LINE_LIMIT = 5
    const val BODY_BARRAGE_MAX_LANES = 5
}
