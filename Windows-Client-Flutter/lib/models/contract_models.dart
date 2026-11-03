// lib/models/contract_models.dart
import 'dart:convert';
import '../core/constants.dart';

/// 1. Handshake Models (Unencrypted initial exchange over USB tunnel)
class HandshakeInit {
  final String type;
  final String version;
  final int timestamp;
  final String secretKeyB64;

  HandshakeInit({
    this.type = ProtocolConstants.typeHandshakeInit,
    this.version = ProtocolConstants.protocolVersion,
    int? timestamp,
    required this.secretKeyB64,
  }) : timestamp = timestamp ?? (DateTime.now().millisecondsSinceEpoch ~/ 1000);

  Map<String, dynamic> toJson() => {
        'type': type,
        'version': version,
        'timestamp': timestamp,
        'payload': {
          'secret_key_b64': secretKeyB64,
        },
      };

  factory HandshakeInit.fromJson(Map<String, dynamic> json) {
    final payload = json['payload'] as Map<String, dynamic>? ?? {};
    return HandshakeInit(
      type: json['type'] as String? ?? ProtocolConstants.typeHandshakeInit,
      version: json['version'] as String? ?? ProtocolConstants.protocolVersion,
      timestamp: json['timestamp'] as int? ?? (DateTime.now().millisecondsSinceEpoch ~/ 1000),
      secretKeyB64: payload['secret_key_b64'] as String? ?? '',
    );
  }
}

class HandshakeResponse {
  final String type;
  final String status; // "AUTHORIZED" or "UNAUTHORIZED"
  final String deviceName;

  HandshakeResponse({
    this.type = ProtocolConstants.typeHandshakeResponse,
    required this.status,
    this.deviceName = ProtocolConstants.defaultDeviceName,
  });

  bool get isAuthorized => status == ProtocolConstants.statusAuthorized;

  Map<String, dynamic> toJson() => {
        'type': type,
        'status': status,
        'device_name': deviceName,
      };

  factory HandshakeResponse.fromJson(Map<String, dynamic> json) {
    return HandshakeResponse(
      type: json['type'] as String? ?? ProtocolConstants.typeHandshakeResponse,
      status: json['status'] as String? ?? ProtocolConstants.statusUnauthorized,
      deviceName: json['device_name'] as String? ?? ProtocolConstants.defaultDeviceName,
    );
  }
}

/// 2. Core Event Data Framing Packet
class EventPacket {
  final String eventType;
  final int timestamp;
  final Map<String, dynamic> data;

  EventPacket({
    required this.eventType,
    int? timestamp,
    required this.data,
  }) : timestamp = timestamp ?? (DateTime.now().millisecondsSinceEpoch ~/ 1000);

  Map<String, dynamic> toJson() => {
        'event_type': eventType,
        'timestamp': timestamp,
        'data': data,
      };

  factory EventPacket.fromJson(Map<String, dynamic> json) {
    return EventPacket(
      eventType: json['event_type'] as String? ?? '',
      timestamp: json['timestamp'] as int? ?? (DateTime.now().millisecondsSinceEpoch ~/ 1000),
      data: json['data'] as Map<String, dynamic>? ?? {},
    );
  }

  String toJsonString() => jsonEncode(toJson());
}

/// 2.1 Interactive Notification Enqueue Payload
class NotificationEnqueueData {
  final int notificationId;
  final String packageName;
  final String appLabel;
  final String title;
  final String body;
  final String iconBase64;

  NotificationEnqueueData({
    required this.notificationId,
    required this.packageName,
    required this.appLabel,
    required this.title,
    required this.body,
    required this.iconBase64,
  });

  factory NotificationEnqueueData.fromJson(Map<String, dynamic> json) {
    return NotificationEnqueueData(
      notificationId: json['notification_id'] as int? ?? 0,
      packageName: json['package_name'] as String? ?? '',
      appLabel: json['app_label'] as String? ?? '',
      title: json['title'] as String? ?? '',
      body: json['body'] as String? ?? '',
      iconBase64: json['icon_base64'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
        'notification_id': notificationId,
        'package_name': packageName,
        'app_label': appLabel,
        'title': title,
        'body': body,
        'icon_base64': iconBase64,
      };

  EventPacket toEventPacket() {
    return EventPacket(
      eventType: ProtocolConstants.eventNotificationEnqueue,
      data: toJson(),
    );
  }
}

/// 2.2 Interactive Quick-Reply Payload
class NotificationReplyData {
  final int notificationId;
  final String packageName;
  final String replyText;

  NotificationReplyData({
    required this.notificationId,
    required this.packageName,
    required this.replyText,
  });

  factory NotificationReplyData.fromJson(Map<String, dynamic> json) {
    return NotificationReplyData(
      notificationId: json['notification_id'] as int? ?? 0,
      packageName: json['package_name'] as String? ?? '',
      replyText: json['reply_text'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
        'notification_id': notificationId,
        'package_name': packageName,
        'reply_text': replyText,
      };

  EventPacket toEventPacket() {
    return EventPacket(
      eventType: ProtocolConstants.eventNotificationReply,
      data: toJson(),
    );
  }
}

/// Clipboard Sync Payload
class ClipboardSyncData {
  final String text;

  ClipboardSyncData({required this.text});

  Map<String, dynamic> toJson() => {
        'text': text,
      };

  EventPacket toEventPacket() {
    return EventPacket(
      eventType: ProtocolConstants.eventClipboardSync,
      data: toJson(),
    );
  }

  factory ClipboardSyncData.fromJson(Map<String, dynamic> json) {
    return ClipboardSyncData(
      text: json['text'] as String? ?? '',
    );
  }
}

