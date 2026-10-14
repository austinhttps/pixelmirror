// lib/services/mode_sync_service.dart
import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import '../models/contract_models.dart';
import '../network/socket_client.dart';

class ModeSyncService {
  final SocketClient socketClient;
  bool _isDndActive = false;
  bool _isSilentActive = false;
  StreamSubscription? _sub;

  final StreamController<bool> _dndStateController = StreamController<bool>.broadcast();
  Stream<bool> get onDndStateChanged => _dndStateController.stream;

  bool get isDndActive => _isDndActive;
  bool get isSilentActive => _isSilentActive;

  ModeSyncService({required this.socketClient});

  void init() {
    _sub = socketClient.onModeSync.listen((SystemModeSyncData data) {
      handleIncomingMode(data);
    });
  }

  void handleIncomingMode(SystemModeSyncData data) {
    debugPrint('[ModeSync] Received SYSTEM_MODE_SYNC: ${data.modeType} -> ${data.isEnabled}');

    if (data.modeType == 'DO_NOT_DISTURB') {
      _isDndActive = data.isEnabled;
      _dndStateController.add(_isDndActive);
      _syncWindowsFocusAssist(_isDndActive);
    } else if (data.modeType == 'RINGER_MODE') {
      _isSilentActive = data.isEnabled;
    }
  }

  /// Synchronizes Windows 11 Focus Mode state matching phone boundaries.
  Future<void> _syncWindowsFocusAssist(bool enabled) async {
    if (!Platform.isWindows) return;

    try {
      // Modify Windows 11 Notification Quiet Hours / Focus Assist registry key
      // 0 = Off, 1 = Priority only, 2 = Alarms only
      final int value = enabled ? 1 : 0;
      final String cmd =
          'Set-ItemProperty -Path "HKCU:\\Software\\Microsoft\\Windows\\CurrentVersion\\Notifications\\Settings" -Name "NOC_GLOBAL_SETTING_TOASTS_ENABLED" -Value ${enabled ? 0 : 1} -ErrorAction SilentlyContinue';

      await Process.run('powershell', ['-NoProfile', '-Command', cmd]);
      debugPrint('[ModeSync] Windows 11 Focus Assist updated: FocusActive=$enabled (regVal=$value)');
    } catch (e) {
      debugPrint('[ModeSync] Could not update Windows Focus Assist registry: $e');
    }
  }

  /// Sends HOTSPOT_REQUEST to force SystemActionHelper to open TetherSettings on Android.
  Future<void> requestPhoneHotspotToggle() async {
    debugPrint('[ModeSync] Dispatching HOTSPOT_REQUEST to phone...');
    await socketClient.sendHotspotRequest();
  }

  /// Allows toggling phone DND from Windows client
  Future<void> togglePhoneDnd(bool enabled) async {
    _isDndActive = enabled;
    _dndStateController.add(_isDndActive);
    await socketClient.sendModeSync(modeType: 'DO_NOT_DISTURB', isEnabled: enabled);
  }

  void dispose() {
    _sub?.cancel();
    _dndStateController.close();
  }
}
