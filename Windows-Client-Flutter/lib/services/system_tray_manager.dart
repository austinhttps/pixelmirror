import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:system_tray/system_tray.dart';

typedef MenuItemSeparator = MenuSeparator;

class SystemTrayManager {
  final SystemTray _systemTray = SystemTray();
  final Menu _menu = Menu();
  final AppWindow _appWindow = AppWindow();

  Future<void> initSystemTray() async {
    try {
      // Determine the icon based on OS
      final String iconPath = Platform.isWindows ? 'assets/app_icon.ico' : 'assets/app_icon.png';

      // Initialize the tray icon natively
      await _systemTray.initSystemTray(
        title: "Pixel Mirror",
        iconPath: iconPath,
      );

      // Reconstruct the Menu using proper system_tray syntax
      await _menu.buildFrom([
        MenuItemLabel(
          label: 'Show Dashboard',
          image: 'assets/show.png',
          onClicked: (menuItem) => _handleShow(),
        ),
        MenuItemSeparator(),
        MenuItemLabel(
          label: 'Disconnect Service',
          onClicked: (menuItem) => _handleDisconnect(),
        ),
        MenuItemLabel(
          label: 'Exit',
          onClicked: (menuItem) => _handleExit(),
        ),
      ]);

      // Context menu link hook
      await _systemTray.setContextMenu(_menu);

      // Handle primary single/double click window restorations
      _systemTray.registerSystemTrayEventHandler((eventName) {
        if (eventName == kSystemTrayEventClick) {
          _handleShow();
        }
      });
    } catch (e) {
      debugPrint('[SystemTray] Initialization note: $e');
    }
  }

  void _handleShow() {
    _appWindow.show();
  }

  void _handleDisconnect() {
    // Session termination loops hook here
  }

  void _handleExit() {
    _appWindow.close();
    exit(0);
  }
}
