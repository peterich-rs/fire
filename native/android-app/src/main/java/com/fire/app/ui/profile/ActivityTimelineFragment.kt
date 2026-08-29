package com.fire.app.ui.profile

import android.os.Bundle
import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn

import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ViewList
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.ComposeView
import androidx.compose.ui.platform.ViewCompositionStrategy
import androidx.compose.ui.unit.dp
import androidx.fragment.app.Fragment
import androidx.fragment.app.viewModels
import androidx.lifecycle.ViewModel
import androidx.lifecycle.ViewModelProvider
import androidx.navigation.fragment.findNavController
import com.fire.app.core.ui.compose.FireAppTheme
import com.fire.app.core.ui.compose.FireEmptyState
import com.fire.app.core.ui.compose.FireSecondaryScaffold
import com.fire.app.core.ui.compose.FireSettingsCard
import com.fire.app.session.FireSessionStore
import com.fire.app.session.FireSessionStoreRepository
import com.fire.app.ui.profile.compose.ProfileActivityRow
import com.fire.app.ui.topicdetail.TopicDetailActivity
import uniffi.fire_uniffi_user.UserActionState

class ActivityTimelineFragment : Fragment() {

    private val args: ActivityTimelineFragmentArgs by lazy {
        ActivityTimelineFragmentArgs.fromBundle(requireArguments())
    }

    private val viewModel: ProfileViewModel by viewModels {
        val store = FireSessionStoreRepository.getIfInitialized()
            ?: error("FireSessionStore must be initialized")
        ProfileViewModelFactory(store)
    }

    override fun onCreateView(
        inflater: LayoutInflater,
        container: ViewGroup?,
        savedInstanceState: Bundle?,
    ): View {
        viewModel.loadProfile(args.username)
        return ComposeView(requireContext()).apply {
            setViewCompositionStrategy(ViewCompositionStrategy.DisposeOnViewTreeLifecycleDestroyed)
            setContent {
                FireAppTheme {
                    val actions by viewModel.actions.collectAsState()
                    val loading by viewModel.actionsLoading.collectAsState()
                    val loaded by viewModel.hasLoadedActionsOnce.collectAsState()
                    val error by viewModel.error.collectAsState()
                    LaunchedEffect(args.username) {
                        viewModel.loadActions(args.username, force = true)
                    }
                    ActivityTimelineScreen(
                        actions = actions,
                        loading = loading,
                        loaded = loaded,
                        error = error,
                        onRetry = { viewModel.loadActions(args.username, force = true) },
                        onActionClick = ::openAction,
                        onLoadMore = { viewModel.loadMoreActions() },
                        onBack = { findNavController().navigateUp() },
                    )
                }
            }
        }
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

    private class ProfileViewModelFactory(
        private val sessionStore: FireSessionStore,
    ) : ViewModelProvider.Factory {
        @Suppress("UNCHECKED_CAST")
        override fun <T : ViewModel> create(modelClass: Class<T>): T {
            return ProfileViewModel.create(sessionStore) as T
        }
    }
}

@Composable
private fun ActivityTimelineScreen(
    actions: List<UserActionState>,
    loading: Boolean,
    loaded: Boolean,
    error: String?,
    onRetry: () -> Unit,
    onActionClick: (UserActionState) -> Unit,
    onLoadMore: () -> Unit,
    onBack: () -> Unit,
) {
    FireSecondaryScaffold(title = "我的动态", onBack = onBack) {
        when {
            loading && actions.isEmpty() -> FireEmptyState(title = "正在加载动态", message = "稍候即可看到最近活动。")
            error != null && actions.isEmpty() -> FireEmptyState(
                title = "动态加载失败",
                message = error,
                actionLabel = "重试",
                onAction = onRetry,
            )
            loaded && actions.isEmpty() -> FireEmptyState(
                title = "暂无动态",
                message = "发布话题或回复后会出现在这里。",
                icon = Icons.AutoMirrored.Filled.ViewList,
            )
            else -> {
                LazyColumn(
                    modifier = Modifier
                        .fillMaxSize()
                        .padding(horizontal = 16.dp),
                ) {
                    item {
                        FireSettingsCard {
                            actions.forEachIndexed { index, action ->
                                ProfileActivityRow(action = action, onClick = { onActionClick(action) })
                                if (index == actions.lastIndex) {
                                    LaunchedEffect(actions.size) { onLoadMore() }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
