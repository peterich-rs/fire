package com.fire.app.ui.composer

import android.app.Dialog
import android.os.Bundle
import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import android.widget.EditText
import android.widget.ProgressBar
import android.widget.TextView
import com.fire.app.R
import com.fire.app.session.FireSessionStoreRepository
import com.google.android.material.bottomsheet.BottomSheetDialogFragment

class TopicComposerSheet : BottomSheetDialogFragment() {

    private lateinit var titleInput: EditText
    private lateinit var bodyInput: EditText
    private lateinit var tagsInput: EditText
    private lateinit var submitButton: TextView
    private lateinit var progressBar: ProgressBar
    private var viewModel: ComposerViewModel? = null

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
        tagsInput = view.findViewById(R.id.topic_tags_input)
        submitButton = view.findViewById(R.id.topic_submit_button)
        progressBar = view.findViewById(R.id.topic_progress)

        val sessionStore = FireSessionStoreRepository.get(requireContext())
        viewModel = ComposerViewModel.create(sessionStore)

        submitButton.setOnClickListener {
            val title = titleInput.text.toString()
            val body = bodyInput.text.toString()
            val tags = tagsInput.text.toString()
                .split("[,\\s]+".toRegex())
                .filter { it.isNotBlank() }

            if (title.length < 5) {
                titleInput.error = getString(R.string.create_topic_title_min_length, "5")
                return@setOnClickListener
            }
            if (body.length < 5) {
                bodyInput.error = getString(R.string.create_topic_body_min_length, "5")
                return@setOnClickListener
            }

            viewModel?.submitTopic(title, body, null, tags)
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
