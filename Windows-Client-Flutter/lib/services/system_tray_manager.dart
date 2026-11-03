// lib/services/system_tray_manager.dart
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:system_tray/system_tray.dart';
import 'package:window_manager/window_manager.dart';

typedef MenuItemSeparator = MenuSeparator;

class SystemTrayManager {
  final SystemTray _systemTray = SystemTray();
  final Menu _menu = Menu();

  Future<void> initSystemTray({
    required VoidCallback onShowDashboard,
    required VoidCallback onSyncClipboardNow,
    required VoidCallback onDisconnect,
  }) async {
    try {
      final String iconPath = Platform.isWindows ? 'assets/app_icon.ico' : 'assets/app_icon.png';

      await _systemTray.initSystemTray(
        title: "Pixel Mirror",
        iconPath: iconPath,
      );

      await _menu.buildFrom([
        MenuItemLabel(
          label: 'Show Dashboard',
          onClicked: (_) => onShowDashboard(),
        ),
        MenuItemLabel(
          label: 'Sync Clipboard Now',
          onClicked: (_) => onSyncClipboardNow(),
        ),
        MenuItemSeparator(),
        MenuItemLabel(
          label: 'Disconnect',
          onClicked: (_) => onDisconnect(),
        ),
        MenuItemLabel(
          label: 'Exit',
          onClicked: (_) => exit(0),
        ),
      ]);

      await _systemTray.setContextMenu(_menu);

      _systemTray.registerSystemTrayEventHandler((eventName) async {
        if (eventName == kSystemTrayEventClick) {
          await toggleWindowVisibility();
        }
      });
    } catch (e) {
      debugPrint('[SystemTray] Initialization note: $e');
    }
  }

  Future<void> toggleWindowVisibility() async {
    try {
      final bool isVisible = await windowManager.isVisible();
      if (isVisible) {
        await windowManager.hide();
      } else {
        await windowManager.show();
        await windowManager.focus();
      }
    } catch (e) {
      debugPrint('[SystemTray] Toggle window visibility error: $e');
    }
  }

  Future<void> showWindow() async {
    try {
      await windowManager.show();
      await windowManager.focus();
    } catch (_) {}
  }
}
