package com.fire.app

import android.content.Context
import android.content.Intent
import android.graphics.Color
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.os.Bundle
import android.view.View
import android.view.ViewGroup
import android.widget.LinearLayout
import android.widget.TextView
import androidx.appcompat.app.AppCompatActivity
import androidx.lifecycle.lifecycleScope
import com.fire.app.databinding.ActivityTopicDetailBinding
import com.fire.app.session.FireSessionStore
import com.fire.app.session.FireSessionStoreRepository
import kotlinx.coroutines.launch
import uniffi.fire_uniffi.plainTextFromHtml
import uniffi.fire_uniffi_session.TopicCategoryState
import uniffi.fire_uniffi_topics.TopicDetailQueryState
import uniffi.fire_uniffi_topics.TopicDetailState
import uniffi.fire_uniffi_topics.TopicPostState

class TopicDetailActivity : AppCompatActivity() {
    private lateinit var binding: ActivityTopicDetailBinding
    private lateinit var sessionStore: FireSessionStore

    private var topicId: ULong = 0uL
    private var topicTitle: String = ""
    private var topicCategories: Map<ULong, TopicCategoryState> = emptyMap()

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
                topicCategories = restored.bootstrap.categories.associateBy { it.id }

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

        detail.flatPosts.firstOrNull { it.isOriginalPost }?.post?.let { originalPost ->
            binding.postsContainer.addView(
                sectionCard(
                    title = getString(R.string.topic_detail_original_post),
                    subtitle = null,
                    accentColor = sectionAccentColor(),
                ) {
                    addView(
                        postCardView(
                            post = originalPost,
                            roleLabel = getString(R.string.topic_detail_original_post_badge),
                            depth = 0,
                            emphasized = true,
                        ),
                    )
                },
            )
        }

        val replyPosts = detail.flatPosts.filterNot { it.isOriginalPost }
        if (replyPosts.isEmpty()) {
            binding.postsContainer.addView(
                sectionBodyText(getString(R.string.topic_detail_no_replies)),
            )
            return
        }

        binding.postsContainer.addView(
            sectionCard(
                title = getString(R.string.topic_detail_replies_section),
                subtitle = getString(R.string.topic_detail_replies_count, replyPosts.size.toString()),
                accentColor = sectionAccentColor(alpha = 0x66),
            ) {
                replyPosts.forEach { flatPost ->
                    addView(
                        postCardView(
                            post = flatPost.post,
                            roleLabel = flatPost.parentPostNumber
                                ?.let { getString(R.string.topic_detail_nested_reply_to, it.toString()) }
                                ?: getString(R.string.topic_detail_reply_to_topic),
                            depth = flatPost.depth.toInt(),
                            emphasized = flatPost.depth == 0u,
                        ),
                    )
                }
            },
        )
    }

    private fun sectionCard(
        title: String,
        subtitle: String?,
        accentColor: Int,
        contentBuilder: LinearLayout.() -> Unit,
    ): View {
        return LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(dp(16), dp(16), dp(16), dp(16))
            layoutParams = LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.WRAP_CONTENT,
            ).apply {
                leftMargin = dp(16)
                rightMargin = dp(16)
                topMargin = dp(12)
            }
            background = roundedBackground(
                fillColor = Color.parseColor("#FFF6F7FB"),
                strokeColor = accentColor,
            )

            addView(
                TextView(context).apply {
                    text = title
                    textSize = 18f
                    setTypeface(typeface, Typeface.BOLD)
                    setTextColor(Color.parseColor("#FF111827"))
                },
            )

            subtitle?.let {
                addView(
                    TextView(context).apply {
                        text = it
                        textSize = 12f
                        setTextColor(Color.parseColor("#FF6B7280"))
                        setPadding(0, dp(4), 0, 0)
                    },
                )
            }

            contentBuilder()
        }
    }

    private fun postCardView(
        post: TopicPostState,
        roleLabel: String?,
        depth: Int,
        emphasized: Boolean,
    ): View {
        val accentColor = if (emphasized) sectionAccentColor() else Color.parseColor("#FF6B91FF")
        val fillColor = if (emphasized) Color.WHITE else Color.parseColor("#FFF9FAFB")
        val strokeColor = if (emphasized) Color.parseColor("#1F2F6FEB") else Color.parseColor("#1F6B91FF")

        return LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            layoutParams = LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.WRAP_CONTENT,
            ).apply {
                topMargin = dp(12)
                marginStart = dp(minOf(depth, 3) * 18)
            }

            addView(
                View(context).apply {
                    layoutParams = LinearLayout.LayoutParams(dp(3), ViewGroup.LayoutParams.MATCH_PARENT)
                    background = GradientDrawable().apply {
                        shape = GradientDrawable.RECTANGLE
                        cornerRadius = dp(3).toFloat()
                        setColor(accentColor)
                    }
                },
            )

            addView(
                LinearLayout(context).apply {
                    orientation = LinearLayout.VERTICAL
                    layoutParams = LinearLayout.LayoutParams(
                        0,
                        ViewGroup.LayoutParams.WRAP_CONTENT,
                        1f,
                    ).apply {
                        marginStart = dp(10)
                    }
                    setPadding(dp(12), dp(12), dp(12), dp(12))
                    background = roundedBackground(fillColor = fillColor, strokeColor = strokeColor)

                    roleLabel?.let {
                        addView(chipView(it, accentColor))
                    }

                    addView(
                        TextView(context).apply {
                            text = post.username.ifBlank { "Unknown" }
                            textSize = 16f
                            setTypeface(typeface, Typeface.BOLD)
                            setTextColor(Color.parseColor("#FF111827"))
                            if (roleLabel != null) {
                                setPadding(0, dp(8), 0, 0)
                            }
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
                            setTextColor(Color.parseColor("#FF6B7280"))
                            setPadding(0, dp(4), 0, 0)
                        },
                    )

                    addView(
                        TextView(context).apply {
                            text = plainTextFromHtml(rawHtml = post.cooked)
                            textSize = 15f
                            setTextColor(Color.parseColor("#FF1F2937"))
                            setPadding(0, dp(8), 0, 0)
                        },
                    )
                },
            )
        }
    }

    private fun chipView(text: String, accentColor: Int): View {
        return TextView(this).apply {
            this.text = text
            textSize = 11f
            setTypeface(typeface, Typeface.BOLD)
            setTextColor(accentColor)
            setPadding(dp(8), dp(4), dp(8), dp(4))
            background = roundedBackground(
                fillColor = sectionAccentColor(alpha = 0x18),
                strokeColor = Color.TRANSPARENT,
                cornerRadiusDp = 999,
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
        return topicCategories[id]?.displayName()
            ?: getString(R.string.topic_detail_category_fallback, id.toString())
    }

    private fun setLoading(loading: Boolean) {
        binding.loadingIndicator.visibility = if (loading) View.VISIBLE else View.GONE
        binding.refreshButton.isEnabled = !loading
    }

    private fun dp(value: Int): Int {
        return (value * resources.displayMetrics.density).toInt()
    }

    private fun roundedBackground(
        fillColor: Int,
        strokeColor: Int,
        cornerRadiusDp: Int = 18,
    ): GradientDrawable {
        return GradientDrawable().apply {
            shape = GradientDrawable.RECTANGLE
            cornerRadius = dp(cornerRadiusDp).toFloat()
            setColor(fillColor)
            if (strokeColor != Color.TRANSPARENT) {
                setStroke(dp(1), strokeColor)
            }
        }
    }

    private fun sectionAccentColor(alpha: Int = 0xFF): Int {
        return Color.argb(alpha, 0x2F, 0x6F, 0xEB)
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
