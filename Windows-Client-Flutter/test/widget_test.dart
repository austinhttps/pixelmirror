import 'package:flutter_test/flutter_test.dart';
import 'package:windows_client_flutter/models/contract_models.dart';

void main() {
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
}
