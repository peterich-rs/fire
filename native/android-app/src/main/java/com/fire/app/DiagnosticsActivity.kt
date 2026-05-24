package com.fire.app

import android.content.Intent
import android.os.Bundle
import android.view.View
import android.view.ViewGroup
import android.widget.Button
import android.widget.FrameLayout
import android.widget.LinearLayout
import android.widget.TextView
import androidx.appcompat.app.AppCompatActivity
import androidx.lifecycle.lifecycleScope
import androidx.recyclerview.widget.DiffUtil
import androidx.recyclerview.widget.LinearLayoutManager
import androidx.recyclerview.widget.ListAdapter
import androidx.recyclerview.widget.RecyclerView
import com.fire.app.session.FireSessionStore
import com.fire.app.session.FireSessionStoreRepository
import kotlinx.coroutines.launch
import uniffi.fire_uniffi_diagnostics.LogFileSummaryState
import uniffi.fire_uniffi_diagnostics.NetworkTraceSummaryState

class DiagnosticsActivity : AppCompatActivity() {
    private data class RequestTraceListItem(
        val key: String,
        val stableId: Long,
        val contentSignature: String,
        val buildView: () -> View,
    )

    private class RequestTraceListAdapter :
        ListAdapter<RequestTraceListItem, RequestTraceListAdapter.DynamicViewHolder>(DiffCallback) {

        init {
            setHasStableIds(true)
        }

        override fun getItemId(position: Int): Long = getItem(position).stableId

        override fun onCreateViewHolder(parent: ViewGroup, viewType: Int): DynamicViewHolder {
            return DynamicViewHolder(FrameLayout(parent.context))
        }

        override fun onBindViewHolder(holder: DynamicViewHolder, position: Int) {
            holder.bind(getItem(position).buildView())
        }

        class DynamicViewHolder(private val container: FrameLayout) : RecyclerView.ViewHolder(container) {
            fun bind(view: View) {
                container.removeAllViews()
                if (view.parent != null) {
                    (view.parent as? ViewGroup)?.removeView(view)
                }
                container.addView(
                    view,
                    FrameLayout.LayoutParams(
                        ViewGroup.LayoutParams.MATCH_PARENT,
                        ViewGroup.LayoutParams.WRAP_CONTENT,
                    ),
                )
            }
        }

        private object DiffCallback : DiffUtil.ItemCallback<RequestTraceListItem>() {
            override fun areItemsTheSame(
                oldItem: RequestTraceListItem,
                newItem: RequestTraceListItem,
            ): Boolean = oldItem.key == newItem.key

            override fun areContentsTheSame(
                oldItem: RequestTraceListItem,
                newItem: RequestTraceListItem,
            ): Boolean = oldItem.contentSignature == newItem.contentSignature
        }
    }

