package com.fire.app.ui.composer

import android.app.Dialog
import android.os.Bundle
import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import android.widget.EditText
import android.widget.ProgressBar
import android.widget.TextView
import android.widget.Toast
import androidx.lifecycle.lifecycleScope
import com.fire.app.R
import com.fire.app.session.FireSessionStoreRepository
import com.google.android.material.bottomsheet.BottomSheetDialogFragment
import kotlinx.coroutines.flow.collectLatest
import kotlinx.coroutines.launch

class ReplyComposerSheet : BottomSheetDialogFragment() {

    private var topicId: ULong = 0u
    private var replyToPostNumber: UInt? = null
    private var onReplySubmitted: (() -> Unit)? = null

    private lateinit var bodyInput: EditText
    private lateinit var submitButton: TextView
    private lateinit var progressBar: ProgressBar
    private var viewModel: ComposerViewModel? = null

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
        progressBar = view.findViewById(R.id.reply_progress)

        val sessionStore = FireSessionStoreRepository.get(requireContext())
        viewModel = ComposerViewModel.create(sessionStore)

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

        submitButton.setOnClickListener {
            val body = bodyInput.text.toString()
            if (body.length < 5) {
                bodyInput.error = getString(R.string.topic_detail_reply_min_length, "5")
                return@setOnClickListener
            }
            viewModel?.submitReply(topicId, body, replyToPostNumber)
        }

        viewModel?.let { vm ->
            viewLifecycleOwner.lifecycleScope.launch {
                vm.isSubmitting.collectLatest { submitting ->
                    progressBar.visibility = if (submitting) View.VISIBLE else View.GONE
                    submitButton.isEnabled = !submitting
                }
            }
            viewLifecycleOwner.lifecycleScope.launch {
                vm.result.collectLatest { result ->
                    if (result != null) {
                        onReplySubmitted?.invoke()
                        dismiss()
                    }
                }
            }
            viewLifecycleOwner.lifecycleScope.launch {
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
