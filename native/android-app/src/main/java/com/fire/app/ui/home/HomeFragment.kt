package com.fire.app.ui.home

import android.graphics.Color
import android.os.Bundle
import android.view.Gravity
import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import android.widget.LinearLayout
import android.widget.PopupMenu
import android.widget.TextView
import android.widget.Toast
import androidx.fragment.app.Fragment
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.ViewModel
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.lifecycleScope
import androidx.lifecycle.repeatOnLifecycle
import androidx.navigation.fragment.findNavController
import androidx.paging.LoadState
import androidx.recyclerview.widget.LinearLayoutManager
import androidx.recyclerview.widget.RecyclerView
import androidx.swiperefreshlayout.widget.SwipeRefreshLayout
import com.fire.app.R
import com.fire.app.core.error.FireErrorClassifier
import com.fire.app.core.ext.dp
import com.fire.app.core.ext.optimizeForPaging
import com.fire.app.core.ui.FireToast
import com.fire.app.session.FireCloudflareRecovery
import com.fire.app.session.FireSessionStore
import com.fire.app.session.FireSessionStoreRepository
import com.fire.app.ui.composer.TopicComposerSheet
import com.fire.app.ui.topicdetail.TopicDetailActivity
import kotlinx.coroutines.flow.collectLatest
import kotlinx.coroutines.launch
import uniffi.fire_uniffi_types.TopicListKindState

class HomeFragment : Fragment() {

    private lateinit var recyclerView: RecyclerView
    private lateinit var adapter: TopicListAdapter
    private lateinit var emptyView: TextView
    private lateinit var loadingSkeletonView: View
    private lateinit var swipeRefresh: SwipeRefreshLayout
    private lateinit var scopeStatusBar: LinearLayout
    private lateinit var childShortcutScroll: View
    private lateinit var childShortcutBar: LinearLayout
    private lateinit var searchButton: View
    private lateinit var createTopicButton: View
    private lateinit var drawerButton: View
    private lateinit var offlineBanner: View

    private var viewModel: HomeViewModel? = null
    private var pendingAutoRefresh = false
    private val topicNavigationGate = HomeTopicNavigationGate()

    override fun onCreateView(
        inflater: LayoutInflater,
        container: ViewGroup?,
        savedInstanceState: Bundle?,
    ): View? {
        return inflater.inflate(R.layout.fragment_home, container, false)
    }

