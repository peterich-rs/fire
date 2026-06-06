package com.fire.app.ui.auth

import android.os.Bundle
import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
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
        loginButton.visibility = View.VISIBLE

        loginButton.setOnClickListener {
            findNavController().navigate(R.id.action_onboarding_to_loginWebView)
        }
    }
}
