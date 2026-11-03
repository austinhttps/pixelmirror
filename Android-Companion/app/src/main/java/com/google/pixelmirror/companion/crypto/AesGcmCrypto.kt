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

    const val ALGORITHM = "AES"
    const val TRANSFORMATION = "AES/GCM/NoPadding"
    const val GCM_IV_LENGTH_BYTES = 12 // Strict 12-byte (96-bit) IV nonce
    const val GCM_TAG_LENGTH_BITS = 128 // Strict 128-bit (16-byte) authentication tag
    const val KEY_LENGTH_BYTES = 32 // 256-bit key

    private val secureRandom = SecureRandom()

    /**
     * Symmetrically decodes a Base64 string (supporting both standard and URL-safe Base64).
     */
    fun decodeBase64(input: String): ByteArray {
        val trimmed = input.trim()
        val normalized = trimmed.replace('-', '+').replace('_', '/')
        val padded = when (normalized.length % 4) {
            2 -> "$normalized=="
            3 -> "$normalized="
            else -> normalized
        }
        return Base64.decode(padded, Base64.NO_WRAP)
    }

    /**
     * Symmetrically encodes a byte array to standard Base64 string without line wrapping.
     */
    fun encodeBase64(bytes: ByteArray): String {
        return Base64.encodeToString(bytes, Base64.NO_WRAP)
    }

    /**
     * Generates a cryptographically secure random 256-bit AES key (Base64-encoded).
     */
    fun generateSecretKeyBase64(): String {
        val keyBytes = ByteArray(KEY_LENGTH_BYTES)
        secureRandom.nextBytes(keyBytes)
        return encodeBase64(keyBytes)
    }

    /**
     * Parses and validates a Base64-encoded 256-bit AES secret key.
     */
    fun parseSecretKey(base64Key: String): SecretKey {
        val decoded = decodeBase64(base64Key)
        require(decoded.size == KEY_LENGTH_BYTES) {
            "Invalid secret key length: expected $KEY_LENGTH_BYTES bytes (256-bit), got ${decoded.size} bytes."
        }
        return SecretKeySpec(decoded, ALGORITHM)
    }

    /**
     * Generates a fresh strict 12-byte cryptographically secure random IV.
     */
    fun generateIv(): ByteArray {
        val iv = ByteArray(GCM_IV_LENGTH_BYTES)
        secureRandom.nextBytes(iv)
        return iv
    }

    /**
     * Encrypts plaintext bytes using 256-bit AES-GCM (AES/GCM/NoPadding).
     * Returns a packed byte array: [12-byte IV] + [Ciphertext + 16-byte Tag].
     */
    fun encrypt(plaintext: ByteArray, secretKey: SecretKey): ByteArray {
        val iv = generateIv()
        require(iv.size == GCM_IV_LENGTH_BYTES) { "IV must be strictly $GCM_IV_LENGTH_BYTES bytes." }

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
        return encodeBase64(encryptedBytes)
    }

    /**
     * Decrypts a packed byte array [12-byte IV] + [Ciphertext + Tag] using 256-bit AES-GCM.
     * Throws AEADBadTagException or GeneralSecurityException if ciphertext is tampered with.
     */
    fun decrypt(packedData: ByteArray, secretKey: SecretKey): ByteArray {
        val tagLengthBytes = GCM_TAG_LENGTH_BITS / 8
        require(packedData.size >= GCM_IV_LENGTH_BYTES + tagLengthBytes) {
            "Payload too short for AES-GCM packet."
        }
        val iv = packedData.copyOfRange(0, GCM_IV_LENGTH_BYTES)
        require(iv.size == GCM_IV_LENGTH_BYTES) { "IV must be strictly $GCM_IV_LENGTH_BYTES bytes." }
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
        val packed = decodeBase64(base64Payload)
        val decryptedBytes = decrypt(packed, secretKey)
        return String(decryptedBytes, Charsets.UTF_8)
    }
}
