package com.fire.app.ui.composer

import android.net.Uri
import android.os.Bundle
import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import android.widget.ArrayAdapter
import android.widget.EditText
import android.widget.LinearLayout
import android.widget.ProgressBar
import android.widget.Spinner
import android.widget.TextView
import androidx.activity.result.contract.ActivityResultContracts
import androidx.lifecycle.lifecycleScope
import com.fire.app.R
import com.fire.app.core.error.FireErrorReporter
import com.fire.app.core.ui.FireToast
import com.fire.app.displayName
import com.fire.app.session.FireSessionStore
import com.fire.app.session.FireSessionStoreRepository
import com.google.android.material.bottomsheet.BottomSheetDialogFragment
import kotlinx.coroutines.flow.collectLatest
import kotlinx.coroutines.launch
import uniffi.fire_uniffi_session.TopicCategoryState
import uniffi.fire_uniffi_types.DraftDataState

class TopicComposerSheet : BottomSheetDialogFragment() {

    private lateinit var titleInput: EditText
    private lateinit var bodyInput: EditText
    private lateinit var markdownToolbar: MarkdownToolbarView
    private lateinit var categorySpinner: Spinner
    private lateinit var categoryLabel: TextView
    private lateinit var tagsInput: EditText
    private lateinit var submitButton: TextView
    private lateinit var uploadButton: TextView
    private lateinit var previewButton: TextView
    private lateinit var previewContainer: LinearLayout
    private lateinit var progressBar: ProgressBar
    private lateinit var sessionStore: FireSessionStore
    private var viewModel: ComposerViewModel? = null
    private var categories: List<TopicCategoryState> = emptyList()
    private var canCreateTopic: Boolean = false
    private var minTitleLength: Int = 5
    private var minBodyLength: Int = 5
    private var draftSequence: UInt = 0u
    private var didSubmit = false
    private var draftAutosave: ComposerDraftAutosave? = null
    private lateinit var previewRenderer: ComposerPreviewRenderer
    private var previewMode = false
    private var baseUrl = "https://linux.do"

    private var onTopicCreated: ((ULong) -> Unit)? = null

    private val imagePicker = registerForActivityResult(ActivityResultContracts.GetContent()) { uri ->
        uri?.let(::uploadImage)
    }

    override fun onCreateView(
        inflater: LayoutInflater,
        container: ViewGroup?,
        savedInstanceState: Bundle?,
    ): View? {
        return inflater.inflate(R.layout.sheet_topic_composer, container, false)
    }

