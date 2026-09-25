package com.fire.app.ui.composer

import android.text.Editable
import android.text.TextWatcher
import android.widget.EditText
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

class ComposerDraftAutosave(
    private val scope: CoroutineScope,
    private val saveDraft: suspend () -> Unit,
    private val onSaveFailed: (Exception) -> Unit = {},
) {
    private var enabled = false
    private var saveJob: Job? = null

    fun attach(vararg inputs: EditText) {
        val watcher = object : TextWatcher {
            override fun beforeTextChanged(s: CharSequence?, start: Int, count: Int, after: Int) = Unit
            override fun onTextChanged(s: CharSequence?, start: Int, before: Int, count: Int) = schedule()
            override fun afterTextChanged(s: Editable?) = Unit
        }
        inputs.forEach { input -> input.addTextChangedListener(watcher) }
    }

    fun start() {
        enabled = true
    }

    fun schedule() {
        if (!enabled) return
        saveJob?.cancel()
        saveJob = scope.launch {
            delay(1_200)
            saveDraftSafely()
        }
    }

    fun flush() {
        if (!enabled) return
        saveJob?.cancel()
        saveJob = scope.launch {
            saveDraftSafely()
        }
    }

    fun cancel() {
        enabled = false
        saveJob?.cancel()
        saveJob = null
    }

    private suspend fun saveDraftSafely() {
        try {
            saveDraft()
        } catch (error: CancellationException) {
            throw error
        } catch (error: Exception) {
            onSaveFailed(error)
        }
    }
}
