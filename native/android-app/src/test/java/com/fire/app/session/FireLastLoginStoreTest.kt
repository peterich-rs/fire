package com.fire.app.session

import android.content.SharedPreferences
import com.fire.app.ui.auth.FireExternalLoginMethod
import com.fire.app.ui.auth.FireLastLoginMethod
import com.fire.app.ui.auth.FireLastLoginMethod.Apple
import com.fire.app.ui.auth.FireLastLoginMethod.Discord
import com.fire.app.ui.auth.FireLastLoginMethod.GitHub
import com.fire.app.ui.auth.FireLastLoginMethod.Google
import com.fire.app.ui.auth.FireLastLoginMethod.Passkey
import com.fire.app.ui.auth.FireLastLoginMethod.Password
import com.fire.app.ui.auth.FireLastLoginMethod.X
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Test

class FireLastLoginStoreTest {

    @Test
    fun fromStorageKey_password_returnsPassword() {
        assertEquals(Password, FireLastLoginMethod.fromStorageKey("password"))
    }

    @Test
    fun fromStorageKey_google_returnsGoogle() {
        assertEquals(Google, FireLastLoginMethod.fromStorageKey("google"))
    }

    @Test
    fun fromStorageKey_github_returnsGitHub() {
        assertEquals(GitHub, FireLastLoginMethod.fromStorageKey("github"))
    }

    @Test
    fun fromStorageKey_x_returnsX() {
        assertEquals(X, FireLastLoginMethod.fromStorageKey("x"))
    }

    @Test
    fun fromStorageKey_discord_returnsDiscord() {
        assertEquals(Discord, FireLastLoginMethod.fromStorageKey("discord"))
    }

    @Test
    fun fromStorageKey_apple_returnsApple() {
        assertEquals(Apple, FireLastLoginMethod.fromStorageKey("apple"))
    }

    @Test
    fun fromStorageKey_passkey_returnsPasskey() {
        assertEquals(Passkey, FireLastLoginMethod.fromStorageKey("passkey"))
    }

    @Test
    fun fromStorageKey_null_returnsNull() {
        assertNull(FireLastLoginMethod.fromStorageKey(null))
    }

    @Test
    fun fromStorageKey_emptyString_returnsNull() {
        assertNull(FireLastLoginMethod.fromStorageKey(""))
    }

    @Test
    fun fromStorageKey_garbage_returnsNull() {
        assertNull(FireLastLoginMethod.fromStorageKey("garbage"))
    }

    @Test
    fun save_thenLoad_password_returnsPassword() {
        val prefs = InMemorySharedPreferences()
        FireLastLoginStore.saveToPrefs(prefs, Password)
        assertEquals(Password, FireLastLoginStore.loadFromPrefs(prefs))
    }

    @Test
    fun save_thenLoad_google_returnsGoogle() {
        val prefs = InMemorySharedPreferences()
        FireLastLoginStore.saveToPrefs(prefs, Google)
        assertEquals(Google, FireLastLoginStore.loadFromPrefs(prefs))
    }

    @Test
    fun clear_thenLoad_returnsNull() {
        val prefs = InMemorySharedPreferences()
        FireLastLoginStore.saveToPrefs(prefs, Google)
        FireLastLoginStore.clearPrefs(prefs)
        assertNull(FireLastLoginStore.loadFromPrefs(prefs))
    }

    @Test
    fun load_emptyPrefs_returnsNull() {
        val prefs = InMemorySharedPreferences()
        assertNull(FireLastLoginStore.loadFromPrefs(prefs))
    }

    @Test
    fun save_writesUnderStorageKey() {
        val prefs = InMemorySharedPreferences()
        FireLastLoginStore.saveToPrefs(prefs, Google)
        assertEquals(Google.storageKey, prefs.getString(FireLastLoginStore.KEY_METHOD, null))
    }

    @Test
    fun allExternalMethods_mapToNonNullExternalMethod() {
        for (method in FireLastLoginMethod.entries) {
            if (method == Password) continue
            val external = method.toExternalLoginMethod()
            assertNotNull(external)
        }
    }

