package com.fire.app.ui.auth

enum class FireLastLoginMethod(val storageKey: String, val displayName: String) {
    Password("password", "账号密码"),
    Google("google", "Google"),
    GitHub("github", "GitHub"),
    X("x", "X"),
    Discord("discord", "Discord"),
    Apple("apple", "Apple"),
    Passkey("passkey", "通行密钥");

    companion object {
        fun fromStorageKey(key: String?): FireLastLoginMethod? =
            entries.firstOrNull { it.storageKey == key }
    }

    val isExternal: Boolean get() = this != Password

    fun toExternalLoginMethod(): FireExternalLoginMethod? = when (this) {
        Google -> FireExternalLoginMethod.Google
        GitHub -> FireExternalLoginMethod.GitHub
        X -> FireExternalLoginMethod.X
        Discord -> FireExternalLoginMethod.Discord
        Apple -> FireExternalLoginMethod.Apple
        Passkey -> FireExternalLoginMethod.Passkey
        Password -> null
    }
}