    private lateinit var sessionStore: FireSessionStore
    private lateinit var requestSummaryText: TextView
    private lateinit var diagnosticsErrorText: TextView
    private lateinit var requestTraceRecyclerView: RecyclerView
    private lateinit var refreshDiagnosticsButton: Button
    private lateinit var openLogViewerButton: Button
    private val requestTraceAdapter = RequestTraceListAdapter()

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_diagnostics)

        supportActionBar?.setDisplayHomeAsUpEnabled(true)
        title = getString(R.string.diagnostics_title)

        sessionStore = FireSessionStoreRepository.get(applicationContext)
        requestSummaryText = findViewById(R.id.requestSummaryText)
        diagnosticsErrorText = findViewById(R.id.diagnosticsErrorText)
        requestTraceRecyclerView = findViewById(R.id.requestTraceRecyclerView)
        refreshDiagnosticsButton = findViewById(R.id.refreshDiagnosticsButton)
        openLogViewerButton = findViewById(R.id.openLogViewerButton)
        requestTraceRecyclerView.apply {
            layoutManager = LinearLayoutManager(this@DiagnosticsActivity)
            adapter = requestTraceAdapter
            itemAnimator = null
            setItemViewCacheSize(8)
            recycledViewPool.setMaxRecycledViews(0, 18)
        }

        refreshDiagnosticsButton.setOnClickListener { refreshDiagnostics() }
        openLogViewerButton.setOnClickListener {
            startActivity(Intent(this, LogViewerActivity::class.java))
        }

        refreshDiagnostics()
    }

    override fun onSupportNavigateUp(): Boolean {
        finish()
        return true
    }

    private fun refreshDiagnostics() {
        lifecycleScope.launch {
            setError(null)
            requestSummaryText.text = getString(R.string.diagnostics_loading)

            try {
                val traces = sessionStore.listNetworkTraces()
                val logFiles = sessionStore.listLogFiles()
                renderTraceSummary(traces, logFiles)
                renderTraceList(traces)
            } catch (error: Exception) {
                setError(error.localizedMessage ?: getString(R.string.diagnostics_trace_error))
                requestSummaryText.text = getString(R.string.diagnostics_trace_error)
                renderTraceList(emptyList())
            }
        }
    }

    private fun renderTraceSummary(
        traces: List<NetworkTraceSummaryState>,
        logFiles: List<LogFileSummaryState>,
    ) {
        requestSummaryText.text = buildString {
            appendLine("Captured Requests: ${traces.size}")
            appendLine("Log Files: ${logFiles.size}")
            traces.firstOrNull()?.let { latest ->
                append("Latest: ${DiagnosticsPresentation.compactUrl(latest.url)}")
            }
        }
    }

    private fun renderTraceList(traces: List<NetworkTraceSummaryState>) {
        if (traces.isEmpty()) {
            requestTraceAdapter.submitList(
                listOf(
                    requestTraceListItem(
                        key = "empty",
                        contentSignature = getString(R.string.diagnostics_no_traces),
                    ) {
                        TextView(this).apply {
                            text = getString(R.string.diagnostics_no_traces)
                            setTextAppearance(androidx.appcompat.R.style.TextAppearance_AppCompat_Body1)
                        }
                    },
                ),
            )
            return
        }

        requestTraceAdapter.submitList(
            traces.map { trace ->
                requestTraceListItem(
                    key = "trace:${trace.id}",
                    contentSignature = trace.toString(),
                ) {
                    requestTraceRow(trace)
                }
            },
        )
    }

    private fun requestTraceListItem(
        key: String,
        contentSignature: String,
        buildView: () -> View,
    ): RequestTraceListItem {
        return RequestTraceListItem(
            key = key,
            stableId = stableIdFor(key),
            contentSignature = contentSignature,
            buildView = buildView,
        )
    }

    private fun stableIdFor(key: String): Long {
        return key.fold(1125899906842597L) { hash, character ->
            (hash * 31) + character.code
        }
    }

    private fun requestTraceRow(trace: NetworkTraceSummaryState): View {
        return LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(0, 0, 0, 24)
            layoutParams = LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.WRAP_CONTENT,
            )
            setOnClickListener {
                startActivity(RequestTraceDetailActivity.intent(this@DiagnosticsActivity, trace.id))
            }

            addView(
                TextView(context).apply {
                    text = "${trace.method} ${DiagnosticsPresentation.compactUrl(trace.url)}"
                    setTextAppearance(androidx.appcompat.R.style.TextAppearance_AppCompat_Medium)
                },
            )

            addView(
                TextView(context).apply {
                    text = buildString {
                        append(trace.operation)
                        append(" · ")
                        append(
                            when (trace.outcome) {
                                uniffi.fire_uniffi_diagnostics.NetworkTraceOutcomeState.IN_PROGRESS -> "In Progress"
                                uniffi.fire_uniffi_diagnostics.NetworkTraceOutcomeState.SUCCEEDED -> "Succeeded"
                                uniffi.fire_uniffi_diagnostics.NetworkTraceOutcomeState.FAILED -> "Failed"
                                uniffi.fire_uniffi_diagnostics.NetworkTraceOutcomeState.CANCELLED -> "Cancelled"
                            },
                        )
                        trace.statusCode?.let { append(" · HTTP ${it.toInt()}") }
                        trace.durationMs?.let { append(" · ${it.toLong()} ms") }
                        append(" · ${DiagnosticsPresentation.formatTimestamp(trace.startedAtUnixMs)}")
                    }
                    setTextAppearance(androidx.appcompat.R.style.TextAppearance_AppCompat_Caption)
                },
            )

            if (!trace.errorMessage.isNullOrBlank()) {
                addView(
                    TextView(context).apply {
                        text = trace.errorMessage
                        setTextAppearance(androidx.appcompat.R.style.TextAppearance_AppCompat_Small)
                        typeface = android.graphics.Typeface.MONOSPACE
                        setTextColor(android.graphics.Color.RED)
                    },
                )
            }
        }
    }

    private fun setError(message: String?) {
        diagnosticsErrorText.text = message.orEmpty()
        diagnosticsErrorText.visibility = if (message.isNullOrBlank()) View.GONE else View.VISIBLE
    }
}
