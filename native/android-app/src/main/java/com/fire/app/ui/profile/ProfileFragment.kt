package com.fire.app.ui.profile

import android.os.Bundle
import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import android.widget.ProgressBar
import android.widget.TextView
import androidx.fragment.app.Fragment
import androidx.lifecycle.lifecycleScope
import androidx.navigation.fragment.findNavController
import androidx.recyclerview.widget.LinearLayoutManager
import androidx.recyclerview.widget.RecyclerView
import com.fire.app.R
import com.fire.app.session.FireSessionStoreRepository
import kotlinx.coroutines.flow.collectLatest
import kotlinx.coroutines.launch

class ProfileFragment : Fragment() {

    private lateinit var recyclerView: RecyclerView
    private lateinit var adapter: ProfileAdapter
    private lateinit var emptyView: TextView
    private lateinit var loadingView: ProgressBar

    private var viewModel: ProfileViewModel? = null

    override fun onCreateView(
        inflater: LayoutInflater,
        container: ViewGroup?,
        savedInstanceState: Bundle?,
    ): View? {
        return inflater.inflate(R.layout.fragment_profile, container, false)
    }

    override fun onViewCreated(view: View, savedInstanceState: Bundle?) {
        super.onViewCreated(view, savedInstanceState)

        recyclerView = view.findViewById(R.id.profile_list)
        emptyView = view.findViewById(R.id.empty_view)
        loadingView = view.findViewById(R.id.loading_view)

        val sessionStore = FireSessionStoreRepository.get(requireContext())
        viewModel = ProfileViewModel.create(sessionStore)

        adapter = ProfileAdapter()
        recyclerView.layoutManager = LinearLayoutManager(requireContext())
        recyclerView.adapter = adapter

        val username = ProfileFragmentArgs.fromBundle(requireArguments()).username
            ?: run {
                // Default to logged-in user's profile
                viewLifecycleOwner.lifecycleScope.launch {
                    val session = sessionStore.snapshot()
                    val name = session.bootstrap.currentUsername ?: return@launch
                    viewModel?.loadProfile(name)
                }
                return@run null
            }

        if (username != null) {
            viewModel?.loadProfile(username)
        }

        observeViewModel()
        setupNavigation()
    }

    private fun observeViewModel() {
        viewModel?.let { vm ->
            viewLifecycleOwner.lifecycleScope.launch {
                vm.profile.collect { profile ->
                    if (profile != null) {
                        updateProfileRows()
                    }
                }
            }

            viewLifecycleOwner.lifecycleScope.launch {
                vm.summary.collect { summary ->
                    if (summary != null) {
                        updateProfileRows()
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
                        emptyView.visibility = View.VISIBLE
                    }
                }
            }
        }
    }

    private fun updateProfileRows() {
        val profile = viewModel?.profile?.value ?: return
        val summary = viewModel?.summary?.value

        val rows = mutableListOf<ProfileRow>()
        rows.add(ProfileRow.HeaderRow(profile))
        if (summary != null) {
            rows.add(ProfileRow.StatsRow(summary.stats))
            if (summary.badges.isNotEmpty()) {
                rows.add(ProfileRow.BadgeRow(summary.badges))
            }
            summary.topTopics.forEach { rows.add(ProfileRow.TopTopicRow(it)) }
        }
        adapter.submitList(rows)
    }

    private fun setupNavigation() {
        // Navigate to bookmarks / private messages from profile menu
        // These actions are defined in the nav graph
    }
}
