package com.fire.app.ui.auth

import androidx.lifecycle.ViewModel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow

class AuthViewModel : ViewModel() {

    private val _errorMessage = MutableStateFlow<String?>(null)
    val errorMessage = _errorMessage.asStateFlow()

    fun dismissError() {
        _errorMessage.value = null
    }

    companion object {
        fun create(): AuthViewModel = AuthViewModel()
    }
}
