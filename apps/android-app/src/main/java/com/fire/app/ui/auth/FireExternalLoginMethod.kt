package com.fire.app.ui.auth

import com.fire.app.R

enum class FireExternalLoginMethod(
    val displayName: String,
    val discourseProviderName: String?,
    val iconRes: Int,
) {
    Google("Google", "google_oauth2", R.drawable.ic_login_google),
    GitHub("GitHub", "github", R.drawable.ic_login_github),
    X("X", "twitter", R.drawable.ic_login_x),
    Discord("Discord", "discord", R.drawable.ic_login_discord),
    Apple("Apple", "apple", R.drawable.ic_login_apple),
    Passkey("Passkey", null, R.drawable.ic_login_passkey);

    val lastLoginMethod: FireLastLoginMethod get() = when (this) {
        Google -> FireLastLoginMethod.Google
        GitHub -> FireLastLoginMethod.GitHub
        X -> FireLastLoginMethod.X
        Discord -> FireLastLoginMethod.Discord
        Apple -> FireLastLoginMethod.Apple
        Passkey -> FireLastLoginMethod.Passkey
    }
}
