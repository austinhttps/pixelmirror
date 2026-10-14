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

/// 3.1 Plaintext Accessibility UI Tree Payload (FLAG_SECURE DRM Workaround)
class NodeBounds {
  final int top;
  final int left;
  final int bottom;
  final int right;

  NodeBounds({
    required this.top,
    required this.left,
    required this.bottom,
    required this.right,
  });

  int get width => (right - left).clamp(0, 4000);
  int get height => (bottom - top).clamp(0, 4000);

  Map<String, dynamic> toJson() => {
        'top': top,
        'left': left,
        'bottom': bottom,
        'right': right,
      };

  factory NodeBounds.fromJson(Map<String, dynamic> json) {
    return NodeBounds(
      top: json['top'] as int? ?? 0,
      left: json['left'] as int? ?? 0,
      bottom: json['bottom'] as int? ?? 0,
      right: json['right'] as int? ?? 0,
    );
  }
}

class AccessibilityNodeMap {
  final String nodeId;
  final String className;
  final String text;
  final bool isClickable;
  final NodeBounds bounds;

  AccessibilityNodeMap({
    required this.nodeId,
    required this.className,
    required this.text,
    required this.isClickable,
    required this.bounds,
  });

  Map<String, dynamic> toJson() => {
        'node_id': nodeId,
        'class_name': className,
        'text': text,
        'is_clickable': isClickable,
        'bounds': bounds.toJson(),
      };

  factory AccessibilityNodeMap.fromJson(Map<String, dynamic> json) {
    return AccessibilityNodeMap(
      nodeId: json['node_id'] as String? ?? '',
      className: json['class_name'] as String? ?? '',
      text: json['text'] as String? ?? '',
      isClickable: json['is_clickable'] as bool? ?? false,
      bounds: NodeBounds.fromJson(json['bounds'] as Map<String, dynamic>? ?? {}),
    );
  }
}

class SecureWindowMapData {
  final String packageName;
  final List<AccessibilityNodeMap> nodes;

  SecureWindowMapData({
    required this.packageName,
    required this.nodes,
  });

  factory SecureWindowMapData.fromJson(Map<String, dynamic> json) {
    final rawNodes = json['nodes'] as List<dynamic>? ?? [];
    final parsedNodes = rawNodes
        .map((n) => AccessibilityNodeMap.fromJson(n as Map<String, dynamic>))
        .toList();

    return SecureWindowMapData(
      packageName: json['package_name'] as String? ?? '',
      nodes: parsedNodes,
    );
  }
}

/// 3.2 Dynamic Action / Touch Mapping Payload
class RemoteInputActionData {
  final String actionType; // "CLICK_COORDINATE", "GLOBAL_BACK", etc.
  final int targetX;
  final int targetY;

  RemoteInputActionData({
    this.actionType = ProtocolConstants.actionClickCoordinate,
    required this.targetX,
    required this.targetY,
  });

  Map<String, dynamic> toJson() => {
        'action_type': actionType,
        'target_x': targetX,
        'target_y': targetY,
      };

  EventPacket toEventPacket() {
    return EventPacket(
      eventType: ProtocolConstants.eventRemoteInputAction,
      data: toJson(),
    );
  }
}

/// 4.1 Phone Mode Toggle Payload
class SystemModeSyncData {
  final String modeType; // "DO_NOT_DISTURB", "RINGER_MODE"
  final bool isEnabled;

  SystemModeSyncData({
    required this.modeType,
    required this.isEnabled,
  });

  Map<String, dynamic> toJson() => {
        'mode_type': modeType,
        'is_enabled': isEnabled,
      };

  EventPacket toEventPacket() {
    return EventPacket(
      eventType: ProtocolConstants.eventSystemModeSync,
      data: toJson(),
    );
  }

  factory SystemModeSyncData.fromJson(Map<String, dynamic> json) {
    return SystemModeSyncData(
      modeType: json['mode_type'] as String? ?? ProtocolConstants.modeDoNotDisturb,
      isEnabled: json['is_enabled'] as bool? ?? false,
    );
  }
}

/// 4.2 Hotspot Trigger Request
class HotspotRequestData {
  final String action; // "LAUNCH_TETHER_SETTINGS"

  HotspotRequestData({
    this.action = ProtocolConstants.actionLaunchTetherSettings,
  });

  Map<String, dynamic> toJson() => {
        'action': action,
      };

  EventPacket toEventPacket() {
    return EventPacket(
      eventType: ProtocolConstants.eventHotspotRequest,
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

/// Smart File Drop & Quick Share Payload
class FileDropData {
  final String filename;
  final String mimeType;
  final String fileBase64;
  final int targetX;
  final int targetY;
  final bool isCanvasPaste;

  FileDropData({
    required this.filename,
    this.mimeType = 'application/octet-stream',
    required this.fileBase64,
    this.targetX = -1,
    this.targetY = -1,
    this.isCanvasPaste = true,
  });

  Map<String, dynamic> toJson() => {
        'filename': filename,
        'mime_type': mimeType,
        'file_base64': fileBase64,
        'target_x': targetX,
        'target_y': targetY,
        'is_canvas_paste': isCanvasPaste,
      };

  EventPacket toEventPacket() {
    return EventPacket(
      eventType: ProtocolConstants.eventFileDrop,
      data: toJson(),
    );
  }
}

/// Installed App Model for App Drawer
class AppPackageModel {
  final String packageName;
  final String label;

  AppPackageModel({
    required this.packageName,
    required this.label,
  });
}
