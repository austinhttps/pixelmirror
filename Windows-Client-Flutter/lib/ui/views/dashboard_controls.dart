// lib/ui/views/dashboard_controls.dart
import 'package:fluent_ui/fluent_ui.dart';
import '../../core/constants.dart';
import '../../network/adb_manager.dart';
import '../../network/mdns_discovery.dart';
import '../../network/socket_client.dart';
import '../../services/mode_sync_service.dart';
import '../widgets/status_badge.dart';

class DashboardControls extends StatefulWidget {
  final SocketClient socketClient;
  final AdbManager adbManager;
  final MdnsDiscoveryManager mdnsDiscovery;
  final ModeSyncService modeSyncService;
  final VoidCallback onConnectUsb;

  const DashboardControls({
    super.key,
    required this.socketClient,
    required this.adbManager,
    required this.mdnsDiscovery,
    required this.modeSyncService,
    required this.onConnectUsb,
  });

  @override
  State<DashboardControls> createState() => _DashboardControlsState();
}

class _DashboardControlsState extends State<DashboardControls> {
  final List<DiscoveredAdbDevice> _discoveredDevices = [];
  bool _isConnecting = false;

  @override
  void initState() {
    super.initState();
    widget.mdnsDiscovery.onDeviceDiscovered.listen((device) {
      if (!mounted) return;
      if (!_discoveredDevices.any((d) => d.endpoint == device.endpoint)) {
        setState(() {
          _discoveredDevices.add(device);
        });
      }
    });
  }

  Future<void> _connectToDiscovered(DiscoveredAdbDevice device) async {
    setState(() => _isConnecting = true);

    // 1. Run adb connect to discovered wireless debugging port
    final bool adbOk = await widget.adbManager.connectWireless(device.ip, device.port);
    debugPrint('[Dashboard] Wireless ADB connect result: $adbOk');

    // 2. Connect socket client to phone IP on default mirror port 8080
    final bool socketOk = await widget.socketClient.connect(
      host: device.ip,
      port: ProtocolConstants.defaultSocketPort,
    );

    if (mounted) {
      setState(() => _isConnecting = false);
      displayInfoBar(
        context,
        builder: (context, close) => InfoBar(
          title: Text(socketOk ? 'Connected to ${device.name}' : 'Connection Failed'),
          content: Text('${device.ip}:${ProtocolConstants.defaultSocketPort} (AES-GCM Authorized: $socketOk)'),
          severity: socketOk ? InfoBarSeverity.success : InfoBarSeverity.error,
          onClose: close,
        ),
      );
    }
  }

