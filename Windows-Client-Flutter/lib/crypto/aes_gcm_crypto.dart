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
  static const int ivLengthBytes = 12; // 96-bit nonce
  static const int tagLengthBytes = 16; // 128-bit authentication tag

  final AesGcm _algorithm = AesGcm.with256bits();
  final Random _secureRandom = Random.secure();

  /// Generates a cryptographically secure random 256-bit AES key (Base64-encoded).
  String generateKeyBase64() {
    final Uint8List keyBytes = Uint8List(keyLengthBytes);
    for (int i = 0; i < keyLengthBytes; i++) {
      keyBytes[i] = _secureRandom.nextInt(256);
    }
    return base64Encode(keyBytes);
  }

  /// Generates a fresh 12-byte cryptographically secure IV nonce.
  Uint8List generateIv() {
    final Uint8List iv = Uint8List(ivLengthBytes);
    for (int i = 0; i < ivLengthBytes; i++) {
      iv[i] = _secureRandom.nextInt(256);
    }
    return iv;
  }

  /// Encrypts plaintext bytes using 256-bit AES-GCM.
  /// Returns packed byte array: [12-byte IV] + [Ciphertext] + [16-byte Tag].
  Future<Uint8List> encryptBytes({
    required Uint8List plaintext,
    required String secretKeyB64,
  }) async {
    final Uint8List keyBytes = base64Decode(secretKeyB64.trim());
    if (keyBytes.length != keyLengthBytes) {
      throw ArgumentError(
        'Invalid secret key length: expected $keyLengthBytes bytes, got ${keyBytes.length}',
      );
    }

    final SecretKey secretKey = SecretKey(keyBytes);
    final Uint8List nonce = generateIv();

    final SecretBox secretBox = await _algorithm.encrypt(
      plaintext,
      secretKey: secretKey,
      nonce: nonce,
    );

    // Pack into [12-byte IV] + [Ciphertext] + [16-byte Tag]
    final Uint8List packed = Uint8List(
      nonce.length + secretBox.cipherText.length + secretBox.mac.bytes.length,
    );

    int offset = 0;
    packed.setRange(offset, offset + nonce.length, nonce);
    offset += nonce.length;

    packed.setRange(offset, offset + secretBox.cipherText.length, secretBox.cipherText);
    offset += secretBox.cipherText.length;

    packed.setRange(offset, offset + secretBox.mac.bytes.length, secretBox.mac.bytes);

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
    return base64Encode(packed);
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

    final Uint8List keyBytes = base64Decode(secretKeyB64.trim());
    if (keyBytes.length != keyLengthBytes) {
      throw ArgumentError(
        'Invalid secret key length: expected $keyLengthBytes bytes, got ${keyBytes.length}',
      );
    }

    final SecretKey secretKey = SecretKey(keyBytes);

    // Extract IV (first 12 bytes)
    final Uint8List nonce = packedData.sublist(0, ivLengthBytes);

    // Extract Auth Tag (last 16 bytes)
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
    final Uint8List packed = base64Decode(base64Payload.trim());
    final Uint8List decryptedBytes = await decryptBytes(
      packedData: packed,
      secretKeyB64: secretKeyB64,
    );
    return utf8.decode(decryptedBytes);
  }
}
