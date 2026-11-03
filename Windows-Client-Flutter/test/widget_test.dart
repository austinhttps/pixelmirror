import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:windows_client_flutter/crypto/aes_gcm_crypto.dart';
import 'package:windows_client_flutter/models/contract_models.dart';

void main() {
  test('AesGcm parameters check (12-byte IV, 128-bit tag, URL-safe Base64)', () async {
    final engine = AesGcmEngine();
    final key = engine.generateKeyBase64();
    final urlSafeKey = key.replaceAll('+', '-').replaceAll('/', '_').replaceAll('=', '');

    final encryptedBytes = await engine.encryptBytes(
      plaintext: Uint8List.fromList('Sync Test'.codeUnits),
      secretKeyB64: urlSafeKey,
    );

    // Minimum length check: 12-byte IV + 9-byte plaintext + 16-byte tag = 37 bytes
    expect(encryptedBytes.length, 12 + 9 + 16);

    final decryptedBytes = await engine.decryptBytes(
      packedData: encryptedBytes,
      secretKeyB64: key,
    );
    expect(String.fromCharCodes(decryptedBytes), 'Sync Test');

    final encryptedB64 = await engine.encryptStringToBase64(
      plaintext: 'Hello Android',
      secretKeyB64: key,
    );
    final decrypted = await engine.decryptBase64ToString(
      base64Payload: encryptedB64,
      secretKeyB64: urlSafeKey,
    );
    expect(decrypted, 'Hello Android');
  });

  test('HandshakeInit serialization and deserialization', () {
    final init = HandshakeInit(
      secretKeyB64: 'dGVzdFNlY3JldEtleTEyMzQ1Njc4OTA=',
    );
    final json = init.toJson();
    expect(json['type'], 'HANDSHAKE_INIT');
    expect(json['payload']['secret_key_b64'], 'dGVzdFNlY3JldEtleTEyMzQ1Njc4OTA=');

    final parsed = HandshakeInit.fromJson(json);
    expect(parsed.secretKeyB64, init.secretKeyB64);
  });

  test('HandshakeResponse status verification', () {
    final authResp = HandshakeResponse(status: 'AUTHORIZED', deviceName: 'Google Pixel 10');
    expect(authResp.isAuthorized, true);
    expect(authResp.deviceName, 'Google Pixel 10');

    final json = authResp.toJson();
    final parsed = HandshakeResponse.fromJson(json);
    expect(parsed.isAuthorized, true);

    final unauthResp = HandshakeResponse(status: 'UNAUTHORIZED');
    expect(unauthResp.isAuthorized, false);
  });

  test('NotificationEnqueueData and NotificationReplyData round-trip', () {
    final enqueue = NotificationEnqueueData(
      notificationId: 4012,
      packageName: 'com.google.android.apps.messaging',
      appLabel: 'Messages',
      title: 'Austin',
      body: 'Testing V1 notification streaming',
      iconBase64: 'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==',
    );

    final packet = enqueue.toEventPacket();
    expect(packet.eventType, 'NOTIFICATION_ENQUEUE');
    expect(packet.data['notification_id'], 4012);
    expect(packet.data['package_name'], 'com.google.android.apps.messaging');

    final parsedEnqueue = NotificationEnqueueData.fromJson(packet.data);
    expect(parsedEnqueue.notificationId, enqueue.notificationId);
    expect(parsedEnqueue.body, enqueue.body);

    final reply = NotificationReplyData(
      notificationId: 4012,
      packageName: 'com.google.android.apps.messaging',
      replyText: 'Replying from Windows client!',
    );

    final replyPacket = reply.toEventPacket();
    expect(replyPacket.eventType, 'NOTIFICATION_REPLY');
    final parsedReply = NotificationReplyData.fromJson(replyPacket.data);
    expect(parsedReply.replyText, reply.replyText);
  });

  test('ClipboardSyncData framing and special characters', () {
    const specialText = 'Hello 🚀 Pixel 10! Includes \n newlines and unicode: 汉字, emojis 🎉!';
    final clipData = ClipboardSyncData(text: specialText);
    final packet = clipData.toEventPacket();

    expect(packet.eventType, 'CLIPBOARD_SYNC');
    expect(packet.data['text'], specialText);

    final jsonStr = packet.toJsonString();
    final parsedPacket = EventPacket.fromJson(jsonDecode(jsonStr));
    final parsedClip = ClipboardSyncData.fromJson(parsedPacket.data);
    expect(parsedClip.text, specialText);
  });
}
