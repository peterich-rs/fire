package com.fire.app.ui.composer

import android.net.Uri
import android.os.Bundle
import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import android.widget.EditText
import android.widget.LinearLayout
import android.widget.ProgressBar
import android.widget.TextView
import androidx.activity.result.contract.ActivityResultContracts
import androidx.lifecycle.lifecycleScope
import com.fire.app.R
import com.fire.app.core.error.FireErrorReporter
import com.fire.app.core.ui.FireToast
import com.fire.app.session.FireSessionStore
import com.fire.app.session.FireSessionStoreRepository
import com.google.android.material.bottomsheet.BottomSheetDialogFragment
import com.google.android.material.chip.ChipGroup
import kotlinx.coroutines.flow.collectLatest
import kotlinx.coroutines.launch
import uniffi.fire_uniffi_types.DraftDataState

class PrivateMessageComposerSheet : BottomSheetDialogFragment() {

    private lateinit var titleInput: EditText
    private lateinit var recipientInput: EditText
    private lateinit var recipientTokens: ChipGroup
    private lateinit var bodyInput: EditText
    private lateinit var markdownToolbar: MarkdownToolbarView
    private lateinit var submitButton: TextView
    private lateinit var uploadButton: TextView
    private lateinit var previewButton: TextView
    private lateinit var previewContainer: LinearLayout
    private lateinit var progressBar: ProgressBar
    private lateinit var sessionStore: FireSessionStore
    private var viewModel: ComposerViewModel? = null

