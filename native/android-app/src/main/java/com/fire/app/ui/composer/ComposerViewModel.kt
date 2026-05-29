package com.fire.app.ui.composer

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.fire.app.session.FireSessionStore
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableStateFlow
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

    private val _error = MutableStateFlow<String?>(null)
    val error = _error.asStateFlow()

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
            } catch (e: Exception) {
                _error.value = e.message
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
            try {
                val input = TopicCreateRequestState(
                    title = title,
                    raw = body,
                    categoryId = categoryId,
                    tags = tags,
                )
                val topicId = sessionStore.createTopic(input)
                _topicCreated.value = topicId
            } catch (e: Exception) {
                _error.value = e.message
            } finally {
                _isSubmitting.value = false
            }
        }
    }

    fun submitPrivateMessage(title: String, body: String, targetUsername: String) {
        if (_isSubmitting.value) return
        viewModelScope.launch {
            _isSubmitting.value = true
            _error.value = null
            try {
                val input = PrivateMessageCreateRequestState(
                    title = title,
                    raw = body,
                    targetRecipients = listOf(targetUsername),
                )
                sessionStore.createPrivateMessage(input)
            } catch (e: Exception) {
                _error.value = e.message
            } finally {
                _isSubmitting.value = false
            }
        }
    }

    companion object {
        fun create(sessionStore: FireSessionStore): ComposerViewModel {
            return ComposerViewModel(sessionStore)
        }
    }
}
