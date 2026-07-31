package com.fire.app.ui.auth

import com.fire.app.session.FireSavedCredential
import com.fire.app.ui.auth.compose.OnboardingEntry
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class FireAutoLoginPlannerTest {

    private val credential = FireSavedCredential(username = "alice", password = "secret")

    @Test
    fun signedOut_neverAutoLogins() {
        assertNull(
            FireAutoLoginPlanner.autoLoginKind(
                entry = OnboardingEntry.SignedOut,
                lastLoginMethod = FireLastLoginMethod.Password,
                savedCredential = credential,
            ),
        )
        assertNull(
            FireAutoLoginPlanner.autoLoginKind(
                entry = OnboardingEntry.SignedOut,
                lastLoginMethod = FireLastLoginMethod.Google,
                savedCredential = null,
            ),
        )
    }

    @Test
    fun coldStart_passwordWithCredential_returnsPassword() {
        val kind = FireAutoLoginPlanner.autoLoginKind(
            entry = OnboardingEntry.ColdStart,
            lastLoginMethod = FireLastLoginMethod.Password,
            savedCredential = credential,
        )
        assertTrue(kind is FireAutoLoginKind.Password)
        assertEquals(credential, (kind as FireAutoLoginKind.Password).credential)
    }

    @Test
    fun coldStart_passwordWithoutCredential_returnsNull() {
        assertNull(
            FireAutoLoginPlanner.autoLoginKind(
                entry = OnboardingEntry.ColdStart,
                lastLoginMethod = FireLastLoginMethod.Password,
                savedCredential = null,
            ),
        )
    }

    @Test
    fun coldStart_googleInPool_returnsExternal() {
        val kind = FireAutoLoginPlanner.autoLoginKind(
            entry = OnboardingEntry.ColdStart,
            lastLoginMethod = FireLastLoginMethod.Google,
            savedCredential = credential,
        )
        assertTrue(kind is FireAutoLoginKind.External)
        assertEquals(FireExternalLoginMethod.Google, (kind as FireAutoLoginKind.External).method)
    }

    @Test
    fun coldStart_githubNotInPool_returnsNull() {
        assertNull(
            FireAutoLoginPlanner.autoLoginKind(
                entry = OnboardingEntry.ColdStart,
                lastLoginMethod = FireLastLoginMethod.GitHub,
                savedCredential = credential,
            ),
        )
    }

    @Test
    fun coldStart_nullLastMethod_returnsNull() {
        assertNull(
            FireAutoLoginPlanner.autoLoginKind(
                entry = OnboardingEntry.ColdStart,
                lastLoginMethod = null,
                savedCredential = credential,
            ),
        )
    }

    @Test
    fun sessionExpired_password_returnsNull() {
        assertNull(
            FireAutoLoginPlanner.autoLoginKind(
                entry = OnboardingEntry.SessionExpired,
                lastLoginMethod = FireLastLoginMethod.Password,
                savedCredential = credential,
            ),
        )
    }

    @Test
    fun sessionExpired_google_returnsExternal() {
        val kind = FireAutoLoginPlanner.autoLoginKind(
            entry = OnboardingEntry.SessionExpired,
            lastLoginMethod = FireLastLoginMethod.Google,
            savedCredential = null,
        )
        assertTrue(kind is FireAutoLoginKind.External)
        assertEquals(FireExternalLoginMethod.Google, (kind as FireAutoLoginKind.External).method)
    }

    @Test
    fun sessionExpired_github_returnsNull() {
        assertNull(
            FireAutoLoginPlanner.autoLoginKind(
                entry = OnboardingEntry.SessionExpired,
                lastLoginMethod = FireLastLoginMethod.GitHub,
                savedCredential = null,
            ),
        )
    }

    @Test
    fun supportsHeadlessExternal_googleOnly() {
        assertTrue(FireAutoLoginPlanner.supportsHeadlessExternal(FireLastLoginMethod.Google))
        assertTrue(!FireAutoLoginPlanner.supportsHeadlessExternal(FireLastLoginMethod.Password))
        assertTrue(!FireAutoLoginPlanner.supportsHeadlessExternal(FireLastLoginMethod.GitHub))
    }
}
