package com.google.pixelmirror.companion.crypto

import android.util.Base64
import java.nio.ByteBuffer
import java.security.SecureRandom
import javax.crypto.Cipher
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec
import javax.crypto.spec.SecretKeySpec

/**
 * High-performance 256-bit AES-GCM cryptographic engine conforming to
 * Section 2 of API_CONTRACT.md.
 */
object AesGcmCrypto {

    private const val ALGORITHM = "AES"
    private const val TRANSFORMATION = "AES/GCM/NoPadding"
    private const val GCM_IV_LENGTH_BYTES = 12 // 96-bit recommended nonce
    private const val GCM_TAG_LENGTH_BITS = 128 // 16-byte authentication tag
    private const val KEY_LENGTH_BYTES = 32 // 256-bit key

    private val secureRandom = SecureRandom()

    /**
     * Parses and validates a Base64-encoded 256-bit AES secret key.
     */
    fun parseSecretKey(base64Key: String): SecretKey {
        val decoded = Base64.decode(base64Key.trim(), Base64.DEFAULT)
        require(decoded.size == KEY_LENGTH_BYTES) {
            "Invalid secret key length: expected 32 bytes (256-bit), got ${decoded.size} bytes."
        }
        return SecretKeySpec(decoded, ALGORITHM)
    }

    /**
     * Generates a fresh 12-byte cryptographically secure random IV.
     */
    fun generateIv(): ByteArray {
        val iv = ByteArray(GCM_IV_LENGTH_BYTES)
        secureRandom.nextBytes(iv)
        return iv
    }

    /**
     * Encrypts plaintext bytes using 256-bit AES-GCM.
     * Returns a packed byte array: [12-byte IV] + [Ciphertext + 16-byte Tag].
     */
    fun encrypt(plaintext: ByteArray, secretKey: SecretKey): ByteArray {
        val iv = generateIv()
        val cipher = Cipher.getInstance(TRANSFORMATION)
        val spec = GCMParameterSpec(GCM_TAG_LENGTH_BITS, iv)
        cipher.init(Cipher.ENCRYPT_MODE, secretKey, spec)

        val cipherBytes = cipher.doFinal(plaintext)
        val buffer = ByteBuffer.allocate(iv.size + cipherBytes.size)
        buffer.put(iv)
        buffer.put(cipherBytes)
        return buffer.array()
    }

    /**
     * Encrypts a UTF-8 string to a Base64-encoded string containing [IV + Ciphertext + Tag].
     */
    fun encryptStringToBase64(plaintext: String, secretKey: SecretKey): String {
        val encryptedBytes = encrypt(plaintext.toByteArray(Charsets.UTF_8), secretKey)
        return Base64.encodeToString(encryptedBytes, Base64.NO_WRAP)
    }

    /**
     * Decrypts a packed byte array [12-byte IV] + [Ciphertext + Tag] using 256-bit AES-GCM.
     * Throws AEADBadTagException or GeneralSecurityException if ciphertext is tampered with.
     */
    fun decrypt(packedData: ByteArray, secretKey: SecretKey): ByteArray {
        require(packedData.size >= GCM_IV_LENGTH_BYTES + (GCM_TAG_LENGTH_BITS / 8)) {
            "Payload too short for AES-GCM packet."
        }
        val iv = packedData.copyOfRange(0, GCM_IV_LENGTH_BYTES)
        val cipherBytes = packedData.copyOfRange(GCM_IV_LENGTH_BYTES, packedData.size)

        val cipher = Cipher.getInstance(TRANSFORMATION)
        val spec = GCMParameterSpec(GCM_TAG_LENGTH_BITS, iv)
        cipher.init(Cipher.DECRYPT_MODE, secretKey, spec)

        return cipher.doFinal(cipherBytes)
    }

    /**
     * Decrypts a Base64-encoded string containing [IV + Ciphertext + Tag] to a UTF-8 string.
     */
    fun decryptBase64ToString(base64Payload: String, secretKey: SecretKey): String {
        val packed = Base64.decode(base64Payload.trim(), Base64.DEFAULT)
        val decryptedBytes = decrypt(packed, secretKey)
        return String(decryptedBytes, Charsets.UTF_8)
    }
}
