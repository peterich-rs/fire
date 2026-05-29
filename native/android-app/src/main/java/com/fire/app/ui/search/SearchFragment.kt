package com.fire.app.ui.search

import android.os.Bundle
import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import android.widget.EditText
import android.widget.ProgressBar
import android.widget.TextView
import androidx.fragment.app.Fragment
import androidx.lifecycle.lifecycleScope
import androidx.navigation.fragment.findNavController
import androidx.recyclerview.widget.LinearLayoutManager
import androidx.recyclerview.widget.RecyclerView
import com.fire.app.R
import com.fire.app.session.FireSessionStoreRepository
import com.fire.app.ui.cloudflare.CloudflareChallengeSupport
import com.fire.app.ui.topicdetail.TopicDetailActivity
import com.google.android.material.chip.Chip
import com.google.android.material.chip.ChipGroup
import kotlinx.coroutines.flow.debounce
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.launch
import uniffi.fire_uniffi_search.SearchTypeFilterState

class SearchFragment : Fragment() {

    private lateinit var searchInput: EditText
    private lateinit var filterChips: ChipGroup
    private lateinit var recyclerView: RecyclerView
    private lateinit var adapter: SearchResultsAdapter
    private lateinit var emptyView: TextView
    private lateinit var loadingView: ProgressBar

    private var viewModel: SearchViewModel? = null

    override fun onCreateView(
        inflater: LayoutInflater,
        container: ViewGroup?,
        savedInstanceState: Bundle?,
    ): View? {
        return inflater.inflate(R.layout.fragment_search, container, false)
    }

    override fun onViewCreated(view: View, savedInstanceState: Bundle?) {
        super.onViewCreated(view, savedInstanceState)

        searchInput = view.findViewById(R.id.search_input)
        filterChips = view.findViewById(R.id.filter_chips)
        recyclerView = view.findViewById(R.id.search_results_list)
        emptyView = view.findViewById(R.id.empty_view)
        loadingView = view.findViewById(R.id.loading_view)

        val sessionStore = FireSessionStoreRepository.get(requireContext())
        viewModel = SearchViewModel.create(sessionStore)

        adapter = SearchResultsAdapter(
            onTopicClick = { topic ->
                TopicDetailActivity.start(
                    context = requireContext(),
                    topicId = topic.id.toLong(),
                    topicTitle = topic.title,
                )
            },
            onPostClick = { post ->
                val topicId = post.topicId ?: return@SearchResultsAdapter
                TopicDetailActivity.start(
                    context = requireContext(),
                    topicId = topicId.toLong(),
                    targetPostNumber = post.postNumber.toInt(),
                )
            },
            onUserClick = { user ->
                val action = SearchFragmentDirections.actionSearchFragmentToProfileFragment(
                    username = user.username,
                )
                findNavController().navigate(action)
            },
        )

        recyclerView.layoutManager = LinearLayoutManager(requireContext())
        recyclerView.adapter = adapter

        setupFilterChips()
        observeViewModel()
        setupSearchInput()
    }

    private fun setupSearchInput() {
        searchInput.setOnEditorActionListener { _, actionId, _ ->
            if (actionId == android.view.inputmethod.EditorInfo.IME_ACTION_SEARCH) {
                viewModel?.setQuery(searchInput.text.toString())
                true
            } else {
                false
            }
        }

        // React to text changes — ViewModel applies debounce internally
        searchInput.addTextChangedListener(object : android.text.TextWatcher {
            override fun beforeTextChanged(s: CharSequence?, start: Int, count: Int, after: Int) {}
            override fun onTextChanged(s: CharSequence?, start: Int, before: Int, count: Int) {}
            override fun afterTextChanged(s: android.text.Editable?) {
                viewModel?.setQuery(s?.toString() ?: "")
            }
        })
    }

    private fun setupFilterChips() {
        val filters = listOf(
            null to getString(R.string.search_filter_all),
            SearchTypeFilterState.TOPIC to getString(R.string.search_filter_topics),
            SearchTypeFilterState.POST to getString(R.string.search_filter_posts),
            SearchTypeFilterState.USER to getString(R.string.search_filter_users),
        )

        filters.forEachIndexed { index, (filter, label) ->
            val chip = Chip(requireContext()).apply {
                text = label
                isCheckable = true
                isChecked = index == 0
                setTag(R.id.tag_search_filter, filter)
                setOnClickListener {
                    val selectedFilter = getTag(R.id.tag_search_filter) as? SearchTypeFilterState
                    viewModel?.setTypeFilter(selectedFilter)
                }
            }
            filterChips.addView(chip)
        }
    }

    private fun observeViewModel() {
        viewModel?.let { vm ->
            viewLifecycleOwner.lifecycleScope.launch {
                vm.results.collect { result ->
                    if (result == null) {
                        adapter.submitList(emptyList())
                        emptyView.text = getString(R.string.search_enter_query)
                        emptyView.visibility = View.VISIBLE
                        return@collect
                    }

                    val rows = buildSearchRows(result)
                    adapter.submitList(rows)

                    val hasResults = rows.isNotEmpty()
                    emptyView.visibility = if (hasResults) View.GONE else View.VISIBLE
                    if (!hasResults) {
                        emptyView.text = getString(R.string.search_empty)
                    }
                }
            }

            viewLifecycleOwner.lifecycleScope.launch {
                vm.isLoading.collect { loading ->
                    loadingView.visibility = if (loading) View.VISIBLE else View.GONE
                }
            }

            viewLifecycleOwner.lifecycleScope.launch {
                vm.error.collect { err ->
                    if (err != null) {
                        emptyView.text = getString(R.string.search_error)
                        emptyView.visibility = View.VISIBLE
                    }
                }
            }

            viewLifecycleOwner.lifecycleScope.launch {
                vm.cloudflareChallenge.collect {
                    CloudflareChallengeSupport.openSiteRoot(requireContext())
                }
            }
        }
    }

    private fun buildSearchRows(result: uniffi.fire_uniffi_search.SearchResultState): List<SearchRow> {
        val rows = mutableListOf<SearchRow>()
        if (result.topics.isNotEmpty()) {
            rows.add(SearchRow.SectionHeader)
            result.topics.forEach { rows.add(SearchRow.TopicRow(it)) }
        }
        if (result.posts.isNotEmpty()) {
            rows.add(SearchRow.SectionHeader)
            result.posts.forEach { rows.add(SearchRow.PostRow(it)) }
        }
        if (result.users.isNotEmpty()) {
            rows.add(SearchRow.SectionHeader)
            result.users.forEach { rows.add(SearchRow.UserRow(it)) }
        }
        return rows
    }
}
