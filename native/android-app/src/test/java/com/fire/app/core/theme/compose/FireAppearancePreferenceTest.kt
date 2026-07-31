package com.fire.app.core.theme.compose

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
    fun fromStorageKey_emptyPrefs_returnsSystem() {
        assertEquals(System, FireAppearancePreference.fromStorageKey(null))
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
}
