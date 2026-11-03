// lib/crypto/aes_gcm_crypto.dart
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:cryptography/cryptography.dart';

/// 256-bit AES-GCM Cryptographic Engine adhering to Section 2 of API_CONTRACT.md.
/// Conforms precisely to Android's AesGcmCrypto.kt packing:
/// Packed format: [12-byte IV/Nonce] + [Ciphertext] + [16-byte Auth Tag].
class AesGcmEngine {
  static const int keyLengthBytes = 32; // 256-bit key
  static const int ivLengthBytes = 12; // Strict 12-byte (96-bit) IV nonce
  static const int tagLengthBytes = 16; // Strict 16-byte (128-bit) authentication tag

  final AesGcm _algorithm = AesGcm.with256bits(nonceLength: 12);
  final Random _secureRandom = Random.secure();

  /// Symmetrically decodes a Base64 string (supporting standard and URL-safe Base64 with/without padding).
  static Uint8List decodeBase64(String input) {
    String normalized = input.trim().replaceAll('-', '+').replaceAll('_', '/');
    while (normalized.length % 4 != 0) {
      normalized += '=';
    }
    return Uint8List.fromList(base64Decode(normalized));
  }

  /// Symmetrically encodes a byte array to standard Base64 string without line wrapping.
  static String encodeBase64(List<int> bytes) {
    return base64Encode(bytes);
  }

  /// Generates a cryptographically secure random 256-bit AES key (Base64-encoded).
  String generateKeyBase64() {
    final Uint8List keyBytes = Uint8List(keyLengthBytes);
    for (int i = 0; i < keyLengthBytes; i++) {
      keyBytes[i] = _secureRandom.nextInt(256);
    }
    return encodeBase64(keyBytes);
  }

  /// Generates a fresh strict 12-byte cryptographically secure random IV nonce.
  Uint8List generateIv() {
    final Uint8List iv = Uint8List(ivLengthBytes);
    for (int i = 0; i < ivLengthBytes; i++) {
      iv[i] = _secureRandom.nextInt(256);
    }
    return iv;
  }

  /// Encrypts plaintext bytes using 256-bit AES-GCM (AES/GCM/NoPadding).
  /// Returns packed byte array: [12-byte IV] + [Ciphertext] + [16-byte Tag].
  Future<Uint8List> encryptBytes({
    required Uint8List plaintext,
    required String secretKeyB64,
  }) async {
    final Uint8List keyBytes = decodeBase64(secretKeyB64);
    if (keyBytes.length != keyLengthBytes) {
      throw ArgumentError(
        'Invalid secret key length: expected $keyLengthBytes bytes (256-bit), got ${keyBytes.length}',
      );
    }

    final SecretKey secretKey = SecretKey(keyBytes);
    final Uint8List nonce = generateIv();

    final SecretBox secretBox = await _algorithm.encrypt(
      plaintext,
      secretKey: secretKey,
      nonce: nonce,
    );

    final List<int> macBytes = secretBox.mac.bytes;
    if (macBytes.length != tagLengthBytes) {
      throw StateError(
        'Unexpected auth tag length: expected $tagLengthBytes bytes (128-bit), got ${macBytes.length}',
      );
    }

    // Pack into [12-byte IV] + [Ciphertext] + [16-byte Tag]
    final Uint8List packed = Uint8List(
      nonce.length + secretBox.cipherText.length + macBytes.length,
    );

    int offset = 0;
    packed.setRange(offset, offset + nonce.length, nonce);
    offset += nonce.length;

    packed.setRange(offset, offset + secretBox.cipherText.length, secretBox.cipherText);
    offset += secretBox.cipherText.length;

    packed.setRange(offset, offset + macBytes.length, macBytes);

    return packed;
  }

  /// Encrypts a UTF-8 string to a Base64-encoded packed payload chunk.
  Future<String> encryptStringToBase64({
    required String plaintext,
    required String secretKeyB64,
  }) async {
    final Uint8List plaintextBytes = Uint8List.fromList(utf8.encode(plaintext));
    final Uint8List packed = await encryptBytes(
      plaintext: plaintextBytes,
      secretKeyB64: secretKeyB64,
    );
    return encodeBase64(packed);
  }

  /// Decrypts a packed byte array [12-byte IV] + [Ciphertext] + [16-byte Tag].
  /// Throws SecretBoxAuthenticationError or ArgumentError if validation fails.
  Future<Uint8List> decryptBytes({
    required Uint8List packedData,
    required String secretKeyB64,
  }) async {
    if (packedData.length < ivLengthBytes + tagLengthBytes) {
      throw ArgumentError('Payload too short for 256-bit AES-GCM packet.');
    }

    final Uint8List keyBytes = decodeBase64(secretKeyB64);
    if (keyBytes.length != keyLengthBytes) {
      throw ArgumentError(
        'Invalid secret key length: expected $keyLengthBytes bytes (256-bit), got ${keyBytes.length}',
      );
    }

    final SecretKey secretKey = SecretKey(keyBytes);

    // Extract IV (strictly first 12 bytes)
    final Uint8List nonce = packedData.sublist(0, ivLengthBytes);

    // Extract Auth Tag (strictly last 16 bytes = 128-bit authentication tag)
    final int tagStart = packedData.length - tagLengthBytes;
    final Uint8List tag = packedData.sublist(tagStart);

    // Extract Ciphertext (middle section)
    final Uint8List cipherText = packedData.sublist(ivLengthBytes, tagStart);

    final SecretBox secretBox = SecretBox(
      cipherText,
      nonce: nonce,
      mac: Mac(tag),
    );

    final List<int> decrypted = await _algorithm.decrypt(
      secretBox,
      secretKey: secretKey,
    );

    return Uint8List.fromList(decrypted);
  }

  /// Decrypts a Base64-encoded string containing [IV + Ciphertext + Tag] to a UTF-8 string.
  Future<String> decryptBase64ToString({
    required String base64Payload,
    required String secretKeyB64,
  }) async {
    final Uint8List packed = decodeBase64(base64Payload);
    final Uint8List decryptedBytes = await decryptBytes(
      packedData: packed,
      secretKeyB64: secretKeyB64,
    );
    return utf8.decode(decryptedBytes);
  }
}
