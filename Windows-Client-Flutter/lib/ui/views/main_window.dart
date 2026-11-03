// lib/ui/views/main_window.dart
import 'dart:async';
import 'dart:convert';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/services.dart';
import '../../core/constants.dart';
import '../../models/contract_models.dart';
import '../../network/adb_manager.dart';
import '../../network/socket_client.dart';
import '../../services/clipboard_sync_service.dart';
import '../../services/notification_service.dart';
import '../widgets/status_badge.dart';

class MainWindow extends StatefulWidget {
  final SocketClient socketClient;
  final AdbManager adbManager;
  final NativeNotificationService notificationService;
  final ClipboardSyncService clipboardSync;
  final ThemeMode currentThemeMode;
  final Function(ThemeMode) onThemeModeChanged;
  final bool isMicaEnabled;
  final Function(bool) onMicaChanged;

  const MainWindow({
    super.key,
    required this.socketClient,
    required this.adbManager,
    required this.notificationService,
    required this.clipboardSync,
    required this.currentThemeMode,
    required this.onThemeModeChanged,
    required this.isMicaEnabled,
    required this.onMicaChanged,
  });

  @override
  State<MainWindow> createState() => _MainWindowState();
}

class _MainWindowState extends State<MainWindow> {
  final Map<String, TextEditingController> _replyControllers = {};
  StreamSubscription? _notifSub;
  StreamSubscription? _clipSub;
  String _lastSyncedSnippet = '';
  bool _autoSync = true;
  bool _isConnecting = false;

  @override
  void initState() {
    super.initState();
    _lastSyncedSnippet = widget.clipboardSync.lastSyncedText;
    _autoSync = widget.clipboardSync.isAutoSyncEnabled;

    // Listen to real-time inbound notification stream
    _notifSub = widget.notificationService.inAppNotifications.listen((notif) {
      if (!mounted) return;
      setState(() {});
    });

    // Listen to clipboard sync updates
    _clipSub = widget.clipboardSync.onClipboardSynced.listen((text) {
      if (!mounted) return;
      setState(() {
        _lastSyncedSnippet = text;
      });
    });
  }

