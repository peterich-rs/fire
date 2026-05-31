package com.fire.app.ui.composer

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.fire.app.core.error.FireErrorReporter
import com.fire.app.session.FireSessionStore
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asSharedFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import uniffi.fire_uniffi_topics.PrivateMessageCreateRequestState
import uniffi.fire_uniffi_topics.TopicCreateRequestState
import uniffi.fire_uniffi_topics.TopicPostState
import uniffi.fire_uniffi_topics.TopicReplyRequestState

class ComposerViewModel(
    private val sessionStore: FireSessionStore,
) : ViewModel() {

    private val _isSubmitting = MutableStateFlow(false)
    val isSubmitting = _isSubmitting.asStateFlow()

    private val _result = MutableStateFlow<TopicPostState?>(null)
    val result = _result.asStateFlow()

    private val _topicCreated = MutableStateFlow<ULong?>(null)
    val topicCreated = _topicCreated.asStateFlow()

    private val _privateMessageCreated = MutableStateFlow<ULong?>(null)
    val privateMessageCreated = _privateMessageCreated.asStateFlow()

    private val _error = MutableStateFlow<String?>(null)
    val error = _error.asStateFlow()

    private val _cloudflareChallenge = MutableSharedFlow<Unit>(extraBufferCapacity = 1)
    val cloudflareChallenge = _cloudflareChallenge.asSharedFlow()

    fun submitReply(topicId: ULong, rawBody: String, replyToPostNumber: UInt?) {
        if (_isSubmitting.value) return
        viewModelScope.launch {
            _isSubmitting.value = true
            _error.value = null
            _result.value = null
            try {
                val input = TopicReplyRequestState(
                    topicId = topicId,
                    raw = rawBody,
                    replyToPostNumber = replyToPostNumber,
                )
                val post = sessionStore.createReply(input)
                _result.value = post
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                handleError(e)
            } finally {
                _isSubmitting.value = false
            }
        }
    }

    fun submitTopic(title: String, body: String, categoryId: ULong, tags: List<String>) {
        if (_isSubmitting.value) return
        viewModelScope.launch {
            _isSubmitting.value = true
            _error.value = null
            _topicCreated.value = null
            _privateMessageCreated.value = null
            try {
                val input = TopicCreateRequestState(
                    title = title,
                    raw = body,
                    categoryId = categoryId,
                    tags = tags,
                )
                val topicId = sessionStore.createTopic(input)
                _topicCreated.value = topicId
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                handleError(e)
            } finally {
                _isSubmitting.value = false
            }
        }
    }

    fun submitPrivateMessage(title: String, body: String, targetUsernames: List<String>) {
        if (_isSubmitting.value) return
        viewModelScope.launch {
            _isSubmitting.value = true
            _error.value = null
            _topicCreated.value = null
            _privateMessageCreated.value = null
            try {
                val input = PrivateMessageCreateRequestState(
                    title = title,
                    raw = body,
                    targetRecipients = targetUsernames,
                )
                val topicId = sessionStore.createPrivateMessage(input)
                _privateMessageCreated.value = topicId
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                handleError(e)
            } finally {
                _isSubmitting.value = false
            }
        }
    }

    private fun handleError(error: Exception) {
        val reported = FireErrorReporter.report(
            operation = "composer.submit",
            error = error,
            sessionStore = sessionStore,
        )
        if (reported.isCloudflareChallenge) {
            _cloudflareChallenge.tryEmit(Unit)
        } else {
            _error.value = reported.displayMessage
        }
    }

    companion object {
        fun create(sessionStore: FireSessionStore): ComposerViewModel {
            return ComposerViewModel(sessionStore)
        }
    }
}
