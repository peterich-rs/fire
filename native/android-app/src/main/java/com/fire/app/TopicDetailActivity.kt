package com.fire.app

import android.content.Context
import android.content.Intent
import android.os.Bundle
import android.text.method.LinkMovementMethod
import android.view.View
import android.view.ViewGroup
import android.widget.LinearLayout
import android.widget.TextView
import androidx.appcompat.app.AppCompatActivity
import androidx.core.text.HtmlCompat
import androidx.lifecycle.lifecycleScope
import com.fire.app.databinding.ActivityTopicDetailBinding
import com.fire.app.session.FireSessionStore
import com.fire.app.session.FireSessionStoreRepository
import kotlinx.coroutines.launch
import uniffi.fire_uniffi.TopicDetailQueryState
import uniffi.fire_uniffi.TopicDetailState
import uniffi.fire_uniffi.TopicPostState

class TopicDetailActivity : AppCompatActivity() {
    private lateinit var binding: ActivityTopicDetailBinding
    private lateinit var sessionStore: FireSessionStore

    private var topicId: ULong = 0uL
    private var topicTitle: String = ""
    private var topicCategories: Map<ULong, TopicCategoryPresentation> = emptyMap()

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        binding = ActivityTopicDetailBinding.inflate(layoutInflater)
        setContentView(binding.root)

        topicId = intent.getLongExtra(EXTRA_TOPIC_ID, -1L).takeIf { it > 0 }?.toULong() ?: 0uL
        topicTitle = intent.getStringExtra(EXTRA_TOPIC_TITLE).orEmpty()
        if (topicId == 0uL) {
            finish()
            return
        }

        sessionStore = FireSessionStoreRepository.get(applicationContext)

        binding.backButton.setOnClickListener { finish() }
        binding.refreshButton.setOnClickListener { loadTopicDetail(force = true) }
        binding.pageTitleText.text = topicTitle.ifBlank { getString(R.string.topic_detail_title_fallback, topicId.toString()) }

        loadTopicDetail()
    }

    private fun loadTopicDetail(force: Boolean = false) {
        lifecycleScope.launch {
            setLoading(true)
            binding.errorText.visibility = View.GONE

            try {
                val restored = sessionStore.restorePersistedSessionIfAvailable() ?: sessionStore.snapshot()
                topicCategories = TopicPresentation.parseCategories(restored.bootstrap.preloadedJson)

                val detail = sessionStore.fetchTopicDetail(
                    TopicDetailQueryState(
                        topicId = topicId,
                        postNumber = null,
                        trackVisit = !force,
                        filter = null,
                        usernameFilters = null,
                        filterTopLevelReplies = false,
                    ),
                )
                renderDetail(detail)
            } catch (error: Exception) {
                binding.pageMetaText.text = getString(R.string.topic_detail_error)
                binding.postsContainer.removeAllViews()
                binding.errorText.text = error.localizedMessage ?: getString(R.string.topic_detail_error)
                binding.errorText.visibility = View.VISIBLE
            } finally {
                setLoading(false)
            }
        }
    }

    private fun renderDetail(detail: TopicDetailState) {
        val tagNames = TopicPresentation.tagNames(detail.tags)
        binding.pageTitleText.text = detail.title
        binding.pageMetaText.text = buildList {
            add(getString(R.string.topic_detail_topic_number, detail.id.toString()))
            categoryLabelFor(detail.categoryId)?.let(::add)
            detail.details.createdBy?.username?.let(::add)
            TopicPresentation.formatTimestamp(detail.createdAt)?.let(::add)
            add(getString(R.string.topic_detail_posts_count, detail.postsCount.toString()))
            add(getString(R.string.topic_detail_views_count, detail.views.toString()))
            add(getString(R.string.topic_detail_likes_count, detail.likeCount.toString()))
            detail.lastReadPostNumber?.let { add(getString(R.string.topic_detail_last_read, it.toString())) }
            if (tagNames.isNotEmpty()) {
                add("#${tagNames.joinToString(" #")}")
            }
        }.joinToString(" · ")

        binding.postsContainer.removeAllViews()
        if (detail.postStream.posts.isEmpty()) {
            binding.postsContainer.addView(sectionBodyText(getString(R.string.topic_detail_empty_posts)))
            return
        }

        detail.postStream.posts.forEachIndexed { index, post ->
            binding.postsContainer.addView(postView(post, index == 0))
        }
    }

    private fun postView(post: TopicPostState, isFirstPost: Boolean): View {
        return LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(dp(16), dp(if (isFirstPost) 0 else 14), dp(16), dp(16))
            layoutParams = LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.WRAP_CONTENT,
            ).apply {
                topMargin = if (isFirstPost) 0 else dp(12)
            }
            setBackgroundResource(android.R.color.transparent)

            addView(
                TextView(context).apply {
                    text = post.username
                    textSize = 16f
                    setTypeface(typeface, android.graphics.Typeface.BOLD)
                },
            )

            addView(
                TextView(context).apply {
                    text = buildList {
                        add("#${post.postNumber}")
                        TopicPresentation.formatTimestamp(post.createdAt)?.let(::add)
                        add(getString(R.string.topic_detail_likes_count, post.likeCount.toString()))
                        if (post.replyCount > 0u) {
                            add(getString(R.string.topic_detail_replies_count, post.replyCount.toString()))
                        }
                        post.replyToPostNumber?.let { add(getString(R.string.topic_detail_reply_to, it.toString())) }
                    }.joinToString(" · ")
                    textSize = 12f
                    setPadding(0, dp(4), 0, 0)
                },
            )

            addView(
                TextView(context).apply {
                    text = HtmlCompat.fromHtml(post.cooked, HtmlCompat.FROM_HTML_MODE_LEGACY)
                    textSize = 15f
                    setPadding(0, dp(8), 0, 0)
                    movementMethod = LinkMovementMethod.getInstance()
                    linksClickable = true
                },
            )
        }
    }

    private fun sectionBodyText(text: String): TextView {
        return TextView(this).apply {
            this.text = text
            textSize = 14f
            setPadding(dp(16), dp(6), dp(16), dp(16))
        }
    }

    private fun categoryLabelFor(categoryId: ULong?): String? {
        val id = categoryId ?: return null
        return topicCategories[id]?.displayName ?: getString(R.string.topic_detail_category_fallback, id.toString())
    }

    private fun setLoading(loading: Boolean) {
        binding.loadingIndicator.visibility = if (loading) View.VISIBLE else View.GONE
        binding.refreshButton.isEnabled = !loading
    }

    private fun dp(value: Int): Int {
        return (value * resources.displayMetrics.density).toInt()
    }

    companion object {
        private const val EXTRA_TOPIC_ID = "topic_id"
        private const val EXTRA_TOPIC_TITLE = "topic_title"

        fun intent(context: Context, topicId: ULong, topicTitle: String): Intent {
            return Intent(context, TopicDetailActivity::class.java).apply {
                putExtra(EXTRA_TOPIC_ID, topicId.toLong())
                putExtra(EXTRA_TOPIC_TITLE, topicTitle)
            }
        }
    }
}
