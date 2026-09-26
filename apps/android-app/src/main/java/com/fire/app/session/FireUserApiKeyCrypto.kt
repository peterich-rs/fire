package com.fire.app.session

import android.content.Context
import android.util.Base64
import java.security.KeyFactory
import java.security.KeyPairGenerator
import java.security.PrivateKey
import java.security.spec.PKCS8EncodedKeySpec
import java.security.spec.RSAPublicKeySpec
import javax.crypto.Cipher
import uniffi.fire_uniffi_session.UserApiKeyCryptoHandler

class FireUserApiKeyCryptoRuntimeHandler(
    context: Context,
) : UserApiKeyCryptoHandler {
    private val prefs = context.getSharedPreferences("fire.user_api_key", Context.MODE_PRIVATE)

    override fun publicKeyPem(): String {
        val privateKey = existingPrivateKey() ?: generatePrivateKey()
        val publicKey = KeyFactory.getInstance("RSA").generatePublic(
            RSAPublicKeySpec(
                (privateKey as java.security.interfaces.RSAPrivateCrtKey).modulus,
                (privateKey as java.security.interfaces.RSAPrivateCrtKey).publicExponent,
            ),
        )
        val encoded = publicKey.encoded
        val body = Base64.encodeToString(encoded, Base64.NO_WRAP)
        val lines = body.chunked(64).joinToString("\n")
        return "-----BEGIN PUBLIC KEY-----\n$lines\n-----END PUBLIC KEY-----"
    }

    override fun decryptPayload(payload: String): String? {
        return runCatching {
            val privateKey = existingPrivateKey() ?: return null
            val cipher = Cipher.getInstance("RSA/ECB/PKCS1Padding")
            cipher.init(Cipher.DECRYPT_MODE, privateKey)
            val normalized = payload.replace("\\s+".toRegex(), "")
            val bytes = Base64.decode(normalized, Base64.DEFAULT)
            String(cipher.doFinal(bytes), Charsets.UTF_8)
        }.getOrNull()
    }

    override fun readApiKey(): String? = prefs.getString(KEY_API, null)

    override fun writeApiKey(apiKey: String) {
        prefs.edit().putString(KEY_API, apiKey).apply()
    }

    override fun clearApiKey() {
        prefs.edit().remove(KEY_API).apply()
    }

    fun clientId(): String {
        val existing = prefs.getString(KEY_CLIENT, null)
        if (!existing.isNullOrBlank()) {
            return existing
        }
        val created = java.util.UUID.randomUUID().toString()
        prefs.edit().putString(KEY_CLIENT, created).apply()
        return created
    }

    fun qrClientId(): String {
        val existing = prefs.getString(KEY_QR_CLIENT, null)
        if (!existing.isNullOrBlank()) {
            return existing
        }
        val created = java.util.UUID.randomUUID().toString()
        prefs.edit().putString(KEY_QR_CLIENT, created).apply()
        return created
    }

    private fun existingPrivateKey(): PrivateKey? {
        val encoded = prefs.getString(KEY_PRIVATE, null) ?: return null
        return runCatching {
            val spec = PKCS8EncodedKeySpec(Base64.decode(encoded, Base64.DEFAULT))
            KeyFactory.getInstance("RSA").generatePrivate(spec)
        }.getOrNull()
    }

    private fun generatePrivateKey(): PrivateKey {
        val generator = KeyPairGenerator.getInstance("RSA")
        generator.initialize(2048)
        val pair = generator.generateKeyPair()
        prefs.edit()
            .putString(KEY_PRIVATE, Base64.encodeToString(pair.private.encoded, Base64.NO_WRAP))
            .apply()
        return pair.private
    }

    companion object {
        private const val KEY_API = "api_key"
        private const val KEY_CLIENT = "client_id"
        private const val KEY_QR_CLIENT = "qr_client_id"
        private const val KEY_PRIVATE = "rsa_private_pkcs8"
    }
}
