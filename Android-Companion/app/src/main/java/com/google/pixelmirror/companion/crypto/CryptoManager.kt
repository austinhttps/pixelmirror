package com.google.pixelmirror.companion.crypto

import android.content.Context
import android.content.SharedPreferences
import android.util.Log
import androidx.security.crypto.EncryptedSharedPreferences
import androidx.security.crypto.MasterKey
import java.util.concurrent.atomic.AtomicBoolean
import javax.crypto.SecretKey

/**
 * Singleton managing AES-GCM 256-bit session secret key, persistent storage,
 * and handshake verification state.
 */
object CryptoManager {

    private const val TAG = "CryptoManager"
    private const val PREFS_FILE = "pixel_mirror_crypto_prefs"
    private const val KEY_SECRET_B64 = "saved_secret_key_b64"

    @Volatile
    private var activeSecretKey: SecretKey? = null
    private val isAuthorizedState = AtomicBoolean(false)

    val isAuthorized: Boolean
        get() = isAuthorizedState.get()

    val currentKey: SecretKey?
        get() = activeSecretKey

    /**
     * Initializes any pre-established paired key from secure storage if available.
     */
    fun init(context: Context) {
        try {
            val masterKey = MasterKey.Builder(context)
                .setKeyScheme(MasterKey.KeyScheme.AES256_GCM)
                .build()

            val prefs = EncryptedSharedPreferences.create(
                context,
                PREFS_FILE,
                masterKey,
                EncryptedSharedPreferences.PrefKeyEncryptionScheme.AES256_SIV,
                EncryptedSharedPreferences.PrefValueEncryptionScheme.AES256_GCM
            )

            val savedKey = prefs.getString(KEY_SECRET_B64, null)
            if (!savedKey.isNullOrBlank()) {
                activeSecretKey = AesGcmCrypto.parseSecretKey(savedKey)
                Log.d(TAG, "Restored pre-established 256-bit AES-GCM key from secure storage.")
            }
        } catch (e: Exception) {
            Log.w(TAG, "EncryptedSharedPreferences not available or reset: ${e.message}")
        }
    }

    /**
     * Registers and stores a new 256-bit AES-GCM session key passed over USB ADB handshake.
     */
    @Synchronized
    fun registerSessionKey(context: Context?, secretKeyB64: String): Boolean {
        return try {
            val parsed = AesGcmCrypto.parseSecretKey(secretKeyB64)
            activeSecretKey = parsed
            isAuthorizedState.set(true)

            if (context != null) {
                try {
                    val masterKey = MasterKey.Builder(context)
                        .setKeyScheme(MasterKey.KeyScheme.AES256_GCM)
                        .build()
                    val prefs = EncryptedSharedPreferences.create(
                        context,
                        PREFS_FILE,
                        masterKey,
                        EncryptedSharedPreferences.PrefKeyEncryptionScheme.AES256_SIV,
                        EncryptedSharedPreferences.PrefValueEncryptionScheme.AES256_GCM
                    )
                    prefs.edit().putString(KEY_SECRET_B64, secretKeyB64).apply()
                } catch (e: Exception) {
                    Log.w(TAG, "Failed to persist key in secure storage: ${e.message}")
                }
            }
            Log.i(TAG, "Successfully validated and registered 256-bit AES-GCM session key.")
            true
        } catch (e: Exception) {
            Log.e(TAG, "Failed to parse secret key: ${e.message}", e)
            false
        }
    }

    /**
     * Resets the current authorization state upon client disconnection.
     */
    fun resetAuthorization() {
        isAuthorizedState.set(false)
    }

    /**
     * Encrypts outgoing data payload if a key is registered and authorized.
     */
    fun encryptPayload(plaintext: String): String {
        val key = activeSecretKey ?: return plaintext
        return AesGcmCrypto.encryptStringToBase64(plaintext, key)
    }

    /**
     * Decrypts incoming payload with the active key.
     */
    fun decryptPayload(ciphertextBase64: String): String {
        val key = activeSecretKey ?: throw IllegalStateException("No active AES-GCM key registered.")
        return AesGcmCrypto.decryptBase64ToString(ciphertextBase64, key)
    }
}