    @Test
    fun password_toExternalLoginMethod_returnsNull() {
        assertNull(Password.toExternalLoginMethod())
    }

    @Test
    fun externalMethods_mapToCorrectLastLoginMethod() {
        assertEquals(Google, FireExternalLoginMethod.Google.lastLoginMethod)
        assertEquals(GitHub, FireExternalLoginMethod.GitHub.lastLoginMethod)
        assertEquals(X, FireExternalLoginMethod.X.lastLoginMethod)
        assertEquals(Discord, FireExternalLoginMethod.Discord.lastLoginMethod)
        assertEquals(Apple, FireExternalLoginMethod.Apple.lastLoginMethod)
        assertEquals(Passkey, FireExternalLoginMethod.Passkey.lastLoginMethod)
    }

    @Test
    fun externalToLastLogin_roundTrip_isStable() {
        for (external in FireExternalLoginMethod.entries) {
            assertEquals(external, external.lastLoginMethod.toExternalLoginMethod())
        }
    }

    @Test
    fun password_isExternal_isFalse() {
        assertEquals(false, Password.isExternal)
    }

    @Test
    fun nonPasswordMethods_isExternal_isTrue() {
        assertEquals(true, Google.isExternal)
        assertEquals(true, GitHub.isExternal)
        assertEquals(true, X.isExternal)
        assertEquals(true, Discord.isExternal)
        assertEquals(true, Apple.isExternal)
        assertEquals(true, Passkey.isExternal)
    }
}

private class InMemorySharedPreferences : SharedPreferences {

    private val values = mutableMapOf<String, Any?>()

    override fun getAll(): Map<String, *> = values.toMap()

    override fun getString(key: String, defValue: String?): String? =
        (values[key] as? String) ?: defValue

    @Suppress("UNCHECKED_CAST")
    override fun getStringSet(key: String, defValues: Set<String>?): Set<String>? =
        (values[key] as? Set<String>) ?: defValues

    override fun getInt(key: String, defValue: Int): Int = (values[key] as? Int) ?: defValue

    override fun getLong(key: String, defValue: Long): Long = (values[key] as? Long) ?: defValue

    override fun getFloat(key: String, defValue: Float): Float = (values[key] as? Float) ?: defValue

    override fun getBoolean(key: String, defValue: Boolean): Boolean =
        (values[key] as? Boolean) ?: defValue

    override fun contains(key: String): Boolean = values.containsKey(key)

    override fun edit(): SharedPreferences.Editor = Editor()

    override fun registerOnSharedPreferenceChangeListener(
        listener: SharedPreferences.OnSharedPreferenceChangeListener,
    ) = Unit

    override fun unregisterOnSharedPreferenceChangeListener(
        listener: SharedPreferences.OnSharedPreferenceChangeListener,
    ) = Unit

    private inner class Editor : SharedPreferences.Editor {

        override fun putString(key: String, value: String?): SharedPreferences.Editor {
            values[key] = value
            return this
        }

        override fun putStringSet(
            key: String,
            values: Set<String>?,
        ): SharedPreferences.Editor {
            this@InMemorySharedPreferences.values[key] = values
            return this
        }

        override fun putInt(key: String, value: Int): SharedPreferences.Editor {
            values[key] = value
            return this
        }

        override fun putLong(key: String, value: Long): SharedPreferences.Editor {
            values[key] = value
            return this
        }

        override fun putFloat(key: String, value: Float): SharedPreferences.Editor {
            values[key] = value
            return this
        }

        override fun putBoolean(key: String, value: Boolean): SharedPreferences.Editor {
            values[key] = value
            return this
        }

        override fun remove(key: String): SharedPreferences.Editor {
            values.remove(key)
            return this
        }

        override fun clear(): SharedPreferences.Editor {
            values.clear()
            return this
        }

        override fun commit(): Boolean = true

        override fun apply() = Unit
    }
}
