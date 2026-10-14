// lib/main.dart
import 'dart:io';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_acrylic/flutter_acrylic.dart' as acrylic;
import 'package:window_manager/window_manager.dart';

import 'core/constants.dart';
import 'core/theme.dart';
import 'network/adb_manager.dart';
import 'network/mdns_discovery.dart';
import 'network/socket_client.dart';
import 'services/clipboard_sync_service.dart';
import 'services/mode_sync_service.dart';
import 'services/notification_service.dart';
import 'services/system_tray_manager.dart';
import 'ui/views/main_window.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 1. Initialize Windows 11 Mica / Acrylic Effect
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

  // 2. Initialize Window Manager for desktop window controls & tray support
  try {
    await windowManager.ensureInitialized();
    const WindowOptions windowOptions = WindowOptions(
      size: Size(1280, 840),
      minimumSize: Size(960, 680),
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

  // 3. Initialize Core Subsystems
  final SocketClient socketClient = SocketClient();
  final AdbManager adbManager = AdbManager();
  final MdnsDiscoveryManager mdnsDiscovery = MdnsDiscoveryManager();
  final NativeNotificationService notificationService = NativeNotificationService(
    socketClient: socketClient,
  );
  final ClipboardSyncService clipboardSync = ClipboardSyncService(
    socketClient: socketClient,
  );
  final ModeSyncService modeSyncService = ModeSyncService(
    socketClient: socketClient,
  );

  // Start background services
  await notificationService.init();
  clipboardSync.startSync();
  modeSyncService.init();

  // Start asynchronous mDNS Wireless Debugging discovery
  await mdnsDiscovery.startDiscovery();

  // 4. Initialize System Tray Manager (Section 1.2)
  final SystemTrayManager trayManager = SystemTrayManager(
    socketClient: socketClient,
    adbManager: adbManager,
    onToggleConnection: () async {
      if (socketClient.isAuthorized) {
        socketClient.disconnect();
      } else {
        // Toggle connection: attempt forward + connect
        await adbManager.setupUsbTunnel();
        await socketClient.connect();
      }
    },
  );
  await trayManager.init();

  runApp(PixelMirrorApp(
    socketClient: socketClient,
    adbManager: adbManager,
    mdnsDiscovery: mdnsDiscovery,
    notificationService: notificationService,
    clipboardSync: clipboardSync,
    modeSyncService: modeSyncService,
  ));
}

class PixelMirrorApp extends StatefulWidget {
  final SocketClient socketClient;
  final AdbManager adbManager;
  final MdnsDiscoveryManager mdnsDiscovery;
  final NativeNotificationService notificationService;
  final ClipboardSyncService clipboardSync;
  final ModeSyncService modeSyncService;

  const PixelMirrorApp({
    super.key,
    required this.socketClient,
    required this.adbManager,
    required this.mdnsDiscovery,
    required this.notificationService,
    required this.clipboardSync,
    required this.modeSyncService,
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
        mdnsDiscovery: widget.mdnsDiscovery,
        notificationService: widget.notificationService,
        clipboardSync: widget.clipboardSync,
        modeSyncService: widget.modeSyncService,
        currentThemeMode: _themeMode,
        onThemeModeChanged: _onThemeModeChanged,
        isMicaEnabled: _isMicaEnabled,
        onMicaChanged: _onMicaChanged,
      ),
    );
  }
}
