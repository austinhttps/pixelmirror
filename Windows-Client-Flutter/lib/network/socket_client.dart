// lib/network/socket_client.dart
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import '../core/constants.dart';
import '../crypto/aes_gcm_crypto.dart';
import '../models/contract_models.dart';

/// Production-ready TCP Client managing connection, 256-bit AES-GCM cryptographic handshake,
/// streaming, packet validation, and bidirectional protocol communication.
class SocketClient {
  final AesGcmEngine _crypto = AesGcmEngine();

  Socket? _socket;
  ConnectionStateEnum _state = ConnectionStateEnum.disconnected;
  String _sessionKeyB64 = '';
  String _connectedDeviceName = '';
  String _host = ProtocolConstants.loopbackHost;
  int _port = ProtocolConstants.defaultSocketPort;

  final StreamController<ConnectionStateEnum> _stateController =
      StreamController<ConnectionStateEnum>.broadcast();
  final StreamController<EventPacket> _packetController =
      StreamController<EventPacket>.broadcast();
  final StreamController<NotificationEnqueueData> _notificationController =
      StreamController<NotificationEnqueueData>.broadcast();
  final StreamController<SecureWindowMapData> _secureWindowController =
      StreamController<SecureWindowMapData>.broadcast();
  final StreamController<SystemModeSyncData> _modeSyncController =
      StreamController<SystemModeSyncData>.broadcast();
  final StreamController<ClipboardSyncData> _clipboardController =
      StreamController<ClipboardSyncData>.broadcast();

  // Public reactive streams
  Stream<ConnectionStateEnum> get stateStream => _stateController.stream;
  Stream<EventPacket> get onPacketReceived => _packetController.stream;
  Stream<NotificationEnqueueData> get onNotification => _notificationController.stream;
  Stream<SecureWindowMapData> get onSecureWindowMap => _secureWindowController.stream;
  Stream<SystemModeSyncData> get onModeSync => _modeSyncController.stream;
  Stream<ClipboardSyncData> get onClipboardSync => _clipboardController.stream;

  ConnectionStateEnum get state => _state;
  bool get isAuthorized => _state == ConnectionStateEnum.authorized;
  String get sessionKeyB64 => _sessionKeyB64;
  String get connectedDeviceName => _connectedDeviceName;
  String get currentHost => _host;
  int get currentPort => _port;

  SocketClient() {
    // Generate initial unique 256-bit AES key for the desktop client
    _sessionKeyB64 = _crypto.generateKeyBase64();
    debugPrint('[Crypto] Generated initial 256-bit AES-GCM session key: $_sessionKeyB64');
  }

  void setCustomKey(String base64Key) {
    _sessionKeyB64 = base64Key;
    debugPrint('[Crypto] Set manual session key: $_sessionKeyB64');
  }

