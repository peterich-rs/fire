package com.fire.app

import android.content.Context
import android.content.Intent
import android.os.Bundle
import android.widget.TextView
import androidx.appcompat.app.AppCompatActivity
import androidx.lifecycle.lifecycleScope
import com.fire.app.session.FireSessionStore
import com.fire.app.session.FireSessionStoreRepository
import kotlinx.coroutines.launch

class RequestTraceDetailActivity : AppCompatActivity() {
    private lateinit var sessionStore: FireSessionStore
    private lateinit var traceOverviewText: TextView
    private lateinit var requestHeadersText: TextView
    private lateinit var responseHeadersText: TextView
    private lateinit var responseBodyText: TextView
    private lateinit var executionChainText: TextView

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_request_trace_detail)

        supportActionBar?.setDisplayHomeAsUpEnabled(true)
        title = getString(R.string.diagnostics_trace_detail_title)

        sessionStore = FireSessionStoreRepository.get(applicationContext)
        traceOverviewText = findViewById(R.id.traceOverviewText)
        requestHeadersText = findViewById(R.id.requestHeadersText)
        responseHeadersText = findViewById(R.id.responseHeadersText)
        responseBodyText = findViewById(R.id.responseBodyText)
        executionChainText = findViewById(R.id.executionChainText)

        val traceId = intent.getLongExtra(EXTRA_TRACE_ID, -1L)
        if (traceId < 0L) {
            traceOverviewText.text = getString(R.string.diagnostics_trace_error)
            return
        }

        lifecycleScope.launch {
            try {
                val detail = sessionStore.networkTraceDetail(traceId.toULong())
                if (detail == null) {
                    traceOverviewText.text = getString(R.string.diagnostics_trace_error)
                    return@launch
                }
                traceOverviewText.text = buildString {
                    appendLine("Operation: ${detail.summary.operation}")
                    appendLine("${detail.summary.method} ${detail.summary.url}")
                    appendLine("Started: ${DiagnosticsPresentation.formatTimestamp(detail.summary.startedAtUnixMs)}")
                    detail.summary.finishedAtUnixMs?.let {
                        appendLine("Finished: ${DiagnosticsPresentation.formatTimestamp(it)}")
                    }
                    detail.summary.durationMs?.let {
                        appendLine("Duration: ${it.toLong()} ms")
                    }
                    appendLine(
                        "Outcome: ${
                            when (detail.summary.outcome) {
                                uniffi.fire_uniffi.NetworkTraceOutcomeState.IN_PROGRESS -> "In Progress"
                                uniffi.fire_uniffi.NetworkTraceOutcomeState.SUCCEEDED -> "Succeeded"
                                uniffi.fire_uniffi.NetworkTraceOutcomeState.FAILED -> "Failed"
                                uniffi.fire_uniffi.NetworkTraceOutcomeState.CANCELLED -> "Cancelled"
                            }
                        }",
                    )
                    detail.summary.statusCode?.let {
                        appendLine("Status: HTTP ${it.toInt()}")
                    }
                    detail.summary.responseContentType?.let {
                        appendLine("Content-Type: $it")
                    }
                    detail.responseBodyBytes?.let {
                        appendLine("Body Size: ${DiagnosticsPresentation.formatBytes(it)}")
                    }
                    detail.responseBodyStoredBytes?.let {
                        appendLine("Cached Preview: ${DiagnosticsPresentation.formatBytes(it)}")
                    }
                    detail.summary.errorMessage?.let {
                        appendLine("Error: $it")
                    }
                }

                requestHeadersText.text =
                    DiagnosticsPresentation.renderHeaders(detail.requestHeaders)
                responseHeadersText.text =
                    DiagnosticsPresentation.renderHeaders(detail.responseHeaders)
                responseBodyText.text = detail.responseBody?.let { body ->
                    buildString {
                        append(body)
                        when {
                            detail.responseBodyStorageTruncated ->
                                append("\n\n<stored preview truncated to the first 256 KB>")
                            detail.responseBodyPageAvailable ->
                                append("\n\n<additional cached body content available>")
                        }
                    }
                } ?: getString(R.string.diagnostics_trace_response_empty)
                executionChainText.text = if (detail.events.isEmpty()) {
                    "No execution events captured."
                } else {
                    detail.events.joinToString(separator = "\n\n") { event ->
                        buildString {
                            append("[${DiagnosticsPresentation.formatTimestamp(event.timestampUnixMs)}] ")
                            append("#${event.sequence} ${event.phase}")
                            append('\n')
                            append(event.summary)
                            event.details?.let {
                                append('\n')
                                append(it)
                            }
                        }
                    }
                }
            } catch (error: Exception) {
                traceOverviewText.text =
                    error.localizedMessage ?: getString(R.string.diagnostics_trace_error)
            }
        }
    }

    override fun onSupportNavigateUp(): Boolean {
        finish()
        return true
    }

    companion object {
        private const val EXTRA_TRACE_ID = "trace_id"

        fun intent(context: Context, traceId: ULong): Intent {
            return Intent(context, RequestTraceDetailActivity::class.java).apply {
                putExtra(EXTRA_TRACE_ID, traceId.toLong())
            }
        }
    }
}
