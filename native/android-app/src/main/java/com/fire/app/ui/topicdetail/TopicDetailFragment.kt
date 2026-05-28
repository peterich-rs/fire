package com.fire.app.ui.topicdetail

import android.os.Bundle
import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import androidx.fragment.app.Fragment
import androidx.navigation.fragment.navArgs
import com.fire.app.R

class TopicDetailFragment : Fragment() {

    private val args: TopicDetailFragmentArgs by navArgs()

    override fun onCreateView(
        inflater: LayoutInflater,
        container: ViewGroup?,
        savedInstanceState: Bundle?,
    ): View? {
        return inflater.inflate(R.layout.fragment_topic_detail, container, false)
    }

    override fun onViewCreated(view: View, savedInstanceState: Bundle?) {
        super.onViewCreated(view, savedInstanceState)
        val topicId = args.topicId
        val topicTitle = args.topicTitle ?: getString(R.string.topic_detail_title_fallback, topicId)
        requireActivity().title = topicTitle
    }
}
