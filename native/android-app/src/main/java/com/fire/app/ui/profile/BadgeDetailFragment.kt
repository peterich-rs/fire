package com.fire.app.ui.profile

import android.os.Bundle
import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.ComposeView
import androidx.compose.ui.platform.ViewCompositionStrategy
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.fragment.app.Fragment
import androidx.lifecycle.lifecycleScope
import androidx.navigation.fragment.findNavController
import com.fire.app.core.theme.compose.fireExtended
import com.fire.app.core.ui.HtmlText
import com.fire.app.core.ui.compose.FireAppTheme
import com.fire.app.core.ui.compose.FireEmptyState
import com.fire.app.core.ui.compose.FireErrorBanner
import com.fire.app.core.ui.compose.FireSecondaryScaffold
import com.fire.app.core.ui.compose.FireSettingsCard
import com.fire.app.session.FireSessionStoreRepository
import kotlinx.coroutines.launch
import uniffi.fire_uniffi_user.BadgeState

class BadgeDetailFragment : Fragment() {

    override fun onCreateView(
        inflater: LayoutInflater,
        container: ViewGroup?,
        savedInstanceState: Bundle?,
    ): View {
        val badgeId = BadgeDetailFragmentArgs.fromBundle(requireArguments()).badgeId.toULong()
        return ComposeView(requireContext()).apply {
            setViewCompositionStrategy(ViewCompositionStrategy.DisposeOnViewTreeLifecycleDestroyed)
            setContent {
                FireAppTheme {
                    var badge by remember { mutableStateOf<BadgeState?>(null) }
                    var error by remember { mutableStateOf<String?>(null) }
                    var loading by remember { mutableStateOf(true) }
                    LaunchedEffect(badgeId) {
                        loading = true
                        error = null
                        val store = FireSessionStoreRepository.getIfInitialized()
                        if (store == null) {
                            error = "会话未就绪"
                            loading = false
                            return@LaunchedEffect
                        }
                        runCatching { store.fetchBadgeDetail(badgeId) }
                            .onSuccess { badge = it }
                            .onFailure { error = it.message }
                        loading = false
                    }
                    val colors = MaterialTheme.fireExtended
                    FireSecondaryScaffold(title = "徽章", onBack = { findNavController().navigateUp() }) {
                        Column(
                            modifier = Modifier
                                .fillMaxSize()
                                .verticalScroll(rememberScrollState())
                                .padding(16.dp),
                        ) {
                            error?.let { FireErrorBanner(it) }
                            when {
                                loading && badge == null -> FireEmptyState("正在加载", "获取徽章详情…")
                                badge == null -> FireEmptyState("未找到徽章信息", "该徽章可能已失效。")
                                else -> {
                                    val current = badge!!
                                    FireSettingsCard {
                                        Column(Modifier.padding(18.dp)) {
                                            Text(
                                                text = current.name,
                                                color = colors.ink,
                                                fontSize = 20.sp,
                                                fontWeight = FontWeight.Bold,
                                            )
                                            Spacer(Modifier.height(6.dp))
                                            Text(
                                                text = typeLabel(current.badgeTypeId),
                                                color = colors.subtleInk,
                                                fontSize = 13.sp,
                                                fontWeight = FontWeight.SemiBold,
                                            )
                                            Spacer(Modifier.height(4.dp))
                                            Text(
                                                text = "已授予 ${ProfileFormat.number(current.grantCount)} 次",
                                                color = colors.tertiaryInk,
                                                fontSize = 13.sp,
                                            )
                                        }
                                    }
                                    HtmlText.toPlain(current.description)?.let { body ->
                                        Spacer(Modifier.height(12.dp))
                                        FireSettingsCard {
                                            Column(Modifier.padding(16.dp)) {
                                                Text("简介", color = colors.tertiaryInk, fontSize = 12.sp)
                                                Spacer(Modifier.height(8.dp))
                                                Text(body, color = colors.ink, fontSize = 15.sp)
                                            }
                                        }
                                    }
                                    HtmlText.toPlain(current.longDescription)?.let { body ->
                                        Spacer(Modifier.height(12.dp))
                                        FireSettingsCard {
                                            Column(Modifier.padding(16.dp)) {
                                                Text("详情", color = colors.tertiaryInk, fontSize = 12.sp)
                                                Spacer(Modifier.height(8.dp))
                                                Text(body, color = colors.ink, fontSize = 15.sp)
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private fun typeLabel(typeId: UInt): String = when (typeId) {
        1u -> "金徽章"
        2u -> "银徽章"
        3u -> "铜徽章"
        else -> "徽章"
    }
}
