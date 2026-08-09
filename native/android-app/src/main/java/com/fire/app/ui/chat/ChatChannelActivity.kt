package com.fire.app.ui.chat

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Bundle
import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import android.widget.EditText
import android.widget.ImageButton
import android.widget.ProgressBar
import android.widget.TextView
import android.widget.Toast
import androidx.activity.enableEdgeToEdge
import androidx.activity.result.contract.ActivityResultContracts
import androidx.appcompat.app.AlertDialog
import androidx.appcompat.app.AppCompatActivity
import androidx.lifecycle.lifecycleScope
import androidx.recyclerview.widget.LinearLayoutManager
import androidx.recyclerview.widget.RecyclerView
import com.fire.app.R
import com.fire.app.messagebus.FireMessageBusCoordinator
import com.fire.app.session.FireSessionStore
import com.fire.app.session.FireSessionStoreRepository
import com.google.android.material.appbar.MaterialToolbar
import kotlinx.coroutines.Job
import kotlinx.coroutines.launch
import uniffi.fire_uniffi_chat.ChatMessageState
import uniffi.fire_uniffi_chat.ChatMessagesQueryState
import uniffi.fire_uniffi_chat.SendChatMessageRequestState
import uniffi.fire_uniffi_messagebus.MessageBusEventState
import uniffi.fire_uniffi_topics.UploadImageRequestState
import java.util.UUID

class ChatChannelActivity : AppCompatActivity() {

    private lateinit var toolbar: MaterialToolbar
    private lateinit var pinBanner: TextView
    private lateinit var recyclerView: RecyclerView
    private lateinit var loadingView: ProgressBar
    private lateinit var input: EditText
    private lateinit var attachButton: ImageButton
    private lateinit var sendButton: ImageButton
    private lateinit var adapter: ChatMessageAdapter

    private var channelId: ULong = 0u
    private var threadId: ULong? = null
    private var threadingEnabled = false
    private var messages: List<ChatMessageState> = emptyList()
    private var pins: List<ChatMessageState> = emptyList()
    private var canLoadMorePast = false
    private var isLoading = false
    private var busJob: Job? = null
    private val ownerToken = "chat-channel-activity"
    private var busChannelName: String = ""

    private val imagePicker = registerForActivityResult(ActivityResultContracts.GetContent()) { uri ->
        uri?.let { uploadAndSend(it) }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        enableEdgeToEdge()
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_chat_channel)

        channelId = intent.getLongExtra(EXTRA_CHANNEL_ID, 0L).toULong()
        threadId = intent.getLongExtra(EXTRA_THREAD_ID, 0L).takeIf { it > 0 }?.toULong()
        val title = intent.getStringExtra(EXTRA_TITLE).orEmpty()
        threadingEnabled = intent.getBooleanExtra(EXTRA_THREADING_ENABLED, false)

        toolbar = findViewById(R.id.chat_channel_toolbar)
        pinBanner = findViewById(R.id.chat_pin_banner)
        recyclerView = findViewById(R.id.chat_message_list)
        loadingView = findViewById(R.id.chat_channel_loading)
        input = findViewById(R.id.chat_message_input)
        attachButton = findViewById(R.id.chat_attach_button)
        sendButton = findViewById(R.id.chat_send_button)

        toolbar.title = if (threadId != null) {
            getString(R.string.chat_thread_title)
        } else {
            title.ifBlank { getString(R.string.tab_chat) }
        }
        toolbar.setNavigationOnClickListener { finish() }

        adapter = ChatMessageAdapter(
            onClick = { message -> showMessageActions(message) },
        )
        val layoutManager = LinearLayoutManager(this).apply { stackFromEnd = true }
        recyclerView.layoutManager = layoutManager
        recyclerView.adapter = adapter
        recyclerView.addOnScrollListener(object : RecyclerView.OnScrollListener() {
            override fun onScrolled(recyclerView: RecyclerView, dx: Int, dy: Int) {
                if (layoutManager.findFirstVisibleItemPosition() <= 2) {
                    loadMorePast()
                }
            }
        })

        sendButton.setOnClickListener { sendMessage() }
        attachButton.setOnClickListener { imagePicker.launch("image/*") }
        pinBanner.setOnClickListener {
            pins.firstOrNull()?.let { pin ->
                val index = messages.indexOfFirst { it.id == pin.id }
                if (index >= 0) recyclerView.scrollToPosition(index)
            }
        }

