package com.fire.app.ui.chat

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Bundle
import android.view.View
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
import com.fire.app.session.FireSessionStoreRepository
import com.fire.app.ui.profile.FireUserCardSheet
import com.google.android.material.appbar.MaterialToolbar
import kotlinx.coroutines.Job
import kotlinx.coroutines.launch
import uniffi.fire_uniffi_chat.ChatMessageState
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
    private lateinit var session: ChatChannelSession

    private var channelId: ULong = 0u
    private var threadId: ULong? = null
    private var snapshot: ChatChannelSession.Snapshot? = null
    private var busJob: Job? = null

    private val imagePicker = registerForActivityResult(ActivityResultContracts.GetContent()) { uri ->
        uri?.let { uploadAndSend(it) }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        enableEdgeToEdge()
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_chat_channel)

        channelId = intent.getLongExtra(EXTRA_CHANNEL_ID, 0L).toULong()
        if (channelId == 0uL) {
            finish()
            return
        }
        threadId = intent.getLongExtra(EXTRA_THREAD_ID, 0L).takeIf { it > 0 }?.toULong()
        val title = intent.getStringExtra(EXTRA_TITLE).orEmpty()
        val threadingEnabled = intent.getBooleanExtra(EXTRA_THREADING_ENABLED, false)

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
            onAuthorClick = { username -> showUserCard(username) },
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
            snapshot?.pins?.firstOrNull()?.let { pin ->
                val index = snapshot?.messages.orEmpty().indexOfFirst { it.id == pin.id }
                if (index >= 0) recyclerView.scrollToPosition(index)
            }
        }

        busJob = lifecycleScope.launch {
            val store = FireSessionStoreRepository.get(this@ChatChannelActivity)
            session = ChatChannelSession(
                store = store,
                channelId = channelId,
                threadId = threadId,
                initialTitle = title,
                initialThreadingEnabled = threadingEnabled,
            )
            session.onChange = { next, change -> applySnapshot(next, change) }
            session.onError = { error ->
                Toast.makeText(
                    this@ChatChannelActivity,
                    error.message ?: getString(R.string.chat_load_failed),
                    Toast.LENGTH_LONG,
                ).show()
            }
            launch {
                FireMessageBusCoordinator(store).chatEvents().collect { event ->
                    session.handleBusEvent(event)
                }
            }
            session.open()
        }
    }

    override fun onDestroy() {
        busJob?.cancel()
        if (::session.isInitialized) {
            val openSession = session
            lifecycleScope.launch { openSession.close() }
        }
        super.onDestroy()
    }

    private fun applySnapshot(
        next: ChatChannelSession.Snapshot,
        change: ChatChannelSession.Change,
    ) {
        snapshot = next
        adapter.submit(next.messages, next.chatBaseUrl)
        loadingView.visibility = if (next.isLoading && next.messages.isEmpty()) {
            View.VISIBLE
        } else {
            View.GONE
        }
        if (threadId == null && next.title.isNotBlank()) {
            toolbar.title = next.title
        }
        updatePinBanner()
        when (change) {
            ChatChannelSession.Change.Initial,
            ChatChannelSession.Change.Latest,
            -> recyclerView.scrollToPosition((next.messages.size - 1).coerceAtLeast(0))
            else -> Unit
        }
    }

    private fun loadMorePast() {
        if (!::session.isInitialized) return
        lifecycleScope.launch {
            runCatching { session.command(ChatChannelSession.Command.LoadMorePast) }
        }
    }

    private fun sendMessage(textOverride: String? = null, uploadIds: List<ULong> = emptyList()) {
        if (!::session.isInitialized) return
        val text = textOverride ?: input.text?.toString()?.trim().orEmpty()
        if (text.isEmpty() && uploadIds.isEmpty()) return
        sendButton.isEnabled = false
        lifecycleScope.launch {
            try {
                session.command(ChatChannelSession.Command.Send(text, uploadIds))
                if (textOverride == null) input.setText("")
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

    private fun showUserCard(username: String) {
        lifecycleScope.launch {
            val store = FireSessionStoreRepository.get(this@ChatChannelActivity)
            FireUserCardSheet.show(this@ChatChannelActivity, store, username)
        }
    }

    private fun updatePinBanner() {
        val pin = snapshot?.pins?.firstOrNull()
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
        val threadingEnabled = snapshot?.threadingEnabled == true
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
                        if (::session.isInitialized) {
                            runCatching {
                                session.command(
                                    ChatChannelSession.Command.SetPinned(message.id, pinned = true),
                                )
                            }
                        }
                    }
                    labels[which] == getString(R.string.chat_unpin) -> lifecycleScope.launch {
                        if (::session.isInitialized) {
                            runCatching {
                                session.command(
                                    ChatChannelSession.Command.SetPinned(message.id, pinned = false),
                                )
                            }
                        }
                    }
                }
            }
            .show()
    }

    private fun toggleReaction(message: ChatMessageState, emoji: String) {
        if (!::session.isInitialized) return
        lifecycleScope.launch {
            runCatching {
                session.command(ChatChannelSession.Command.ToggleReaction(message.id, emoji))
            }
        }
    }

    private fun openThread(message: ChatMessageState) {
        if (!::session.isInitialized) return
        lifecycleScope.launch {
            try {
                val result = session.command(ChatChannelSession.Command.ResolveThread(message.id))
                val id = (result as? ChatChannelSession.CommandResult.ThreadId)?.id ?: return@launch
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