    override fun onViewCreated(view: View, savedInstanceState: Bundle?) {
        super.onViewCreated(view, savedInstanceState)

        recyclerView = view.findViewById(R.id.topic_list)
        emptyView = view.findViewById(R.id.empty_view)
        loadingSkeletonView = view.findViewById(R.id.loading_skeleton_view)
        swipeRefresh = view.findViewById(R.id.swipe_refresh)
        scopeStatusBar = view.findViewById(R.id.scope_status_bar)
        childShortcutScroll = view.findViewById(R.id.child_shortcut_scroll)
        childShortcutBar = view.findViewById(R.id.child_shortcut_bar)
        searchButton = view.findViewById(R.id.search_button)
        createTopicButton = view.findViewById(R.id.create_topic_button)
        drawerButton = view.findViewById(R.id.category_drawer_button)
        offlineBanner = view.findViewById(R.id.offline_banner)

        viewLifecycleOwner.lifecycleScope.launch {
            val sessionStore = FireSessionStoreRepository.get(requireContext())
            viewModel = ViewModelProvider(this@HomeFragment, HomeViewModelFactory(sessionStore))[HomeViewModel::class.java]

            adapter = TopicListAdapter(
                onTopicClick = { row ->
                    if (!topicNavigationGate.tryBeginOpeningTopicDetail()) {
                        return@TopicListAdapter
                    }
                    TopicDetailActivity.start(
                        context = requireContext(),
                        topicId = row.topic.id.toLong(),
                        topicTitle = row.topic.title,
                    )
                },
                onTagClick = { tag ->
                    viewModel?.selectTag(tag)
                    recyclerView.scrollToPosition(0)
                },
            )

            recyclerView.layoutManager = LinearLayoutManager(requireContext())
            recyclerView.adapter = adapter
            recyclerView.optimizeForPaging()
            recyclerView.addOnScrollListener(object : RecyclerView.OnScrollListener() {
                override fun onScrolled(recyclerView: RecyclerView, dx: Int, dy: Int) {
                    flushPendingAutoRefreshIfAtTop()
                }
            })
            adapter.addLoadStateListener { loadStates ->
                val refresh = loadStates.refresh
                val isInitialLoading = refresh is LoadState.Loading && adapter.itemCount == 0
                loadingSkeletonView.visibility = if (isInitialLoading) View.VISIBLE else View.GONE
                swipeRefresh.isEnabled = !isInitialLoading
                if (refresh is LoadState.Loading && adapter.itemCount > 0) {
                    swipeRefresh.isRefreshing = true
                }
                emptyView.visibility = when {
                    refresh is LoadState.Error -> {
                        val isCloudflare = FireErrorClassifier.isCloudflareChallenge(refresh.error)
                        emptyView.text = if (isCloudflare) {
                            FireErrorClassifier.displayMessage(refresh.error) +
                                "\n" +
                                getString(R.string.action_cloudflare_verify)
                        } else {
                            refresh.error.localizedMessage ?: getString(R.string.home_empty)
                        }
                        emptyView.setOnClickListener(
                            if (isCloudflare) {
                                View.OnClickListener { recoverHomeCloudflareChallenge() }
                            } else {
                                null
                            },
                        )
                        View.VISIBLE
                    }
                    refresh is LoadState.NotLoading && adapter.itemCount == 0 -> {
                        emptyView.text = getString(R.string.home_empty)
                        emptyView.setOnClickListener(null)
                        View.VISIBLE
                    }
                    else -> {
                        emptyView.setOnClickListener(null)
                        View.GONE
                    }
                }
                if (refresh !is LoadState.Loading) {
                    swipeRefresh.isRefreshing = false
                    flushPendingAutoRefreshIfAtTop()
                }
            }

            setupSwipeRefresh()
            setupToolbarActions()

            viewModel?.let { vm ->
                viewLifecycleOwner.repeatOnLifecycle(Lifecycle.State.STARTED) {
                    launch {
                        vm.topicPagingFlow.collectLatest { pagingData ->
                            adapter.submitData(pagingData)
                        }
                    }
                    launch {
                        HomeTopicDetailPatchRepository.patches.collect { patches ->
                            adapter.applyDetailPatches(patches)
                        }
                    }
                    launch {
                        vm.session.collectLatest { session ->
                            adapter.updateCategories(session?.bootstrap?.categories.orEmpty())
                            renderScopeChrome()
                        }
                    }
                    launch {
                        vm.selectedKind.collectLatest { renderScopeChrome() }
                    }
                    launch {
                        vm.selectedCategoryId.collectLatest { renderScopeChrome() }
                    }
                    launch {
                        vm.selectedTags.collectLatest { renderScopeChrome() }
                    }
                    launch {
                        vm.isOffline.collectLatest { isOffline ->
                            offlineBanner.visibility = if (isOffline) View.VISIBLE else View.GONE
                        }
                    }
                    launch {
                        vm.topicListRefreshEvents.collect {
                            if (isTopicListAtTop()) {
                                pendingAutoRefresh = false
                                vm.prepareTopicRefresh()
                                adapter.refresh()
                            } else {
                                pendingAutoRefresh = true
                            }
                        }
                    }
                    launch {
                        vm.error.collect { error ->
                            Toast.makeText(requireContext(), error, Toast.LENGTH_SHORT).show()
                        }
                    }
                }
            }
        }
    }

    override fun onResume() {
        super.onResume()
        topicNavigationGate.reset()
    }

