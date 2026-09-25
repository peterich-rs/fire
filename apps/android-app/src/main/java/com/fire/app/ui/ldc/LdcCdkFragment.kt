package com.fire.app.ui.ldc

import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.os.Bundle
import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import android.widget.LinearLayout
import android.widget.TextView
import android.widget.Toast
import androidx.fragment.app.Fragment
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.ViewModel
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.lifecycleScope
import androidx.lifecycle.repeatOnLifecycle
import com.fire.app.R
import com.fire.app.databinding.FragmentLdcBinding
import com.fire.app.session.FireSessionStore
import com.fire.app.session.FireSessionStoreRepository
import kotlinx.coroutines.launch
import uniffi.fire_uniffi_ldc.CdkUserInfoState
import uniffi.fire_uniffi_ldc.LdcApprovalStatusKindState
import uniffi.fire_uniffi_ldc.LdcApprovalStatusState
import uniffi.fire_uniffi_ldc.LdcUserInfoState

abstract class LdcCdkFragment : Fragment() {

    protected abstract val mode: LdcCdkMode

    private var _binding: FragmentLdcBinding? = null
    private val binding: FragmentLdcBinding
        get() = _binding ?: error("Fragment binding is only valid between onCreateView and onDestroyView")

    private var viewModel: LdcCdkViewModel? = null

    override fun onCreateView(
        inflater: LayoutInflater,
        container: ViewGroup?,
        savedInstanceState: Bundle?,
    ): View {
        _binding = FragmentLdcBinding.inflate(inflater, container, false)
        return binding.root
    }

    override fun onViewCreated(view: View, savedInstanceState: Bundle?) {
        super.onViewCreated(view, savedInstanceState)

        configureStaticText()
        viewLifecycleOwner.lifecycleScope.launch {
            val sessionStore = FireSessionStoreRepository.get(requireContext())
            viewModel = ViewModelProvider(
                this@LdcCdkFragment,
                LdcCdkViewModelFactory(sessionStore, mode),
            )[LdcCdkViewModel::class.java]

            setupActions()
            observeState()
            viewModel?.loadUserInfo()
        }
    }

    override fun onDestroyView() {
        super.onDestroyView()
        _binding = null
    }

    private fun configureStaticText() {
        when (mode) {
            LdcCdkMode.LDC -> {
                binding.emptyTitle.setText(R.string.ldc_empty)
                binding.emptyDetail.setText(R.string.ldc_empty_detail)
                binding.primaryMetricLabel.setText(R.string.ldc_balance_available)
                binding.secondaryMetricLabel.setText(R.string.ldc_balance_community)
            }
            LdcCdkMode.CDK -> {
                binding.emptyTitle.setText(R.string.cdk_empty)
                binding.emptyDetail.setText(R.string.cdk_empty_detail)
                binding.primaryMetricLabel.setText(R.string.cdk_score)
                binding.secondaryMetricPanel.visibility = View.GONE
            }
        }
    }

    private fun setupActions() {
        binding.prepareAuthButton.setOnClickListener {
            viewModel?.prepareAuthorization(getString(R.string.oauth_link_ready))
        }
        binding.completeAuthButton.setOnClickListener {
            viewModel?.completeAuthorization(
                callbackMissingMessage = getString(R.string.oauth_callback_missing),
                completedMessage = when (mode) {
                    LdcCdkMode.LDC -> getString(R.string.ldc_auth_complete)
                    LdcCdkMode.CDK -> getString(R.string.cdk_auth_complete)
                },
                pendingMessage = getString(R.string.oauth_pending_notice),
                deniedMessage = when (mode) {
                    LdcCdkMode.LDC -> getString(R.string.ldc_auth_denied)
                    LdcCdkMode.CDK -> getString(R.string.cdk_auth_denied)
                },
            )
        }
        binding.logoutButton.setOnClickListener {
            viewModel?.logout(
                when (mode) {
                    LdcCdkMode.LDC -> getString(R.string.ldc_logout_complete)
                    LdcCdkMode.CDK -> getString(R.string.cdk_logout_complete)
                },
            )
        }
        binding.refreshButton.setOnClickListener {
            viewModel?.loadUserInfo(force = true)
        }
    }

    private fun observeState() {
        val vm = viewModel ?: return
        viewLifecycleOwner.lifecycleScope.launch {
            viewLifecycleOwner.repeatOnLifecycle(Lifecycle.State.STARTED) {
                vm.state.collect { render(it) }
            }
        }
    }

    private fun render(state: LdcCdkUiState) {
        binding.loadingView.visibility = if (state.isLoadingUserInfo && state.userInfo == null) {
            View.VISIBLE
        } else {
            View.GONE
        }
        binding.refreshButton.isEnabled = !state.isLoadingUserInfo && !state.isBusy

        renderMessage(binding.noticePanel, binding.noticeText, state.noticeMessage)
        renderMessage(binding.errorPanel, binding.errorText, state.errorMessage)

        when (val info = state.userInfo) {
            null -> renderEmpty()
            is LdcCdkUserInfo.Ldc -> renderLdc(info.info)
            is LdcCdkUserInfo.Cdk -> renderCdk(info.info)
        }

        renderAuthorization(state)
    }

