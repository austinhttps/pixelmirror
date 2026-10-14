// lib/services/clipboard_sync_service.dart
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import '../models/contract_models.dart';
import '../network/socket_client.dart';

/// Unified Bidirectional Clipboard Synchronization Service.
/// Symmetrically tracks Windows clipboard changes and synchronizes with
/// ClipboardSyncHelper on Android, preventing circular feedback loops.
class ClipboardSyncService {
  final SocketClient socketClient;
  String _lastSyncedText = '';
  Timer? _clipboardPollTimer;
  StreamSubscription? _sub;
  bool _isSyncing = false;

  final StreamController<String> _clipboardEvents = StreamController<String>.broadcast();
  Stream<String> get onClipboardSynced => _clipboardEvents.stream;
  String get lastSyncedText => _lastSyncedText;

  ClipboardSyncService({required this.socketClient});

  void startSync({Duration pollInterval = const Duration(milliseconds: 700)}) {
    if (_isSyncing) return;
    _isSyncing = true;

    // 1. Listen for inbound clipboard packets from Android
    _sub = socketClient.onClipboardSync.listen((ClipboardSyncData data) {
      _handleInboundClipboard(data.text);
    });

    // 2. Poll Windows OS clipboard for local changes
    _clipboardPollTimer = Timer.periodic(pollInterval, (_) => _checkWindowsClipboard());
    debugPrint('[ClipboardSync] Clipboard synchronization active.');
  }

  Future<void> _checkWindowsClipboard() async {
    if (!_isSyncing || !socketClient.isAuthorized) return;

    try {
      final ClipboardData? data = await Clipboard.getData(Clipboard.kTextPlain);
      final String? currentText = data?.text;

      if (currentText != null &&
          currentText.isNotEmpty &&
          currentText != _lastSyncedText) {
        _lastSyncedText = currentText;
        debugPrint('[ClipboardSync] Local PC clipboard changed. Transmitting to Android: "$currentText"');
        await socketClient.sendClipboard(currentText);
        _clipboardEvents.add(currentText);
      }
    } catch (e) {
      // Clipboard access might occasionally be locked by another Windows app
    }
  }

  Future<void> _handleInboundClipboard(String text) async {
    if (text.isEmpty || text == _lastSyncedText) return;

    _lastSyncedText = text;
    try {
      await Clipboard.setData(ClipboardData(text: text));
      debugPrint('[ClipboardSync] Updated Windows PC clipboard from phone: "$text"');
      _clipboardEvents.add(text);
    } catch (e) {
      debugPrint('[ClipboardSync] Failed to update Windows clipboard: $e');
    }
  }

  void stopSync() {
    _isSyncing = false;
    _clipboardPollTimer?.cancel();
    _clipboardPollTimer = null;
    _sub?.cancel();
    _sub = null;
    debugPrint('[ClipboardSync] Clipboard synchronization stopped.');
  }

  void dispose() {
    stopSync();
    _clipboardEvents.close();
  }
}
