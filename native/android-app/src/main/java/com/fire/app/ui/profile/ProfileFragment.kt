package com.fire.app.ui.profile

import android.os.Bundle
import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import android.widget.ProgressBar
import android.widget.TextView
import androidx.fragment.app.Fragment
import androidx.lifecycle.ViewModel
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.lifecycleScope
import androidx.navigation.fragment.findNavController
import androidx.recyclerview.widget.LinearLayoutManager
import androidx.recyclerview.widget.RecyclerView
import com.fire.app.R
import com.fire.app.session.FireSessionStore
import com.fire.app.session.FireSessionStoreRepository
import com.fire.app.ui.composer.PrivateMessageComposerSheet
import com.fire.app.ui.topicdetail.TopicDetailActivity
import kotlinx.coroutines.launch
import uniffi.fire_uniffi_user.UserProfileState

class ProfileFragment : Fragment() {

    private lateinit var recyclerView: RecyclerView
    private lateinit var adapter: ProfileAdapter
    private lateinit var emptyView: TextView
    private lateinit var loadingView: ProgressBar
    private lateinit var profileActions: View
    private lateinit var bookmarksButton: View
    private lateinit var privateMessagesButton: View

    private var viewModel: ProfileViewModel? = null
    private var requestedUsername: String? = null
    private var currentUsername: String? = null

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
        profileActions = view.findViewById(R.id.profile_actions)
        bookmarksButton = view.findViewById(R.id.bookmarks_button)
        privateMessagesButton = view.findViewById(R.id.private_messages_button)

        viewLifecycleOwner.lifecycleScope.launch {
            val sessionStore = FireSessionStoreRepository.get(requireContext())
            viewModel = ViewModelProvider(
                this@ProfileFragment,
                ProfileViewModelFactory(sessionStore),
            )[ProfileViewModel::class.java]

            adapter = ProfileAdapter(
                onFollowClick = { viewModel?.toggleFollow() },
                onMessageClick = { profile -> showPrivateMessageComposer(profile) },
                onTopicClick = { topic ->
                    TopicDetailActivity.start(
                        context = requireContext(),
                        topicId = topic.id.toLong(),
                        topicTitle = topic.title,
                    )
                },
            )
            recyclerView.layoutManager = LinearLayoutManager(requireContext())
            recyclerView.adapter = adapter

            observeViewModel()

            requestedUsername = ProfileFragmentArgs.fromBundle(requireArguments()).username
            currentUsername = runCatching {
                sessionStore.snapshot().bootstrap.currentUsername
            }.getOrNull()
            updateProfileRows()
            setupNavigation(requestedUsername)
            viewModel?.loadProfile(requestedUsername)
        }
    }

    private fun observeViewModel() {
        viewModel?.let { vm ->
            viewLifecycleOwner.lifecycleScope.launch {
                vm.profile.collect { profile ->
                    if (profile != null) {
                        emptyView.visibility = View.GONE
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
                    if (loading) {
                        emptyView.visibility = View.GONE
                    }
                }
            }

            viewLifecycleOwner.lifecycleScope.launch {
                vm.error.collect { err ->
                    if (err != null) {
                        emptyView.text = err.ifBlank { getString(R.string.profile_error) }
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
        rows.add(ProfileRow.HeaderRow(profile, isOwnProfile(profile.username)))
        if (summary != null) {
            rows.add(ProfileRow.StatsRow(summary.stats))
            if (summary.badges.isNotEmpty()) {
                rows.add(ProfileRow.BadgeRow(summary.badges))
            }
            summary.topTopics.forEach { rows.add(ProfileRow.TopTopicRow(it)) }
        }
        adapter.submitList(rows)
    }

    private fun setupNavigation(username: String?) {
        val isCurrentUserProfile = username.isNullOrBlank() || username.equals("null", ignoreCase = true)
        profileActions.visibility = if (isCurrentUserProfile) View.VISIBLE else View.GONE
        if (!isCurrentUserProfile) return

        bookmarksButton.setOnClickListener {
            findNavController().navigate(ProfileFragmentDirections.actionProfileToBookmarks())
        }
        privateMessagesButton.setOnClickListener {
            findNavController().navigate(ProfileFragmentDirections.actionProfileToPrivateMessages())
        }
    }

    private fun showPrivateMessageComposer(profile: UserProfileState) {
        val displayName = profile.name?.takeIf { it.isNotBlank() } ?: profile.username
        PrivateMessageComposerSheet.newInstance(
            targetUsername = profile.username,
            displayName = displayName,
            onPrivateMessageCreated = { topicId, title ->
                TopicDetailActivity.start(
                    context = requireContext(),
                    topicId = topicId.toLong(),
                    topicTitle = title,
                )
            },
        ).show(childFragmentManager, "private_message_composer")
    }

    private fun isOwnProfile(profileUsername: String): Boolean {
        if (requestedUsername.normalizedUsername() == null) {
            return true
        }
        val current = currentUsername.normalizedUsername() ?: return false
        return current.equals(profileUsername.trim(), ignoreCase = true)
    }

    private fun String?.normalizedUsername(): String? {
        val trimmed = this?.trim()
        return trimmed?.takeIf { it.isNotEmpty() && !it.equals("null", ignoreCase = true) }
    }

    private class ProfileViewModelFactory(
        private val sessionStore: FireSessionStore,
    ) : ViewModelProvider.Factory {
        @Suppress("UNCHECKED_CAST")
        override fun <T : ViewModel> create(modelClass: Class<T>): T {
            if (modelClass.isAssignableFrom(ProfileViewModel::class.java)) {
                return ProfileViewModel.create(sessionStore) as T
            }
            throw IllegalArgumentException("Unknown ViewModel class: ${modelClass.name}")
        }
    }
}