    private fun recoverHomeCloudflareChallenge() {
        viewLifecycleOwner.lifecycleScope.launch {
            val sessionStore = FireSessionStoreRepository.get(requireContext())
            val ok = FireCloudflareRecovery.completeManualVerification(
                context = requireContext(),
                sessionStore = sessionStore,
                operation = "home.manual_verify",
                originUrl = "https://linux.do/",
            )
            if (ok) {
                viewModel?.prepareTopicRefresh()
                if (::adapter.isInitialized) {
                    adapter.refresh()
                }
            } else {
                FireToast.show(
                    requireView(),
                    getString(R.string.login_cloudflare_retry_failed),
                    FireToast.Style.ERROR,
                )
            }
        }
    }

    private fun setupSwipeRefresh() {
        swipeRefresh.setOnRefreshListener {
            pendingAutoRefresh = false
            viewModel?.prepareTopicRefresh()
            adapter.refresh()
        }
    }

    private fun setupToolbarActions() {
        searchButton.setOnClickListener {
            findNavController().navigate(HomeFragmentDirections.actionHomeToSearch())
        }
        createTopicButton.setOnClickListener {
            TopicComposerSheet.newInstance { topicId ->
                viewModel?.prepareTopicRefresh()
                adapter.refresh()
                TopicDetailActivity.start(
                    context = requireContext(),
                    topicId = topicId.toLong(),
                )
            }.show(parentFragmentManager, "topic_composer")
        }
        drawerButton.setOnClickListener { presentCategoryDrawer() }
    }

    private fun renderScopeChrome() {
        val vm = viewModel ?: return
        if (!isAdded) return
        val presentation = vm.scopePresentation()
        renderStatusBar(presentation)
        renderChildShortcuts(presentation)
    }

    private fun renderStatusBar(presentation: HomeScopePresentation) {
        scopeStatusBar.removeAllViews()
        scopeStatusBar.addView(
            capsule(
                title = presentation.categoryPathTitle,
                emphasized = !presentation.isDefaultCategory,
                accentHex = presentation.categoryAccentHex,
            ) {
                if (presentation.showsChildShortcutStrip) {
                    presentSubcategorySheet(presentation)
                } else {
                    presentCategoryDrawer()
                }
            },
        )
        val kindView = capsule(
            title = presentation.kindTitle,
            emphasized = !presentation.isDefaultKind,
            accentHex = null,
        ) {}
        kindView.setOnClickListener { showKindMenu(kindView, presentation.kind) }
        scopeStatusBar.addView(kindView)
        presentation.tags.forEach { tag ->
            scopeStatusBar.addView(
                capsule(title = "#$tag", emphasized = true, accentHex = null) {
                    viewModel?.removeTag(tag)
                    recyclerView.scrollToPosition(0)
                },
            )
        }
        if (!presentation.isDefaultScope) {
            scopeStatusBar.addView(
                capsule(title = "清除", emphasized = false, accentHex = null) {
                    viewModel?.clearHomeScopeFilters()
                    recyclerView.scrollToPosition(0)
                },
            )
        }
    }

    private fun renderChildShortcuts(presentation: HomeScopePresentation) {
        childShortcutBar.removeAllViews()
        if (!presentation.showsChildShortcutStrip) {
            childShortcutScroll.visibility = View.GONE
            return
        }
        childShortcutScroll.visibility = View.VISIBLE
        presentation.childShortcuts.forEach { shortcut ->
            childShortcutBar.addView(
                capsule(
                    title = shortcut.title,
                    emphasized = shortcut.isSelected,
                    accentHex = presentation.categoryAccentHex,
                    compact = true,
                ) {
                    viewModel?.selectCategory(shortcut.categoryId)
                    recyclerView.scrollToPosition(0)
                },
            )
        }
    }

