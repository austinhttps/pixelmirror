// lib/ui/views/main_window.dart
import 'package:fluent_ui/fluent_ui.dart';
import 'package:window_manager/window_manager.dart';
import '../../core/constants.dart';
import '../../models/contract_models.dart';
import '../../network/adb_manager.dart';
import '../../network/mdns_discovery.dart';
import '../../network/socket_client.dart';
import '../../services/clipboard_sync_service.dart';
import '../../services/mode_sync_service.dart';
import '../../services/notification_service.dart';
import '../widgets/quick_reply_dialog.dart';
import '../widgets/status_badge.dart';
import 'app_drawer_panel.dart';
import 'dashboard_controls.dart';
import 'mirror_viewport.dart';
import 'quick_share_box.dart';
import 'settings_view.dart';

class MainWindow extends StatefulWidget {
  final SocketClient socketClient;
  final AdbManager adbManager;
  final MdnsDiscoveryManager mdnsDiscovery;
  final NativeNotificationService notificationService;
  final ClipboardSyncService clipboardSync;
  final ModeSyncService modeSyncService;
  final ThemeMode currentThemeMode;
  final Function(ThemeMode) onThemeModeChanged;
  final bool isMicaEnabled;
  final Function(bool) onMicaChanged;

  const MainWindow({
    super.key,
    required this.socketClient,
    required this.adbManager,
    required this.mdnsDiscovery,
    required this.notificationService,
    required this.clipboardSync,
    required this.modeSyncService,
    required this.currentThemeMode,
    required this.onThemeModeChanged,
    required this.isMicaEnabled,
    required this.onMicaChanged,
  });

  @override
  State<MainWindow> createState() => _MainWindowState();
}

class _MainWindowState extends State<MainWindow> with WindowListener {
  int _selectedPaneIndex = 0;

  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);

    // Listen for in-app notifications and trigger quick reply modal if user chooses
    widget.notificationService.inAppNotifications.listen((notif) {
      if (!mounted) return;
      _showInAppNotificationBanner(notif);
    });
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    super.dispose();
  }

  void _showInAppNotificationBanner(NotificationEnqueueData notif) {
    displayInfoBar(
      context,
      builder: (context, close) {
        return InfoBar(
          title: Text('${notif.appLabel}: ${notif.title}'),
          content: Text(notif.body),
          severity: InfoBarSeverity.info,
          action: Button(
            child: const Text('Quick Reply'),
            onPressed: () {
              close();
              showDialog(
                context: context,
                builder: (context) => QuickReplyDialog(
                  notification: notif,
                  onSend: (replyText) {
                    widget.notificationService.submitReply(
                      notificationId: notif.notificationId,
                      packageName: notif.packageName,
                      replyText: replyText,
                    );
                  },
                ),
              );
            },
          ),
          onClose: close,
        );
      },
    );
  }

  Future<void> _handleUsbConnect() async {
    // 1. Setup USB port forwarding: adb forward tcp:8080 tcp:8080
    final bool forwarded = await widget.adbManager.setupUsbTunnel();
    if (!forwarded) {
      if (mounted) {
        displayInfoBar(
          context,
          builder: (context, close) => InfoBar(
            title: const Text('ADB USB Forward Failed'),
            content: const Text('Ensure USB debugging is enabled on Pixel 10.'),
            severity: InfoBarSeverity.error,
            onClose: close,
          ),
        );
      }
      return;
    }

    // 2. Connect to local forwarded port 8080 and perform 256-bit AES-GCM handshake
    final bool ok = await widget.socketClient.connect(
      host: ProtocolConstants.loopbackHost,
      port: ProtocolConstants.defaultSocketPort,
    );

    if (mounted) {
      displayInfoBar(
        context,
        builder: (context, close) => InfoBar(
          title: Text(ok ? 'USB Pairing Succeeded' : 'Pairing Failed'),
          content: Text(ok ? '256-bit AES-GCM key securely established with Pixel 10.' : 'Device rejected handshake.'),
          severity: ok ? InfoBarSeverity.success : InfoBarSeverity.error,
          onClose: close,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return NavigationView(
      appBar: NavigationAppBar(
        title: const DragToMoveArea(
          child: Align(
            alignment: AlignmentDirectional.centerStart,
            child: Text(
              'Google Pixel 10 Mirror',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
            ),
          ),
        ),
        actions: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            StreamBuilder<ConnectionStateEnum>(
              stream: widget.socketClient.stateStream,
              initialData: widget.socketClient.state,
              builder: (context, snapshot) {
                return StatusBadge(
                  state: snapshot.data ?? ConnectionStateEnum.disconnected,
                  deviceName: widget.socketClient.connectedDeviceName,
                );
              },
            ),
            const SizedBox(width: 12),
            IconButton(
              icon: const Icon(FluentIcons.usb, size: 16),
              onPressed: _handleUsbConnect,
            ),
            const SizedBox(width: 8),
          ],
        ),
      ),
      pane: NavigationPane(
        selected: _selectedPaneIndex,
        onChanged: (index) => setState(() => _selectedPaneIndex = index),
        displayMode: PaneDisplayMode.compact,
        items: [
          PaneItem(
            icon: const Icon(FluentIcons.cell_phone),
            title: const Text('Mirror Viewport'),
            body: MirrorViewport(socketClient: widget.socketClient),
          ),
          PaneItem(
            icon: const Icon(FluentIcons.apps_content),
            title: const Text('App Drawer'),
            body: AppDrawerPanel(adbManager: widget.adbManager),
          ),
          PaneItem(
            icon: const Icon(FluentIcons.share),
            title: const Text('Quick Share'),
            body: QuickShareBox(socketClient: widget.socketClient),
          ),
          PaneItem(
            icon: const Icon(FluentIcons.view_dashboard),
            title: const Text('Dashboard & Hardware'),
            body: DashboardControls(
              socketClient: widget.socketClient,
              adbManager: widget.adbManager,
              mdnsDiscovery: widget.mdnsDiscovery,
              modeSyncService: widget.modeSyncService,
              onConnectUsb: _handleUsbConnect,
            ),
          ),
        ],
        footerItems: [
          PaneItemSeparator(),
          PaneItem(
            icon: const Icon(FluentIcons.settings),
            title: const Text('Settings'),
            body: SettingsView(
              socketClient: widget.socketClient,
              currentThemeMode: widget.currentThemeMode,
              onThemeModeChanged: widget.onThemeModeChanged,
              isMicaEnabled: widget.isMicaEnabled,
              onMicaChanged: widget.onMicaChanged,
            ),
          ),
        ],
      ),
    );
  }
}
