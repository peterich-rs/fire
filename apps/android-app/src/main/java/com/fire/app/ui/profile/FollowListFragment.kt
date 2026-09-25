package com.fire.app.ui.profile

import android.os.Bundle
import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Group
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.ComposeView
import androidx.compose.ui.platform.ViewCompositionStrategy
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.fragment.app.Fragment
import androidx.fragment.app.viewModels
import androidx.lifecycle.ViewModel
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.viewModelScope
import androidx.navigation.fragment.findNavController
import com.fire.app.core.theme.compose.fireExtended
import com.fire.app.core.ui.compose.FireAppTheme
import com.fire.app.core.ui.compose.FireEmptyState
import com.fire.app.core.ui.compose.FireRemoteAvatar
import com.fire.app.core.ui.compose.FireSecondaryScaffold
import com.fire.app.core.ui.compose.FireSettingsCard
import com.fire.app.data.repository.UserRepository
import com.fire.app.session.FireSessionStore
import com.fire.app.session.FireSessionStoreRepository
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import uniffi.fire_uniffi_user.FollowUserState

class FollowListFragment : Fragment() {

    private val args: FollowListFragmentArgs by lazy {
        FollowListFragmentArgs.fromBundle(requireArguments())
    }

    private val viewModel: FollowListViewModel by viewModels {
        val store = FireSessionStoreRepository.getIfInitialized()
            ?: error("FireSessionStore must be initialized")
        FollowListViewModel.factory(store, args.username, args.kind)
    }

    override fun onCreateView(
        inflater: LayoutInflater,
        container: ViewGroup?,
        savedInstanceState: Bundle?,
    ): View {
        val title = if (args.kind == "followers") "粉丝" else "关注"
        return ComposeView(requireContext()).apply {
            setViewCompositionStrategy(ViewCompositionStrategy.DisposeOnViewTreeLifecycleDestroyed)
            setContent {
                FireAppTheme {
                    val users by viewModel.users.collectAsState()
                    val loading by viewModel.isLoading.collectAsState()
                    val error by viewModel.error.collectAsState()
                    LaunchedEffect(Unit) { viewModel.load() }
                    FollowListScreen(
                        title = title,
                        username = args.username,
                        users = users,
                        loading = loading,
                        error = error,
                        onRetry = { viewModel.load(force = true) },
                        onUserClick = { user ->
                            findNavController().navigate(
                                FollowListFragmentDirections.actionFollowListToProfile(user.username),
                            )
                        },
                        onBack = { findNavController().navigateUp() },
                    )
                }
            }
        }
    }
}

@Composable
private fun FollowListScreen(
    title: String,
    username: String,
    users: List<FollowUserState>,
    loading: Boolean,
    error: String?,
    onRetry: () -> Unit,
    onUserClick: (FollowUserState) -> Unit,
    onBack: () -> Unit,
) {
    val colors = MaterialTheme.fireExtended
    FireSecondaryScaffold(title = title, onBack = onBack) {
        when {
            loading && users.isEmpty() -> FireEmptyState(title = "加载中…", message = "正在获取$title")
            error != null && users.isEmpty() -> FireEmptyState(
                title = "${title}列表加载失败",
                message = error,
                actionLabel = "重试",
                onAction = onRetry,
            )
            users.isEmpty() -> FireEmptyState(
                title = "@$username 还没有$title",
                message = "关注关系会出现在这里。",
                icon = Icons.Filled.Group,
            )
            else -> {
                LazyColumn(
                    modifier = Modifier
                        .fillMaxSize()
                        .padding(horizontal = 16.dp),
                ) {
                    item {
                        FireSettingsCard {
                            users.forEach { user ->
                                FollowUserRow(user = user, onClick = { onUserClick(user) })
                            }
                        }
                    }
                }
            }
        }
        if (!error.isNullOrBlank() && users.isNotEmpty()) {
            Text(
                text = error,
                color = colors.error,
                modifier = Modifier.padding(16.dp),
            )
        }
    }
}

@Composable
private fun FollowUserRow(user: FollowUserState, onClick: () -> Unit) {
    val colors = MaterialTheme.fireExtended
    val name = user.name?.trim()?.takeIf { it.isNotEmpty() } ?: user.username
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clickable(onClick = onClick)
            .padding(horizontal = 14.dp, vertical = 12.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        FireRemoteAvatar(username = user.username, avatarTemplate = user.avatarTemplate, size = 40.dp)
        Column(modifier = Modifier.padding(start = 12.dp)) {
            Text(text = name, color = colors.ink, fontSize = 16.sp)
            Text(text = "@${user.username}", color = colors.subtleInk, fontSize = 13.sp)
        }
    }
}

class FollowListViewModel(
    private val repository: UserRepository,
    private val username: String,
    private val kind: String,
) : ViewModel() {
    private val _users = MutableStateFlow<List<FollowUserState>>(emptyList())
    val users = _users.asStateFlow()
    private val _isLoading = MutableStateFlow(false)
    val isLoading = _isLoading.asStateFlow()
    private val _error = MutableStateFlow<String?>(null)
    val error = _error.asStateFlow()

    fun load(force: Boolean = false) {
        if (_isLoading.value) return
        if (!force && _users.value.isNotEmpty()) return
        viewModelScope.launch {
            _isLoading.value = true
            _error.value = null
            try {
                _users.value = if (kind == "followers") {
                    repository.fetchFollowers(username)
                } else {
                    repository.fetchFollowing(username)
                }
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                _error.value = e.message
            } finally {
                _isLoading.value = false
            }
        }
    }

    companion object {
        fun factory(store: FireSessionStore, username: String, kind: String): ViewModelProvider.Factory =
            object : ViewModelProvider.Factory {
                @Suppress("UNCHECKED_CAST")
                override fun <T : ViewModel> create(modelClass: Class<T>): T {
                    return FollowListViewModel(UserRepository(store), username, kind) as T
                }
            }
    }
}