    private fun presentCategoryDrawer() {
        val vm = viewModel ?: return
        HomeCategoryDrawerFragment().apply {
            categories = vm.session.value?.bootstrap?.categories.orEmpty()
            selectedCategoryId = vm.selectedCategoryId.value
            onSelect = { id ->
                vm.selectCategory(id)
                recyclerView.scrollToPosition(0)
            }
        }.show(parentFragmentManager, "home_category_drawer")
    }

    private fun presentSubcategorySheet(presentation: HomeScopePresentation) {
        HomeSubcategorySheetFragment().apply {
            shortcuts = presentation.childShortcuts
            onSelect = { id ->
                viewModel?.selectCategory(id)
                recyclerView.scrollToPosition(0)
            }
        }.show(parentFragmentManager, "home_subcategory")
    }

    private fun showKindMenu(anchor: View, selected: TopicListKindState) {
        val popup = PopupMenu(requireContext(), anchor)
        homeFeedKinds.forEachIndexed { index, kind ->
            popup.menu.add(0, index, index, kind.fireTitle()).isChecked = kind == selected
        }
        popup.menu.setGroupCheckable(0, true, true)
        popup.setOnMenuItemClickListener { item ->
            val kind = homeFeedKinds.getOrNull(item.itemId) ?: return@setOnMenuItemClickListener false
            viewModel?.selectKind(kind)
            recyclerView.scrollToPosition(0)
            true
        }
        popup.show()
    }

    private fun capsule(
        title: String,
        emphasized: Boolean,
        accentHex: String?,
        compact: Boolean = false,
        onClick: () -> Unit,
    ): TextView {
        val context = requireContext()
        return TextView(context).apply {
            text = title
            textSize = if (compact) 13f else 14f
            setPadding(context.dp(12), context.dp(if (compact) 6 else 8), context.dp(12), context.dp(if (compact) 6 else 8))
            gravity = Gravity.CENTER
            setBackgroundResource(
                if (emphasized) R.drawable.bg_scope_capsule_selected else R.drawable.bg_scope_capsule,
            )
            val accent = parseAccent(accentHex)
            setTextColor(if (emphasized) accent else context.getColor(R.color.fire_text_primary))
            val params = LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.WRAP_CONTENT,
                ViewGroup.LayoutParams.WRAP_CONTENT,
            )
            params.marginEnd = context.dp(8)
            layoutParams = params
            setOnClickListener { onClick() }
        }
    }

    private fun parseAccent(hex: String?): Int {
        val raw = hex?.trim()?.removePrefix("#").orEmpty()
        return runCatching { Color.parseColor(if (raw.length == 6) "#$raw" else hex) }
            .getOrElse { requireContext().getColor(R.color.fire_accent) }
    }

    private fun isTopicListAtTop(): Boolean {
        val layoutManager = recyclerView.layoutManager as? LinearLayoutManager ?: return true
        val firstVisiblePosition = layoutManager.findFirstVisibleItemPosition()
        if (firstVisiblePosition > 0) {
            return false
        }
        val firstVisibleView = layoutManager.findViewByPosition(firstVisiblePosition)
        return firstVisibleView == null || firstVisibleView.top >= recyclerView.paddingTop
    }

    private fun flushPendingAutoRefreshIfAtTop() {
        if (!pendingAutoRefresh || swipeRefresh.isRefreshing) {
            return
        }
        if (!isTopicListAtTop()) {
            return
        }
        pendingAutoRefresh = false
        viewModel?.prepareTopicRefresh()
        adapter.refresh()
    }

    private class HomeViewModelFactory(
        private val sessionStore: FireSessionStore,
    ) : ViewModelProvider.Factory {
        @Suppress("UNCHECKED_CAST")
        override fun <T : ViewModel> create(modelClass: Class<T>): T {
            if (modelClass.isAssignableFrom(HomeViewModel::class.java)) {
                return HomeViewModel.create(sessionStore) as T
            }
            throw IllegalArgumentException("Unknown ViewModel class: ${modelClass.name}")
        }
    }
}
