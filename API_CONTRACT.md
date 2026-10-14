# API Contract: WinUI 3 to Android Companion Mirroring Protocol

This document establishes the strict communication data frames over the local TCP socket connection between the Windows Client (C#) and the Android Companion APK (Kotlin). Both AI development agents (Codex and Antigravity) must strictly implement these exact models.

---

## 1. Network Initialization & Cryptographic Handshake

All network messages following the initial setup must be encrypted using **256-bit AES-GCM**. The initial key exchange happens via a physical USB ADB tunnel (`adb forward`).

### 1.1 Initial Key Exchange Payload (Unencrypted, USB Setup Only)

Sent by the WinUI 3 PC client to the Android APK port to establish the shared secret.

```json
{
  "type": "HANDSHAKE_INIT",
  "version": "1.0.0",
  "timestamp": 1792036800,
  "payload": {
    "secret_key_b64": "U01BUlRfTUlSUk9SX0FFU19HQ01fMjU2X0tFWV9TQU1QTEU="
  }
}
```

### 1.2 Handshake Response

Sent by the Android Companion APK back to the WinUI client.

```json
{
  "type": "HANDSHAKE_RESPONSE",
  "status": "AUTHORIZED",
  "device_name": "Google Pixel 10"
}
```

---

## 2. Core Event Data Packets (AES-GCM Encrypted Payloads)

Once authorized, all strings passed across the TCP stream must wrap inside this outer framing structure:

```json
{
  "event_type": "STRING_UPPERCASE_IDENTIFIER",
  "timestamp": 1792036805,
  "data": {}
}
```

### 2.1 Interactive Notification Payload (`NOTIFICATION_ENQUEUE`)

Sent by Android to Windows when an alert arrives.

```json
{
  "event_type": "NOTIFICATION_ENQUEUE",
  "timestamp": 1792036810,
  "data": {
    "notification_id": 4012,
    "package_name": "com.google.android.apps.messaging",
    "app_label": "Messages",
    "title": "John Doe",
    "body": "Hey Austin! Did you finish syncing the GitHub repo?",
    "icon_base64": "iVBORw0KGgoAAAANSUhEUgAAAEAAAABACAYAAACqaXHeAAAABGdBTUEAALGPC/xhBQAA..."
  }
}
```

### 2.2 Interactive Quick-Reply Payload (`NOTIFICATION_REPLY`)

Sent by Windows to Android when you click and submit a quick-reply toast response.

```json
{
  "event_type": "NOTIFICATION_REPLY",
  "timestamp": 1792036815,
  "data": {
    "notification_id": 4012,
    "package_name": "com.google.android.apps.messaging",
    "reply_text": "Yeah, Codex and Antigravity matched up the contract files perfectly!"
  }
}
```

---

## 3. DRM Workaround & Input Event Maps

### 3.1 Plaintext Accessibility UI Tree Payload (`SECURE_WINDOW_MAP`)

Sent by Android to Windows automatically when a `FLAG_SECURE` window is entered.

```json
{
  "event_type": "SECURE_WINDOW_MAP",
  "timestamp": 1792036850,
  "data": {
    "package_name": "com.target.banking.app",
    "nodes": [
      {
        "node_id": "btn_submit_login",
        "class_name": "android.widget.Button",
        "text": "Sign In",
        "is_clickable": true,
        "bounds": {
          "top": 1250,
          "left": 100,
          "bottom": 1370,
          "right": 980
        }
      },
      {
        "node_id": "txt_username_entry",
        "class_name": "android.widget.EditText",
        "text": "AustinM",
        "is_clickable": true,
        "bounds": {
          "top": 800,
          "left": 100,
          "bottom": 920,
          "right": 980
        }
      }
    ]
  }
}
```

### 3.2 Dynamic Action / Touch Mapping Payload (`REMOTE_INPUT_ACTION`)

Sent by Windows to Android when interacting with either standard coordinates or vector overlay grids.

```json
{
  "event_type": "REMOTE_INPUT_ACTION",
  "timestamp": 1792036855,
  "data": {
    "action_type": "CLICK_COORDINATE",
    "target_x": 540,
    "target_y": 1310
  }
}
```

---

## 4. Hardware System Control Sync

### 4.1 Phone Mode Toggle (`SYSTEM_MODE_SYNC`)

Used symmetrically to match device states (Do Not Disturb, Quiet/Silent).

```json
{
  "event_type": "SYSTEM_MODE_SYNC",
  "timestamp": 1792036900,
  "data": {
    "mode_type": "DO_NOT_DISTURB",
    "is_enabled": true
  }
}
```

### 4.2 Hotspot Trigger Request (`HOTSPOT_REQUEST`)

Sent by Windows to Android to open deep-linked panels.

```json
{
  "event_type": "HOTSPOT_REQUEST",
  "timestamp": 1792036910,
  "data": {
    "action": "LAUNCH_TETHER_SETTINGS"
  }
}
```
