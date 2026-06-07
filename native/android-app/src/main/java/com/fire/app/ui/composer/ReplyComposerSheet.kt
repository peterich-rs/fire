package com.fire.app.ui.composer

import android.app.Dialog
import android.net.Uri
import android.os.Bundle
import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import android.widget.EditText
import android.widget.LinearLayout
import android.widget.ProgressBar
import android.widget.TextView
import android.widget.Toast
import androidx.activity.result.contract.ActivityResultContracts
import androidx.lifecycle.lifecycleScope
import com.fire.app.R
import com.fire.app.core.error.FireErrorReporter
import com.fire.app.session.FireSessionStore
import com.fire.app.session.FireSessionStoreRepository
import com.google.android.material.bottomsheet.BottomSheetDialogFragment
import kotlinx.coroutines.flow.collectLatest
import kotlinx.coroutines.launch
import uniffi.fire_uniffi_types.DraftDataState

class ReplyComposerSheet : BottomSheetDialogFragment() {

    private var topicId: ULong = 0u
    private var replyToPostNumber: UInt? = null
    private var onReplySubmitted: (() -> Unit)? = null

    private lateinit var bodyInput: EditText
    private lateinit var submitButton: TextView
    private lateinit var uploadButton: TextView
    private lateinit var previewButton: TextView
    private lateinit var previewContainer: LinearLayout
    private lateinit var progressBar: ProgressBar
    private lateinit var sessionStore: FireSessionStore
    private var viewModel: ComposerViewModel? = null
    private var draftSequence: UInt = 0u
    private var didSubmit = false
    private var draftAutosave: ComposerDraftAutosave? = null
    private lateinit var previewRenderer: ComposerPreviewRenderer
    private var previewMode = false
    private var baseUrl = "https://linux.do"

    private val imagePicker = registerForActivityResult(ActivityResultContracts.GetContent()) { uri ->
        uri?.let(::uploadImage)
    }

    override fun onCreateView(
        inflater: LayoutInflater,
        container: ViewGroup?,
        savedInstanceState: Bundle?,
    ): View? {
        return inflater.inflate(R.layout.sheet_reply_composer, container, false)
    }

    override fun onViewCreated(view: View, savedInstanceState: Bundle?) {
        super.onViewCreated(view, savedInstanceState)

        bodyInput = view.findViewById(R.id.reply_body_input)
        submitButton = view.findViewById(R.id.reply_submit_button)
        uploadButton = view.findViewById(R.id.reply_upload_button)
        previewButton = view.findViewById(R.id.reply_preview_button)
        previewContainer = view.findViewById(R.id.reply_preview_container)
        progressBar = view.findViewById(R.id.reply_progress)

        arguments?.let { args ->
            topicId = args.getLong(ARG_TOPIC_ID).toULong()
            replyToPostNumber = args.getInt(ARG_REPLY_TO_POST_NUMBER).takeIf { it > 0 }?.toUInt()
        }

        val title = if (replyToPostNumber != null) {
            getString(R.string.topic_detail_reply_post_title, replyToPostNumber)
        } else {
            getString(R.string.topic_detail_reply_topic_title)
        }
        view.findViewById<TextView>(R.id.reply_title).text = title

        viewLifecycleOwner.lifecycleScope.launch {
            sessionStore = FireSessionStoreRepository.get(requireContext())
            viewModel = ComposerViewModel.create(sessionStore)
            previewRenderer = ComposerPreviewRenderer(
                previewContainer,
                sessionStore,
                viewLifecycleOwner.lifecycleScope,
            )

            ComposerMentionAssist(
                input = bodyInput,
                suggestions = view.findViewById(R.id.reply_mention_suggestions),
                sessionStore = sessionStore,
                scope = viewLifecycleOwner.lifecycleScope,
                includeGroups = true,
                topicId = topicId.takeIf { it > 0u },
            ).attach()
            draftAutosave = ComposerDraftAutosave(
                scope = viewLifecycleOwner.lifecycleScope,
                saveDraft = { persistDraftIfNeeded() },
                onSaveFailed = { error ->
                    FireErrorReporter.report(
                        operation = "reply_composer.draft_autosave",
                        error = error,
                        sessionStore = sessionStore,
                    )
                },
            ).also { autosave ->
                autosave.attach(bodyInput)
            }

            baseUrl = runCatching { sessionStore.snapshot().bootstrap.baseUrl }
                .getOrNull()
                ?.ifBlank { "https://linux.do" }
                ?: "https://linux.do"
            restoreDraftIfAvailable()
            draftAutosave?.start()

            uploadButton.setOnClickListener {
                imagePicker.launch("image/*")
            }
            previewButton.setOnClickListener {
                previewMode = !previewMode
                updatePreviewMode()
            }

            submitButton.setOnClickListener {
                val body = bodyInput.text.toString()
                if (body.length < 5) {
                    bodyInput.error = getString(R.string.topic_detail_reply_min_length, "5")
                    return@setOnClickListener
                }
                viewModel?.submitReply(topicId, body, replyToPostNumber)
            }

            viewModel?.let { vm ->
                launch {
                vm.isSubmitting.collectLatest { submitting ->
                    progressBar.visibility = if (submitting) View.VISIBLE else View.GONE
                    submitButton.isEnabled = !submitting
                }
            }
                launch {
                vm.result.collectLatest { result ->
                    if (result != null) {
                        didSubmit = true
                        draftAutosave?.cancel()
                        deleteDraftIfNeeded()
                        onReplySubmitted?.invoke()
                        dismiss()
                    }
                }
            }
                launch {
                vm.error.collectLatest { error ->
                    if (error != null) {
                        Toast.makeText(
                            requireContext(),
                            error.ifBlank { getString(R.string.topic_detail_reply_error) },
                            Toast.LENGTH_SHORT,
                        ).show()
                    }
                }
            }
            }
        }
    }

