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
import android.widget.ImageView
import android.widget.LinearLayout
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
import com.fire.app.core.image.FireAvatarUrls
import com.fire.app.core.image.FireImageLoader
import com.fire.app.messagebus.FireMessageBusCoordinator
import com.fire.app.richtext.FireRenderBlockBuilder
import com.fire.app.richtext.FireRichTextBlock
import com.fire.app.richtext.FireRichTextBlockBuilder
import com.fire.app.richtext.FireRichTextView
import com.fire.app.richtext.FireSpannableBuilder
import com.fire.app.session.FireSessionStore
import com.fire.app.session.FireSessionStoreRepository
import com.google.android.material.appbar.MaterialToolbar
import kotlinx.coroutines.Job
import kotlinx.coroutines.launch
import uniffi.fire_uniffi.renderCookedHtml
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
            onThreadClick = { message -> openThread(message) },
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
                val uploadId = result.id
                if (uploadId != null && uploadId > 0uL) {
                    sendMessage(textOverride = "", uploadIds = listOf(uploadId))
                } else {
                    // Fallback: embed Discourse short URL markdown when id is absent.
                    val alt = result.originalFilename?.takeIf { it.isNotBlank() } ?: "image"
                    val markdown = "![${alt}](${result.shortUrl})"
                    sendMessage(textOverride = markdown)
                }
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
    private val onThreadClick: (ChatMessageState) -> Unit,
    private val baseUrl: String = "https://linux.do",
) : RecyclerView.Adapter<ChatMessageAdapter.Holder>() {
    private var items: List<ChatMessageState> = emptyList()

    fun submit(messages: List<ChatMessageState>) {
        items = messages
        notifyDataSetChanged()
    }

    override fun onCreateViewHolder(parent: ViewGroup, viewType: Int): Holder {
        val view = LayoutInflater.from(parent.context)
            .inflate(R.layout.item_chat_message, parent, false)
        return Holder(view, onClick, onThreadClick, baseUrl)
    }

    override fun onBindViewHolder(holder: Holder, position: Int) {
        val previous = items.getOrNull(position - 1)
        holder.bind(items[position], previous)
    }

    override fun getItemCount(): Int = items.size

    class Holder(
        itemView: View,
        private val onClick: (ChatMessageState) -> Unit,
        private val onThreadClick: (ChatMessageState) -> Unit,
        private val baseUrl: String,
    ) : RecyclerView.ViewHolder(itemView) {
        private val avatarContainer: View = itemView.findViewById(R.id.message_avatar_container)
        private val avatar: ImageView = itemView.findViewById(R.id.message_avatar)
        private val monogram: TextView = itemView.findViewById(R.id.message_avatar_monogram)
        private val header: View = itemView.findViewById(R.id.message_header)
        private val author: TextView = itemView.findViewById(R.id.message_author)
        private val time: TextView = itemView.findViewById(R.id.message_time)
        private val bodyContainer: LinearLayout = itemView.findViewById(R.id.message_body_container)
        private val meta: TextView = itemView.findViewById(R.id.message_meta)
        private val thread: TextView = itemView.findViewById(R.id.message_thread)

        fun bind(message: ChatMessageState, previous: ChatMessageState?) {
            val username = message.user?.username ?: "user"
            val grouped = shouldGroup(previous, message)
            author.text = username
            time.text = formatTime(message.createdAt)
            bindBody(message)
            bindMeta(message)
            bindThread(message)
            bindAvatar(username, message.user?.avatarTemplate, grouped)

            itemView.setPadding(
                itemView.paddingLeft,
                if (grouped) dp(2) else dp(8),
                itemView.paddingRight,
                itemView.paddingBottom,
            )
            itemView.setOnClickListener { onClick(message) }
        }

        private fun bindBody(message: ChatMessageState) {
            bodyContainer.removeAllViews()
            val contentId = "chat:${message.id}:${message.cooked.hashCode()}:${message.message.hashCode()}"
            if (message.isDeleted) {
                bodyContainer.addView(
                    TextView(itemView.context).apply {
                        text = itemView.context.getString(R.string.chat_message_deleted)
                        setTextColor(itemView.context.getColor(R.color.fire_text_secondary))
                        setTypeface(typeface, android.graphics.Typeface.ITALIC)
                        textSize = 15f
                    },
                )
                return
            }

            val cooked = message.cooked.trim()
            if (cooked.isNotEmpty()) {
                val document = renderCookedHtml(cooked, baseUrl)
                val content = FireRenderBlockBuilder.build(document)
                val blocks = FireRichTextBlockBuilder.build(content)
                if (blocks.isNotEmpty()) {
                    blocks.forEachIndexed { index, block ->
                        when (block) {
                            is FireRichTextBlock.Text -> {
                                val spannable = FireSpannableBuilder.build(
                                    nodes = block.nodes,
                                    context = itemView.context,
                                    onLinkClicked = null,
                                )
                                if (spannable.isNotBlank()) {
                                    val textView = FireRichTextView(itemView.context).apply {
                                        setTextAppearance(androidx.appcompat.R.style.TextAppearance_AppCompat_Body1)
                                        setTextColor(itemView.context.getColor(R.color.fire_text_primary))
                                        setTextIsSelectable(false)
                                        setContent("$contentId:text:$index", spannable)
                                    }
                                    bodyContainer.addView(textView)
                                }
                            }
                            is FireRichTextBlock.Image -> {
                                // Lightweight chat image: open URL via FireImageLoader thumbnail.
                                val imageView = ImageView(itemView.context).apply {
                                    adjustViewBounds = true
                                    maxHeight = dp(220)
                                    scaleType = ImageView.ScaleType.CENTER_CROP
                                    layoutParams = LinearLayout.LayoutParams(
                                        LinearLayout.LayoutParams.MATCH_PARENT,
                                        LinearLayout.LayoutParams.WRAP_CONTENT,
                                    ).apply {
                                        if (index > 0) topMargin = dp(6)
                                    }
                                }
                                FireImageLoader.load(block.image.url, imageView)
                                bodyContainer.addView(imageView)
                            }
                        }
                    }
                    if (bodyContainer.childCount > 0) return
                }
                val plain = document.plainText.trim()
                if (plain.isNotEmpty()) {
                    bodyContainer.addView(plainTextView(plain))
                    return
                }
            }

            val plain = when {
                message.message.isNotBlank() -> message.message
                message.uploads.isNotEmpty() -> itemView.context.getString(R.string.chat_image_attachment)
                else -> message.previewText
            }
            bodyContainer.addView(plainTextView(plain))
        }

        private fun plainTextView(textValue: String): TextView {
            return TextView(itemView.context).apply {
                text = textValue
                setTextColor(itemView.context.getColor(R.color.fire_text_primary))
                textSize = 15f
            }
        }

        private fun bindMeta(message: ChatMessageState) {
            val parts = buildList {
                if (message.edited) add(itemView.context.getString(R.string.chat_edited))
                if (message.pinned) add(itemView.context.getString(R.string.chat_pinned_message))
                if (message.reactions.isNotEmpty()) {
                    add(message.reactions.joinToString("  ") { ":${it.emoji}: ${it.count}" })
                }
            }
            if (parts.isEmpty()) {
                meta.visibility = View.GONE
            } else {
                meta.visibility = View.VISIBLE
                meta.text = parts.joinToString(" · ")
            }
        }

        private fun bindThread(message: ChatMessageState) {
            val replyCount = message.thread?.replyCount ?: 0u
            if (replyCount > 0u) {
                thread.visibility = View.VISIBLE
                thread.text = itemView.context.getString(R.string.chat_thread_replies, replyCount.toInt())
                thread.setOnClickListener { onThreadClick(message) }
            } else {
                thread.visibility = View.GONE
                thread.setOnClickListener(null)
            }
        }

        private fun bindAvatar(username: String, avatarTemplate: String?, grouped: Boolean) {
            if (grouped) {
                header.visibility = View.GONE
                avatarContainer.visibility = View.INVISIBLE
                return
            }
            header.visibility = View.VISIBLE
            avatarContainer.visibility = View.VISIBLE
            monogram.text = username.take(1).uppercase()
            monogram.visibility = View.VISIBLE
            avatar.setImageDrawable(null)
            // Avatar ImageView sits above monogram; successful Coil loads cover it.
            FireAvatarUrls.build(avatarTemplate, baseUrl = baseUrl)?.let { url ->
                FireImageLoader.load(url, avatar)
            }
        }

        private fun dp(value: Int): Int =
            (value * itemView.resources.displayMetrics.density).toInt()

        private fun formatTime(value: String?): String {
            if (value.isNullOrBlank()) return ""
            return value
                .removeSuffix("Z")
                .substringAfter('T')
                .take(5)
                .ifBlank { value.takeLast(5) }
        }

        private fun shouldGroup(previous: ChatMessageState?, current: ChatMessageState): Boolean {
            if (previous == null) return false
            if (previous.user?.id == null || previous.user?.id != current.user?.id) return false
            val prev = previous.createdAt ?: return false
            val curr = current.createdAt ?: return false
            return prev.take(16) == curr.take(16) || prev.take(13) == curr.take(13)
        }
    }
}
