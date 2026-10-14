# Pixel Mirror — Android Companion Core

Lightweight, high-performance native Android companion application built for the **Google Pixel 10** within the Pixel Mirror ecosystem. Isolated entirely inside `/Android-Companion`.

---

## 🏗️ Architecture Overview

```
com.google.pixelmirror.companion/
├── crypto/
│   ├── AesGcmCrypto.kt                 # 256-bit AES-GCM encryption/decryption routines
│   └── CryptoManager.kt                # Session secret key management & secure storage
├── model/
│   └── ContractModels.kt               # Strict serialization matching root API_CONTRACT.md
├── network/
│   ├── SocketServerService.kt          # Foreground TCP socket server (Port 8080)
│   ├── ClientSession.kt                # Connection lifecycle, handshake & frame routing
│   └── SocketEventBus.kt               # Inter-service reactive flow event bus
├── service/
│   ├── MirrorTileService.kt            # Quick Settings pull-down toggle ("Pixel Mirror")
│   ├── MirrorNotificationListenerService.kt # Notification interception & quick-reply bridge
│   ├── MirrorAccessibilityService.kt   # FLAG_SECURE view tree scraper & remote touch injection
│   └── ScreenPrivacyOverlayService.kt  # OLED screen dimming/blackout privacy canvas
├── receiver/
│   └── RingerModeReceiver.kt           # System ringer & DND sync broadcast receiver
├── util/
│   ├── ClipboardSyncHelper.kt          # Bidirectional clipboard synchronization
│   ├── FileDropHelper.kt               # Download drop, FileProvider URI & tap-paste macro
│   ├── QuickShareHelper.kt             # Native ACTION_SEND chooser for Quick Share
│   └── SystemActionHelper.kt           # TetherSettings explicit routing & mode changes
└── ui/
    └── MainActivity.kt                 # Material Design 3 configuration dashboard
```

---

## 🔒 Cryptographic Security (Section 2)

- **Handshake Protocol**: Upon TCP connection, the PC client transmits a `HANDSHAKE_INIT` payload over a physical USB ADB tunnel (`adb forward tcp:8080 tcp:8080`).
- **256-Bit AES-GCM**: Key is validated, registered into `CryptoManager`, and acknowledged with a `HANDSHAKE_RESPONSE` (`status: "AUTHORIZED"`).
- **Challenge Verification**: Connections failing the key exchange challenge are instantly dropped.
- **Session Protection**: All subsequent socket payloads (notifications, gestures, clipboard, files) are protected by 256-bit AES-GCM with 96-bit unique nonces (IVs) and 128-bit authentication tags.

---

## ⚡ System Bridges & Integrations (Sections 1, 3, 4)

1. **Background Socket Server**:
   - Runs as an Android 14+ Foreground Service (`connectedDevice|dataSync`).
   - Listens on `0.0.0.0:8080` for low-overhead local TCP socket connections.
2. **Quick Settings Toggle Tile**:
   - `MirrorTileService` appears in the system pull-down drawer labeled **"Pixel Mirror"**.
   - Toggling the tile directly starts or stops `SocketServerService` to preserve battery life.
3. **Screen Privacy Handler**:
   - `ScreenPrivacyOverlayService` deploys a full-screen `TYPE_APPLICATION_OVERLAY` window with `screenBrightness = 0.01f` and a pitch-black OLED background as soon as an active mirroring session connects.
4. **Interactive Notifications**:
   - `MirrorNotificationListenerService` serializes alerts into `NOTIFICATION_ENQUEUE` with Base64 app icons.
   - Listens for `NOTIFICATION_REPLY` and dispatches `RemoteInput` responses directly via the original notification's `PendingIntent`.
5. **DRM Workaround (Accessibility)**:
   - `MirrorAccessibilityService` detects `TYPE_WINDOW_STATE_CHANGED` in `FLAG_SECURE` banking/protected windows.
   - Scrapes the `AccessibilityNodeInfo` hierarchy and streams structured `SECURE_WINDOW_MAP` JSON to Windows for vector re-rendering.
6. **Smart File Drops & Quick Share**:
   - Saves dropped file bytes to `/sdcard/Download/`.
   - Resolves a secure `content://com.google.pixelmirror.companion.fileprovider` URI.
   - Accessibility macro taps incoming `(target_x, target_y)` coordinates and fires `ACTION_PASTE`.
   - `QuickShareHelper` opens the native Android Quick Share sheet via `Intent.createChooser()`.
7. **Hardware Mode Sync & Tether Settings**:
   - Synchronizes DND and Silent ringer modes via `RingerModeReceiver`.
   - Routes `HOTSPOT_REQUEST` directly to `com.android.settings.TetherSettings`.

---

## 🎨 Material Design 3 Dashboard (Section 5)

- Dynamic wallpaper color palette inheritance via `DynamicColors.applyToActivityIfAvailable()`.
- 24dp rounded corner card containers (`Widget.PixelMirror.Card`).
- Standard Material motion switches and permission bridge inspectors.
