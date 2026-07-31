package com.fire.app.core.theme.compose

import android.content.Context
import android.content.SharedPreferences

enum class FireAppearancePreference(val storageKey: String) {
    System("system"),
    Light("light"),
    Dark("dark");

    companion object {
        const val STORAGE_KEY = "fire.appearancePreference"

        fun load(context: Context, prefsName: String = "fire.appearance"): FireAppearancePreference =
            loadFromPrefs(context.getSharedPreferences(prefsName, Context.MODE_PRIVATE))

        fun save(
            context: Context,
            preference: FireAppearancePreference,
            prefsName: String = "fire.appearance",
        ) {
            saveToPrefs(context.getSharedPreferences(prefsName, Context.MODE_PRIVATE), preference)
        }

        fun loadFromPrefs(prefs: SharedPreferences): FireAppearancePreference =
            fromStorageKey(prefs.getString(STORAGE_KEY, null))

        fun saveToPrefs(prefs: SharedPreferences, preference: FireAppearancePreference) {
            prefs.edit().putString(STORAGE_KEY, preference.storageKey).apply()
        }

        fun fromStorageKey(raw: String?): FireAppearancePreference =
            entries.firstOrNull { it.storageKey == raw } ?: System
    }
}