    private fun renderEmpty() {
        binding.accountContent.visibility = View.GONE
        binding.emptyContent.visibility = View.VISIBLE
        binding.detailsPanel.visibility = View.GONE
        binding.logoutButton.visibility = View.GONE
    }

    private fun renderLdc(info: LdcUserInfoState) {
        binding.emptyContent.visibility = View.GONE
        binding.accountContent.visibility = View.VISIBLE
        binding.secondaryMetricPanel.visibility = View.VISIBLE
        binding.logoutButton.visibility = View.VISIBLE

        binding.accountTitle.text = info.nickname.ifBlank { "@${info.username}" }
        binding.accountSubtitle.text = "@${info.username} / TL${info.trustLevel}"
        binding.statusChip.text = getString(
            if (info.isPayKey) R.string.ldc_status_pay_enabled else R.string.ldc_status_read_only,
        )
        binding.primaryMetricValue.text = info.availableBalance
        binding.secondaryMetricValue.text = info.communityBalance
        binding.primaryMetricLabel.setText(R.string.ldc_balance_available)
        binding.secondaryMetricLabel.setText(R.string.ldc_balance_community)

        binding.detailsPanel.visibility = View.VISIBLE
        binding.detailsPanel.removeAllViews()
        addSectionTitle(binding.detailsPanel, getString(R.string.ldc_metrics_title))
        addKeyValue(binding.detailsPanel, getString(R.string.ldc_total_receive), info.totalReceive)
        addKeyValue(binding.detailsPanel, getString(R.string.ldc_total_payment), info.totalPayment)
        addKeyValue(binding.detailsPanel, getString(R.string.ldc_total_transfer), info.totalTransfer)
        addKeyValue(binding.detailsPanel, getString(R.string.ldc_total_community), info.totalCommunity)
        addKeyValue(binding.detailsPanel, getString(R.string.ldc_remain_quota), info.remainQuota)
        addKeyValue(binding.detailsPanel, getString(R.string.ldc_daily_limit), info.dailyLimit.toString())

        addSectionTitle(binding.detailsPanel, getString(R.string.ldc_permissions_title))
        addKeyValue(binding.detailsPanel, getString(R.string.ldc_pay_score), info.payScore.toString())
        addKeyValue(binding.detailsPanel, getString(R.string.ldc_pay_level), info.payLevel.toString())
        addKeyValue(binding.detailsPanel, getString(R.string.ldc_pay_key), boolText(info.isPayKey))
        addKeyValue(binding.detailsPanel, getString(R.string.ldc_admin), boolText(info.isAdmin))
        info.gamificationScore?.let {
            addKeyValue(binding.detailsPanel, getString(R.string.ldc_gamification_score), it.toString())
        }
    }

    private fun renderCdk(info: CdkUserInfoState) {
        binding.emptyContent.visibility = View.GONE
        binding.accountContent.visibility = View.VISIBLE
        binding.secondaryMetricPanel.visibility = View.GONE
        binding.logoutButton.visibility = View.VISIBLE
        binding.detailsPanel.visibility = View.GONE

        binding.accountTitle.text = info.nickname.ifBlank { "@${info.username}" }
        binding.accountSubtitle.text = "@${info.username} / TL${info.trustLevel}"
        binding.statusChip.setText(R.string.cdk_status_connected)
        binding.primaryMetricValue.text = info.score.toString()
        binding.primaryMetricLabel.setText(R.string.cdk_score)
    }

    private fun renderAuthorization(state: LdcCdkUiState) {
        binding.prepareAuthButton.text = getString(
            if (state.isPreparingAuthorization) R.string.oauth_preparing else R.string.oauth_prepare,
        )
        binding.prepareAuthButton.isEnabled = !state.isBusy

        binding.completeAuthButton.text = getString(
            if (state.isCompletingAuthorization) R.string.oauth_completing else R.string.oauth_complete,
        )
        binding.completeAuthButton.visibility = if (state.authorization?.approvalPath != null) {
            View.VISIBLE
        } else {
            View.GONE
        }
        binding.completeAuthButton.isEnabled = !state.isCompletingAuthorization && !state.isLoggingOut

        binding.logoutButton.text = getString(
            if (state.isLoggingOut) R.string.oauth_logging_out else R.string.oauth_logout,
        )
        binding.logoutButton.isEnabled = !state.isCompletingAuthorization && !state.isLoggingOut

        binding.authDetailsContainer.removeAllViews()
        val auth = state.authorization
        binding.authDetailsContainer.visibility = if (auth == null) View.GONE else View.VISIBLE
        if (auth != null) {
            addCopyableRow(binding.authDetailsContainer, getString(R.string.oauth_state), auth.state)
            addCopyableRow(binding.authDetailsContainer, getString(R.string.oauth_authorization_url), auth.url)
            auth.approvalPath?.let {
                addCopyableRow(binding.authDetailsContainer, getString(R.string.oauth_approval_path), it)
            }
            auth.approvalStatus?.let {
                addKeyValue(
                    binding.authDetailsContainer,
                    getString(R.string.oauth_status),
                    approvalText(it),
                )
            }
        }
    }