        busChannelName = threadId?.let { "/chat/$channelId/thread/$it" } ?: "/chat/$channelId"
        lifecycleScope.launch { loadInitial() }
        busJob = lifecycleScope.launch {
            val store = FireSessionStoreRepository.get(this@ChatChannelActivity)
            FireMessageBusCoordinator(store).chatEvents().collect { event ->
                handleBusEvent(event)
            }
        }
    }

    override fun onDestroy() {
        busJob?.cancel()
        lifecycleScope.launch {
            val store = FireSessionStoreRepository.get(this@ChatChannelActivity)
            store.unsubscribeMessageBusChannel(busChannelName, ownerToken)
        }
        super.onDestroy()
    }

    private suspend fun loadInitial() {
        if (channelId == 0uL) {
            finish()
            return
        }
        isLoading = true
        loadingView.visibility = View.VISIBLE
        try {
            val store = FireSessionStoreRepository.get(this)
            if (threadId == null) {
                val channel = store.fetchChatChannel(channelId)
                threadingEnabled = channel.threadingEnabled
                toolbar.title = channel.displayTitle
                pins = store.fetchChatChannelPins(channelId)
                updatePinBanner()
                if (pins.isNotEmpty()) {
                    runCatching { store.markChatChannelPinsRead(channelId) }
                }
            }
            val query = ChatMessagesQueryState(
                channelId = channelId,
                direction = null,
                targetMessageId = null,
                fetchFromLastRead = true,
                pageSize = 50u,
            )
            val page = if (threadId != null) {
                store.fetchChatThreadMessages(channelId, threadId!!, query).also {
                    runCatching { store.markChatThreadRead(channelId, threadId!!) }
                }
            } else {
                store.fetchChatMessages(query)
            }
            messages = page.messages
            canLoadMorePast = page.canLoadMorePast
            adapter.submit(messages)
            recyclerView.scrollToPosition((messages.size - 1).coerceAtLeast(0))
            page.messages.lastOrNull()?.id?.let { latest ->
                if (threadId == null) {
                    runCatching { store.markChatChannelRead(channelId, latest) }
                }
            }
            store.subscribeMessageBusChannel(
                channel = busChannelName,
                ownerToken = ownerToken,
                lastMessageId = null,
            )
        } catch (error: Exception) {
            Toast.makeText(this, error.message ?: getString(R.string.chat_load_failed), Toast.LENGTH_LONG).show()
        } finally {
            isLoading = false
            loadingView.visibility = View.GONE
        }
    }

    private fun loadMorePast() {
        if (!canLoadMorePast || isLoading) return
        val oldest = messages.firstOrNull() ?: return
        lifecycleScope.launch {
            isLoading = true
            try {
                val store = FireSessionStoreRepository.get(this@ChatChannelActivity)
                val query = ChatMessagesQueryState(
                    channelId = channelId,
                    direction = "past",
                    targetMessageId = oldest.id,
                    fetchFromLastRead = false,
                    pageSize = 50u,
                )
                val page = if (threadId != null) {
                    store.fetchChatThreadMessages(channelId, threadId!!, query)
                } else {
                    store.fetchChatMessages(query)
                }
                messages = page.messages + messages
                canLoadMorePast = page.canLoadMorePast
                adapter.submit(messages)
            } catch (_: Exception) {
            } finally {
                isLoading = false
            }
        }
    }

    private fun sendMessage(textOverride: String? = null, uploadIds: List<ULong> = emptyList()) {
        val text = textOverride ?: input.text?.toString()?.trim().orEmpty()
        if (text.isEmpty() && uploadIds.isEmpty()) return
        sendButton.isEnabled = false
        lifecycleScope.launch {
            try {
                val store = FireSessionStoreRepository.get(this@ChatChannelActivity)
                store.sendChatMessage(
                    SendChatMessageRequestState(
                        channelId = channelId,
                        message = text,
                        stagedId = UUID.randomUUID().toString(),
                        inReplyToId = null,
                        threadId = threadId,
                        uploadIds = uploadIds,
                    ),
                )
                if (textOverride == null) input.setText("")
                softRefreshLatest(store)
            } catch (error: Exception) {
                Toast.makeText(
                    this@ChatChannelActivity,
                    error.message ?: getString(R.string.chat_send_failed),
                    Toast.LENGTH_LONG,
                ).show()
            } finally {
                sendButton.isEnabled = true
            }
        }
    }

    private fun uploadAndSend(uri: Uri) {
        lifecycleScope.launch {
            try {
                val store = FireSessionStoreRepository.get(this@ChatChannelActivity)
                val bytes = contentResolver.openInputStream(uri)?.use { it.readBytes() }
                    ?: error("unable to read image")
                val result = store.uploadImage(
                    UploadImageRequestState(
                        fileName = "chat-${UUID.randomUUID()}.jpg",
                        mimeType = contentResolver.getType(uri) ?: "image/jpeg",
                        bytes = bytes,
                    ),
                )
                sendMessage(textOverride = "", uploadIds = listOf(result.id))
            } catch (error: Exception) {
                Toast.makeText(
                    this@ChatChannelActivity,
                    error.message ?: getString(R.string.chat_send_failed),
                    Toast.LENGTH_LONG,
                ).show()
            }
        }
    }

    private suspend fun softRefreshLatest(store: FireSessionStore) {
        val query = ChatMessagesQueryState(
            channelId = channelId,
            direction = null,
            targetMessageId = null,
            fetchFromLastRead = false,
            pageSize = 50u,
        )
        val page = if (threadId != null) {
            store.fetchChatThreadMessages(channelId, threadId!!, query)
        } else {
            store.fetchChatMessages(query)
        }
        messages = page.messages
        canLoadMorePast = page.canLoadMorePast
        adapter.submit(messages)
        recyclerView.scrollToPosition((messages.size - 1).coerceAtLeast(0))
        page.messages.lastOrNull()?.id?.let { latest ->
            if (threadId == null) {
                runCatching { store.markChatChannelRead(channelId, latest) }
            }
        }
    }

    private fun handleBusEvent(event: MessageBusEventState) {
        if (event.channel != busChannelName) return
        val type = event.detailEventType ?: event.messageType
        when (type) {
            "sent", "edit", "processed", "refresh", "restore",
            "thread_created", "update_thread_original_message",
            -> lifecycleScope.launch {
                val store = FireSessionStoreRepository.get(this@ChatChannelActivity)
                softRefreshLatest(store)
            }
            "delete", "reaction", "pin", "unpin" -> lifecycleScope.launch {
                val store = FireSessionStoreRepository.get(this@ChatChannelActivity)
                softRefreshLatest(store)
                if (threadId == null) {
                    pins = store.fetchChatChannelPins(channelId)
                    updatePinBanner()
                }
            }
        }
    }

    private fun updatePinBanner() {
        val pin = pins.firstOrNull()
        if (pin == null || threadId != null) {
            pinBanner.visibility = View.GONE
            return
        }
        pinBanner.visibility = View.VISIBLE
        pinBanner.text = getString(
            R.string.chat_pin_banner,
            pin.previewText.ifBlank { getString(R.string.chat_pinned_message) },
        )
    }

    private fun showMessageActions(message: ChatMessageState) {
        val emojis = listOf("heart", "tada", "laughing", "+1", "eyes")
        val labels = emojis.map { emoji ->
            val reacted = message.reactions.any { it.emoji == emoji && it.reacted }
            if (reacted) "取消 :$emoji:" else ":$emoji:"
        }.toMutableList()
        if (threadingEnabled && threadId == null) {
            labels.add(getString(R.string.chat_open_thread))
        }
        labels.add(getString(R.string.chat_pin))
        labels.add(getString(R.string.chat_unpin))
        AlertDialog.Builder(this)
            .setItems(labels.toTypedArray()) { _, which ->
                when {
                    which < emojis.size -> toggleReaction(message, emojis[which])
                    labels[which] == getString(R.string.chat_open_thread) -> openThread(message)
                    labels[which] == getString(R.string.chat_pin) -> lifecycleScope.launch {
                        runCatching {
                            FireSessionStoreRepository.get(this@ChatChannelActivity)
                                .pinChatMessage(channelId, message.id)
                        }
                    }
                    labels[which] == getString(R.string.chat_unpin) -> lifecycleScope.launch {
                        runCatching {
                            FireSessionStoreRepository.get(this@ChatChannelActivity)
                                .unpinChatMessage(channelId, message.id)
                        }
                    }
                }
            }
            .show()
    }

    private fun toggleReaction(message: ChatMessageState, emoji: String) {
        val reacted = message.reactions.any { it.emoji == emoji && it.reacted }
        lifecycleScope.launch {
            runCatching {
                FireSessionStoreRepository.get(this@ChatChannelActivity).reactChatMessage(
                    channelId = channelId,
                    messageId = message.id,
                    emoji = emoji,
                    reactAction = if (reacted) "remove" else "add",
                )
            }
        }
    }

    private fun openThread(message: ChatMessageState) {
        lifecycleScope.launch {
            try {
                val store = FireSessionStoreRepository.get(this@ChatChannelActivity)
                val id = message.threadId
                    ?: message.thread?.id
                    ?: store.createChatThread(channelId, message.id)
                startActivity(
                    intent(
                        this@ChatChannelActivity,
                        channelId = channelId,
                        title = toolbar.title?.toString().orEmpty(),
                        threadId = id,
                        threadingEnabled = true,
                    ),
                )
            } catch (error: Exception) {
                Toast.makeText(this@ChatChannelActivity, error.message, Toast.LENGTH_LONG).show()
            }
        }
    }

    companion object {
        private const val EXTRA_CHANNEL_ID = "channel_id"
        private const val EXTRA_TITLE = "title"
        private const val EXTRA_THREAD_ID = "thread_id"
        private const val EXTRA_THREADING_ENABLED = "threading_enabled"

        fun intent(
            context: Context,
            channelId: ULong,
            title: String,
            threadId: ULong? = null,
            threadingEnabled: Boolean = false,
        ): Intent {
            return Intent(context, ChatChannelActivity::class.java)
                .putExtra(EXTRA_CHANNEL_ID, channelId.toLong())
                .putExtra(EXTRA_TITLE, title)
                .putExtra(EXTRA_THREAD_ID, threadId?.toLong() ?: 0L)
                .putExtra(EXTRA_THREADING_ENABLED, threadingEnabled)
        }
    }
}

