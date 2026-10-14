# Windows 11 Desktop Client - Google Pixel 10 Mirroring Ecosystem

A native, high-performance Windows 11 desktop client application built with **Flutter** and **Fluent UI** (`fluent_ui`) to mirror and control the Google Pixel 10. Strictly complies with the data models and network framing declared in `API_CONTRACT.md`.

---

## 1. Architecture & Subsystem Separation

This project lives entirely within `/Windows-Client-Flutter` and maintains complete separation from `/Android-Companion`.

```
Windows-Client-Flutter/
├── pubspec.yaml                 # Dependencies (fluent_ui, cryptography, tray_manager, etc.)
├── analysis_options.yaml        # Strict linter configuration
├── assets/                      # App and System Tray icons
├── windows/                     # Native Win32 desktop runner and CMake configuration
│   ├── CMakeLists.txt
│   └── runner/                  # Win32 DPI-aware PerMonitorV2 entrypoint
└── lib/
    ├── main.dart                # Master entrypoint (Mica theme, tray init, service startup)
    ├── core/
    │   ├── constants.dart       # Contract strings, default ports, event types
    │   └── theme.dart           # Windows 11 Fluent dark/light themes & Mica textures
    ├── crypto/
    │   └── aes_gcm_crypto.dart  # 256-bit AES-GCM engine (matching Android's AesGcmCrypto.kt)
    ├── models/
    │   └── contract_models.dart # Full model representations conforming to API_CONTRACT.md
    ├── network/
    │   ├── adb_manager.dart     # ADB process orchestration (pairing, pm list, monkey, cleanup)
    │   ├── mdns_discovery.dart  # Asynchronous mDNS listener (_adb-tls-connect._tcp)
    │   └── socket_client.dart   # TCP client with handshake, framing, and packet verification
    ├── services/
    │   ├── clipboard_sync_service.dart # Bidirectional loop-preventing clipboard synchronizer
    │   ├── mode_sync_service.dart      # Ringer/DND receiver & Hotspot settings request
    │   ├── notification_service.dart   # Win11 Toast with quick-reply & NOTIFICATION_REPLY routing
    │   └── system_tray_manager.dart    # System tray lifecycle, headless mode & ADB termination
    └── ui/
        ├── views/
        │   ├── app_drawer_panel.dart       # Third-party app grid with instant launch
        │   ├── dashboard_controls.dart     # Hardware controls (Hotspot, DND, mDNS, USB pair)
        │   ├── drm_overlay_viewport.dart   # Dynamic Vector Overlay Engine for FLAG_SECURE
        │   ├── main_window.dart            # Fluent UI NavigationView & NavigationPane layout
        │   ├── mirror_viewport.dart        # Video canvas, Drag-and-Drop pastings, Nav keys
        │   ├── quick_share_box.dart        # Dedicated Quick Share drag target
        │   └── settings_view.dart          # Windows 11 SettingsCards, Key re-gen, Port config
        └── widgets/
            ├── quick_reply_dialog.dart     # In-app quick-reply modal
            └── status_badge.dart           # Visual connection & cryptographic state pill
```

---

## 2. Cryptographic Security Handshake (Section 2)

1. **Key Generation**: A unique, cryptographically random 256-bit AES key is generated on the PC using `Random.secure()`.
2. **Initial Exchange**: The key is transmitted unencrypted over the physical USB debugging tunnel (`adb forward tcp:8080 tcp:8080` to `SocketServerService`) inside the `HANDSHAKE_INIT` payload:
   ```json
   {
     "type": "HANDSHAKE_INIT",
     "version": "1.0.0",
     "timestamp": 1792036800,
     "payload": {
       "secret_key_b64": "..."
     }
   }
   ```
3. **Challenge Validation**: The Android APK verifies the key and responds with `HANDSHAKE_RESPONSE` (`status: "AUTHORIZED"`).
4. **Encrypted Transport**: All subsequent TCP communications (video stream notifications, clipboard sync, file drops, gestures) are packed as `[12-byte IV/Nonce] + [Ciphertext] + [16-byte Tag]` and Base64-encoded. Any payload that fails authentication or decryption is dropped immediately.

---

## 3. Key Features

- **System Tray Controls**: The client can run headlessly minimized to the Windows system tray. Left-clicking toggles the connection engine or cleans up ADB processes. Right-clicking displays full management actions.
- **mDNS Auto-Discovery**: Asynchronously discovers Wireless Debugging via `_adb-tls-connect._tcp`, resolving device IP and port automatically on local Wi-Fi.
- **Interactive Windows 11 Toasts**: Parses `NOTIFICATION_ENQUEUE`, produces native Windows 11 Toasts with inline quick-reply textboxes, and routes `NOTIFICATION_REPLY` back to the phone.
- **Symmetric Clipboard Sync**: Tracks Windows clipboard changes, streams `CLIPBOARD_SYNC`, and syncs incoming phone clipboard data with infinite-loop prevention.
- **App Drawer**: Runs `adb shell pm list packages -3` in the background and populates an interactive app grid. Clicking any app launches it on the Pixel 10 via ADB monkey intent.
- **Canvas Drag-and-Drop Pasting**: Dropping a file onto the mirror viewport calculates relative (X, Y) coordinates, streams raw bytes base64 as `FILE_DROP`, and triggers Android's `FileDropHelper` and `MirrorAccessibilityService` tap-and-paste macro.
- **Quick Share Tile**: Dedicated drag-target tile uploads files and commands `QuickShareHelper` to deploy the Android system share sheet directly into the stream.
- **Hardware Mode & Hotspot Sync**: Automatically toggles Windows Focus Assist when `RingerModeReceiver` reports DND or silent mode. Provides a "Toggle Phone Hotspot" action to open phone tether settings.
- **FLAG_SECURE DRM Workaround Overlay Engine**: When banking apps trigger `FLAG_SECURE`, the video stream hides and the dynamic vector overlay parses `SECURE_WINDOW_MAP` from `MirrorAccessibilityService`, dynamically reconstructing interactive Fluent UI buttons, inputs, and text controls. Mouse clicks are translated back into `REMOTE_INPUT_ACTION` coordinate taps.
- **Fluent UI & Mica Styling**: Built with `fluent_ui` and `flutter_acrylic`, supporting native Windows 11 Mica translucent backgrounds and adaptive light/dark modes.

---

## 4. Build & Run Instructions

```powershell
# Inside /Windows-Client-Flutter
cd Windows-Client-Flutter

# Fetch dependencies
flutter pub get

# Run on Windows Desktop
flutter run -d windows
```
