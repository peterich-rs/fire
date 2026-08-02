package com.fire.app.ui.feedback

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Bundle
import android.widget.ArrayAdapter
import android.widget.Button
import android.widget.CheckBox
import android.widget.EditText
import android.widget.Spinner
import android.widget.TextView
import android.widget.Toast
import androidx.appcompat.app.AppCompatActivity
import androidx.core.content.FileProvider
import androidx.lifecycle.lifecycleScope
import com.fire.app.R
import com.fire.app.session.FireSessionStoreRepository
import java.io.File
import java.time.Instant
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

/**
 * In-app feedback form. Works without login.
 * Submit uses the system share sheet (text + optional redacted diagnostics JSON).
 */
class FeedbackActivity : AppCompatActivity() {

    private lateinit var titleInput: EditText
    private lateinit var bodyInput: EditText
    private lateinit var categorySpinner: Spinner
    private lateinit var attachLogs: CheckBox
    private lateinit var metaLabel: TextView
    private lateinit var statusLabel: TextView
    private lateinit var submitButton: Button
    private lateinit var githubButton: Button

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_feedback)
        supportActionBar?.setDisplayHomeAsUpEnabled(true)
        title = getString(R.string.feedback_title)

        titleInput = findViewById(R.id.feedback_title)
        bodyInput = findViewById(R.id.feedback_body)
        categorySpinner = findViewById(R.id.feedback_category)
        attachLogs = findViewById(R.id.feedback_attach_logs)
        metaLabel = findViewById(R.id.feedback_meta)
        statusLabel = findViewById(R.id.feedback_status)
        submitButton = findViewById(R.id.feedback_submit)
        githubButton = findViewById(R.id.feedback_github)

        categorySpinner.adapter = ArrayAdapter(
            this,
            android.R.layout.simple_spinner_dropdown_item,
            resources.getStringArray(R.array.feedback_categories),
        )
        attachLogs.isChecked = true

        lifecycleScope.launch {
            metaLabel.text = buildMeta()
        }

        submitButton.setOnClickListener { submit() }
        githubButton.setOnClickListener {
            startActivity(
                Intent(
                    Intent.ACTION_VIEW,
                    Uri.parse("https://github.com/peterich-rs/fire/issues"),
                ),
            )
        }
    }

    override fun onSupportNavigateUp(): Boolean {
        finish()
        return true
    }

    private suspend fun buildMeta(): String {
        val store = runCatching { FireSessionStoreRepository.get(this) }.getOrNull()
        val username = store?.let {
            runCatching { it.snapshot().bootstrap.currentUsername }.getOrNull()
        } ?: getString(R.string.feedback_not_logged_in)
        val pm = packageManager.getPackageInfo(packageName, 0)
        val version = pm.versionName ?: "?"
        val build = if (android.os.Build.VERSION.SDK_INT >= 28) {
            pm.longVersionCode.toString()
        } else {
            @Suppress("DEPRECATION")
            pm.versionCode.toString()
        }
        return getString(
            R.string.feedback_meta_format,
            username,
            version,
            build,
            android.os.Build.VERSION.RELEASE,
            android.os.Build.MODEL,
        )
    }

    private fun submit() {
        val title = titleInput.text?.toString()?.trim().orEmpty()
        val body = bodyInput.text?.toString()?.trim().orEmpty()
        if (title.isEmpty() && body.isEmpty()) {
            Toast.makeText(this, R.string.feedback_empty, Toast.LENGTH_SHORT).show()
            return
        }

        submitButton.isEnabled = false
        statusLabel.text = getString(R.string.feedback_preparing)
        lifecycleScope.launch {
            try {
                val uris = ArrayList<Uri>()
                val report = buildReportText(title, body)
                val reportFile = withContext(Dispatchers.IO) {
                    File(cacheDir, "fire-feedback-report.txt").also {
                        it.writeText(report)
                    }
                }
                uris.add(fileUri(reportFile))

                if (attachLogs.isChecked) {
                    val shareBundle = withContext(Dispatchers.IO) {
                        runCatching {
                            val store = FireSessionStoreRepository.get(this@FeedbackActivity)
                            val pm = packageManager.getPackageInfo(packageName, 0)
                            val export = store.exportFeedbackBundle(
                                platform = "android",
                                appVersion = pm.versionName,
                                buildNumber = null,
                                scenePhase = "active",
                            )
                            val source = File(export.absolutePath)
                            // Copy into cache so FileProvider can share it.
                            val dest = File(cacheDir, export.fileName)
                            source.copyTo(dest, overwrite = true)
                            dest
                        }.getOrNull()
                    }
                    if (shareBundle != null && shareBundle.exists()) {
                        uris.add(fileUri(shareBundle))
                        statusLabel.text = getString(R.string.feedback_bundle_ok, shareBundle.name)
                    } else {
                        statusLabel.text = getString(R.string.feedback_bundle_failed)
                    }
                }

                val share = Intent(Intent.ACTION_SEND_MULTIPLE).apply {
                    type = "*/*"
                    putParcelableArrayListExtra(Intent.EXTRA_STREAM, uris)
                    putExtra(Intent.EXTRA_SUBJECT, title.ifBlank { getString(R.string.feedback_title) })
                    putExtra(Intent.EXTRA_TEXT, report)
                    addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                }
                startActivity(Intent.createChooser(share, getString(R.string.feedback_share)))
            } catch (error: Exception) {
                statusLabel.text = error.message
                Toast.makeText(this@FeedbackActivity, error.message, Toast.LENGTH_LONG).show()
            } finally {
                submitButton.isEnabled = true
            }
        }
    }

    private suspend fun buildReportText(title: String, body: String): String {
        val categories = resources.getStringArray(R.array.feedback_category_keys)
        val category = categories.getOrElse(categorySpinner.selectedItemPosition) { "other" }
        val store = runCatching { FireSessionStoreRepository.get(this) }.getOrNull()
        val username = store?.let {
            runCatching { it.snapshot().bootstrap.currentUsername }.getOrNull()
        } ?: "anonymous"
        val pm = packageManager.getPackageInfo(packageName, 0)
        val version = pm.versionName ?: "?"
        return """
            ## ${title.ifBlank { "(no title)" }}

            ### Type
            $category

            ### Description
            ${body.ifBlank { "(empty)" }}

            ### Environment
            - Platform: android
            - App: $version
            - Android: ${android.os.Build.VERSION.RELEASE}
            - Device: ${android.os.Build.MODEL}
            - LinuxDo: $username
            - Source: ${intent.getStringExtra(EXTRA_SOURCE) ?: "profile"}
            - Submitted: ${Instant.now()}

            _Generated by Fire in-app feedback._
        """.trimIndent()
    }

    private fun fileUri(file: File): Uri {
        return FileProvider.getUriForFile(
            this,
            "$packageName.fileprovider",
            file,
        )
    }

    companion object {
        private const val EXTRA_SOURCE = "source"

        fun start(context: Context, source: String = "profile") {
            context.startActivity(
                Intent(context, FeedbackActivity::class.java).putExtra(EXTRA_SOURCE, source),
            )
        }
    }
}
