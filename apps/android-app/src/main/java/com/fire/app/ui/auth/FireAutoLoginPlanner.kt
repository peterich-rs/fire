package com.fire.app.ui.auth

import com.fire.app.session.FireSavedCredential
import com.fire.app.ui.auth.compose.OnboardingEntry

/**
 * Pure eligibility + routing helper for automatic login.
 * Mirrors iOS `FireAutoLoginPlanner`.
 *
 * Cold-start: password when last method is password + saved credential.
 * Session-expired: headless-capable external only (Google today); without a
 * headless engine the host may open a visible OAuth surface with auto-start.
 * Signed-out: never auto-login.
 */
sealed class FireAutoLoginKind {
    data class Password(val credential: FireSavedCredential) : FireAutoLoginKind()
    data class External(val method: FireExternalLoginMethod) : FireAutoLoginKind()
}

object FireAutoLoginPlanner {
    /** External providers eligible for mid-session / headless-style auto-login. */
    val headlessExternalPool: Map<FireLastLoginMethod, FireExternalLoginMethod> = mapOf(
        FireLastLoginMethod.Google to FireExternalLoginMethod.Google,
    )

    fun autoLoginKind(
        entry: OnboardingEntry,
        lastLoginMethod: FireLastLoginMethod?,
        savedCredential: FireSavedCredential?,
    ): FireAutoLoginKind? = when (entry) {
        OnboardingEntry.SignedOut -> null
        OnboardingEntry.ColdStart -> coldStartKind(lastLoginMethod, savedCredential)
        OnboardingEntry.SessionExpired ->
            midSessionHeadlessKind(lastLoginMethod)?.let { FireAutoLoginKind.External(it) }
    }

    fun midSessionHeadlessKind(lastLoginMethod: FireLastLoginMethod?): FireExternalLoginMethod? {
        if (lastLoginMethod == null) return null
        return headlessExternalPool[lastLoginMethod]
    }

    fun supportsHeadlessExternal(method: FireLastLoginMethod): Boolean =
        headlessExternalPool.containsKey(method)

    private fun coldStartKind(
        lastLoginMethod: FireLastLoginMethod?,
        savedCredential: FireSavedCredential?,
    ): FireAutoLoginKind? = when (lastLoginMethod) {
        FireLastLoginMethod.Password -> {
            val credential = savedCredential ?: return null
            FireAutoLoginKind.Password(credential)
        }
        FireLastLoginMethod.Google,
        FireLastLoginMethod.GitHub,
        FireLastLoginMethod.X,
        FireLastLoginMethod.Discord,
        FireLastLoginMethod.Apple,
        FireLastLoginMethod.Passkey,
        -> {
            val external = lastLoginMethod.let { headlessExternalPool[it] } ?: return null
            FireAutoLoginKind.External(external)
        }
        null -> null
    }
}