    private var targetUsername: String = ""
    private var displayName: String = ""
    private var canSendMessage: Boolean = false
    private var minTitleLength: Int = 1
    private var minBodyLength: Int = 1
    private var onPrivateMessageCreated: ((ULong, String) -> Unit)? = null
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
        return inflater.inflate(R.layout.sheet_private_message_composer, container, false)
    }

    override fun onViewCreated(view: View, savedInstanceState: Bundle?) {
        super.onViewCreated(view, savedInstanceState)

        titleInput = view.findViewById(R.id.private_message_title_input)
        recipientInput = view.findViewById(R.id.private_message_recipient_input)
        recipientTokens = view.findViewById(R.id.private_message_recipient_tokens)
        bodyInput = view.findViewById(R.id.private_message_body_input)
        markdownToolbar = view.findViewById(R.id.private_message_markdown_toolbar)
        submitButton = view.findViewById(R.id.private_message_submit_button)
        uploadButton = view.findViewById(R.id.private_message_upload_button)
        previewButton = view.findViewById(R.id.private_message_preview_button)
        previewContainer = view.findViewById(R.id.private_message_preview_container)
        progressBar = view.findViewById(R.id.private_message_progress)

        arguments?.let { args ->
            targetUsername = args.getString(ARG_TARGET_USERNAME).orEmpty()
            displayName = args.getString(ARG_DISPLAY_NAME).orEmpty().ifBlank { targetUsername }
        }

        view.findViewById<TextView>(R.id.private_message_title).text =
            if (targetUsername.isBlank()) {
                getString(R.string.profile_private_message_new_title)
            } else {
                getString(R.string.profile_private_message_title, displayName.ifBlank { targetUsername })
            }
        recipientInput.setText(targetUsername)

        viewLifecycleOwner.lifecycleScope.launch {
            sessionStore = FireSessionStoreRepository.get(requireContext())
            viewModel = ComposerViewModel.create(sessionStore)
            previewRenderer = ComposerPreviewRenderer(
                previewContainer,
                sessionStore,
                viewLifecycleOwner.lifecycleScope,
            )
            markdownToolbar.bind(bodyInput)

            ComposerRecipientAssist(
                input = recipientInput,
                suggestions = view.findViewById(R.id.private_message_recipient_suggestions),
                sessionStore = sessionStore,
                scope = viewLifecycleOwner.lifecycleScope,
            ).attach()
            ComposerRecipientTokenView(
                input = recipientInput,
                tokens = recipientTokens,
            ).attach()
            ComposerMentionAssist(
                input = bodyInput,
                suggestions = view.findViewById(R.id.private_message_mention_suggestions),
                sessionStore = sessionStore,
                scope = viewLifecycleOwner.lifecycleScope,
                includeGroups = false,
            ).attach()
            draftAutosave = ComposerDraftAutosave(
                scope = viewLifecycleOwner.lifecycleScope,
                saveDraft = { persistDraftIfNeeded() },
                onSaveFailed = { error ->
                    FireErrorReporter.report(
                        operation = "private_message_composer.draft_autosave",
                        error = error,
                        sessionStore = sessionStore,
                    )
                },
            ).also { autosave ->
                autosave.attach(titleInput, recipientInput, bodyInput)
            }

            runCatching { sessionStore.snapshot() }
                .onSuccess { session ->
                    baseUrl = session.bootstrap.baseUrl.ifBlank { "https://linux.do" }
                    minTitleLength = session.bootstrap.minPersonalMessageTitleLength.toInt().coerceAtLeast(1)
                    minBodyLength = session.bootstrap.minPersonalMessagePostLength.toInt().coerceAtLeast(1)
                    canSendMessage = session.readiness.canWriteAuthenticatedApi
                    submitButton.isEnabled = canSendMessage
                    if (!canSendMessage) {
                        showToast(
                            getString(R.string.profile_private_message_login_required),
                            FireToast.Style.WARNING,
                        )
                    }
                }
                .onFailure {
                    canSendMessage = false
                    submitButton.isEnabled = false
                    showToast(getString(R.string.profile_private_message_error), FireToast.Style.ERROR)
                }
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
                val title = titleInput.text.toString().trim()
                val recipients = recipientValues()
                val body = bodyInput.text.toString().trim()
                if (recipients.isEmpty()) {
                    recipientInput.error = getString(R.string.profile_private_message_recipient_required)
                    return@setOnClickListener
                }
                if (title.length < minTitleLength) {
                    titleInput.error = getString(
                        R.string.profile_private_message_title_min_length,
                        minTitleLength.toString(),
                    )
                    return@setOnClickListener
                }
                if (body.length < minBodyLength) {
                    bodyInput.error = getString(
                        R.string.profile_private_message_body_min_length,
                        minBodyLength.toString(),
                    )
                    return@setOnClickListener
                }
                if (!canSendMessage) {
                    showToast(
                        getString(R.string.profile_private_message_login_required),
                        FireToast.Style.WARNING,
                    )
                    return@setOnClickListener
                }
                viewModel?.submitPrivateMessage(title, body, recipients)
            }

            viewModel?.let { vm ->
                launch {
                vm.isSubmitting.collectLatest { submitting ->
                    progressBar.visibility = if (submitting) View.VISIBLE else View.GONE
                    submitButton.isEnabled = !submitting && canSendMessage
                }
            }
                launch {
                vm.privateMessageCreated.collectLatest { topicId ->
                    if (topicId != null) {
                        didSubmit = true
                        draftAutosave?.cancel()
                        deleteDraftIfNeeded()
                        val title = titleInput.text.toString().trim()
                        onPrivateMessageCreated?.invoke(topicId, title)
                        dismiss()
                    }
                }
            }
                launch {
                vm.error.collectLatest { error ->
                    if (error != null) {
                        showToast(
                            error.ifBlank { getString(R.string.profile_private_message_error) },
                            FireToast.Style.ERROR,
                        )
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
        val editorVisibility = if (previewMode) View.GONE else View.VISIBLE
        recipientInput.visibility = editorVisibility
        recipientTokens.visibility = if (previewMode || recipientValues().isEmpty()) View.GONE else View.VISIBLE
        titleInput.visibility = editorVisibility
        bodyInput.visibility = editorVisibility
        markdownToolbar.visibility = editorVisibility
        view?.findViewById<LinearLayout>(R.id.private_message_recipient_suggestions)?.visibility = View.GONE
        view?.findViewById<LinearLayout>(R.id.private_message_mention_suggestions)?.visibility = View.GONE
        previewContainer.visibility = if (previewMode) View.VISIBLE else View.GONE
        previewButton.text = getString(
            if (previewMode) R.string.composer_continue_editing else R.string.composer_preview,
        )
        if (previewMode) {
            previewRenderer.render(
                ComposerPreviewContent(
                    title = titleInput.text.toString()
                        .trim()
                        .ifBlank { getString(R.string.composer_preview_no_title) },
                    recipients = recipientValues(),
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
                showToast(
                    e.localizedMessage ?: getString(R.string.composer_upload_error),
                    FireToast.Style.ERROR,
                )
            } finally {
                progressBar.visibility = View.GONE
                uploadButton.isEnabled = true
            }
        }
    }

    private fun recipientValues(): List<String> =
        recipientInput.text.toString()
            .split("[,\\s]+".toRegex())
            .map { it.trim().removePrefix("@") }
            .filter { it.isNotBlank() }
            .distinct()

    private suspend fun restoreDraftIfAvailable() {
        val draft = runCatching { sessionStore.fetchDraft(DRAFT_KEY) }.getOrNull() ?: return
        val draftRecipients = draft.data.recipients.normalizedRecipients()
        val explicitRecipients = listOf(targetUsername).normalizedRecipients()
        if (explicitRecipients.isNotEmpty() && draftRecipients != explicitRecipients) {
            return
        }

        draftSequence = draft.sequence
        draft.data.title?.let { titleInput.setText(it) }
        draft.data.reply?.let { bodyInput.setText(it) }
        if (draft.data.recipients.isNotEmpty()) {
            recipientInput.setText(draft.data.recipients.joinToString(" "))
        }
        showToast(getString(R.string.composer_draft_restored), FireToast.Style.INFO)
    }

    private fun showToast(message: String, style: FireToast.Style) {
        FireToast.show(view ?: return, message, style)
    }

    private suspend fun persistDraftIfNeeded() {
        if (didSubmit) return
        val recipients = recipientValues()
        val hasContent = titleInput.text.isNotBlank() ||
            bodyInput.text.isNotBlank() ||
            recipients.isNotEmpty()
        if (!hasContent) {
            deleteDraftIfNeeded()
            return
        }
        draftSequence = sessionStore.saveDraft(
            DRAFT_KEY,
            DraftDataState(
                reply = bodyInput.text.toString(),
                title = titleInput.text.toString(),
                categoryId = null,
                tags = emptyList(),
                replyToPostNumber = null,
                action = "private_message",
                recipients = recipients,
                archetypeId = "private_message",
                composerTime = null,
                typingTime = null,
            ),
            draftSequence,
        )
    }

    private suspend fun deleteDraftIfNeeded() {
        if (draftSequence == 0u) return
        runCatching { sessionStore.deleteDraft(DRAFT_KEY, draftSequence) }
        draftSequence = 0u
    }

    private fun List<String>.normalizedRecipients(): List<String> =
        map { it.trim().removePrefix("@").lowercase() }
            .filter { it.isNotBlank() }
            .distinct()

    companion object {
        private const val DRAFT_KEY = "new_private_message"
        private const val ARG_TARGET_USERNAME = "target_username"
        private const val ARG_DISPLAY_NAME = "display_name"

        fun newInstance(
            targetUsername: String,
            displayName: String?,
            onPrivateMessageCreated: ((ULong, String) -> Unit)? = null,
        ): PrivateMessageComposerSheet {
            return PrivateMessageComposerSheet().apply {
                arguments = Bundle().apply {
                    putString(ARG_TARGET_USERNAME, targetUsername)
                    putString(ARG_DISPLAY_NAME, displayName)
                }
                this.onPrivateMessageCreated = onPrivateMessageCreated
            }
        }
    }
}