  @override
  void dispose() {
    _notifSub?.cancel();
    _clipSub?.cancel();
    for (final controller in _replyControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  TextEditingController _getControllerFor(int id, String pkg) {
    final key = '${pkg}_$id';
    return _replyControllers.putIfAbsent(key, () => TextEditingController());
  }

  Future<void> _handleConnect() async {
    setState(() => _isConnecting = true);

    try {
      // 1. Setup USB port forwarding: adb forward tcp:8080 tcp:8080
      final bool forwarded = await widget.adbManager.setupUsbTunnel();
      if (!forwarded) {
        debugPrint('[Connection] ADB USB forwarding not available or failed; attempting direct TCP...');
      }

      // 2. Connect to local port 8080 and perform 256-bit AES-GCM handshake
      final bool ok = await widget.socketClient.connect(
        host: ProtocolConstants.loopbackHost,
        port: ProtocolConstants.defaultSocketPort,
      );

      if (mounted) {
        displayInfoBar(
          context,
          builder: (context, close) => InfoBar(
            title: Text(ok ? 'Pixel 10 Connected' : 'Connection Failed'),
            content: Text(ok
                ? '256-bit AES-GCM encrypted session securely active with Pixel 10.'
                : 'Could not connect. Ensure SocketServerService is running on port 8080.'),
            severity: ok ? InfoBarSeverity.success : InfoBarSeverity.error,
            onClose: close,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isConnecting = false);
    }
  }

  void _handleDisconnect() {
    widget.socketClient.disconnect(manual: true);
    if (mounted) {
      displayInfoBar(
        context,
        builder: (context, close) => InfoBar(
          title: const Text('Disconnected'),
          content: const Text('Session terminated. Auto-reconnect paused.'),
          severity: InfoBarSeverity.info,
          onClose: close,
        ),
      );
    }
  }

  Future<void> _handlePushClipboard() async {
    final bool ok = await widget.clipboardSync.pushCurrentClipboardNow();
    if (mounted) {
      displayInfoBar(
        context,
        builder: (context, close) => InfoBar(
          title: Text(ok ? 'PC Clipboard Pushed' : 'Nothing to Push'),
          content: Text(ok
              ? 'PC clipboard synced down to Pixel 10.'
              : 'PC clipboard is empty or could not be read.'),
          severity: ok ? InfoBarSeverity.success : InfoBarSeverity.warning,
          onClose: close,
        ),
      );
    }
  }

  Future<void> _submitInlineReply(NotificationEnqueueData notif) async {
    final controller = _getControllerFor(notif.notificationId, notif.packageName);
    final replyText = controller.text.trim();
    if (replyText.isEmpty) return;

    await widget.notificationService.submitReply(
      notificationId: notif.notificationId,
      packageName: notif.packageName,
      replyText: replyText,
    );

    controller.clear();

    if (mounted) {
      displayInfoBar(
        context,
        builder: (context, close) => InfoBar(
          title: Text('Replied to ${notif.appLabel}'),
          content: Text('"$replyText" dispatched to Pixel 10.'),
          severity: InfoBarSeverity.success,
          onClose: close,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: FluentTheme.of(context).scaffoldBackgroundColor,
      child: Column(
        children: [
          _buildTopBar(),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // CARD 1: Real-Time Notification Stream
                  Expanded(
                    flex: 6,
                    child: _buildNotificationStreamCard(),
                  ),
                  const SizedBox(width: 16),
                  // CARD 2: Clipboard Sync Hub
                  Expanded(
                    flex: 5,
                    child: _buildClipboardSyncCard(),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTopBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 10.0),
      decoration: BoxDecoration(
        color: FluentTheme.of(context).cardColor,
        border: Border(
          bottom: BorderSide(
            color: FluentTheme.of(context).resources.dividerStrokeColorDefault,
            width: 1.0,
          ),
        ),
      ),
      child: Row(
        children: [
          // Device branding
          const Icon(FluentIcons.cell_phone, size: 20),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Google Pixel 10',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
              ),
              Text(
                'Pixel Mirror V1 Core',
                style: TextStyle(
                  fontSize: 11,
                  color: FluentTheme.of(context).resources.textFillColorSecondary,
                ),
              ),
            ],
          ),
          const SizedBox(width: 16),
          // Connection status badge
          StreamBuilder<ConnectionStateEnum>(
            stream: widget.socketClient.stateStream,
            initialData: widget.socketClient.state,
            builder: (context, snapshot) {
              final state = snapshot.data ?? ConnectionStateEnum.disconnected;
              return StatusBadge(
                state: state,
                deviceName: widget.socketClient.connectedDeviceName,
              );
            },
          ),
          const Spacer(),
          // Action Buttons
          StreamBuilder<ConnectionStateEnum>(
            stream: widget.socketClient.stateStream,
            initialData: widget.socketClient.state,
            builder: (context, snapshot) {
              final isConnected = snapshot.data == ConnectionStateEnum.authorized;
              if (isConnected) {
                return Button(
                  onPressed: _handleDisconnect,
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(FluentIcons.plug_disconnected, size: 14),
                      SizedBox(width: 6),
                      Text('Disconnect'),
                    ],
                  ),
                );
              }
              return FilledButton(
                onPressed: _isConnecting ? null : _handleConnect,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_isConnecting)
                      const SizedBox(width: 14, height: 14, child: ProgressRing(strokeWidth: 2))
                    else
                      const Icon(FluentIcons.usb, size: 14),
                    const SizedBox(width: 6),
                    Text(_isConnecting ? 'Connecting...' : 'Connect USB / Wi-Fi'),
                  ],
                ),
              );
            },
          ),
          const SizedBox(width: 10),
          // Theme Toggle
          IconButton(
            icon: Icon(
              widget.currentThemeMode == ThemeMode.dark
                  ? FluentIcons.sunny
                  : FluentIcons.clear_night,
              size: 16,
            ),
            onPressed: () {
              final next = widget.currentThemeMode == ThemeMode.dark
                  ? ThemeMode.light
                  : ThemeMode.dark;
              widget.onThemeModeChanged(next);
            },
          ),
        ],
      ),
    );
  }

