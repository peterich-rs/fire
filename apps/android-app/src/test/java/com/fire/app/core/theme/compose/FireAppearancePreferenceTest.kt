package com.fire.app.core.theme.compose

import android.content.SharedPreferences
import com.fire.app.core.theme.compose.FireAppearancePreference.Dark
import com.fire.app.core.theme.compose.FireAppearancePreference.Light
import com.fire.app.core.theme.compose.FireAppearancePreference.System
import org.junit.Assert.assertEquals
import org.junit.Test

class FireAppearancePreferenceTest {

    @Test
    fun fromStorageKey_null_returnsSystem() {
        assertEquals(System, FireAppearancePreference.fromStorageKey(null))
    }

    @Test
    fun fromStorageKey_emptyString_returnsSystem() {
        assertEquals(System, FireAppearancePreference.fromStorageKey(""))
    }

    @Test
    fun fromStorageKey_roundTripLight_returnsLight() {
        assertEquals(Light, FireAppearancePreference.fromStorageKey(Light.storageKey))
    }

    @Test
    fun fromStorageKey_roundTripDark_returnsDark() {
        assertEquals(Dark, FireAppearancePreference.fromStorageKey(Dark.storageKey))
    }

    @Test
    fun fromStorageKey_garbageString_returnsSystem() {
        assertEquals(System, FireAppearancePreference.fromStorageKey("garbage"))
    }

    @Test
    fun fromStorageKey_systemStorageKey_returnsSystem() {
        assertEquals(System, FireAppearancePreference.fromStorageKey("system"))
    }

    @Test
    fun storageKeys_areStable() {
        assertEquals("system", System.storageKey)
        assertEquals("light", Light.storageKey)
        assertEquals("dark", Dark.storageKey)
    }

    @Test
    fun storageKeyConstant_isCorrect() {
        assertEquals("fire.appearancePreference", FireAppearancePreference.STORAGE_KEY)
    }

    @Test
    fun save_thenLoad_Light_returnsLight() {
        val prefs = InMemorySharedPreferences()
        FireAppearancePreference.saveToPrefs(prefs, Light)
        assertEquals(Light, FireAppearancePreference.loadFromPrefs(prefs))
    }

    @Test
    fun save_thenLoad_Dark_returnsDark() {
        val prefs = InMemorySharedPreferences()
        FireAppearancePreference.saveToPrefs(prefs, Dark)
        assertEquals(Dark, FireAppearancePreference.loadFromPrefs(prefs))
    }

    @Test
    fun save_thenLoad_System_returnsSystem() {
        val prefs = InMemorySharedPreferences()
        FireAppearancePreference.saveToPrefs(prefs, System)
        assertEquals(System, FireAppearancePreference.loadFromPrefs(prefs))
    }

    @Test
    fun load_emptyPrefs_returnsSystem() {
        val prefs = InMemorySharedPreferences()
        assertEquals(System, FireAppearancePreference.loadFromPrefs(prefs))
    }

    @Test
    fun save_writesUnderStorageKey() {
        val prefs = InMemorySharedPreferences()
        FireAppearancePreference.saveToPrefs(prefs, Dark)
        assertEquals(Dark.storageKey, prefs.getString(FireAppearancePreference.STORAGE_KEY, null))
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
