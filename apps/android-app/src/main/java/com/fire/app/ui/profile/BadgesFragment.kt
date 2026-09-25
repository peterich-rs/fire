package com.fire.app.ui.profile

import android.os.Bundle
import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.EmojiEvents
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.ComposeView
import androidx.compose.ui.platform.ViewCompositionStrategy
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.fragment.app.Fragment
import androidx.fragment.app.viewModels
import androidx.lifecycle.ViewModel
import androidx.lifecycle.ViewModelProvider
import androidx.navigation.fragment.findNavController
import com.fire.app.core.theme.compose.FireShapes
import com.fire.app.core.theme.compose.fireExtended
import com.fire.app.core.ui.compose.FireAppTheme
import com.fire.app.core.ui.compose.FireEmptyState
import com.fire.app.core.ui.compose.FireSecondaryScaffold
import com.fire.app.core.ui.compose.FireSectionHeader
import com.fire.app.session.FireSessionStore
import com.fire.app.session.FireSessionStoreRepository
import uniffi.fire_uniffi_user.BadgeState

class BadgesFragment : Fragment() {

    private val viewModel: ProfileViewModel by viewModels {
        val store = FireSessionStoreRepository.getIfInitialized()
            ?: error("FireSessionStore must be initialized")
        object : ViewModelProvider.Factory {
            @Suppress("UNCHECKED_CAST")
            override fun <T : ViewModel> create(modelClass: Class<T>): T {
                return ProfileViewModel.create(store) as T
            }
        }
    }

    override fun onCreateView(
        inflater: LayoutInflater,
        container: ViewGroup?,
        savedInstanceState: Bundle?,
    ): View {
        viewModel.loadProfile(null)
        return ComposeView(requireContext()).apply {
            setViewCompositionStrategy(ViewCompositionStrategy.DisposeOnViewTreeLifecycleDestroyed)
            setContent {
                FireAppTheme {
                    val summary by viewModel.summary.collectAsState()
                    val loading by viewModel.isLoading.collectAsState()
                    BadgesScreen(
                        badges = summary?.badges.orEmpty(),
                        loading = loading,
                        onBadgeClick = { badge ->
                            findNavController().navigate(
                                BadgesFragmentDirections.actionBadgesToDetail(badgeId = badge.id.toLong()),
                            )
                        },
                        onBack = { findNavController().navigateUp() },
                    )
                }
            }
        }
    }
}

private enum class BadgeSection(val title: String, val typeId: UInt, val color: Color) {
    Gold("金徽章", 1u, Color(0xFFE6AD29)),
    Silver("银徽章", 2u, Color(0xFF99A3B8)),
    Bronze("铜徽章", 3u, Color(0xFFBA7D47)),
    Other("其他徽章", 0u, Color(0xFF8E8E93)),
}

@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun BadgesScreen(
    badges: List<BadgeState>,
    loading: Boolean,
    onBadgeClick: (BadgeState) -> Unit,
    onBack: () -> Unit,
) {
    FireSecondaryScaffold(title = "我的勋章", onBack = onBack) {
        if (loading && badges.isEmpty()) {
            FireEmptyState(title = "正在加载勋章", message = "稍候即可看到已获得的徽章。")
            return@FireSecondaryScaffold
        }
        if (badges.isEmpty()) {
            FireEmptyState(
                title = "还没有勋章",
                message = "参与社区后获得的徽章会出现在这里。",
                icon = Icons.Filled.EmojiEvents,
            )
            return@FireSecondaryScaffold
        }
        Column(
            modifier = Modifier
                .fillMaxSize()
                .verticalScroll(rememberScrollState())
                .padding(horizontal = 16.dp)
                .padding(bottom = 24.dp),
        ) {
            Text(
                text = "共 ${badges.size} 枚",
                color = MaterialTheme.fireExtended.subtleInk,
                modifier = Modifier.padding(bottom = 16.dp),
            )
            BadgeSection.entries.forEach { section ->
                val group = badges.filter { badge ->
                    when (section) {
                        BadgeSection.Other -> badge.badgeTypeId != 1u && badge.badgeTypeId != 2u && badge.badgeTypeId != 3u
                        else -> badge.badgeTypeId == section.typeId
                    }
                }
                if (group.isEmpty()) return@forEach
                FireSectionHeader(section.title)
                FlowRow(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(top = 10.dp, bottom = 16.dp),
                    horizontalArrangement = Arrangement.spacedBy(8.dp),
                    verticalArrangement = Arrangement.spacedBy(8.dp),
                ) {
                    group.forEach { badge ->
                        Text(
                            text = badge.name,
                            color = Color.White,
                            fontSize = 13.sp,
                            fontWeight = FontWeight.SemiBold,
                            modifier = Modifier
                                .clip(FireShapes.chip)
                                .background(section.color)
                                .clickable { onBadgeClick(badge) }
                                .padding(horizontal = 12.dp, vertical = 8.dp),
                        )
                    }
                }
            }
        }
    }
}