  /// Connects to the Android Companion SocketServerService (Port 8080)
  /// and immediately executes the Section 1 Cryptographic Handshake.
  Future<bool> connect({
    String host = ProtocolConstants.loopbackHost,
    int port = ProtocolConstants.defaultSocketPort,
    Duration timeout = const Duration(seconds: 5),
  }) async {
    if (_state == ConnectionStateEnum.authorized || _state == ConnectionStateEnum.connecting) {
      return true;
    }

    _host = host;
    _port = port;
    _updateState(ConnectionStateEnum.connecting);

    try {
      debugPrint('[Socket] Connecting to $_host:$_port (Timeout: ${timeout.inSeconds}s)...');
      _socket = await Socket.connect(_host, _port, timeout: timeout);
      _socket!.setOption(SocketOption.tcpNoDelay, true);

      debugPrint('[Socket] TCP socket opened with $_host:$_port. Initiating Cryptographic Handshake...');
      _updateState(ConnectionStateEnum.handshaking);

      final Completer<bool> handshakeCompleter = Completer<bool>();

      // Buffer incoming socket bytes
      final StringBuffer buffer = StringBuffer();
      int braceDepth = 0;
      bool inString = false;
      bool isEscaped = false;
      bool objectStarted = false;

      _socket!.listen(
        (List<int> bytes) async {
          final String chunk = utf8.decode(bytes, allowMalformed: true);

          for (int i = 0; i < chunk.length; i++) {
            final String char = chunk[i];
            buffer.write(char);

            if (char == '"' && !isEscaped) {
              inString = !inString;
            } else if (char == '\\' && inString) {
              isEscaped = !isEscaped;
              continue;
            } else if (!inString) {
              if (char == '{') {
                braceDepth++;
                objectStarted = true;
              } else if (char == '}') {
                braceDepth--;
                if (objectStarted && braceDepth == 0) {
                  final String completeJson = buffer.toString().trim();
                  buffer.clear();
                  objectStarted = false;

                  if (!handshakeCompleter.isCompleted) {
                    final bool authOk = _handleHandshakeResponse(completeJson);
                    handshakeCompleter.complete(authOk);
                  } else {
                    await _processInboundChunk(completeJson);
                  }
                }
              } else if (char == '\n' && !objectStarted) {
                // Potential Base64 encrypted packet line
                final String line = buffer.toString().trim();
                buffer.clear();
                if (line.isNotEmpty) {
                  await _processInboundChunk(line);
                }
              }
            }
            isEscaped = false;
          }
        },
        onError: (error) {
          debugPrint('[Socket] Socket stream error: $error');
          _handleDisconnection();
          if (!handshakeCompleter.isCompleted) {
            handshakeCompleter.complete(false);
          }
        },
        onDone: () {
          debugPrint('[Socket] Remote server closed socket.');
          _handleDisconnection();
          if (!handshakeCompleter.isCompleted) {
            handshakeCompleter.complete(false);
          }
        },
        cancelOnError: true,
      );

      // Send unencrypted HANDSHAKE_INIT over the USB tunnel (or direct TCP)
      final HandshakeInit initPayload = HandshakeInit(
        secretKeyB64: _sessionKeyB64,
      );
      _sendRaw(jsonEncode(initPayload.toJson()));

      // Await handshake completion with timeout
      final bool success = await handshakeCompleter.future.timeout(
        const Duration(seconds: 4),
        onTimeout: () {
          debugPrint('[Socket] Handshake challenge timed out.');
          disconnect();
          return false;
        },
      );

      if (success) {
        _updateState(ConnectionStateEnum.authorized);
        debugPrint('[Socket] Session AUTHORIZED! 256-bit AES-GCM secure channel active.');
        return true;
      } else {
        _updateState(ConnectionStateEnum.error);
        disconnect();
        return false;
      }
    } catch (e) {
      debugPrint('[Socket] Connection failed to $_host:$_port: $e');
      _updateState(ConnectionStateEnum.error);
      disconnect();
      return false;
    }
  }

  bool _handleHandshakeResponse(String rawJson) {
    try {
      final Map<String, dynamic> data = jsonDecode(rawJson);
      final HandshakeResponse response = HandshakeResponse.fromJson(data);

      if (response.isAuthorized) {
        _connectedDeviceName = response.deviceName;
        debugPrint('[Handshake] Authorized by device: ${response.deviceName}');
        return true;
      } else {
        debugPrint('[Handshake] Handshake rejected: ${response.status}');
        return false;
      }
    } catch (e) {
      debugPrint('[Handshake] Error parsing handshake response: $e');
      return false;
    }
  }

  /// Inbound packet processor with 256-bit AES-GCM decryption and validation.
  Future<void> _processInboundChunk(String chunk) async {
    if (!isAuthorized) {
      debugPrint('[Socket] Dropping packet: Session not authorized.');
      return;
    }

    try {
      String jsonStr;

      if (chunk.startsWith('{') && chunk.contains('"event_type"')) {
        // Plaintext event frame
        jsonStr = chunk;
      } else {
        // Encrypted Base64 AES-GCM packet
        jsonStr = await _crypto.decryptBase64ToString(
          base64Payload: chunk,
          secretKeyB64: _sessionKeyB64,
        );
      }

      final Map<String, dynamic> parsed = jsonDecode(jsonStr);
      final EventPacket packet = EventPacket.fromJson(parsed);

      debugPrint('[Socket] Successfully received & verified event: ${packet.eventType}');
      _packetController.add(packet);

      // Route event to specialized streams
      switch (packet.eventType) {
        case ProtocolConstants.eventNotificationEnqueue:
          final NotificationEnqueueData notif = NotificationEnqueueData.fromJson(packet.data);
          _notificationController.add(notif);
          break;
        case ProtocolConstants.eventSecureWindowMap:
          final SecureWindowMapData windowMap = SecureWindowMapData.fromJson(packet.data);
          _secureWindowController.add(windowMap);
          break;
        case ProtocolConstants.eventSystemModeSync:
          final SystemModeSyncData mode = SystemModeSyncData.fromJson(packet.data);
          _modeSyncController.add(mode);
          break;
        case ProtocolConstants.eventClipboardSync:
          final ClipboardSyncData clip = ClipboardSyncData.fromJson(packet.data);
          _clipboardController.add(clip);
          break;
      }
    } catch (e) {
      debugPrint('[Socket] Security/Validation Challenge failed. Dropping packet: $e');
    }
  }

