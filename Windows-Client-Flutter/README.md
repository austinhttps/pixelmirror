# Windows Desktop App - Google Pixel 10 Companion

Desktop app built with Flutter and Fluent UI (`fluent_ui`) to pair with the Google Pixel 10 companion. Implements the models and network framing specified in `API_CONTRACT.md`.

## 1. Architecture and Project Structure

This directory contains the desktop code for Windows:

```
Windows-Client-Flutter/
├── pubspec.yaml                 # Dependencies (fluent_ui, cryptography, tray_manager, local_notifier)
├── analysis_options.yaml        # Linter configuration
├── assets/                      # App and tray icons
├── test/                        # Unit and widget tests
│   └── widget_test.dart
├── windows/                     # Native Win32 desktop runner and CMake build
└── lib/
    ├── main.dart                # Application entrypoint, window setup, tray initialization
    ├── core/
    │   ├── constants.dart       # Protocol constants, action names, defaults
    │   └── theme.dart           # Fluent UI themes and palette definitions
    ├── crypto/
    │   └── aes_gcm_crypto.dart  # 256-bit AES-GCM encryption and decryption engine
    ├── models/
    │   └── contract_models.dart # Contract representations conforming to API_CONTRACT.md
    ├── network/
    │   ├── adb_manager.dart     # ADB process orchestration (port forwarding and wireless connect)
    │   └── socket_client.dart   # TCP client with handshake, auto-reconnect, and frame parsing
    ├── services/
    │   ├── clipboard_sync_service.dart # Bidirectional clipboard synchronizer with hash deduplication
    │   ├── notification_service.dart   # In-app notification store and Windows toast routing
    │   └── system_tray_manager.dart    # System tray lifecycle and quick actions
    └── ui/
        ├── views/
        │   └── main_window.dart        # Dual-card layout (Notification Stream and Clipboard Sync Hub)
        └── widgets/
            ├── quick_reply_dialog.dart # In-app quick reply dialog
            └── status_badge.dart       # Connection status indicator
```

## 2. Cryptographic Security Handshake

1. Key Generation: Generates a 256-bit AES key on the desktop using `Random.secure()`.
2. Initial Exchange: Transmits the key over the local TCP socket inside a plaintext `HANDSHAKE_INIT` frame:
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
3. Validation: Android verifies the key and responds with `HANDSHAKE_RESPONSE` (`status: "AUTHORIZED"`).
4. Encrypted Transport: Post-handshake TCP frames are packed as `[12-byte IV] + [Ciphertext] + [16-byte Tag]` and encoded as Base64 strings. Frames ending with `\n` are parsed and decrypted immediately. Frames failing verification are dropped.

## 3. Features

- Dual-Card Dashboard: Centralizes incoming notifications and clipboard controls in a single window.
- Notification Stream: Shows recent notifications with app details, body text, and direct reply inputs.
- Quick Replies: Routes typed replies back to the Android companion as `NOTIFICATION_REPLY` frames.
- System Toasts: Displays notifications using Windows native notifications with action buttons.
- Clipboard Sync: Watches the Windows clipboard, sends changes to Android, and applies incoming clips. Hash checking prevents circular synchronization loops.
- System Tray: Minimizes to the notification area with quick actions to sync clipboard or disconnect.
- Auto-Reconnect: Attempts reconnection every three seconds if the socket disconnects unexpectedly.

## 4. Build and Test Instructions

```powershell
# Navigate to the project directory
cd Windows-Client-Flutter

# Fetch packages
flutter pub get

# Run static analysis
flutter analyze

# Run automated tests
flutter test

# Launch the desktop application
flutter run -d windows
```
