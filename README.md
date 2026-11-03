# Pixel Mirror

Companion ecosystem connecting the Google Pixel 10 to a Windows PC.

## V1 Scope

Pixel Mirror V1 focuses on two core synchronization features:

1. Bidirectional Clipboard Synchronization
   - Copies text between Windows and Android.
   - Uses hash checking and timestamp windows to stop feedback loops.
   - Includes manual push and automatic background sync.

2. Android Notification Streaming and Quick Replies
   - Forwards notifications from Android to the Windows client.
   - Supports inline quick replies routed directly to Android notification actions.

Screen mirroring, file transfers, and remote display rendering are deferred to future releases.

## Repository Layout

- `Android-Companion`: Kotlin Android application targeting Pixel 10. Runs the background notification listener and TCP socket server.
- `Windows-Client-Flutter`: Desktop app built with Flutter and Fluent UI. Connects to the companion over local TCP or ADB port forwarding.
- `API_CONTRACT.md`: Specification for frame formats, cryptographic handshakes, and event packets.

## Security and Transport

- Port: TCP port 8080 (tunneled via `adb forward tcp:8080 tcp:8080` or direct local network).
- Encryption: 256-bit AES-GCM for all post-handshake frames.
- Framing: Newline-delimited strings (`\n`) with immediate socket flush on every transmission.
- Handshake: The Windows host initiates the connection by generating a secure key and sending a `HANDSHAKE_INIT` frame. The companion verifies and returns `HANDSHAKE_RESPONSE`.

## Getting Started

### Android Companion
1. Open `Android-Companion` in Android Studio.
2. Build and install the APK on your Pixel 10.
3. Grant Notification Listener access and disable battery optimization when prompted.
4. The background server starts automatically on port 8080.

### Windows App
1. Connect your phone via USB with USB debugging enabled.
2. Forward the port:
   ```powershell
   adb forward tcp:8080 tcp:8080
   ```
3. Run the desktop application:
   ```powershell
   cd Windows-Client-Flutter
   flutter pub get
   flutter run -d windows
   ```