    private fun renderMessage(panel: View, textView: TextView, message: String?) {
        panel.visibility = if (message.isNullOrBlank()) View.GONE else View.VISIBLE
        textView.text = message.orEmpty()
    }

    private fun addSectionTitle(parent: LinearLayout, title: String) {
        val view = TextView(parent.context).apply {
            text = title
            setTextAppearance(com.google.android.material.R.style.TextAppearance_Material3_TitleSmall)
            setTextColor(resources.getColor(R.color.fire_text_primary, null))
            setTypeface(typeface, android.graphics.Typeface.BOLD)
            setPadding(0, if (parent.childCount == 0) 0 else dp(16), 0, dp(6))
        }
        parent.addView(view)
    }

    private fun addKeyValue(parent: LinearLayout, label: String, value: String) {
        val row = LinearLayout(parent.context).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = android.view.Gravity.CENTER_VERTICAL
            setPadding(0, dp(8), 0, dp(8))
        }
        val labelView = TextView(parent.context).apply {
            text = label
            setTextAppearance(com.google.android.material.R.style.TextAppearance_Material3_BodyMedium)
            setTextColor(resources.getColor(R.color.fire_text_secondary, null))
            layoutParams = LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f)
        }
        val valueView = TextView(parent.context).apply {
            text = value
            textAlignment = View.TEXT_ALIGNMENT_TEXT_END
            setTextAppearance(com.google.android.material.R.style.TextAppearance_Material3_BodyMedium)
            setTextColor(resources.getColor(R.color.fire_text_primary, null))
            setTypeface(typeface, android.graphics.Typeface.BOLD)
        }
        row.addView(labelView)
        row.addView(valueView)
        parent.addView(row)
    }

    private fun addCopyableRow(parent: LinearLayout, label: String, value: String) {
        val row = LinearLayout(parent.context).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(0, dp(8), 0, dp(8))
        }
        val labelView = TextView(parent.context).apply {
            text = label
            setTextAppearance(com.google.android.material.R.style.TextAppearance_Material3_BodySmall)
            setTextColor(resources.getColor(R.color.fire_text_tertiary, null))
        }
        val valueView = TextView(parent.context).apply {
            text = value
            setTextIsSelectable(true)
            setTextAppearance(com.google.android.material.R.style.TextAppearance_Material3_BodySmall)
            setTextColor(resources.getColor(R.color.fire_text_primary, null))
            setPadding(0, dp(4), 0, dp(4))
        }
        val copyButton = TextView(parent.context).apply {
            text = getString(R.string.oauth_copy)
            setTextAppearance(com.google.android.material.R.style.TextAppearance_Material3_LabelMedium)
            setTextColor(resources.getColor(R.color.fire_accent, null))
            setPadding(0, dp(4), 0, dp(4))
            setOnClickListener { copyToClipboard(label, value) }
        }
        row.addView(labelView)
        row.addView(valueView)
        row.addView(copyButton)
        parent.addView(row)
    }

    private fun copyToClipboard(label: String, value: String) {
        val clipboard = requireContext().getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
        clipboard.setPrimaryClip(ClipData.newPlainText(label, value))
        Toast.makeText(requireContext(), getString(R.string.oauth_copied, label), Toast.LENGTH_SHORT).show()
    }

    private fun approvalText(status: LdcApprovalStatusState): String {
        return when (status.kind) {
            LdcApprovalStatusKindState.PENDING -> getString(R.string.oauth_status_pending)
            LdcApprovalStatusKindState.APPROVED -> getString(R.string.oauth_status_approved)
            LdcApprovalStatusKindState.DENIED -> getString(R.string.oauth_status_denied)
        }
    }

    private fun boolText(value: Boolean): String {
        return getString(if (value) R.string.common_yes else R.string.common_no)
    }

    private fun dp(value: Int): Int {
        return (value * resources.displayMetrics.density).toInt()
    }

    private class LdcCdkViewModelFactory(
        private val sessionStore: FireSessionStore,
        private val mode: LdcCdkMode,
    ) : ViewModelProvider.Factory {
        @Suppress("UNCHECKED_CAST")
        override fun <T : ViewModel> create(modelClass: Class<T>): T {
            if (modelClass.isAssignableFrom(LdcCdkViewModel::class.java)) {
                return LdcCdkViewModel.create(sessionStore, mode) as T
            }
            throw IllegalArgumentException("Unknown ViewModel class: ${modelClass.name}")
        }
    }
}
