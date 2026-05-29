package com.fire.app.ui.topicdetail

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Bundle
import android.view.View
import android.widget.ProgressBar
import android.widget.TextView
import androidx.appcompat.app.AppCompatActivity
import androidx.core.view.ViewCompat
import androidx.core.view.WindowInsetsCompat
import androidx.core.view.updatePadding
import androidx.lifecycle.lifecycleScope
import androidx.recyclerview.widget.ConcatAdapter
import androidx.recyclerview.widget.LinearLayoutManager
import androidx.recyclerview.widget.RecyclerView
import com.fire.app.R
import com.fire.app.databinding.ActivityTopicDetailBinding
import com.fire.app.session.FireSessionStoreRepository
import com.fire.app.ui.composer.ReplyComposerSheet
import kotlinx.coroutines.flow.collectLatest
import kotlinx.coroutines.launch

class TopicDetailActivity : AppCompatActivity() {

    private lateinit var binding: ActivityTopicDetailBinding
    private lateinit var recyclerView: RecyclerView
    private lateinit var loadingView: ProgressBar
    private lateinit var errorView: View
    private lateinit var errorText: TextView
    private lateinit var retryButton: View
    private lateinit var replyFab: View

    private var viewModel: TopicDetailViewModel? = null
    private var route: TopicDetailRoute? = null

    private val headerAdapter = HeaderAdapter { /* original post click handler */ }
    private val postListAdapter = PostListAdapter { /* post click handler */ }
    private val loadingFooterAdapter = LoadingFooterAdapter()
    private var loadMorePostsPosted = false

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        binding = ActivityTopicDetailBinding.inflate(layoutInflater)
        setContentView(binding.root)
        applySystemBarInsets()

        val parsedRoute = TopicDetailRoute.from(intent)
        if (parsedRoute == null) {
            finish()
            return
        }
        route = parsedRoute

        recyclerView = binding.postList
        loadingView = binding.loadingView
        errorView = binding.errorView
        errorText = binding.errorText
        retryButton = binding.retryButton
        replyFab = binding.replyFab

        binding.topicDetailToolbar.setNavigationOnClickListener {
            finish()
        }
        binding.topicDetailToolbar.title = parsedRoute.title
            ?: getString(R.string.topic_detail_title_fallback, parsedRoute.topicId)

        val sessionStore = FireSessionStoreRepository.get(this)
        viewModel = TopicDetailViewModel.create(sessionStore)

        val concatAdapter = ConcatAdapter(headerAdapter, postListAdapter, loadingFooterAdapter)
        recyclerView.layoutManager = LinearLayoutManager(this)
        recyclerView.adapter = concatAdapter

        recyclerView.addOnScrollListener(object : RecyclerView.OnScrollListener() {
            override fun onScrolled(rv: RecyclerView, dx: Int, dy: Int) {
                val layoutManager = rv.layoutManager as? LinearLayoutManager ?: return
                val totalItemCount = layoutManager.itemCount
                val lastVisible = layoutManager.findLastVisibleItemPosition()
                if (lastVisible >= totalItemCount - 5) {
                    scheduleLoadMorePosts(rv)
                }
            }
        })

        observeViewModel()

        retryButton.setOnClickListener {
            loadRoute(parsedRoute)
        }

        replyFab.setOnClickListener {
            val sheet = ReplyComposerSheet.newInstance(parsedRoute.topicId) {
                viewModel?.loadTopicDetail(parsedRoute.topicId.toULong())
            }
            sheet.show(supportFragmentManager, "reply_composer")
        }

