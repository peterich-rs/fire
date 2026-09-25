package com.fire.app.ui.topicdetail

import android.util.LruCache
import androidx.lifecycle.ViewModel
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.viewModelScope
import com.fire.app.core.error.FireErrorReporter
import com.fire.app.richtext.FireRichTextContent
import com.fire.app.richtext.FireRenderPresentation
import com.fire.app.session.FireSessionStore
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asSharedFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import uniffi.fire_uniffi_topics.PollState
import uniffi.fire_uniffi_topics.TopicAiSummaryState
import uniffi.fire_uniffi_topics.TopicDetailState
import uniffi.fire_uniffi_topics.TopicPostState
import uniffi.fire_uniffi_topics.TopicPostStreamState
import uniffi.fire_uniffi_topics.TopicTreeRowState

class TopicDetailViewModel(
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

    private val _isCloudflareError = MutableStateFlow(false)
    val isCloudflareError = _isCloudflareError.asStateFlow()

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

    private val _bookmarkEvents = MutableSharedFlow<BookmarkEvent>(extraBufferCapacity = 1)
    val bookmarkEvents = _bookmarkEvents.asSharedFlow()

    private var openedTopicId: ULong? = null
    private var snapshotReplyRows: List<TopicTreeRowState> = emptyList()
    private val expandedReplyRootPostIds = mutableSetOf<ULong>()
    private var sessionHandle: uniffi.fire_uniffi_topics.TopicDetailSessionHandle? = null
    private val sessionObserver = object : uniffi.fire_uniffi_topics.TopicDetailObserver {
        override fun onSnapshot(snapshot: uniffi.fire_uniffi_topics.TopicDetailUiSnapshotState) {
            viewModelScope.launch(Dispatchers.Main) {
                applyUiSnapshot(snapshot)
            }
        }
    }

    private var snapshotHasMore = false
    val hasMorePosts: Boolean get() = snapshotHasMore

    private val renderCache = LruCache<Pair<ULong, ULong>, FireRichTextContent>(64)

    fun loadTopicDetail(topicId: ULong, targetPostNumber: UInt? = null) {
        if (_isLoading.value) return
        viewModelScope.launch {
            _isLoading.value = true
            _errorMessage.value = null
            _isCloudflareError.value = false
            prepareForTopicLoad(topicId)
            try {
                val shouldUseSuggestedUnreadRootTarget = targetPostNumber == null && _detail.value == null
                val owner = "android.topic-detail.$topicId"
                sessionHandle = sessionStore.openTopicDetail(
                    uniffi.fire_uniffi_topics.TopicDetailOpenRequestState(
                        topicId = topicId,
                        ownerToken = owner,
                        slugHint = null,
                        targetPostNumber = targetPostNumber,
                        bypassCache = true,
                        forceLoad = true,
                        trackVisit = true,
                        allowSuggestedUnreadRoot = shouldUseSuggestedUnreadRootTarget,
                    ),
                    sessionObserver,
                )
                openedTopicId = topicId
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                val reported = FireErrorReporter.report(
                    operation = "topic_detail.load",
                    error = e,
                    sessionStore = sessionStore,
                    fallbackMessage = "加载话题详情失败",
                )
                if (_detail.value == null && _postRows.value.isEmpty()) {
                    _errorMessage.value = reported.displayMessage
                    _isCloudflareError.value = reported.isCloudflareChallenge
                } else {
                    _actionError.tryEmit(reported.displayMessage)
                }
            } finally {
                _isLoading.value = false
            }
        }
    }

    private fun prepareForTopicLoad(topicId: ULong) {
        val previousTopicId = openedTopicId ?: _detail.value?.id
        if (previousTopicId != null && previousTopicId != topicId) {
            sessionHandle?.release()
            sessionHandle = null
            openedTopicId = null
            snapshotReplyRows = emptyList()
            expandedReplyRootPostIds.clear()
            renderCache.evictAll()
            _detail.value = null
            _postRows.value = emptyList()
            _topicAiSummary.value = null
            _topicAiSummaryError.value = null
            _isLoadingTopicAiSummary.value = false
        }
    }

    fun setTopicDetailScrollInteractionActive(active: Boolean) {
        sessionHandle?.noteScrollInteraction(active)
    }

    fun loadMorePosts() {
        if (_isLoadingMore.value) return
        sessionHandle?.loadMore()
    }

    fun reloadTopicAiSummary() {
        sessionHandle?.reloadAiSummary(skipAgeCheck = true)
    }

    fun expandReplyThread(post: TopicPostState) {
        if (!expandedReplyRootPostIds.add(post.id)) return
        val postsById = _detail.value
            ?.postStream
            ?.posts
            ?.let(TopicDetailPostRows::postsById)
            ?: return
        val rows = TopicDetailPostRows.projectRows(
            rows = snapshotReplyRows,
            postsById = postsById,
            expandedReplyRootPostIds = expandedReplyRootPostIds,
        )
        if (_postRows.value != rows) {
            _postRows.value = rows
        }
    }

    fun toggleTopicVote() {
        val detail = _detail.value ?: return
        if (!detail.canVote && !detail.userVoted) return
        viewModelScope.launch {
            try {
                sessionHandle?.voteTopic(voted = !detail.userVoted)
            } catch (e: Exception) {
                handleActionError(e, "投票状态更新失败")
            }
        }
    }

    fun setTopicNotificationLevel(notificationLevel: Int) {
        if (_detail.value == null) return
        viewModelScope.launch {
            try {
                sessionHandle?.setNotificationLevel(notificationLevel)
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
                sessionHandle?.updateTopic(
                    title = trimmedTitle,
                    categoryId = categoryId,
                    tags = tags.map { it.trim() }.filter { it.isNotEmpty() },
                )
            } catch (e: Exception) {
                handleActionError(e, "话题编辑失败")
            }
        }
    }

    fun votePoll(post: TopicPostState, poll: PollState, options: List<String>) {
        if (options.isEmpty()) return
        viewModelScope.launch {
            try {
                sessionHandle?.votePoll(post.id, poll.name, options)
            } catch (e: Exception) {
                handleActionError(e, "投票更新失败")
            }
        }
    }

    fun unvotePoll(post: TopicPostState, poll: PollState) {
        viewModelScope.launch {
            try {
                sessionHandle?.unvotePoll(post.id, poll.name)
            } catch (e: Exception) {
                handleActionError(e, "投票更新失败")
            }
        }
    }

    fun getRenderContent(post: TopicPostState): FireRichTextContent? {
        val cacheKey = renderCacheKey(post)
        val cached = renderCache.get(cacheKey)
        if (cached != null) return cached

        val content = parsePostContent(post)
        if (content != null) {
            renderCache.put(cacheKey, content)
        }
        return content
    }

    fun toggleHeart(post: TopicPostState) {
        viewModelScope.launch {
            try {
                val liked = post.currentUserReaction?.id != HEART_REACTION_ID
                sessionHandle?.setLiked(post.id, liked)
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
                sessionHandle?.toggleReaction(post.id, trimmedReactionId)
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
                        sessionHandle?.deleteBookmark(bookmarkId)
                        _bookmarkEvents.tryEmit(
                            BookmarkEvent.Deleted(
                                bookmarkableId = post.id,
                                bookmarkableType = "Post",
                            ),
                        )
                    }
                } else {
                    sessionHandle?.createBookmark(
                        bookmarkableId = post.id,
                        bookmarkableType = "Post",
                        name = null,
                        reminderAt = null,
                        autoDeletePreference = null,
                    )
                }
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
                    sessionHandle?.updateBookmark(
                        bookmarkId = bookmarkId,
                        name = normalizedName,
                        reminderAt = normalizedReminder,
                        autoDeletePreference = null,
                    )
                } else {
                    sessionHandle?.createBookmark(
                        bookmarkableId = bookmarkableId,
                        bookmarkableType = bookmarkableType,
                        name = normalizedName,
                        reminderAt = normalizedReminder,
                        autoDeletePreference = null,
                    )
                }
                _bookmarkEvents.tryEmit(
                    BookmarkEvent.Saved(
                        bookmarkableId = bookmarkableId,
                        bookmarkableType = bookmarkableType,
                        reminderAt = normalizedReminder,
                    ),
                )
            } catch (e: Exception) {
                handleActionError(e, "书签更新失败")
            }
        }
    }

    fun deleteBookmark(
        bookmarkId: ULong,
        bookmarkableId: ULong,
        bookmarkableType: String,
        targetPostNumber: UInt?,
    ) {
        viewModelScope.launch {
            try {
                sessionHandle?.deleteBookmark(bookmarkId)
                _bookmarkEvents.tryEmit(
                    BookmarkEvent.Deleted(
                        bookmarkableId = bookmarkableId,
                        bookmarkableType = bookmarkableType,
                    ),
                )
            } catch (e: Exception) {
                handleActionError(e, "书签删除失败")
            }
        }
    }

    fun deletePost(post: TopicPostState) {
        viewModelScope.launch {
            try {
                sessionHandle?.deletePost(post.id)
            } catch (e: Exception) {
                handleActionError(e, "帖子删除失败")
            }
        }
    }

    fun recoverPost(post: TopicPostState) {
        viewModelScope.launch {
            try {
                sessionHandle?.recoverPost(post.id)
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
                sessionHandle?.updatePost(
                    postId = post.id,
                    raw = trimmedRaw,
                    editReason = editReason?.trim()?.takeIf { it.isNotEmpty() },
                )
                renderCache.remove(renderCacheKey(post))
            } catch (e: Exception) {
                handleActionError(e, "帖子编辑失败")
            }
        }
    }

    private fun preloadRenderContent(posts: List<TopicPostState>) {
        viewModelScope.launch(Dispatchers.Default) {
            for (post in posts) {
                if (renderCache.get(renderCacheKey(post)) == null) {
                    val content = parsePostContent(post)
                    if (content != null) {
                        renderCache.put(renderCacheKey(post), content)
                    }
                }
            }
        }
    }

    private fun renderCacheKey(post: TopicPostState): Pair<ULong, ULong> {
        return post.id to (post.presentation?.checksum() ?: 0uL)
    }

    private fun parsePostContent(post: TopicPostState): FireRichTextContent? {
        val presentation = post.presentation ?: return null
        return try {
            FireRenderPresentation.content(presentation)
        } catch (_: Exception) {
            null
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

    private fun rowToPost(row: uniffi.fire_uniffi_topics.TopicDetailUiRowState): TopicPostState {
        val author = row.author
        return TopicPostState(
            id = row.postId,
            username = author.username,
            name = author.name,
            avatarTemplate = author.avatarTemplate,
            authorMetadata = uniffi.fire_uniffi_topics.TopicPostAuthorMetadataState(
                userId = author.userId,
                userTitle = author.userTitle,
                primaryGroupName = author.primaryGroupName,
                flairUrl = author.flairUrl,
                flairName = author.flairName,
                flairBgColor = author.flairBgColor,
                flairColor = author.flairColor,
                flairGroupId = author.flairGroupId,
                moderator = author.moderator,
                admin = author.admin,
                groupModerator = author.groupModerator,
                userStatusEmoji = author.userStatusEmoji,
                userStatusDescription = author.userStatusDescription,
            ),
            presentation = row.presentation,
            raw = null,
            postNumber = row.postNumber,
            postType = row.postType,
            createdAt = row.createdAt,
            updatedAt = row.updatedAt,
            likeCount = row.likeCount,
            replyCount = row.replyCount,
            replyToPostNumber = row.parentPostNumber,
            replyToUser = row.replyToUser?.let {
                uniffi.fire_uniffi_topics.TopicReplyToUserState(it.username, it.name, it.avatarTemplate)
            },
            bookmarked = row.bookmarked,
            bookmarkId = row.bookmarkId,
            bookmarkName = row.bookmarkName,
            bookmarkReminderAt = row.bookmarkReminderAt,
            reactions = row.reactions.map {
                uniffi.fire_uniffi_topics.TopicReactionState(it.id, it.kind, it.count, it.canUndo)
            },
            currentUserReaction = row.currentReactionId?.let { id ->
                row.reactions.firstOrNull { it.id == id }?.let {
                    uniffi.fire_uniffi_topics.TopicReactionState(it.id, it.kind, it.count, it.canUndo)
                }
            },
            boosts = row.boosts.map { boost ->
                uniffi.fire_uniffi_topics.TopicPostBoostState(
                    id = boost.id,
                    presentation = boost.presentation,
                    displayText = boost.displayText,
                    user = uniffi.fire_uniffi_topics.TopicPostBoostUserState(
                        boost.user.id,
                        boost.user.username,
                        boost.user.name,
                        boost.user.avatarTemplate,
                    ),
                    canDelete = boost.canDelete,
                    canFlag = boost.canFlag,
                    userFlagStatus = boost.userFlagStatus,
                    availableFlags = boost.availableFlags,
                )
            },
            canBoost = row.canBoost,
            polls = row.polls,
            acceptedAnswer = row.acceptedAnswer,
            canAcceptAnswer = row.canAcceptAnswer,
            canUnacceptAnswer = row.canUnacceptAnswer,
            canEdit = row.canEdit,
            canDelete = row.canDelete,
            canRecover = row.canRecover,
            hidden = row.hidden,
        )
    }

    private fun rowToTreeRow(row: uniffi.fire_uniffi_topics.TopicDetailUiRowState): TopicTreeRowState {
        return TopicTreeRowState(
            postId = row.postId,
            postNumber = row.postNumber,
            rootPostNumber = row.rootPostNumber,
            parentPostNumber = row.parentPostNumber,
            depth = row.depth,
            preorderIndex = 0u,
            hasChildren = row.hasChildren,
            descendantCount = row.descendantCount,
            siblingIndex = 0.toUShort(),
            isLastSibling = row.isLastSibling,
        )
    }

    private fun detailFromSnapshot(
        snapshot: uniffi.fire_uniffi_topics.TopicDetailUiSnapshotState,
        posts: List<TopicPostState>,
    ): TopicDetailState {
        val chrome = snapshot.chrome
        return TopicDetailState(
            id = snapshot.topicId,
            messageBusLastId = null,
            title = chrome.title,
            slug = chrome.slug,
            postsCount = chrome.postsCount,
            replyCount = chrome.replyCount,
            categoryId = chrome.categoryId,
            tags = chrome.tags.map { uniffi.fire_uniffi_types.TopicTagState(id = null, name = it, slug = null) },
            views = chrome.views,
            likeCount = chrome.likeCount,
            createdAt = chrome.createdAt,
            highestPostNumber = chrome.highestPostNumber,
            lastReadPostNumber = chrome.lastReadPostNumber,
            bookmarks = emptyList(),
            bookmarked = chrome.bookmarked,
            bookmarkId = chrome.bookmarkId,
            bookmarkName = chrome.bookmarkName,
            bookmarkReminderAt = chrome.bookmarkReminderAt,
            acceptedAnswer = false,
            hasAcceptedAnswer = chrome.hasAcceptedAnswer,
            canVote = chrome.canVote,
            voteCount = chrome.voteCount,
            userVoted = chrome.userVoted,
            summarizable = chrome.summarizable,
            hasCachedSummary = snapshot.sidecar.summarizedText != null,
            hasSummary = snapshot.sidecar.summarizedText != null,
            archetype = chrome.archetype,
            postStream = TopicPostStreamState(posts = posts, stream = posts.map { it.id }),
            details = uniffi.fire_uniffi_topics.TopicDetailMetaState(
                notificationLevel = chrome.notificationLevel,
                canEdit = chrome.canEdit,
                createdBy = null,
                participants = chrome.participants.map {
                    uniffi.fire_uniffi_types.TopicParticipantState(
                        userId = it.userId,
                        username = it.username,
                        name = it.name,
                        avatarTemplate = null,
                    )
                },
            ),
        )
    }

    private fun applyUiSnapshot(snapshot: uniffi.fire_uniffi_topics.TopicDetailUiSnapshotState) {
        _isLoading.value = snapshot.phase == uniffi.fire_uniffi_topics.TopicDetailPhaseState.LOADING
        _isLoadingMore.value = snapshot.isLoadingMore
        _errorMessage.value = when (val error = snapshot.loadError) {
            is uniffi.fire_uniffi_topics.TopicDetailLoadErrorState.Unrecoverable -> error.message
            uniffi.fire_uniffi_topics.TopicDetailLoadErrorState.Network -> "网络错误"
            uniffi.fire_uniffi_topics.TopicDetailLoadErrorState.LoginRequired -> "需要登录"
            null -> null
        }
        snapshotHasMore = snapshot.hasMore
        snapshot.scrollTargetPostNumber?.let { _scrollTargetPostNumber.tryEmit(it) }
        snapshot.homeRowPatch?.let { com.fire.app.ui.home.HomeTopicDetailPatchRepository.publish(it) }
        val posts = snapshot.rows.map { rowToPost(it) }
        val detail = detailFromSnapshot(snapshot, posts)
        _detail.value = detail
        snapshotReplyRows = snapshot.rows.filter { !it.isOriginalPost }.map { rowToTreeRow(it) }
        _postRows.value = TopicDetailPostRows.projectRows(
            rows = snapshotReplyRows,
            postsById = posts.associateBy { it.id },
            expandedReplyRootPostIds = expandedReplyRootPostIds,
            focusedPostNumber = snapshot.scrollTargetPostNumber,
        )
        _topicAiSummary.value = snapshot.sidecar.summarizedText?.let { text ->
            TopicAiSummaryState(
                summarizedText = text,
                algorithm = snapshot.sidecar.algorithm,
                outdated = snapshot.sidecar.outdated,
                canRegenerate = snapshot.sidecar.canRegenerate,
                newPostsSinceSummary = snapshot.sidecar.newPostsSinceSummary,
                updatedAt = snapshot.sidecar.updatedAt,
            )
        }
        _isLoadingTopicAiSummary.value = snapshot.sidecar.isLoading
        _topicAiSummaryError.value = snapshot.sidecar.error
        preloadRenderContent(posts)
    }

    override fun onCleared() {
        sessionHandle?.release()
        sessionHandle = null
        super.onCleared()
    }

    companion object {
        private const val HEART_REACTION_ID = "heart"

        fun create(sessionStore: FireSessionStore): TopicDetailViewModel {
            return TopicDetailViewModel(sessionStore)
        }
    }
}

sealed class BookmarkEvent {
    data class Saved(
        val bookmarkableId: ULong,
        val bookmarkableType: String,
        val reminderAt: String?,
    ) : BookmarkEvent()

    data class Deleted(
        val bookmarkableId: ULong,
        val bookmarkableType: String,
    ) : BookmarkEvent()
}

class TopicDetailViewModelFactory(
    private val sessionStore: FireSessionStore,
) : ViewModelProvider.Factory {
    @Suppress("UNCHECKED_CAST")
    override fun <T : ViewModel> create(modelClass: Class<T>): T {
        if (modelClass.isAssignableFrom(TopicDetailViewModel::class.java)) {
            return TopicDetailViewModel.create(sessionStore) as T
        }
        throw IllegalArgumentException("Unknown ViewModel class: ${modelClass.name}")
    }
}
