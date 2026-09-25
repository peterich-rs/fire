package com.fire.app.ui.profile

import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.content.Intent
import android.os.Bundle
import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.DropdownMenu
import androidx.compose.foundation.layout.Box
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.ComposeView
import androidx.compose.ui.platform.ViewCompositionStrategy
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.fragment.app.Fragment
import androidx.lifecycle.lifecycleScope
import androidx.navigation.fragment.findNavController
import com.fire.app.core.theme.compose.FireShapes
import com.fire.app.core.theme.compose.fireExtended
import com.fire.app.core.ui.compose.FireAppTheme
import com.fire.app.core.ui.compose.FireErrorBanner
import com.fire.app.core.ui.compose.FireSecondaryScaffold
import com.fire.app.core.ui.compose.FireSectionHeader
import com.fire.app.core.ui.compose.FireSettingsCard
import com.fire.app.session.FireSessionStoreRepository
import java.time.Instant
import java.time.temporal.ChronoUnit
import kotlinx.coroutines.launch
import uniffi.fire_uniffi_user.InviteCreateRequestState
import uniffi.fire_uniffi_user.InviteLinkState

class InviteLinksFragment : Fragment() {

    override fun onCreateView(
        inflater: LayoutInflater,
        container: ViewGroup?,
        savedInstanceState: Bundle?,
    ): View {
        val username = InviteLinksFragmentArgs.fromBundle(requireArguments()).username
        return ComposeView(requireContext()).apply {
            setViewCompositionStrategy(ViewCompositionStrategy.DisposeOnViewTreeLifecycleDestroyed)
            setContent {
                FireAppTheme {
                    var invites by remember { mutableStateOf<List<InviteLinkState>>(emptyList()) }
                    var loading by remember { mutableStateOf(false) }
                    var submitting by remember { mutableStateOf(false) }
                    var error by remember { mutableStateOf<String?>(null) }
                    var notice by remember { mutableStateOf<String?>(null) }
                    var maxRedemptions by remember { mutableStateOf(5u) }
                    var expiryDays by remember { mutableStateOf(7) }
                    var description by remember { mutableStateOf("") }
                    var email by remember { mutableStateOf("") }
                    val colors = MaterialTheme.fireExtended

                    fun reload() {
                        val store = FireSessionStoreRepository.getIfInitialized() ?: return
                        loading = true
                        viewLifecycleOwner.lifecycleScope.launch {
                            runCatching { store.fetchPendingInvites(username) }
                                .onSuccess { invites = it; error = null }
                                .onFailure { error = it.message }
                            loading = false
                        }
                    }

                    LaunchedEffect(username) { reload() }

                    FireSecondaryScaffold(title = "邀请链接", onBack = { findNavController().navigateUp() }) {
                        Column(
                            modifier = Modifier
                                .fillMaxSize()
                                .verticalScroll(rememberScrollState())
                                .padding(16.dp),
                        ) {
                            notice?.let {
                                Text(it, color = colors.success, modifier = Modifier.padding(bottom = 12.dp))
                            }
                            error?.let {
                                FireErrorBanner(it) { error = null }
                                Spacer(Modifier.height(12.dp))
                            }

                            FireSectionHeader("创建邀请链接")
                            Spacer(Modifier.height(10.dp))
                            FireSettingsCard {
                                Column(Modifier.padding(14.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                                    ChoiceRow(
                                        label = "可用次数",
                                        value = "$maxRedemptions 次",
                                        options = listOf(1u, 3u, 5u, 10u).map { it to "$it 次" },
                                        onSelect = { maxRedemptions = it },
                                    )
                                    ChoiceRow(
                                        label = "有效期",
                                        value = expiryLabel(expiryDays),
                                        options = listOf(1 to "1 天", 7 to "7 天", 30 to "30 天", -1 to "永不过期"),
                                        onSelect = { expiryDays = it },
                                    )
                                    OutlinedTextField(
                                        value = description,
                                        onValueChange = { description = it },
                                        modifier = Modifier.fillMaxWidth(),
                                        label = { Text("说明（可选）") },
                                        singleLine = true,
                                    )
                                    OutlinedTextField(
                                        value = email,
                                        onValueChange = { email = it },
                                        modifier = Modifier.fillMaxWidth(),
                                        label = { Text("邮箱（可选）") },
                                        singleLine = true,
                                    )
                                    Button(
                                        onClick = {
                                            val store = FireSessionStoreRepository.getIfInitialized() ?: return@Button
                                            submitting = true
                                            viewLifecycleOwner.lifecycleScope.launch {
                                                runCatching {
                                                    store.createInviteLink(
                                                        InviteCreateRequestState(
                                                            maxRedemptionsAllowed = maxRedemptions,
                                                            expiresAt = expiryIso(expiryDays),
                                                            description = description.trim().ifEmpty { null },
                                                            email = email.trim().ifEmpty { null },
                                                        ),
                                                    )
                                                }.onSuccess { created ->
                                                    notice = "邀请链接已生成"
                                                    error = null
                                                    invites = listOf(created) + invites
                                                }.onFailure { error = it.message }
                                                submitting = false
                                            }
                                        },
                                        enabled = !submitting,
                                        modifier = Modifier.fillMaxWidth(),
                                        colors = ButtonDefaults.buttonColors(containerColor = colors.accent),
                                        shape = FireShapes.chip,
                                    ) {
                                        Text(if (submitting) "生成中…" else "生成邀请链接")
                                    }
                                }
                            }

                            Spacer(Modifier.height(16.dp))
                            FireSectionHeader("待使用邀请")
                            Spacer(Modifier.height(10.dp))
                            FireSettingsCard {
                                if (loading && invites.isEmpty()) {
                                    Text("加载中…", color = colors.tertiaryInk, modifier = Modifier.padding(16.dp))
                                } else if (invites.isEmpty()) {
                                    Text(
                                        "暂时没有待使用的邀请链接。",
                                        color = colors.subtleInk,
                                        modifier = Modifier.padding(16.dp),
                                    )
                                } else {
                                    invites.forEach { invite ->
                                        val link = effectiveLink(invite)
                                        Column(Modifier.padding(14.dp)) {
                                            Text(link, color = colors.ink, fontSize = 15.sp)
                                            Spacer(Modifier.height(8.dp))
                                            Text(usageText(invite), color = colors.subtleInk, fontSize = 13.sp)
                                            Row {
                                                TextButton(onClick = {
                                                    copyLink(link)
                                                    notice = "邀请链接已复制"
                                                }) { Text("复制") }
                                                TextButton(onClick = { shareLink(link) }) { Text("分享") }
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

    private fun copyLink(link: String) {
        val clipboard = requireContext().getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
        clipboard.setPrimaryClip(ClipData.newPlainText("invite", link))
    }

    private fun shareLink(link: String) {
        startActivity(
            Intent.createChooser(
                Intent(Intent.ACTION_SEND).apply {
                    type = "text/plain"
                    putExtra(Intent.EXTRA_TEXT, link)
                },
                "分享邀请链接",
            ),
        )
    }

    private fun effectiveLink(invite: InviteLinkState): String {
        val link = invite.inviteLink.trim()
        if (link.isNotEmpty()) return link
        val key = invite.invite?.inviteKey?.trim().orEmpty()
        return if (key.isEmpty()) "" else "https://linux.do/invites/$key"
    }

    private fun usageText(invite: InviteLinkState): String {
        val used = invite.invite?.redemptionCount ?: 0u
        val max = invite.invite?.maxRedemptionsAllowed ?: 0u
        val expiry = if (invite.invite?.expiresAt.isNullOrBlank()) "长期有效" else invite.invite?.expiresAt
        return "已使用 $used / $max · $expiry"
    }

    private fun expiryLabel(days: Int): String = when (days) {
        1 -> "1 天"
        7 -> "7 天"
        30 -> "30 天"
        else -> "永不过期"
    }

    private fun expiryIso(days: Int): String? {
        if (days <= 0) return null
        return Instant.now().plus(days.toLong(), ChronoUnit.DAYS).toString()
    }
}

@androidx.compose.runtime.Composable
private fun <T> ChoiceRow(
    label: String,
    value: String,
    options: List<Pair<T, String>>,
    onSelect: (T) -> Unit,
) {
    var expanded by remember { mutableStateOf(false) }
    val colors = MaterialTheme.fireExtended
    Box {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(vertical = 4.dp),
        ) {
            Text(label, color = colors.ink, modifier = Modifier.weight(1f), fontSize = 16.sp)
            TextButton(onClick = { expanded = true }) { Text(value) }
        }
        DropdownMenu(expanded = expanded, onDismissRequest = { expanded = false }) {
            options.forEach { (item, title) ->
                DropdownMenuItem(
                    text = { Text(title) },
                    onClick = {
                        onSelect(item)
                        expanded = false
                    },
                )
            }
        }
    }
}
