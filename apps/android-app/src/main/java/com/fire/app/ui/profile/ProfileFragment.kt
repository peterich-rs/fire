package com.fire.app.ui.profile

import android.os.Bundle
import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.platform.ComposeView
import androidx.compose.ui.platform.ViewCompositionStrategy
import androidx.fragment.app.Fragment
import androidx.fragment.app.viewModels
import androidx.lifecycle.ViewModel
import androidx.lifecycle.ViewModelProvider
import androidx.navigation.fragment.findNavController
import com.fire.app.core.ui.compose.FireAppTheme
import com.fire.app.session.FireSessionStore
import com.fire.app.session.FireSessionStoreRepository
import com.fire.app.ui.composer.PrivateMessageComposerSheet
import com.fire.app.ui.feedback.FeedbackActivity
import com.fire.app.ui.profile.compose.ProfileScreen
import com.fire.app.ui.profile.compose.ProfileUiState
import com.fire.app.ui.settings.SettingsActivity
import com.fire.app.ui.topicdetail.TopicDetailActivity
import uniffi.fire_uniffi_user.UserActionState
import uniffi.fire_uniffi_user.UserProfileState

class ProfileFragment : Fragment() {

    private val sessionStore: FireSessionStore by lazy {
        FireSessionStoreRepository.getIfInitialized()
            ?: error("FireSessionStore must be initialized before ProfileFragment")
    }

    private val viewModel: ProfileViewModel by viewModels {
        ProfileViewModelFactory(sessionStore)
    }

    private val requestedUsername: String?
        get() = runCatching {
            ProfileFragmentArgs.fromBundle(requireArguments()).username
        }.getOrNull()

    override fun onCreateView(
        inflater: LayoutInflater,
        container: ViewGroup?,
        savedInstanceState: Bundle?,
    ): View {
        viewModel.loadProfile(requestedUsername)
        val ownOnTab = requestedUsername.normalizedUsername() == null
        return ComposeView(requireContext()).apply {
            setViewCompositionStrategy(ViewCompositionStrategy.DisposeOnViewTreeLifecycleDestroyed)
            setContent {
                FireAppTheme {
                    val profile by viewModel.profile.collectAsState()
                    val summary by viewModel.summary.collectAsState()
                    val actions by viewModel.actions.collectAsState()
                    val loading by viewModel.isLoading.collectAsState()
                    val actionsLoading by viewModel.actionsLoading.collectAsState()
                    val loadedActions by viewModel.hasLoadedActionsOnce.collectAsState()
                    val error by viewModel.error.collectAsState()
                    val selfUsername by viewModel.selfUsername.collectAsState()
                    val own = isOwnProfile(profile?.username, selfUsername)
                    ProfileScreen(
                        state = ProfileUiState(
                            profile = profile,
                            summary = summary,
                            actions = actions,
                            isOwnProfile = own,
                            isLoading = loading,
                            actionsLoading = actionsLoading,
                            hasLoadedActionsOnce = loadedActions,
                            error = error,
                        ),
                        onRefresh = { viewModel.refresh(requestedUsername) },
                        onFollowClick = { viewModel.toggleFollow() },
                        onMessageClick = { profile?.let(::showPrivateMessageComposer) },
                        onFollowingClick = { openFollowList("following") },
                        onFollowersClick = { openFollowList("followers") },
                        onActivityClick = { openActivity(profile?.username) },
                        onActivityItemClick = ::openAction,
                        onBookmarksClick = {
                            findNavController().navigate(ProfileFragmentDirections.actionProfileToBookmarks())
                        },
                        onHistoryClick = {
                            findNavController().navigate(ProfileFragmentDirections.actionProfileToReadHistory())
                        },
                        onDraftsClick = {
                            findNavController().navigate(ProfileFragmentDirections.actionProfileToDrafts())
                        },
                        onMessagesClick = {
                            findNavController().navigate(ProfileFragmentDirections.actionProfileToPrivateMessages())
                        },
                        onBadgesClick = {
                            findNavController().navigate(ProfileFragmentDirections.actionProfileToBadges())
                        },
                        onFeedbackClick = {
                            FeedbackActivity.start(requireContext(), source = "profile")
                        },
                        onInvitesClick = {
                            val username = viewModel.profile.value?.username ?: return@ProfileScreen
                            findNavController().navigate(
                                ProfileFragmentDirections.actionProfileToInvites(username = username),
                            )
                        },
                        onLdcClick = {
                            findNavController().navigate(ProfileFragmentDirections.actionProfileToLdc())
                        },
                        onCdkClick = {
                            findNavController().navigate(ProfileFragmentDirections.actionProfileToCdk())
                        },
                        onSettingsClick = { SettingsActivity.start(requireContext()) },
                        onBack = if (ownOnTab) null else ({ findNavController().navigateUp() }),
                        onDismissError = { viewModel.dismissError() },
                    )
                }
            }
        }
    }

    private fun openFollowList(kind: String) {
        val username = viewModel.profile.value?.username ?: return
        findNavController().navigate(
            ProfileFragmentDirections.actionProfileToFollowList(username = username, kind = kind),
        )
    }

    private fun openActivity(username: String?) {
        val target = username ?: return
        findNavController().navigate(
            ProfileFragmentDirections.actionProfileToActivity(username = target),
        )
    }

    private fun openAction(action: UserActionState) {
        val topicId = action.topicId ?: return
        TopicDetailActivity.start(
            context = requireContext(),
            topicId = topicId.toLong(),
            topicTitle = action.title,
            targetPostNumber = action.postNumber?.toInt() ?: -1,
        )
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

    private fun isOwnProfile(profileUsername: String?, selfUsername: String?): Boolean {
        if (requestedUsername.normalizedUsername() == null) return true
        val current = selfUsername.normalizedUsername() ?: return false
        val requested = requestedUsername.normalizedUsername()
        val profile = profileUsername.normalizedUsername()
        return current.equals(requested, ignoreCase = true) ||
            current.equals(profile, ignoreCase = true)
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
