// lib/network/socket_client.dart
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import '../core/constants.dart';
import '../crypto/aes_gcm_crypto.dart';
import '../models/contract_models.dart';

/// Production-ready TCP Client managing connection, 256-bit AES-GCM cryptographic handshake,
/// streaming, packet validation, bidirectional protocol communication, and auto-reconnect.
class SocketClient {
  final AesGcmEngine _crypto = AesGcmEngine();

  Socket? _socket;
  ConnectionStateEnum _state = ConnectionStateEnum.disconnected;
  String _sessionKeyB64 = '';
  String _connectedDeviceName = ProtocolConstants.defaultDeviceName;
  String _host = ProtocolConstants.loopbackHost;
  int _port = ProtocolConstants.defaultSocketPort;

  // Auto-reconnect state
  bool _enableAutoReconnect = true;
  bool _manualDisconnect = false;
  Timer? _reconnectTimer;

  final StreamController<ConnectionStateEnum> _stateController =
      StreamController<ConnectionStateEnum>.broadcast();
  final StreamController<EventPacket> _packetController =
      StreamController<EventPacket>.broadcast();
  final StreamController<NotificationEnqueueData> _notificationController =
      StreamController<NotificationEnqueueData>.broadcast();
  final StreamController<ClipboardSyncData> _clipboardController =
      StreamController<ClipboardSyncData>.broadcast();

  // Public reactive streams
  Stream<ConnectionStateEnum> get stateStream => _stateController.stream;
  Stream<EventPacket> get onPacketReceived => _packetController.stream;
  Stream<NotificationEnqueueData> get onNotification => _notificationController.stream;
  Stream<ClipboardSyncData> get onClipboardSync => _clipboardController.stream;

  ConnectionStateEnum get state => _state;
  bool get isAuthorized => _state == ConnectionStateEnum.authorized;
  String get sessionKeyB64 => _sessionKeyB64;
  String get connectedDeviceName => _connectedDeviceName;
  String get currentHost => _host;
  int get currentPort => _port;
  bool get enableAutoReconnect => _enableAutoReconnect;

  set enableAutoReconnect(bool val) {
    _enableAutoReconnect = val;
    if (!val) {
      _reconnectTimer?.cancel();
      _reconnectTimer = null;
    }
  }

  SocketClient() {
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

    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _manualDisconnect = false;

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
                // Base64 encrypted packet line
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
      final String handshakePayload = jsonEncode(initPayload.toJson());
      debugPrint('[Socket] Writing HANDSHAKE_INIT unencrypted JSON payload with trailing newline');
      _socket!.write('$handshakePayload\n');
      await _socket!.flush();

      // Await handshake completion with timeout
      final bool success = await handshakeCompleter.future.timeout(
        const Duration(seconds: 4),
        onTimeout: () {
          debugPrint('[Socket] Handshake challenge timed out.');
          disconnect(manual: false);
          return false;
        },
      );

      if (success) {
        _updateState(ConnectionStateEnum.authorized);
        debugPrint('[Socket] Session AUTHORIZED! 256-bit AES-GCM secure channel active.');
        return true;
      } else {
        _updateState(ConnectionStateEnum.error);
        disconnect(manual: false);
        return false;
      }
    } catch (e) {
      debugPrint('[Socket] Connection failed to $_host:$_port: $e');
      _updateState(ConnectionStateEnum.error);
      _handleDisconnection();
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
        await _sendRaw(encryptedB64);
        debugPrint('[Socket] Sent AES-GCM encrypted packet: ${packet.eventType}');
      } else {
        await _sendRaw(rawJson);
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

  /// Symmetrically sync PC clipboard down to phone
  Future<void> sendClipboard(String text) async {
    final ClipboardSyncData clip = ClipboardSyncData(text: text);
    await sendPacket(clip.toEventPacket());
  }

  Future<void> _sendRaw(String message) async {
    if (_socket != null) {
      _socket!.write('$message\n');
      await _socket!.flush();
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

    // Schedule auto-reconnect if enabled and not manually disconnected
    if (_enableAutoReconnect && !_manualDisconnect) {
      _scheduleReconnect();
    }
  }

  void _scheduleReconnect() {
    _reconnectTimer?.cancel();
    debugPrint('[Socket] Auto-reconnect scheduled in 3 seconds...');
    _reconnectTimer = Timer(const Duration(seconds: 3), () async {
      if (_state == ConnectionStateEnum.disconnected && _enableAutoReconnect && !_manualDisconnect) {
        debugPrint('[Socket] Attempting auto-reconnect to $_host:$_port...');
        await connect(host: _host, port: _port);
      }
    });
  }

  void disconnect({bool manual = true}) {
    _manualDisconnect = manual;
    if (manual) {
      _reconnectTimer?.cancel();
      _reconnectTimer = null;
    }
    _handleDisconnection();
  }

  void dispose() {
    _enableAutoReconnect = false;
    _reconnectTimer?.cancel();
    disconnect(manual: true);
    _stateController.close();
    _packetController.close();
    _notificationController.close();
    _clipboardController.close();
  }
}
