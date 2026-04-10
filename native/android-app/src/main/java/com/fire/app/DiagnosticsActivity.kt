package com.fire.app

import android.content.Intent
import android.os.Bundle
import android.view.View
import android.view.ViewGroup
import android.widget.Button
import android.widget.LinearLayout
import android.widget.TextView
import androidx.appcompat.app.AppCompatActivity
import androidx.lifecycle.lifecycleScope
import com.fire.app.session.FireSessionStore
import com.fire.app.session.FireSessionStoreRepository
import kotlinx.coroutines.launch
import uniffi.fire_uniffi.LogFileSummaryState
import uniffi.fire_uniffi.NetworkTraceSummaryState

class DiagnosticsActivity : AppCompatActivity() {
    private lateinit var sessionStore: FireSessionStore
    private lateinit var requestSummaryText: TextView
    private lateinit var diagnosticsErrorText: TextView
    private lateinit var requestTraceListContainer: LinearLayout
    private lateinit var refreshDiagnosticsButton: Button
    private lateinit var openLogViewerButton: Button

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_diagnostics)

        supportActionBar?.setDisplayHomeAsUpEnabled(true)
        title = getString(R.string.diagnostics_title)

        sessionStore = FireSessionStoreRepository.get(applicationContext)
        requestSummaryText = findViewById(R.id.requestSummaryText)
        diagnosticsErrorText = findViewById(R.id.diagnosticsErrorText)
        requestTraceListContainer = findViewById(R.id.requestTraceListContainer)
        refreshDiagnosticsButton = findViewById(R.id.refreshDiagnosticsButton)
        openLogViewerButton = findViewById(R.id.openLogViewerButton)

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
        requestTraceListContainer.removeAllViews()

        if (traces.isEmpty()) {
            requestTraceListContainer.addView(
                TextView(this).apply {
                    text = getString(R.string.diagnostics_no_traces)
                    setTextAppearance(androidx.appcompat.R.style.TextAppearance_AppCompat_Body1)
                },
            )
            return
        }

        traces.forEach { trace ->
            requestTraceListContainer.addView(requestTraceRow(trace))
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
                                uniffi.fire_uniffi.NetworkTraceOutcomeState.IN_PROGRESS -> "In Progress"
                                uniffi.fire_uniffi.NetworkTraceOutcomeState.SUCCEEDED -> "Succeeded"
                                uniffi.fire_uniffi.NetworkTraceOutcomeState.FAILED -> "Failed"
                                uniffi.fire_uniffi.NetworkTraceOutcomeState.CANCELLED -> "Cancelled"
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