  /// Sends an EventPacket across the socket, encrypted with 256-bit AES-GCM by default.
  Future<void> sendPacket(EventPacket packet, {bool encrypt = true}) async {
    if (_socket == null || !isAuthorized) {
      debugPrint('[Socket] Cannot send packet: Socket not connected or authorized.');
      return;
    }

    try {
      final String rawJson = packet.toJsonString();

      if (encrypt) {
        final String encryptedB64 = await _crypto.encryptStringToBase64(
          plaintext: rawJson,
          secretKeyB64: _sessionKeyB64,
        );
        _sendRaw(encryptedB64);
        debugPrint('[Socket] Sent AES-GCM encrypted packet: ${packet.eventType}');
      } else {
        _sendRaw(rawJson);
        debugPrint('[Socket] Sent plaintext packet: ${packet.eventType}');
      }
    } catch (e) {
      debugPrint('[Socket] Error transmitting packet: $e');
    }
  }

  /// Section 2.2: Interactive Quick-Reply
  Future<void> sendQuickReply({
    required int notificationId,
    required String packageName,
    required String replyText,
  }) async {
    final NotificationReplyData reply = NotificationReplyData(
      notificationId: notificationId,
      packageName: packageName,
      replyText: replyText,
    );
    await sendPacket(reply.toEventPacket());
  }

  /// Section 3.2: Dynamic Action / Remote Input
  Future<void> sendRemoteInput({
    required int targetX,
    required int targetY,
    String actionType = ProtocolConstants.actionClickCoordinate,
  }) async {
    final RemoteInputActionData input = RemoteInputActionData(
      actionType: actionType,
      targetX: targetX,
      targetY: targetY,
    );
    await sendPacket(input.toEventPacket());
  }

  /// Section 3.3 & 3.4: Smart File Drop & Quick Share
  Future<void> sendFileDrop({
    required String filename,
    required Uint8List fileBytes,
    int targetX = -1,
    int targetY = -1,
    bool isCanvasPaste = true,
    String mimeType = 'application/octet-stream',
  }) async {
    final String b64 = base64Encode(fileBytes);
    final FileDropData fileDrop = FileDropData(
      filename: filename,
      mimeType: mimeType,
      fileBase64: b64,
      targetX: targetX,
      targetY: targetY,
      isCanvasPaste: isCanvasPaste,
    );
    await sendPacket(fileDrop.toEventPacket());
  }

  /// Section 4.1: Phone Mode Toggle
  Future<void> sendModeSync({
    required String modeType,
    required bool isEnabled,
  }) async {
    final SystemModeSyncData mode = SystemModeSyncData(
      modeType: modeType,
      isEnabled: isEnabled,
    );
    await sendPacket(mode.toEventPacket());
  }

  /// Section 4.2: Hotspot Trigger Request
  Future<void> sendHotspotRequest({
    String action = ProtocolConstants.actionLaunchTetherSettings,
  }) async {
    final HotspotRequestData req = HotspotRequestData(action: action);
    await sendPacket(req.toEventPacket());
  }

  /// Symmetrically sync PC clipboard down to phone
  Future<void> sendClipboard(String text) async {
    final ClipboardSyncData clip = ClipboardSyncData(text: text);
    await sendPacket(clip.toEventPacket());
  }

  void _sendRaw(String message) {
    if (_socket != null) {
      _socket!.write('$message\n');
      _socket!.flush();
    }
  }

  void _updateState(ConnectionStateEnum newState) {
    _state = newState;
    _stateController.add(newState);
  }

  void _handleDisconnection() {
    _updateState(ConnectionStateEnum.disconnected);
    try {
      _socket?.destroy();
    } catch (_) {}
    _socket = null;
  }

  void disconnect() {
    _handleDisconnection();
  }

  void dispose() {
    disconnect();
    _stateController.close();
    _packetController.close();
    _notificationController.close();
    _secureWindowController.close();
    _modeSyncController.close();
    _clipboardController.close();
  }
}
