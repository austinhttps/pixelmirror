// lib/services/notification_service.dart
import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:local_notifier/local_notifier.dart';
import '../models/contract_models.dart';
import '../network/socket_client.dart';

class NativeNotificationService {
  final SocketClient socketClient;
  final List<NotificationEnqueueData> _recentNotifications = [];
  final StreamController<NotificationEnqueueData> _inAppNotificationStream =
      StreamController<NotificationEnqueueData>.broadcast();

  Stream<NotificationEnqueueData> get inAppNotifications => _inAppNotificationStream.stream;
  List<NotificationEnqueueData> get recentNotifications => List.unmodifiable(_recentNotifications);

  StreamSubscription? _sub;

  NativeNotificationService({required this.socketClient});

  Future<void> init() async {
    try {
      await localNotifier.setup(
        appName: 'Pixel 10 Mirror',
        shortcutPolicy: ShortcutPolicy.requireCreate,
      );
    } catch (e) {
      debugPrint('[NotificationService] Error initializing local_notifier: $e');
    }

    _sub = socketClient.onNotification.listen((NotificationEnqueueData data) {
      handleIncomingNotification(data);
    });
  }

  void handleIncomingNotification(NotificationEnqueueData data) {
    debugPrint('[NotificationService] Incoming alert from ${data.appLabel}: ${data.title} - ${data.body}');

    _recentNotifications.insert(0, data);
    if (_recentNotifications.length > 50) {
      _recentNotifications.removeLast();
    }
    _inAppNotificationStream.add(data);

    // Show native Windows 11 toast notification with quick-reply
    _showWindowsToast(data);
  }

  Future<void> _showWindowsToast(NotificationEnqueueData data) async {
    if (!Platform.isWindows) return;

    try {
      // 1. Attempt PowerShell WinRT native Windows 11 interactive toast with inline quick reply
      final bool scriptSuccess = await _showInteractiveWin11ToastWithQuickReply(data);
      if (scriptSuccess) return;

      // 2. Fallback to standard local_notifier toast
      final LocalNotification notification = LocalNotification(
        identifier: '${data.packageName}_${data.notificationId}',
        title: '${data.appLabel}: ${data.title}',
        body: data.body,
        actions: [
          LocalNotificationAction(text: 'Quick Reply'),
        ],
      );

      notification.onClickAction = (actionIndex) {
        debugPrint('[NotificationService] User clicked notification action.');
      };

      await notification.show();
    } catch (e) {
      debugPrint('[NotificationService] Error showing toast notification: $e');
    }
  }

  /// Displays a true native Windows 11 Toast with inline text input using WinRT XML Toast schema.
  Future<bool> _showInteractiveWin11ToastWithQuickReply(NotificationEnqueueData data) async {
    try {
      final String safeTitle = data.title.replaceAll('"', '`"').replaceAll("'", "''");
      final String safeBody = data.body.replaceAll('"', '`"').replaceAll("'", "''");
      final String safeApp = data.appLabel.replaceAll('"', '`"').replaceAll("'", "''");

      // PowerShell script invoking Windows.UI.Notifications WinRT API with input element
      final String psScript = '''
[Windows.UI.Notifications.ToastNotificationManager, Windows.UI.Notifications, ContentType = WindowsRuntime] > \$null
[Windows.Data.Xml.Dom.XmlDocument, Windows.Data.Xml.Dom.XmlDocument, ContentType = WindowsRuntime] > \$null

\$template = @"
<toast>
    <visual>
        <binding template="ToastGeneric">
            <text>$safeApp - $safeTitle</text>
            <text>$safeBody</text>
        </binding>
    </visual>
    <actions>
        <input id="quickReplyText" type="text" placeHolderContent="Type a quick reply to phone..." />
        <action content="Reply" arguments="action=reply&amp;id=${data.notificationId}&amp;pkg=${data.packageName}" activationType="background" />
    </actions>
</toast>
"@

\$xml = New-Object Windows.Data.Xml.Dom.XmlDocument
\$xml.LoadXml(\$template)
\$toast = [Windows.UI.Notifications.ToastNotification]::new(\$xml)
[Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier("Pixel 10 Mirror").Show(\$toast)
''';

      final ProcessResult result = await Process.run('powershell', ['-NoProfile', '-Command', psScript]);
      return result.exitCode == 0;
    } catch (e) {
      debugPrint('[NotificationService] Failed PowerShell WinRT toast: $e');
      return false;
    }
  }

  /// Submits quick-reply response back across the socket conforming to Section 2.2 of API_CONTRACT.md
  Future<void> submitReply({
    required int notificationId,
    required String packageName,
    required String replyText,
  }) async {
    debugPrint('[NotificationService] Submitting NOTIFICATION_REPLY to $packageName [$notificationId]: "$replyText"');
    await socketClient.sendQuickReply(
      notificationId: notificationId,
      packageName: packageName,
      replyText: replyText,
    );
  }

  void dispose() {
    _sub?.cancel();
    _inAppNotificationStream.close();
  }
}
