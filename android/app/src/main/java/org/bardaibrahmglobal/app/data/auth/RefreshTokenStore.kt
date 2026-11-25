package org.bardaibrahmglobal.app.data.auth

import android.content.Context
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Base64
import java.security.KeyStore
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

/** Keeps the long-lived refresh token between app launches. The short-lived access token stays in memory. */
interface RefreshTokenStore {
    fun load(): String?
    fun save(token: String?)
}

class InMemoryRefreshTokenStore : RefreshTokenStore {
    @Volatile private var token: String? = null
    override fun load(): String? = token
    override fun save(token: String?) { this.token = token }
}

/**
 * Encrypts the refresh token with an AES-GCM key that never leaves the Android Keystore.
 * Any failure (key invalidated, data corrupted) simply forgets the token: the user signs in again.
 */
class KeystoreRefreshTokenStore(context: Context) : RefreshTokenStore {
    private val prefs = context.applicationContext.getSharedPreferences("bbg_session", Context.MODE_PRIVATE)

    override fun load(): String? = try {
        prefs.getString(PREF_KEY, null)?.let { stored ->
            val parts = stored.split(':')
            val cipher = Cipher.getInstance(TRANSFORMATION)
            cipher.init(Cipher.DECRYPT_MODE, key(), GCMParameterSpec(128, Base64.decode(parts[0], Base64.NO_WRAP)))
            String(cipher.doFinal(Base64.decode(parts[1], Base64.NO_WRAP)), Charsets.UTF_8)
        }
    } catch (e: Exception) {
        prefs.edit().remove(PREF_KEY).apply()
        null
    }

    override fun save(token: String?) {
        if (token == null) {
            prefs.edit().remove(PREF_KEY).apply()
            return
        }
        try {
            val cipher = Cipher.getInstance(TRANSFORMATION)
            cipher.init(Cipher.ENCRYPT_MODE, key())
            val iv = Base64.encodeToString(cipher.iv, Base64.NO_WRAP)
            val data = Base64.encodeToString(cipher.doFinal(token.toByteArray(Charsets.UTF_8)), Base64.NO_WRAP)
            prefs.edit().putString(PREF_KEY, "$iv:$data").apply()
        } catch (e: Exception) {
            prefs.edit().remove(PREF_KEY).apply()   // never fall back to plain text
        }
    }

    private fun key(): SecretKey {
        val keyStore = KeyStore.getInstance(ANDROID_KEYSTORE).apply { load(null) }
        (keyStore.getKey(KEY_ALIAS, null) as? SecretKey)?.let { return it }
        val generator = KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, ANDROID_KEYSTORE)
        generator.init(
            KeyGenParameterSpec.Builder(KEY_ALIAS, KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT)
                .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                .setKeySize(256)
                .build()
        )
        return generator.generateKey()
    }

    private companion object {
        const val ANDROID_KEYSTORE = "AndroidKeyStore"
        const val KEY_ALIAS = "bbg_refresh_token_key"
        const val TRANSFORMATION = "AES/GCM/NoPadding"
        const val PREF_KEY = "refresh_token"
    }
}
