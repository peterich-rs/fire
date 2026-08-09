package com.fire.app.ui.chat

import android.content.Context
import android.content.Intent
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
import androidx.appcompat.app.AppCompatActivity
import androidx.lifecycle.lifecycleScope
import androidx.recyclerview.widget.LinearLayoutManager
import androidx.recyclerview.widget.RecyclerView
import com.fire.app.R
import com.fire.app.session.FireSessionStoreRepository
import com.google.android.material.appbar.MaterialToolbar
import kotlinx.coroutines.launch
import uniffi.fire_uniffi_chat.ChatMessageState
import uniffi.fire_uniffi_chat.ChatMessagesQueryState
import uniffi.fire_uniffi_chat.SendChatMessageRequestState
import java.util.UUID

class ChatChannelActivity : AppCompatActivity() {

    private lateinit var toolbar: MaterialToolbar
    private lateinit var recyclerView: RecyclerView
    private lateinit var loadingView: ProgressBar
    private lateinit var input: EditText
    private lateinit var sendButton: ImageButton
    private lateinit var adapter: ChatMessageAdapter

    private var channelId: ULong = 0u
    private var messages: List<ChatMessageState> = emptyList()
    private var canLoadMorePast = false
    private var isLoading = false

    override fun onCreate(savedInstanceState: Bundle?) {
        enableEdgeToEdge()
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_chat_channel)

        channelId = intent.getLongExtra(EXTRA_CHANNEL_ID, 0L).toULong()
        val title = intent.getStringExtra(EXTRA_TITLE).orEmpty()

        toolbar = findViewById(R.id.chat_channel_toolbar)
        recyclerView = findViewById(R.id.chat_message_list)
        loadingView = findViewById(R.id.chat_channel_loading)
        input = findViewById(R.id.chat_message_input)
        sendButton = findViewById(R.id.chat_send_button)

        toolbar.title = title.ifBlank { getString(R.string.tab_chat) }
        toolbar.setNavigationOnClickListener { finish() }

        adapter = ChatMessageAdapter()
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
        lifecycleScope.launch { loadInitial() }
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
            val page = store.fetchChatMessages(
                ChatMessagesQueryState(
                    channelId = channelId,
                    direction = null,
                    targetMessageId = null,
                    fetchFromLastRead = true,
                    pageSize = 50u,
                ),
            )
            messages = page.messages
            canLoadMorePast = page.canLoadMorePast
            adapter.submit(messages)
            recyclerView.scrollToPosition((messages.size - 1).coerceAtLeast(0))
            page.messages.lastOrNull()?.id?.let { latest ->
                runCatching { store.markChatChannelRead(channelId, latest) }
            }
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
                val page = store.fetchChatMessages(
                    ChatMessagesQueryState(
                        channelId = channelId,
                        direction = "past",
                        targetMessageId = oldest.id,
                        fetchFromLastRead = false,
                        pageSize = 50u,
                    ),
                )
                messages = page.messages + messages
                canLoadMorePast = page.canLoadMorePast
                adapter.submit(messages)
            } catch (_: Exception) {
                // Keep current window on pagination failure.
            } finally {
                isLoading = false
            }
        }
    }

    private fun sendMessage() {
        val text = input.text?.toString()?.trim().orEmpty()
        if (text.isEmpty()) return
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
                        threadId = null,
                        uploadIds = emptyList(),
                    ),
                )
                input.setText("")
                val page = store.fetchChatMessages(
                    ChatMessagesQueryState(
                        channelId = channelId,
                        direction = null,
                        targetMessageId = null,
                        fetchFromLastRead = false,
                        pageSize = 50u,
                    ),
                )
                messages = page.messages
                canLoadMorePast = page.canLoadMorePast
                adapter.submit(messages)
                recyclerView.scrollToPosition((messages.size - 1).coerceAtLeast(0))
                page.messages.lastOrNull()?.id?.let { latest ->
                    runCatching { store.markChatChannelRead(channelId, latest) }
                }
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

    companion object {
        private const val EXTRA_CHANNEL_ID = "channel_id"
        private const val EXTRA_TITLE = "title"

        fun intent(context: Context, channelId: ULong, title: String): Intent {
            return Intent(context, ChatChannelActivity::class.java)
                .putExtra(EXTRA_CHANNEL_ID, channelId.toLong())
                .putExtra(EXTRA_TITLE, title)
        }
    }
}

private class ChatMessageAdapter : RecyclerView.Adapter<ChatMessageAdapter.Holder>() {
    private var items: List<ChatMessageState> = emptyList()

    fun submit(messages: List<ChatMessageState>) {
        items = messages
        notifyDataSetChanged()
    }

    override fun onCreateViewHolder(parent: ViewGroup, viewType: Int): Holder {
        val view = LayoutInflater.from(parent.context)
            .inflate(R.layout.item_chat_message, parent, false)
        return Holder(view)
    }

    override fun onBindViewHolder(holder: Holder, position: Int) {
        holder.bind(items[position])
    }

    override fun getItemCount(): Int = items.size

    class Holder(itemView: View) : RecyclerView.ViewHolder(itemView) {
        private val author: TextView = itemView.findViewById(R.id.message_author)
        private val body: TextView = itemView.findViewById(R.id.message_body)
        private val meta: TextView = itemView.findViewById(R.id.message_meta)

        fun bind(message: ChatMessageState) {
            author.text = message.user?.username ?: "user"
            body.text = if (message.isDeleted) {
                itemView.context.getString(R.string.chat_message_deleted)
            } else {
                message.message.ifBlank { message.previewText }
            }
            val parts = buildList {
                message.createdAt?.let { add(it) }
                if (message.edited) add(itemView.context.getString(R.string.chat_edited))
            }
            meta.text = parts.joinToString(" · ")
        }
    }
}
