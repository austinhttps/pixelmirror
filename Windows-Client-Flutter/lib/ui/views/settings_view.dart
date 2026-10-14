// lib/ui/views/settings_view.dart
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/services.dart';
import '../../crypto/aes_gcm_crypto.dart';
import '../../network/socket_client.dart';

class SettingsView extends StatefulWidget {
  final SocketClient socketClient;
  final ThemeMode currentThemeMode;
  final Function(ThemeMode) onThemeModeChanged;
  final bool isMicaEnabled;
  final Function(bool) onMicaChanged;

  const SettingsView({
    super.key,
    required this.socketClient,
    required this.currentThemeMode,
    required this.onThemeModeChanged,
    required this.isMicaEnabled,
    required this.onMicaChanged,
  });

  @override
  State<SettingsView> createState() => _SettingsViewState();
}

class _SettingsViewState extends State<SettingsView> {
  bool _revealKey = false;
  final AesGcmEngine _crypto = AesGcmEngine();

  void _regenerateKey() {
    final String newKey = _crypto.generateKeyBase64();
    widget.socketClient.setCustomKey(newKey);
    setState(() {});

    displayInfoBar(
      context,
      builder: (context, close) => InfoBar(
        title: const Text('New Key Generated'),
        content: const Text('Pair over USB to push this new 256-bit key to the Pixel 10.'),
        severity: InfoBarSeverity.info,
        onClose: close,
      ),
    );
  }

  void _copyKey() {
    Clipboard.setData(ClipboardData(text: widget.socketClient.sessionKeyB64));
    displayInfoBar(
      context,
      builder: (context, close) => InfoBar(
        title: const Text('Key Copied'),
        content: const Text('Base64 256-bit AES-GCM key copied to clipboard.'),
        severity: InfoBarSeverity.success,
        onClose: close,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ScaffoldPage.scrollable(
      header: const PageHeader(
        title: Text('Settings & Configuration'),
      ),
      children: [
        // Section: Personalization & Window Aesthetics
        _buildSectionHeader('Appearance & Aesthetics'),
        const SizedBox(height: 8),
        _buildSettingsCard(
          icon: FluentIcons.color,
          title: 'App Theme',
          subtitle: 'Select between Light, Dark, or System Mica integration',
          action: ComboBox<ThemeMode>(
            value: widget.currentThemeMode,
            items: const [
              ComboBoxItem(value: ThemeMode.system, child: Text('System Default')),
              ComboBoxItem(value: ThemeMode.light, child: Text('Light Mode')),
              ComboBoxItem(value: ThemeMode.dark, child: Text('Dark Mode')),
            ],
            onChanged: (mode) {
              if (mode != null) widget.onThemeModeChanged(mode);
            },
          ),
        ),
        const SizedBox(height: 8),
        _buildSettingsCard(
          icon: FluentIcons.brush,
          title: 'Windows 11 Mica / Acrylic Effect',
          subtitle: 'Enable dynamic semi-transparent background texture layer',
          action: ToggleSwitch(
            checked: widget.isMicaEnabled,
            onChanged: widget.onMicaChanged,
          ),
        ),

        const SizedBox(height: 24),

        // Section: Local Cryptographic Security
        _buildSectionHeader('Local Cryptographic Security (Section 2)'),
        const SizedBox(height: 8),
        _buildSettingsCard(
          icon: FluentIcons.shield,
          title: '256-bit AES-GCM Session Key',
          subtitle: _revealKey
              ? widget.socketClient.sessionKeyB64
              : '••••••••••••••••••••••••••••••••••••••••••••',
          action: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                icon: Icon(_revealKey ? FluentIcons.hide : FluentIcons.view),
                onPressed: () => setState(() => _revealKey = !_revealKey),
              ),
              const SizedBox(width: 8),
              IconButton(
                icon: const Icon(FluentIcons.copy),
                onPressed: _copyKey,
              ),
              const SizedBox(width: 8),
              Button(
                onPressed: _regenerateKey,
                child: const Text('Regenerate Key'),
              ),
            ],
          ),
        ),

        const SizedBox(height: 24),

        // Section: Network & Ports
        _buildSectionHeader('Network & Ports'),
        const SizedBox(height: 8),
        _buildSettingsCard(
          icon: FluentIcons.network_tower,
          title: 'TCP Socket Port',
          subtitle: 'Port 8080 (Matches SocketServerService on Android)',
          action: const Text(
            '8080',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
          ),
        ),
        const SizedBox(height: 8),
        _buildSettingsCard(
          icon: FluentIcons.radar,
          title: 'mDNS Wireless Debugging Service String',
          subtitle: 'Target: _adb-tls-connect._tcp',
          action: const Text(
            'Active',
            style: TextStyle(fontWeight: FontWeight.bold, color: Colors.green),
          ),
        ),

        const SizedBox(height: 24),

        // Section: About
        _buildSectionHeader('About Pixel 10 Mirror Ecosystem'),
        const SizedBox(height: 8),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Pixel 10 Windows Mirror Desktop Client',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                ),
                const SizedBox(height: 4),
                Text(
                  'Version 1.0.0 • Native Fluent UI Desktop Application\nStrict separation maintained with Android Companion APK\nProtocol conforming to API_CONTRACT.md.',
                  style: TextStyle(fontSize: 12, color: Colors.grey[100]),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSectionHeader(String title) {
    return Text(
      title,
      style: const TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.bold,
      ),
    );
  }

  Widget _buildSettingsCard({
    required IconData icon,
    required String title,
    required String subtitle,
    required Widget action,
  }) {
    return Card(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Icon(icon, size: 20, color: Colors.blue),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: TextStyle(fontSize: 11, color: Colors.grey[100]),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          action,
        ],
      ),
    );
  }
}