    override fun onStop() {
        if (!didSubmit) {
            draftAutosave?.flush()
        }
        super.onStop()
    }

    private fun updatePreviewMode() {
        bodyInput.visibility = if (previewMode) View.GONE else View.VISIBLE
        view?.findViewById<LinearLayout>(R.id.reply_mention_suggestions)?.visibility = View.GONE
        previewContainer.visibility = if (previewMode) View.VISIBLE else View.GONE
        previewButton.text = getString(
            if (previewMode) R.string.composer_continue_editing else R.string.composer_preview,
        )
        if (previewMode) {
            previewRenderer.render(
                ComposerPreviewContent(
                    body = bodyInput.text.toString(),
                    baseUrl = baseUrl,
                ),
            )
        }
    }

    private fun uploadImage(uri: Uri) {
        viewLifecycleOwner.lifecycleScope.launch {
            progressBar.visibility = View.VISIBLE
            uploadButton.isEnabled = false
            try {
                val markdown = uploadImageMarkdown(requireContext(), sessionStore, uri)
                insertMarkdownAtCursor(bodyInput, markdown)
            } catch (e: Exception) {
                Toast.makeText(
                    requireContext(),
                    e.localizedMessage ?: getString(R.string.composer_upload_error),
                    Toast.LENGTH_SHORT,
                ).show()
            } finally {
                progressBar.visibility = View.GONE
                uploadButton.isEnabled = true
            }
        }
    }

    private suspend fun restoreDraftIfAvailable() {
        val draft = runCatching { sessionStore.fetchDraft(draftKey()) }.getOrNull() ?: return
        draftSequence = draft.sequence
        draft.data.reply?.let { bodyInput.setText(it) }
        Toast.makeText(requireContext(), R.string.composer_draft_restored, Toast.LENGTH_SHORT).show()
    }

    private suspend fun persistDraftIfNeeded() {
        if (didSubmit) return
        if (bodyInput.text.isBlank()) {
            deleteDraftIfNeeded()
            return
        }
        draftSequence = sessionStore.saveDraft(
            draftKey(),
            DraftDataState(
                reply = bodyInput.text.toString(),
                title = null,
                categoryId = null,
                tags = emptyList(),
                replyToPostNumber = replyToPostNumber,
                action = "reply",
                recipients = emptyList(),
                archetypeId = null,
                composerTime = null,
                typingTime = null,
            ),
            draftSequence,
        )
    }

    private suspend fun deleteDraftIfNeeded() {
        if (draftSequence == 0u) return
        runCatching { sessionStore.deleteDraft(draftKey(), draftSequence) }
        draftSequence = 0u
    }

    private fun draftKey(): String {
        val postNumber = replyToPostNumber
        return if (postNumber != null && postNumber > 0u) {
            "topic_${topicId}_post_$postNumber"
        } else {
            "topic_$topicId"
        }
    }

    override fun onCreateDialog(savedInstanceState: Bundle?): Dialog {
        return super.onCreateDialog(savedInstanceState).apply {
            setOnShowListener {
                // Expand the bottom sheet
            }
        }
    }

    companion object {
        private const val ARG_TOPIC_ID = "topic_id"
        private const val ARG_REPLY_TO_POST_NUMBER = "reply_to_post_number"

        fun newInstance(
            topicId: Long,
            replyToPostNumber: Int? = null,
            onReplySubmitted: (() -> Unit)? = null,
        ): ReplyComposerSheet {
            return ReplyComposerSheet().apply {
                arguments = Bundle().apply {
                    putLong(ARG_TOPIC_ID, topicId)
                    replyToPostNumber?.let { putInt(ARG_REPLY_TO_POST_NUMBER, it) }
                }
                this.onReplySubmitted = onReplySubmitted
            }
        }
    }
}