  Future<void> _triggerHotspot() async {
    await widget.modeSyncService.requestPhoneHotspotToggle();
    if (mounted) {
      displayInfoBar(
        context,
        builder: (context, close) => InfoBar(
          title: const Text('Hotspot Settings Requested'),
          content: const Text('Dispatched HOTSPOT_REQUEST to open TetherSettings on Pixel 10.'),
          severity: InfoBarSeverity.info,
          onClose: close,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool isAuthorized = widget.socketClient.isAuthorized;
    final bool isDnd = widget.modeSyncService.isDndActive;

    return ScaffoldPage.scrollable(
      header: PageHeader(
        title: const Text('Ecosystem Dashboard & Controls'),
        commandBar: StatusBadge(
          state: widget.socketClient.state,
          deviceName: widget.socketClient.connectedDeviceName,
        ),
      ),
      children: [
        // System Hardware Integration Cards Grid
        Wrap(
          spacing: 16,
          runSpacing: 16,
          children: [
            // Focus Mode Sync Tile
            SizedBox(
              width: 320,
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            isDnd ? FluentIcons.ringer_off : FluentIcons.ringer,
                            size: 20,
                            color: isDnd ? Colors.orange : Colors.blue,
                          ),
                          const SizedBox(width: 10),
                          const Text(
                            'Focus Mode / DND Sync',
                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        isDnd
                            ? 'Pixel 10 in Do Not Disturb. Windows Focus Assist enabled.'
                            : 'Normal audio profile active. Notifications synchronized.',
                        style: TextStyle(fontSize: 12, color: Colors.grey[100]),
                      ),
                      const SizedBox(height: 14),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            isDnd ? 'Status: DND ON' : 'Status: DND OFF',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: isDnd ? Colors.orange : Colors.grey,
                            ),
                          ),
                          ToggleSwitch(
                            checked: isDnd,
                            onChanged: isAuthorized
                                ? (val) => widget.modeSyncService.togglePhoneDnd(val)
                                : null,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),

            // Toggle Phone Hotspot Tile
            SizedBox(
              width: 320,
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Row(
                        children: [
                          Icon(FluentIcons.wifi, size: 20, color: Colors.blue),
                          const SizedBox(width: 10),
                          Text(
                            'Toggle Phone Hotspot',
                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Sends HOTSPOT_REQUEST to force SystemActionHelper to open tethering settings on phone.',
                        style: TextStyle(fontSize: 12, color: Colors.grey[100]),
                      ),
                      const SizedBox(height: 14),
                      Button(
                        onPressed: isAuthorized ? _triggerHotspot : null,
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(FluentIcons.open_in_new_window, size: 14),
                            SizedBox(width: 8),
                            Text('Open Tethering Settings'),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

            // Physical USB Tunnel Pairing Tile
            SizedBox(
              width: 320,
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Row(
                        children: [
                          Icon(FluentIcons.usb, size: 20, color: Colors.green),
                          const SizedBox(width: 10),
                          Text(
                            'Physical USB Tunnel',
                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Forward tcp:8080 and transfer 256-bit AES-GCM key over physical USB debugging.',
                        style: TextStyle(fontSize: 12, color: Colors.grey[100]),
                      ),
                      const SizedBox(height: 14),
                      FilledButton(
                        onPressed: widget.onConnectUsb,
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(FluentIcons.link, size: 14),
                            SizedBox(width: 8),
                            Text('Pair over USB Tunnel'),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),

        const SizedBox(height: 24),

        // Wireless Auto-Discovery (mDNS) Section
        const Text(
          'Wireless Debugging Auto-Discovery (mDNS: _adb-tls-connect._tcp)',
          style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),
        Card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(FluentIcons.radar, size: 16, color: Colors.blue),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Text(
                      'Subnet Listener Active',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                  if (_isConnecting)
                    const ProgressRing(size: 16, strokeWidth: 2),
                ],
              ),
              const SizedBox(height: 12),
              if (_discoveredDevices.isEmpty)
                Text(
                  'Listening for Pixel 10 Wireless Debugging broadcasts on local Wi-Fi subnet...',
                  style: TextStyle(color: Colors.grey[100], fontSize: 12),
                )
              else
                ListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: _discoveredDevices.length,
                  itemBuilder: (context, index) {
                    final d = _discoveredDevices[index];
                    return ListTile(
                      leading: const Icon(FluentIcons.cell_phone, color: Colors.blue),
                      title: Text('${d.name} (${d.endpoint})'),
                      subtitle: Text('Discovered at ${d.discoveredAt.toLocal()}'),
                      trailing: FilledButton(
                        onPressed: _isConnecting ? null : () => _connectToDiscovered(d),
                        child: const Text('Connect'),
                      ),
                    );
                  },
                ),
            ],
          ),
        ),

        const SizedBox(height: 24),

        // Background ADB Management Section
        const Text(
          'ADB Subprocess Management',
          style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),
        Card(
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Terminate Background ADB Daemon',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Cleanly terminates any spawned background ADB loops and releases system ports.',
                    style: TextStyle(fontSize: 12, color: Colors.grey[100]),
                  ),
                ],
              ),
              Button(
                onPressed: () async {
                  await widget.adbManager.cleanTerminateAdb();
                  if (mounted) {
                    displayInfoBar(
                      context,
                      builder: (context, close) => InfoBar(
                        title: const Text('ADB Subprocesses Terminated'),
                        content: const Text('Background server killed and port bindings released.'),
                        severity: InfoBarSeverity.warning,
                        onClose: close,
                      ),
                    );
                  }
                },
                child: const Text('Kill ADB Server'),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
