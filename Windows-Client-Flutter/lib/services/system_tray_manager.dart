// lib/services/system_tray_manager.dart
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';
import '../network/adb_manager.dart';
import '../network/socket_client.dart';

class SystemTrayManager with TrayListener {
  final SocketClient socketClient;
  final AdbManager adbManager;
  final VoidCallback onToggleConnection;

  bool _isWindowVisible = true;

  SystemTrayManager({
    required this.socketClient,
    required this.adbManager,
    required this.onToggleConnection,
  });

  Future<void> init() async {
    try {
      trayManager.addListener(this);

      // Set default tray icon
      await trayManager.setIcon(
        Platform.isWindows ? 'assets/tray_icon.ico' : 'assets/app_icon.png',
      );

      await trayManager.setToolTip('Pixel 10 Mirror - Windows Client');
      await updateContextMenu();
    } catch (e) {
      debugPrint('[SystemTray] Failed to initialize system tray: $e');
    }
  }

  Future<void> updateContextMenu() async {
    final bool isConnected = socketClient.isAuthorized;

    final Menu menu = Menu(
      items: [
        MenuItem(
          key: 'status',
          label: isConnected
              ? 'Status: Connected (${socketClient.connectedDeviceName})'
              : 'Status: Disconnected',
          disabled: true,
        ),
        MenuItem.separator(),
        MenuItem(
          key: 'toggle_connect',
          label: isConnected ? 'Disconnect Socket' : 'Connect to Pixel 10',
        ),
        MenuItem(
          key: 'toggle_window',
          label: _isWindowVisible ? 'Minimize to Tray' : 'Show Mirror Window',
        ),
        MenuItem.separator(),
        MenuItem(
          key: 'terminate_adb',
          label: 'Clean Terminate ADB Subprocesses',
        ),
        MenuItem(
          key: 'exit_app',
          label: 'Exit Completely',
        ),
      ],
    );

    try {
      await trayManager.setContextMenu(menu);
    } catch (e) {
      debugPrint('[SystemTray] Error updating context menu: $e');
    }
  }

  @override
  void onTrayIconMouseDown() {
    debugPrint('[SystemTray] Left-click on tray icon detected: toggling connection & window state.');
    // Left-clicking the tray icon toggles the connection engine or cleanly terminates background ADB subprocesses
    if (socketClient.isAuthorized) {
      onToggleConnection();
    } else {
      toggleWindowVisibility();
      onToggleConnection();
    }
  }

  @override
  void onTrayIconRightMouseDown() {
    trayManager.popUpContextMenu();
  }

  @override
  void onTrayMenuItemClick(MenuItem menuItem) async {
    switch (menuItem.key) {
      case 'toggle_connect':
        onToggleConnection();
        await updateContextMenu();
        break;
      case 'toggle_window':
        await toggleWindowVisibility();
        break;
      case 'terminate_adb':
        debugPrint('[SystemTray] Terminating ADB subprocesses from tray...');
        await adbManager.cleanTerminateAdb();
        break;
      case 'exit_app':
        debugPrint('[SystemTray] Cleaning up resources before exit...');
        socketClient.disconnect();
        await adbManager.cleanTerminateAdb();
        await trayManager.destroy();
        exit(0);
    }
  }

  Future<void> toggleWindowVisibility() async {
    if (_isWindowVisible) {
      await windowManager.hide();
      _isWindowVisible = false;
    } else {
      await windowManager.show();
      await windowManager.focus();
      _isWindowVisible = true;
    }
    await updateContextMenu();
  }

  void dispose() {
    trayManager.removeListener(this);
    trayManager.destroy();
  }
}
