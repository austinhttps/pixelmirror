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

    // Avoid duplicates of the same notification ID
    _recentNotifications.removeWhere((item) =>
        item.notificationId == data.notificationId && item.packageName == data.packageName);

    _recentNotifications.insert(0, data);
    if (_recentNotifications.length > 50) {
      _recentNotifications.removeLast();
    }
    _inAppNotificationStream.add(data);

    // Show native Windows toast notification
    _showWindowsToast(data);
  }

  void clearNotifications() {
    _recentNotifications.clear();
  }

  void removeNotification(int notificationId, String packageName) {
    _recentNotifications.removeWhere((item) =>
        item.notificationId == notificationId && item.packageName == packageName);
  }

  Future<void> _showWindowsToast(NotificationEnqueueData data) async {
    if (!Platform.isWindows) return;

    try {
      final LocalNotification notification = LocalNotification(
        identifier: '${data.packageName}:::${data.notificationId}',
        title: '${data.appLabel}: ${data.title}',
        body: data.body,
        actions: [
          LocalNotificationAction(text: 'Reply'),
        ],
      );

      notification.onClickAction = (actionIndex) {
        debugPrint('[NotificationService] User clicked notification action on toast: $actionIndex');
        _inAppNotificationStream.add(data);
      };

      notification.onClick = () {
        debugPrint('[NotificationService] User clicked notification toast');
        _inAppNotificationStream.add(data);
      };

      await notification.show();
    } catch (e) {
      debugPrint('[NotificationService] Error showing toast notification: $e');
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