    override fun onViewCreated(view: View, savedInstanceState: Bundle?) {
        super.onViewCreated(view, savedInstanceState)

        titleInput = view.findViewById(R.id.topic_title_input)
        bodyInput = view.findViewById(R.id.topic_body_input)
        markdownToolbar = view.findViewById(R.id.topic_markdown_toolbar)
        categorySpinner = view.findViewById(R.id.topic_category_spinner)
        categoryLabel = view.findViewById(R.id.topic_category_label)
        tagsInput = view.findViewById(R.id.topic_tags_input)
        submitButton = view.findViewById(R.id.topic_submit_button)
        uploadButton = view.findViewById(R.id.topic_upload_button)
        previewButton = view.findViewById(R.id.topic_preview_button)
        previewContainer = view.findViewById(R.id.topic_preview_container)
        progressBar = view.findViewById(R.id.topic_progress)

        viewLifecycleOwner.lifecycleScope.launch {
            sessionStore = FireSessionStoreRepository.get(requireContext())
            viewModel = ComposerViewModel.create(sessionStore)
            previewRenderer = ComposerPreviewRenderer(
                previewContainer,
                sessionStore,
                viewLifecycleOwner.lifecycleScope,
            )
            markdownToolbar.bind(bodyInput)

            ComposerMentionAssist(
                input = bodyInput,
                suggestions = view.findViewById(R.id.topic_mention_suggestions),
                sessionStore = sessionStore,
                scope = viewLifecycleOwner.lifecycleScope,
                includeGroups = true,
                categoryIdProvider = { categories.getOrNull(categorySpinner.selectedItemPosition)?.id },
            ).attach()
            ComposerTagAssist(
                input = tagsInput,
                suggestions = view.findViewById(R.id.topic_tag_suggestions),
                sessionStore = sessionStore,
                scope = viewLifecycleOwner.lifecycleScope,
                categoryIdProvider = { categories.getOrNull(categorySpinner.selectedItemPosition)?.id },
                selectedTagsProvider = { tagValues() },
            ).attach()
            draftAutosave = ComposerDraftAutosave(
                scope = viewLifecycleOwner.lifecycleScope,
                saveDraft = { persistDraftIfNeeded() },
                onSaveFailed = { error ->
                    FireErrorReporter.report(
                        operation = "topic_composer.draft_autosave",
                        error = error,
                        sessionStore = sessionStore,
                    )
                },
            ).also { autosave ->
                autosave.attach(titleInput, bodyInput, tagsInput)
            }

            val session = sessionStore.snapshot()
            baseUrl = session.bootstrap.baseUrl.ifBlank { "https://linux.do" }
            minTitleLength = session.bootstrap.minTopicTitleLength.toInt().coerceAtLeast(1)
            minBodyLength = session.bootstrap.minFirstPostLength.toInt().coerceAtLeast(1)
            categories = session.bootstrap.categories
                .filter { category -> category.permission?.toInt()?.let { it <= 1 } ?: true }
            val categoryNames = categories.map { it.displayName() }
            categorySpinner.adapter = ArrayAdapter(
                requireContext(),
                android.R.layout.simple_spinner_item,
                categoryNames,
            ).apply {
                setDropDownViewResource(android.R.layout.simple_spinner_dropdown_item)
            }
            val defaultIndex = categories.indexOfFirst {
                it.id == session.bootstrap.defaultComposerCategory
            }
            if (defaultIndex >= 0) {
                categorySpinner.setSelection(defaultIndex)
            }
            canCreateTopic = session.readiness.canWriteAuthenticatedApi && categories.isNotEmpty()
            categorySpinner.isEnabled = canCreateTopic
            submitButton.isEnabled = canCreateTopic
            if (!canCreateTopic && categories.isEmpty()) {
                showToast(getString(R.string.create_topic_no_categories), FireToast.Style.WARNING)
            } else if (!canCreateTopic) {
                showToast(getString(R.string.create_topic_login_required), FireToast.Style.WARNING)
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
                val title = titleInput.text.toString()
                val body = bodyInput.text.toString()
                val tags = tagValues()
                val category = categories.getOrNull(categorySpinner.selectedItemPosition)

                if (title.length < minTitleLength) {
                    titleInput.error = getString(
                        R.string.create_topic_title_min_length,
                        minTitleLength.toString(),
                    )
                    return@setOnClickListener
                }
                if (body.length < minBodyLength) {
                    bodyInput.error = getString(
                        R.string.create_topic_body_min_length,
                        minBodyLength.toString(),
                    )
                    return@setOnClickListener
                }
                if (category == null) {
                    showToast(getString(R.string.create_topic_no_categories), FireToast.Style.WARNING)
                    return@setOnClickListener
                }
                if (tags.size < category.minimumRequiredTags.toInt()) {
                    tagsInput.error = getString(
                        R.string.create_topic_tags_required,
                        category.minimumRequiredTags.toString(),
                    )
                    return@setOnClickListener
                }
                val disallowedTags = if (category.allowedTags.isEmpty()) {
                    emptyList()
                } else {
                    tags.filterNot { tag -> category.allowedTags.contains(tag) }
                }
                if (disallowedTags.isNotEmpty()) {
                    tagsInput.error = getString(
                        R.string.create_topic_tags_not_allowed,
                        disallowedTags.joinToString(", "),
                    )
                    return@setOnClickListener
                }

                viewModel?.submitTopic(title, body, category.id, tags)
            }

            viewModel?.let { vm ->
                launch {
                vm.isSubmitting.collectLatest { submitting ->
                    progressBar.visibility = if (submitting) View.VISIBLE else View.GONE
                    submitButton.isEnabled = !submitting && canCreateTopic
                }
            }
                launch {
                vm.topicCreated.collectLatest { topicId ->
                    if (topicId != null) {
                        didSubmit = true
                        draftAutosave?.cancel()
                        deleteDraftIfNeeded()
                        onTopicCreated?.invoke(topicId)
                        dismiss()
                    }
                }
            }
                launch {
                vm.error.collectLatest { error ->
                    if (error != null) {
                        showToast(
                            error.ifBlank { getString(R.string.create_topic_error) },
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
        titleInput.visibility = editorVisibility
        bodyInput.visibility = editorVisibility
        markdownToolbar.visibility = editorVisibility
        categoryLabel.visibility = editorVisibility
        categorySpinner.visibility = editorVisibility
        tagsInput.visibility = editorVisibility
        view?.findViewById<LinearLayout>(R.id.topic_mention_suggestions)?.visibility = View.GONE
        view?.findViewById<LinearLayout>(R.id.topic_tag_suggestions)?.visibility = View.GONE
        previewContainer.visibility = if (previewMode) View.VISIBLE else View.GONE
        previewButton.text = getString(
            if (previewMode) R.string.composer_continue_editing else R.string.composer_preview,
        )
        if (previewMode) {
            val category = categories.getOrNull(categorySpinner.selectedItemPosition)
            previewRenderer.render(
                ComposerPreviewContent(
                    title = titleInput.text.toString()
                        .trim()
                        .ifBlank { getString(R.string.composer_preview_no_title) },
                    categoryName = category?.displayName(),
                    tags = tagValues(),
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

    private fun tagValues(): List<String> =
        tagsInput.text.toString()
            .split("[,\\s]+".toRegex())
            .filter { it.isNotBlank() }

    private suspend fun restoreDraftIfAvailable() {
        val draft = runCatching { sessionStore.fetchDraft(DRAFT_KEY) }.getOrNull() ?: return
        draftSequence = draft.sequence
        draft.data.title?.let { titleInput.setText(it) }
        draft.data.reply?.let { bodyInput.setText(it) }
        draft.data.categoryId?.let { categoryId ->
            val index = categories.indexOfFirst { it.id == categoryId }
            if (index >= 0) {
                categorySpinner.setSelection(index)
            }
        }
        if (draft.data.tags.isNotEmpty()) {
            tagsInput.setText(draft.data.tags.joinToString(" "))
        }
        showToast(getString(R.string.composer_draft_restored), FireToast.Style.INFO)
    }

    private fun showToast(message: String, style: FireToast.Style) {
        FireToast.show(view ?: return, message, style)
    }

    private suspend fun persistDraftIfNeeded() {
        if (didSubmit) return
        val hasContent = titleInput.text.isNotBlank() ||
            bodyInput.text.isNotBlank() ||
            tagValues().isNotEmpty()
        if (!hasContent) {
            deleteDraftIfNeeded()
            return
        }
        val category = categories.getOrNull(categorySpinner.selectedItemPosition)
        draftSequence = sessionStore.saveDraft(
            DRAFT_KEY,
            DraftDataState(
                reply = bodyInput.text.toString(),
                title = titleInput.text.toString(),
                categoryId = category?.id,
                tags = tagValues(),
                replyToPostNumber = null,
                action = "create_topic",
                recipients = emptyList(),
                archetypeId = "regular",
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

    companion object {
        private const val DRAFT_KEY = "new_topic"

        fun newInstance(onTopicCreated: ((ULong) -> Unit)? = null): TopicComposerSheet {
            return TopicComposerSheet().apply {
                this.onTopicCreated = onTopicCreated
            }
        }
    }
}
