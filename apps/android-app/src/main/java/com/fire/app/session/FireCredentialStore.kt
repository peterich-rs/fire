package com.fire.app.session

import android.content.Context
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Base64
import org.json.JSONObject
import java.nio.charset.StandardCharsets
import java.security.KeyStore
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

data class FireSavedCredential(
    val username: String,
    val password: String,
)

object FireCredentialStore {
    private const val PREFS_NAME = "fire_login_credentials"
    private const val FIELD_PAYLOAD = "payload"
    private const val FIELD_IV = "iv"
    private const val KEY_ALIAS = "fire_login_credentials_key"
    private const val AES_MODE = "AES/GCM/NoPadding"
    private const val GCM_TAG_LENGTH_BITS = 128

    fun load(context: Context): FireSavedCredential? {
        val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        val payload = prefs.getString(FIELD_PAYLOAD, null) ?: return null
        val iv = prefs.getString(FIELD_IV, null) ?: return null
        val plaintext = decrypt(
            payload = Base64.decode(payload, Base64.NO_WRAP),
            iv = Base64.decode(iv, Base64.NO_WRAP),
        ) ?: return null
        return runCatching {
            val json = JSONObject(plaintext)
            val username = json.optString("username").trim()
            val password = json.optString("password").trim()
            if (username.isEmpty() || password.isEmpty()) {
                null
            } else {
                FireSavedCredential(username = username, password = password)
            }
        }.getOrNull()
    }

    fun save(context: Context, username: String, password: String) {
        val normalizedUsername = username.trim()
        val normalizedPassword = password.trim()
        if (normalizedUsername.isEmpty() || normalizedPassword.isEmpty()) {
            return
        }
        val plaintext = JSONObject()
            .put("username", normalizedUsername)
            .put("password", normalizedPassword)
            .toString()
            .toByteArray(StandardCharsets.UTF_8)
        val encrypted = encrypt(plaintext)
        val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        prefs.edit()
            .putString(FIELD_PAYLOAD, Base64.encodeToString(encrypted.first, Base64.NO_WRAP))
            .putString(FIELD_IV, Base64.encodeToString(encrypted.second, Base64.NO_WRAP))
            .apply()
    }

    fun clear(context: Context) {
        context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            .edit()
            .remove(FIELD_PAYLOAD)
            .remove(FIELD_IV)
            .apply()
    }

    private fun encrypt(plaintext: ByteArray): Pair<ByteArray, ByteArray> {
        val cipher = Cipher.getInstance(AES_MODE)
        cipher.init(Cipher.ENCRYPT_MODE, secretKey())
        return cipher.doFinal(plaintext) to cipher.iv
    }

    private fun decrypt(payload: ByteArray, iv: ByteArray): String? {
        return runCatching {
            val cipher = Cipher.getInstance(AES_MODE)
            cipher.init(
                Cipher.DECRYPT_MODE,
                secretKey(),
                GCMParameterSpec(GCM_TAG_LENGTH_BITS, iv),
            )
            String(cipher.doFinal(payload), StandardCharsets.UTF_8)
        }.getOrNull()
    }

    private fun secretKey(): SecretKey {
        val keyStore = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
        val existing = keyStore.getKey(KEY_ALIAS, null) as? SecretKey
        if (existing != null) {
            return existing
        }

        val keyGenerator = KeyGenerator.getInstance(
            KeyProperties.KEY_ALGORITHM_AES,
            "AndroidKeyStore",
        )
        keyGenerator.init(
            KeyGenParameterSpec.Builder(
                KEY_ALIAS,
                KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT,
            )
                .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                .setUserAuthenticationRequired(false)
                .build(),
        )
        return keyGenerator.generateKey()
    }
}