private class ChatMessageAdapter(
    private val onClick: (ChatMessageState) -> Unit,
) : RecyclerView.Adapter<ChatMessageAdapter.Holder>() {
    private var items: List<ChatMessageState> = emptyList()

    fun submit(messages: List<ChatMessageState>) {
        items = messages
        notifyDataSetChanged()
    }

    override fun onCreateViewHolder(parent: ViewGroup, viewType: Int): Holder {
        val view = LayoutInflater.from(parent.context)
            .inflate(R.layout.item_chat_message, parent, false)
        return Holder(view, onClick)
    }

    override fun onBindViewHolder(holder: Holder, position: Int) {
        holder.bind(items[position])
    }

    override fun getItemCount(): Int = items.size

    class Holder(
        itemView: View,
        private val onClick: (ChatMessageState) -> Unit,
    ) : RecyclerView.ViewHolder(itemView) {
        private val author: TextView = itemView.findViewById(R.id.message_author)
        private val body: TextView = itemView.findViewById(R.id.message_body)
        private val meta: TextView = itemView.findViewById(R.id.message_meta)

        fun bind(message: ChatMessageState) {
            author.text = message.user?.username ?: "user"
            body.text = when {
                message.isDeleted -> itemView.context.getString(R.string.chat_message_deleted)
                message.message.isBlank() && message.uploads.isNotEmpty() ->
                    itemView.context.getString(R.string.chat_image_attachment)
                else -> message.message.ifBlank { message.previewText }
            }
            val parts = buildList {
                message.createdAt?.let { add(it) }
                if (message.edited) add(itemView.context.getString(R.string.chat_edited))
                if (message.pinned) add(itemView.context.getString(R.string.chat_pinned_message))
                if (message.reactions.isNotEmpty()) {
                    add(message.reactions.joinToString(" ") { ":${it.emoji}: ${it.count}" })
                }
                message.thread?.replyCount?.takeIf { it > 0u }?.let {
                    add(itemView.context.getString(R.string.chat_thread_replies, it.toInt()))
                }
            }
            meta.text = parts.joinToString(" · ")
            itemView.setOnClickListener { onClick(message) }
        }
    }
}
