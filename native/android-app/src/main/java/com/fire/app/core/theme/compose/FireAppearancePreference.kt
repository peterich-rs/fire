package com.fire.app.core.theme.compose

import android.content.Context

enum class FireAppearancePreference(val storageKey: String) {
    System("system"),
    Light("light"),
    Dark("dark");

    companion object {
        const val STORAGE_KEY = "fire.appearancePreference"

        fun load(context: Context, prefsName: String = "fire.appearance"): FireAppearancePreference {
            val prefs = context.getSharedPreferences(prefsName, Context.MODE_PRIVATE)
            val raw = prefs.getString(STORAGE_KEY, null)
            return fromStorageKey(raw)
        }

        fun save(
            context: Context,
            preference: FireAppearancePreference,
            prefsName: String = "fire.appearance",
        ) {
            context.getSharedPreferences(prefsName, Context.MODE_PRIVATE)
                .edit()
                .putString(STORAGE_KEY, preference.storageKey)
                .apply()
        }

        fun fromStorageKey(raw: String?): FireAppearancePreference =
            entries.firstOrNull { it.storageKey == raw } ?: System
    }
}
