package com.fire.app.session

import android.content.Context
import android.content.SharedPreferences
import com.fire.app.ui.auth.FireLastLoginMethod

object FireLastLoginStore {
    const val PREFS_NAME = "fire_last_login"
    const val KEY_METHOD = "last_login_method"

    fun load(context: Context): FireLastLoginMethod? =
        loadFromPrefs(context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE))

    fun save(context: Context, method: FireLastLoginMethod) {
        saveToPrefs(context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE), method)
    }

    fun clear(context: Context) {
        clearPrefs(context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE))
    }

    fun loadFromPrefs(prefs: SharedPreferences): FireLastLoginMethod? =
        FireLastLoginMethod.fromStorageKey(prefs.getString(KEY_METHOD, null))

    fun saveToPrefs(prefs: SharedPreferences, method: FireLastLoginMethod) {
        prefs.edit().putString(KEY_METHOD, method.storageKey).apply()
    }

    fun clearPrefs(prefs: SharedPreferences) {
        prefs.edit().remove(KEY_METHOD).apply()
    }
}