  // CARD 1: Real-Time Notification Stream
  Widget _buildNotificationStreamCard() {
    final notifications = widget.notificationService.recentNotifications;

    return Card(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              const Icon(FluentIcons.action_center, size: 18),
              const SizedBox(width: 8),
              const Text(
                'Notification Stream',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.blue.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '${notifications.length}',
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.blue),
                ),
              ),
              const Spacer(),
              if (notifications.isNotEmpty)
                Button(
                  child: const Text('Clear All'),
                  onPressed: () {
                    setState(() {
                      widget.notificationService.clearNotifications();
                    });
                  },
                ),
            ],
          ),
          const SizedBox(height: 12),
          const Divider(),
          const SizedBox(height: 12),
          // Notification List or Empty State
          Expanded(
            child: notifications.isEmpty
                ? _buildNotificationEmptyState()
                : ListView.separated(
                    itemCount: notifications.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 12),
                    itemBuilder: (context, index) {
                      final notif = notifications[index];
                      return _buildNotificationItem(notif);
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildNotificationEmptyState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            FluentIcons.action_center,
            size: 48,
            color: FluentTheme.of(context).resources.textFillColorSecondary,
          ),
          const SizedBox(height: 12),
          const Text(
            'No notifications yet',
            style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
          ),
          const SizedBox(height: 6),
          Text(
            'Incoming phone notifications will appear here in real time.\nYou can quick-reply directly to any alert.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12,
              color: FluentTheme.of(context).resources.textFillColorSecondary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNotificationItem(NotificationEnqueueData notif) {
    final controller = _getControllerFor(notif.notificationId, notif.packageName);

    Widget iconWidget;
    if (notif.iconBase64.isNotEmpty) {
      try {
        final bytes = base64Decode(notif.iconBase64);
        iconWidget = ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: Image.memory(
            bytes,
            width: 32,
            height: 32,
            errorBuilder: (_, __, ___) => const Icon(FluentIcons.cell_phone, size: 24),
          ),
        );
      } catch (_) {
        iconWidget = const Icon(FluentIcons.cell_phone, size: 24);
      }
    } else {
      iconWidget = const Icon(FluentIcons.cell_phone, size: 24);
    }

    return Container(
      padding: const EdgeInsets.all(12.0),
      decoration: BoxDecoration(
        color: FluentTheme.of(context).resources.cardBackgroundFillColorDefault,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: FluentTheme.of(context).resources.cardStrokeColorDefault,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              iconWidget,
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          notif.appLabel,
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                        ),
                        const Spacer(),
                        Text(
                          'Just now',
                          style: TextStyle(
                            fontSize: 10,
                            color: FluentTheme.of(context).resources.textFillColorSecondary,
                          ),
                        ),
                      ],
                    ),
                    if (notif.title.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        notif.title,
                        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                      ),
                    ],
                    if (notif.body.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        notif.body,
                        style: TextStyle(
                          fontSize: 12,
                          color: FluentTheme.of(context).resources.textFillColorSecondary,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          // Inline Quick Reply Row
          Row(
            children: [
              Expanded(
                child: TextBox(
                  controller: controller,
                  placeholder: 'Type a quick reply to phone...',
                  onSubmitted: (_) => _submitInlineReply(notif),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: () => _submitInlineReply(notif),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(FluentIcons.send, size: 12),
                    SizedBox(width: 4),
                    Text('Reply'),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // CARD 2: Clipboard Sync Hub
  Widget _buildClipboardSyncCard() {
    return Card(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          const Row(
            children: [
              Icon(FluentIcons.clipboard_list, size: 18),
              SizedBox(width: 8),
              Text(
                'Clipboard Sync Hub',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Divider(),
          const SizedBox(height: 16),

          // Status Indicator
          StreamBuilder<ConnectionStateEnum>(
            stream: widget.socketClient.stateStream,
            initialData: widget.socketClient.state,
            builder: (context, snapshot) {
              final isConnected = snapshot.data == ConnectionStateEnum.authorized;

              return Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: isConnected
                      ? Colors.green.withValues(alpha: 0.12)
                      : Colors.orange.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: isConnected
                        ? Colors.green.withValues(alpha: 0.3)
                        : Colors.orange.withValues(alpha: 0.3),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      isConnected ? FluentIcons.completed : FluentIcons.sync,
                      color: isConnected ? Colors.green : Colors.orange,
                      size: 20,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            isConnected
                                ? 'Clipboard in sync with Pixel 10'
                                : 'Awaiting connection to sync clipboard',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                              color: isConnected ? Colors.green : Colors.orange,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            isConnected
                                ? '256-bit AES-GCM bidirectional tunnel active.'
                                : 'Connect USB or Wi-Fi to establish secure clipboard bridge.',
                            style: TextStyle(
                              fontSize: 11,
                              color: FluentTheme.of(context).resources.textFillColorSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            },
          ),

          const SizedBox(height: 20),

          // Last Synced Snippet Preview
          Text(
            'LAST SYNCED CONTENT',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.8,
              color: FluentTheme.of(context).resources.textFillColorSecondary,
            ),
          ),
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            constraints: const BoxConstraints(minHeight: 110, maxHeight: 180),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: FluentTheme.of(context).resources.cardBackgroundFillColorDefault,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: FluentTheme.of(context).resources.cardStrokeColorDefault,
              ),
            ),
            child: SingleChildScrollView(
              child: SelectableText(
                _lastSyncedSnippet.isNotEmpty
                    ? _lastSyncedSnippet
                    : 'No clipboard snippet synced yet.\nCopy text on your Pixel 10 or PC to test synchronization.',
                style: TextStyle(
                  fontSize: 12,
                  fontFamily: _lastSyncedSnippet.isNotEmpty ? 'Consolas' : null,
                  color: _lastSyncedSnippet.isNotEmpty
                      ? FluentTheme.of(context).resources.textFillColorPrimary
                      : FluentTheme.of(context).resources.textFillColorSecondary,
                ),
              ),
            ),
          ),

          if (_lastSyncedSnippet.isNotEmpty) ...[
            const SizedBox(height: 6),
            Align(
              alignment: Alignment.centerRight,
              child: Button(
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(FluentIcons.copy, size: 12),
                    SizedBox(width: 4),
                    Text('Copy to PC Clipboard'),
                  ],
                ),
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: _lastSyncedSnippet));
                  displayInfoBar(
                    context,
                    builder: (context, close) => InfoBar(
                      title: const Text('Copied'),
                      content: const Text('Snippet copied to PC clipboard.'),
                      severity: InfoBarSeverity.success,
                      onClose: close,
                    ),
                  );
                },
              ),
            ),
          ],

          const Spacer(),

          // Actions & Controls
          FilledButton(
            onPressed: _handlePushClipboard,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(FluentIcons.upload, size: 14),
                  SizedBox(width: 8),
                  Text('Push PC Clipboard Now'),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              ToggleSwitch(
                checked: _autoSync,
                onChanged: (val) {
                  setState(() => _autoSync = val);
                  widget.clipboardSync.setAutoSync(val);
                },
              ),
              const SizedBox(width: 10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Automatic Background Sync',
                    style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                  ),
                  Text(
                    'Sync Windows clipboard copies with Pixel 10 silently',
                    style: TextStyle(
                      fontSize: 11,
                      color: FluentTheme.of(context).resources.textFillColorSecondary,
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}
