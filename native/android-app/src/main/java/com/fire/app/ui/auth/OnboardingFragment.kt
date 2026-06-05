package com.fire.app.ui.auth

import android.os.Bundle
import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import android.widget.TextView
import androidx.fragment.app.Fragment
import androidx.navigation.fragment.findNavController
import com.fire.app.R
import com.google.android.material.button.MaterialButton

class OnboardingFragment : Fragment() {

    override fun onCreateView(
        inflater: LayoutInflater,
        container: ViewGroup?,
        savedInstanceState: Bundle?,
    ): View? {
        return inflater.inflate(R.layout.fragment_onboarding, container, false)
    }

    override fun onViewCreated(view: View, savedInstanceState: Bundle?) {
        super.onViewCreated(view, savedInstanceState)

        val loginButton: MaterialButton = view.findViewById(R.id.login_button)
        val errorBanner: View = view.findViewById(R.id.error_banner)
        val restoreButton: TextView = view.findViewById(R.id.restore_session_button)
        val bootstrappingLayout: View = view.findViewById(R.id.bootstrapping_layout)
        val dismissError: View = view.findViewById(R.id.dismiss_error)

        val viewModel = AuthViewModel.create()
        errorBanner.visibility = View.GONE
        restoreButton.visibility = View.GONE
        bootstrappingLayout.visibility = View.GONE
        loginButton.visibility = View.VISIBLE

        loginButton.setOnClickListener {
            findNavController().navigate(R.id.action_onboarding_to_loginWebView)
        }

        dismissError.setOnClickListener {
            viewModel.dismissError()
            errorBanner.visibility = View.GONE
        }
    }
}
