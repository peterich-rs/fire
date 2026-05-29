package com.fire.app.ui.composer

import android.os.Bundle
import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import android.widget.ArrayAdapter
import android.widget.EditText
import android.widget.ProgressBar
import android.widget.Spinner
import android.widget.TextView
import android.widget.Toast
import androidx.lifecycle.lifecycleScope
import com.fire.app.R
import com.fire.app.displayName
import com.fire.app.session.FireSessionStoreRepository
import com.google.android.material.bottomsheet.BottomSheetDialogFragment
import kotlinx.coroutines.flow.collectLatest
import kotlinx.coroutines.launch
import uniffi.fire_uniffi_session.TopicCategoryState

class TopicComposerSheet : BottomSheetDialogFragment() {

    private lateinit var titleInput: EditText
    private lateinit var bodyInput: EditText
    private lateinit var categorySpinner: Spinner
    private lateinit var tagsInput: EditText
    private lateinit var submitButton: TextView
    private lateinit var progressBar: ProgressBar
    private var viewModel: ComposerViewModel? = null
    private var categories: List<TopicCategoryState> = emptyList()
    private var canCreateTopic: Boolean = false
    private var minTitleLength: Int = 5
    private var minBodyLength: Int = 5

    private var onTopicCreated: ((ULong) -> Unit)? = null

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
        categorySpinner = view.findViewById(R.id.topic_category_spinner)
        tagsInput = view.findViewById(R.id.topic_tags_input)
        submitButton = view.findViewById(R.id.topic_submit_button)
        progressBar = view.findViewById(R.id.topic_progress)

        val sessionStore = FireSessionStoreRepository.get(requireContext())
        viewModel = ComposerViewModel.create(sessionStore)

        viewLifecycleOwner.lifecycleScope.launch {
            val session = sessionStore.snapshot()
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
                Toast.makeText(
                    requireContext(),
                    R.string.create_topic_no_categories,
                    Toast.LENGTH_SHORT,
                ).show()
            } else if (!canCreateTopic) {
                Toast.makeText(
                    requireContext(),
                    R.string.create_topic_login_required,
                    Toast.LENGTH_SHORT,
                ).show()
            }
        }

        submitButton.setOnClickListener {
            val title = titleInput.text.toString()
            val body = bodyInput.text.toString()
            val tags = tagsInput.text.toString()
                .split("[,\\s]+".toRegex())
                .filter { it.isNotBlank() }
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
                Toast.makeText(requireContext(), R.string.create_topic_no_categories, Toast.LENGTH_SHORT).show()
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
            viewLifecycleOwner.lifecycleScope.launch {
                vm.isSubmitting.collectLatest { submitting ->
                    progressBar.visibility = if (submitting) View.VISIBLE else View.GONE
                    submitButton.isEnabled = !submitting && canCreateTopic
                }
            }
            viewLifecycleOwner.lifecycleScope.launch {
                vm.topicCreated.collectLatest { topicId ->
                    if (topicId != null) {
                        onTopicCreated?.invoke(topicId)
                        dismiss()
                    }
                }
            }
            viewLifecycleOwner.lifecycleScope.launch {
                vm.error.collectLatest { error ->
                    if (error != null) {
                        Toast.makeText(
                            requireContext(),
                            error.ifBlank { getString(R.string.create_topic_error) },
                            Toast.LENGTH_SHORT,
                        ).show()
                    }
                }
            }
        }
    }

    companion object {
        fun newInstance(onTopicCreated: ((ULong) -> Unit)? = null): TopicComposerSheet {
            return TopicComposerSheet().apply {
                this.onTopicCreated = onTopicCreated
            }
        }
    }
}
