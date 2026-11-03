// lib/ui/widgets/status_badge.dart
import 'package:fluent_ui/fluent_ui.dart';
import '../../core/constants.dart';

class StatusBadge extends StatelessWidget {
  final ConnectionStateEnum state;
  final String deviceName;

  const StatusBadge({
    super.key,
    required this.state,
    this.deviceName = ProtocolConstants.defaultDeviceName,
  });

  @override
  Widget build(BuildContext context) {
    Color color;
    String text;
    IconData icon;

    switch (state) {
      case ConnectionStateEnum.authorized:
        color = Colors.green;
        text = '256-Bit Encrypted • $deviceName';
        icon = FluentIcons.lock12;
        break;
      case ConnectionStateEnum.connecting:
      case ConnectionStateEnum.handshaking:
        color = Colors.orange;
        text = 'Performing AES-GCM Handshake...';
        icon = FluentIcons.sync;
        break;
      case ConnectionStateEnum.discovering:
        color = Colors.blue;
        text = 'Discovering mDNS...';
        icon = FluentIcons.radio_bullet;
        break;
      case ConnectionStateEnum.error:
        color = Colors.red;
        text = 'Connection Challenge Failed';
        icon = FluentIcons.error_badge;
        break;
      case ConnectionStateEnum.disconnected:
        color = Colors.grey[100];
        text = 'Disconnected';
        icon = FluentIcons.plug_disconnected;
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: color,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
