// lib/main.dart
import 'dart:io';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_acrylic/flutter_acrylic.dart' as acrylic;
import 'package:window_manager/window_manager.dart';

import 'core/theme.dart';
import 'network/adb_manager.dart';
import 'network/socket_client.dart';
import 'services/clipboard_sync_service.dart';
import 'services/notification_service.dart';
import 'services/system_tray_manager.dart';
import 'ui/views/main_window.dart';

void main() async {
  // 1. Ensure Flutter bindings are initialized
  WidgetsFlutterBinding.ensureInitialized();

  // 2. Initialize Windows 11 Mica / Acrylic Effect
  if (Platform.isWindows) {
    try {
      await acrylic.Window.initialize();
      await acrylic.Window.setEffect(
        effect: acrylic.WindowEffect.mica,
        dark: true,
      );
    } catch (e) {
      debugPrint('[Window] Acrylic/Mica initialization note: $e');
    }
  }

  // 3. Initialize Window Manager for desktop window frame
  try {
    await windowManager.ensureInitialized();
    const WindowOptions windowOptions = WindowOptions(
      size: Size(1020, 680),
      minimumSize: Size(820, 560),
      center: true,
      backgroundColor: Colors.transparent,
      skipTaskbar: false,
      title: 'Google Pixel 10 Mirror',
      titleBarStyle: TitleBarStyle.normal,
    );

    await windowManager.waitUntilReadyToShow(windowOptions, () async {
      await windowManager.show();
      await windowManager.focus();
    });
  } catch (e) {
    debugPrint('[Window] Window manager initialization note: $e');
  }

  // 4. Initialize Core V1 Subsystems
  final SocketClient socketClient = SocketClient();
  final AdbManager adbManager = AdbManager();
  final NativeNotificationService notificationService = NativeNotificationService(
    socketClient: socketClient,
  );
  final ClipboardSyncService clipboardSync = ClipboardSyncService(
    socketClient: socketClient,
  );
  final SystemTrayManager systemTrayManager = SystemTrayManager();

  // 5. Mount widget tree
  runApp(PixelMirrorApp(
    socketClient: socketClient,
    adbManager: adbManager,
    notificationService: notificationService,
    clipboardSync: clipboardSync,
  ));

  // 6. Asynchronous initialization of tray & background services
  WidgetsBinding.instance.addPostFrameCallback((_) async {
    await systemTrayManager.initSystemTray(
      onShowDashboard: () => systemTrayManager.showWindow(),
      onSyncClipboardNow: () => clipboardSync.pushCurrentClipboardNow(),
      onDisconnect: () => socketClient.disconnect(manual: true),
    );

    try {
      await notificationService.init();
    } catch (e) {
      debugPrint('[NotificationService] Post-frame initialization note: $e');
    }

    try {
      clipboardSync.startSync();
    } catch (e) {
      debugPrint('[ClipboardSync] Post-frame start note: $e');
    }
  });
}

class PixelMirrorApp extends StatefulWidget {
  final SocketClient socketClient;
  final AdbManager adbManager;
  final NativeNotificationService notificationService;
  final ClipboardSyncService clipboardSync;

  const PixelMirrorApp({
    super.key,
    required this.socketClient,
    required this.adbManager,
    required this.notificationService,
    required this.clipboardSync,
  });

  @override
  State<PixelMirrorApp> createState() => _PixelMirrorAppState();
}

class _PixelMirrorAppState extends State<PixelMirrorApp> {
  ThemeMode _themeMode = ThemeMode.dark;
  bool _isMicaEnabled = true;

  void _onThemeModeChanged(ThemeMode mode) {
    setState(() => _themeMode = mode);
    if (Platform.isWindows && _isMicaEnabled) {
      acrylic.Window.setEffect(
        effect: acrylic.WindowEffect.mica,
        dark: mode == ThemeMode.dark,
      );
    }
  }

  void _onMicaChanged(bool enabled) {
    setState(() => _isMicaEnabled = enabled);
    if (Platform.isWindows) {
      if (enabled) {
        acrylic.Window.setEffect(
          effect: acrylic.WindowEffect.mica,
          dark: _themeMode == ThemeMode.dark,
        );
      } else {
        acrylic.Window.setEffect(effect: acrylic.WindowEffect.disabled);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return FluentApp(
      title: 'Google Pixel 10 Mirror',
      themeMode: _themeMode,
      debugShowCheckedModeBanner: false,
      color: Colors.blue,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      home: MainWindow(
        socketClient: widget.socketClient,
        adbManager: widget.adbManager,
        notificationService: widget.notificationService,
        clipboardSync: widget.clipboardSync,
        currentThemeMode: _themeMode,
        onThemeModeChanged: _onThemeModeChanged,
        isMicaEnabled: _isMicaEnabled,
        onMicaChanged: _onMicaChanged,
      ),
    );
  }
}
