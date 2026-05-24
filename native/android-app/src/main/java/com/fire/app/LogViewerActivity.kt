package com.fire.app

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

class LogViewerActivity : AppCompatActivity() {
    private data class LogFileListItem(
        val key: String,
        val stableId: Long,
        val contentSignature: String,
        val buildView: () -> View,
    )

    private class LogFileListAdapter :
        ListAdapter<LogFileListItem, LogFileListAdapter.DynamicViewHolder>(DiffCallback) {

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

        private object DiffCallback : DiffUtil.ItemCallback<LogFileListItem>() {
            override fun areItemsTheSame(
                oldItem: LogFileListItem,
                newItem: LogFileListItem,
            ): Boolean = oldItem.key == newItem.key

            override fun areContentsTheSame(
                oldItem: LogFileListItem,
                newItem: LogFileListItem,
            ): Boolean = oldItem.contentSignature == newItem.contentSignature
        }
    }

    private lateinit var sessionStore: FireSessionStore
    private lateinit var refreshLogButton: Button
    private lateinit var logFileRecyclerView: RecyclerView
    private lateinit var logMetaText: TextView
    private lateinit var logContentText: TextView
    private val logFileAdapter = LogFileListAdapter()
    private var selectedRelativePath: String? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_log_viewer)

        supportActionBar?.setDisplayHomeAsUpEnabled(true)
        title = getString(R.string.diagnostics_log_title)

        sessionStore = FireSessionStoreRepository.get(applicationContext)
        refreshLogButton = findViewById(R.id.refreshLogButton)
        logFileRecyclerView = findViewById(R.id.logFileRecyclerView)
        logMetaText = findViewById(R.id.logMetaText)
        logContentText = findViewById(R.id.logContentText)
        logFileRecyclerView.apply {
            layoutManager = LinearLayoutManager(this@LogViewerActivity)
            adapter = logFileAdapter
            itemAnimator = null
            setItemViewCacheSize(6)
            recycledViewPool.setMaxRecycledViews(0, 12)
        }

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
                val selectedFile = files.firstOrNull { it.relativePath == selectedRelativePath }
                    ?: files.firstOrNull()
                if (selectedFile == null) {
                    renderLogFileList(files)
                    logMetaText.text = getString(R.string.diagnostics_log_empty)
                    logContentText.text = ""
                    return@launch
                }

                selectedRelativePath = selectedFile.relativePath
                renderLogFileList(files)
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
        if (files.isEmpty()) {
            logFileAdapter.submitList(
                listOf(
                    logFileListItem("empty", getString(R.string.diagnostics_log_empty)) {
                        TextView(this).apply {
                            text = getString(R.string.diagnostics_log_empty)
                            setTextAppearance(androidx.appcompat.R.style.TextAppearance_AppCompat_Body1)
                        }
                    },
                ),
            )
            return
        }

        logFileAdapter.submitList(
            files.map { file ->
                logFileListItem(
                    key = "log:${file.relativePath}",
                    contentSignature = listOf(file.toString(), file.relativePath == selectedRelativePath)
                        .joinToString("|"),
                ) {
                    TextView(this).apply {
                        text = "${file.fileName} · ${DiagnosticsPresentation.formatTimestamp(file.modifiedAtUnixMs)}"
                        setTextAppearance(androidx.appcompat.R.style.TextAppearance_AppCompat_Body1)
                        setPadding(0, 0, 0, 12)
                        setTypeface(typeface, if (file.relativePath == selectedRelativePath) {
                            android.graphics.Typeface.BOLD
                        } else {
                            android.graphics.Typeface.NORMAL
                        })
                        setOnClickListener {
                            selectedRelativePath = file.relativePath
                            refreshLog()
                        }
                        layoutParams = LinearLayout.LayoutParams(
                            ViewGroup.LayoutParams.MATCH_PARENT,
                            ViewGroup.LayoutParams.WRAP_CONTENT,
                        )
                    }
                }
            },
        )
    }

    private fun logFileListItem(
        key: String,
        contentSignature: String,
        buildView: () -> View,
    ): LogFileListItem {
        return LogFileListItem(
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
}
