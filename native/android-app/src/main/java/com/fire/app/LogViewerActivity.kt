package com.fire.app

import android.os.Bundle
import android.view.ViewGroup
import android.widget.Button
import android.widget.LinearLayout
import android.widget.TextView
import androidx.appcompat.app.AppCompatActivity
import androidx.lifecycle.lifecycleScope
import com.fire.app.session.FireSessionStore
import com.fire.app.session.FireSessionStoreRepository
import kotlinx.coroutines.launch
import uniffi.fire_uniffi_diagnostics.LogFileSummaryState

class LogViewerActivity : AppCompatActivity() {
    private lateinit var sessionStore: FireSessionStore
    private lateinit var refreshLogButton: Button
    private lateinit var logFileListContainer: LinearLayout
    private lateinit var logMetaText: TextView
    private lateinit var logContentText: TextView
    private var selectedRelativePath: String? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_log_viewer)

        supportActionBar?.setDisplayHomeAsUpEnabled(true)
        title = getString(R.string.diagnostics_log_title)

        sessionStore = FireSessionStoreRepository.get(applicationContext)
        refreshLogButton = findViewById(R.id.refreshLogButton)
        logFileListContainer = findViewById(R.id.logFileListContainer)
        logMetaText = findViewById(R.id.logMetaText)
        logContentText = findViewById(R.id.logContentText)

        refreshLogButton.setOnClickListener { refreshLog() }
        refreshLog()
    }

    override fun onSupportNavigateUp(): Boolean {
        finish()
        return true
    }

    private fun refreshLog() {
        lifecycleScope.launch {
            logMetaText.text = getString(R.string.diagnostics_loading)
            logContentText.text = ""

            try {
                val files = sessionStore.listLogFiles()
                renderLogFileList(files)

                val selectedFile = files.firstOrNull { it.relativePath == selectedRelativePath }
                    ?: files.firstOrNull()
                if (selectedFile == null) {
                    logMetaText.text = getString(R.string.diagnostics_log_empty)
                    logContentText.text = ""
                    return@launch
                }

                selectedRelativePath = selectedFile.relativePath
                val detail = sessionStore.readLogFile(selectedFile.relativePath)
                logMetaText.text = buildString {
                    appendLine(detail.fileName)
                    appendLine(detail.relativePath)
                    append(DiagnosticsPresentation.formatBytes(detail.sizeBytes))
                    if (detail.isTruncated) {
                        append(" · truncated")
                    }
                }
                logContentText.text =
                    detail.contents.ifBlank { getString(R.string.diagnostics_log_empty) }
            } catch (error: Exception) {
                logMetaText.text =
                    error.localizedMessage ?: getString(R.string.diagnostics_trace_error)
                logContentText.text = ""
            }
        }
    }

    private fun renderLogFileList(files: List<LogFileSummaryState>) {
        logFileListContainer.removeAllViews()

        files.forEach { file ->
            logFileListContainer.addView(
                TextView(this).apply {
                    text = "${file.fileName} · ${DiagnosticsPresentation.formatTimestamp(file.modifiedAtUnixMs)}"
                    setTextAppearance(androidx.appcompat.R.style.TextAppearance_AppCompat_Body1)
                    setPadding(0, 0, 0, 12)
                    setOnClickListener {
                        selectedRelativePath = file.relativePath
                        refreshLog()
                    }
                    layoutParams = LinearLayout.LayoutParams(
                        ViewGroup.LayoutParams.MATCH_PARENT,
                        ViewGroup.LayoutParams.WRAP_CONTENT,
                    )
                },
            )
        }
    }
}
