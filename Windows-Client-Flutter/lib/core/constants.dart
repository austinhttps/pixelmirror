// lib/core/constants.dart
/// Core system constants and protocol identifiers adhering to API_CONTRACT.md.

class ProtocolConstants {
  // Protocol Version
  static const String protocolVersion = "1.0.0";

  // Network & Ports
  static const int defaultSocketPort = 8080;
  static const String loopbackHost = "127.0.0.1";
  static const String mdnsAdbServiceType = "_adb-tls-connect._tcp";

  // Handshake Types
  static const String typeHandshakeInit = "HANDSHAKE_INIT";
  static const String typeHandshakeResponse = "HANDSHAKE_RESPONSE";
  static const String statusAuthorized = "AUTHORIZED";
  static const String statusUnauthorized = "UNAUTHORIZED";

  // Event Types
  static const String eventNotificationEnqueue = "NOTIFICATION_ENQUEUE";
  static const String eventNotificationReply = "NOTIFICATION_REPLY";
  static const String eventSecureWindowMap = "SECURE_WINDOW_MAP";
  static const String eventRemoteInputAction = "REMOTE_INPUT_ACTION";
  static const String eventSystemModeSync = "SYSTEM_MODE_SYNC";
  static const String eventHotspotRequest = "HOTSPOT_REQUEST";
  static const String eventClipboardSync = "CLIPBOARD_SYNC";
  static const String eventFileDrop = "FILE_DROP";

  // Input Action Types
  static const String actionClickCoordinate = "CLICK_COORDINATE";
  static const String actionGlobalBack = "GLOBAL_BACK";
  static const String actionGlobalHome = "GLOBAL_HOME";
  static const String actionGlobalRecents = "GLOBAL_RECENTS";

  // Mode Sync Types
  static const String modeDoNotDisturb = "DO_NOT_DISTURB";
  static const String modeRingerMode = "RINGER_MODE";

  // Hotspot Actions
  static const String actionLaunchTetherSettings = "LAUNCH_TETHER_SETTINGS";

  // Default Device Name
  static const String defaultDeviceName = "Google Pixel 10";
}

enum ConnectionStateEnum {
  disconnected,
  discovering,
  connecting,
  handshaking,
  authorized,
  error
}