        loadRoute(parsedRoute)
    }

    private fun observeViewModel() {
        val vm = viewModel ?: return
        lifecycleScope.launch {
            vm.isLoading.collectLatest { loading ->
                loadingView.visibility = if (loading) View.VISIBLE else View.GONE
                recyclerView.visibility = if (loading && vm.postRows.value.isEmpty()) View.GONE else View.VISIBLE
            }
        }

        lifecycleScope.launch {
            vm.errorMessage.collectLatest { error ->
                if (error != null) {
                    errorView.visibility = View.VISIBLE
                    errorText.text = error
                } else {
                    errorView.visibility = View.GONE
                }
            }
        }

        lifecycleScope.launch {
            vm.detail.collectLatest { detail ->
                headerAdapter.detail = detail
                if (detail != null) {
                    binding.topicDetailToolbar.title = detail.title.trim()
                }
            }
        }

        lifecycleScope.launch {
            vm.postRows.collectLatest { rows ->
                postListAdapter.submitList(rows)
            }
        }

        lifecycleScope.launch {
            vm.isLoadingMore.collectLatest { loadingMore ->
                loadingFooterAdapter.isLoading = loadingMore
            }
        }
    }

    private fun loadRoute(route: TopicDetailRoute) {
        val targetPostNumber = route.targetPostNumber.takeIf { it > 0 }?.toUInt()
        viewModel?.loadTopicDetail(route.topicId.toULong(), targetPostNumber)
    }

    private fun scheduleLoadMorePosts(rv: RecyclerView) {
        if (loadMorePostsPosted) return
        loadMorePostsPosted = true
        rv.post {
            loadMorePostsPosted = false
            viewModel?.loadMorePosts()
        }
    }

    private fun applySystemBarInsets() {
        val root = binding.root
        val initialLeft = root.paddingLeft
        val initialTop = root.paddingTop
        val initialRight = root.paddingRight
        val initialBottom = root.paddingBottom
        ViewCompat.setOnApplyWindowInsetsListener(root) { view, insets ->
            val systemBars = insets.getInsets(WindowInsetsCompat.Type.systemBars())
            view.updatePadding(
                left = initialLeft + systemBars.left,
                top = initialTop + systemBars.top,
                right = initialRight + systemBars.right,
                bottom = initialBottom + systemBars.bottom,
            )
            insets
        }
        ViewCompat.requestApplyInsets(root)
    }

    private data class TopicDetailRoute(
        val topicId: Long,
        val title: String?,
        val targetPostNumber: Int,
    ) {
        companion object {
            fun from(intent: Intent): TopicDetailRoute? {
                val extraTopicId = intent.getLongExtra(EXTRA_TOPIC_ID, -1L)
                if (extraTopicId > 0L) {
                    return TopicDetailRoute(
                        topicId = extraTopicId,
                        title = intent.getStringExtra(EXTRA_TOPIC_TITLE),
                        targetPostNumber = intent.getIntExtra(EXTRA_TARGET_POST_NUMBER, -1),
                    )
                }

                return fromUri(intent.data)
            }

            private fun fromUri(uri: Uri?): TopicDetailRoute? {
                if (uri?.scheme != "fire" || uri.host != "topic") {
                    return null
                }
                val segments = uri.pathSegments
                val topicId = segments.getOrNull(0)?.toLongOrNull()?.takeIf { it > 0L } ?: return null
                val postNumber = segments.getOrNull(1)?.toIntOrNull() ?: -1
                return TopicDetailRoute(
                    topicId = topicId,
                    title = null,
                    targetPostNumber = postNumber,
                )
            }
        }
    }

    companion object {
        private const val EXTRA_TOPIC_ID = "com.fire.app.extra.TOPIC_ID"
        private const val EXTRA_TOPIC_TITLE = "com.fire.app.extra.TOPIC_TITLE"
        private const val EXTRA_TARGET_POST_NUMBER = "com.fire.app.extra.TARGET_POST_NUMBER"

        fun createIntent(
            context: Context,
            topicId: Long,
            topicTitle: String? = null,
            targetPostNumber: Int = -1,
        ): Intent {
            return Intent(context, TopicDetailActivity::class.java).apply {
                putExtra(EXTRA_TOPIC_ID, topicId)
                putExtra(EXTRA_TARGET_POST_NUMBER, targetPostNumber)
                topicTitle?.let { putExtra(EXTRA_TOPIC_TITLE, it) }
            }
        }

        fun start(
            context: Context,
            topicId: Long,
            topicTitle: String? = null,
            targetPostNumber: Int = -1,
        ) {
            context.startActivity(
                createIntent(
                    context = context,
                    topicId = topicId,
                    topicTitle = topicTitle,
                    targetPostNumber = targetPostNumber,
                ),
            )
        }
    }
}
