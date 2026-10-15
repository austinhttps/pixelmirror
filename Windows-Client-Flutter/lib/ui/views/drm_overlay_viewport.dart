// lib/ui/views/drm_overlay_viewport.dart
import 'package:fluent_ui/fluent_ui.dart';
import '../../models/contract_models.dart';
import '../../network/socket_client.dart';

/// Section 4: System-Contained DRM Workaround Vector Overlay Engine.
/// Reconstructs native Fluent UI controls on-the-fly from scraped accessibility nodes,
/// routing remote inputs back across the encrypted socket without streaming blacked-out canvas bytes.
class DrmOverlayViewport extends StatefulWidget {
  final SecureWindowMapData mapData;
  final SocketClient socketClient;
  final VoidCallback onDismiss;

  const DrmOverlayViewport({
    super.key,
    required this.mapData,
    required this.socketClient,
    required this.onDismiss,
  });

  @override
  State<DrmOverlayViewport> createState() => _DrmOverlayViewportState();
}

class _DrmOverlayViewportState extends State<DrmOverlayViewport> {
  // Reference resolution for Google Pixel 10 (1080 x 2424)
  static const double referencePhoneWidth = 1080.0;
  static const double referencePhoneHeight = 2424.0;

  void _onNodeClicked(AccessibilityNodeMap node) {
    final int centerX = (node.bounds.left + node.bounds.right) ~/ 2;
    final int centerY = (node.bounds.top + node.bounds.bottom) ~/ 2;

    debugPrint('[DRM Overlay] Clicked element "${node.text}" at ($centerX, $centerY)');
    widget.socketClient.sendRemoteInput(
      targetX: centerX,
      targetY: centerY,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black.withValues(alpha: 0.92),
      child: Stack(
        children: [
          // Dynamic Vector Phone Screen Bounds Canvas
          Center(
            child: AspectRatio(
              aspectRatio: 9 / 19.5, // Standard Pixel 10 aspect ratio
              child: Container(
                decoration: BoxDecoration(
                  color: const Color(0xFF1E1E1E),
                  borderRadius: BorderRadius.circular(28),
                  border: Border.all(color: Colors.grey[140], width: 2),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.5),
                      blurRadius: 30,
                      spreadRadius: 5,
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(26),
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final double scaleX = constraints.maxWidth / referencePhoneWidth;
                      final double scaleY = constraints.maxHeight / referencePhoneHeight;

                      return Stack(
                        children: [
                          // App Title Bar Header
                          Positioned(
                            top: 12,
                            left: 16,
                            right: 16,
                            child: Row(
                              children: [
                                Icon(FluentIcons.shield, color: Colors.blue),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    widget.mapData.packageName,
                                    style: const TextStyle(
                                      fontSize: 11,
                                      color: Colors.grey,
                                      fontWeight: FontWeight.w600,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          ),

                          // Render dynamic vector elements dynamically positioned
                          ...widget.mapData.nodes.map((node) {
                            return _buildDynamicControl(node, scaleX, scaleY);
                          }),
                        ],
                      );
                    },
                  ),
                ),
              ),
            ),
          ),

          // Security Overlay Status Pill & Dismiss Control
          Positioned(
            top: 20,
            left: 20,
            right: 20,
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.blue.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.blue.withValues(alpha: 0.5)),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.3),
                      blurRadius: 10,
                    ),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(FluentIcons.lock12, color: Colors.blue),
                    const SizedBox(width: 8),
                    const Text(
                      'FLAG_SECURE Active: Dynamic Vector Engine Engaged',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Button(
                      style: ButtonStyle(
                        padding: WidgetStateProperty.all(const EdgeInsets.symmetric(horizontal: 8, vertical: 4)),
                      ),
                      onPressed: widget.onDismiss,
                      child: const Text('Return to Stream', style: TextStyle(fontSize: 11)),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDynamicControl(AccessibilityNodeMap node, double scaleX, double scaleY) {
    final double left = (node.bounds.left * scaleX).clamp(0.0, 1000.0);
    final double top = (node.bounds.top * scaleY).clamp(0.0, 2000.0);
    final double width = ((node.bounds.right - node.bounds.left) * scaleX).clamp(30.0, 600.0);
    final double height = ((node.bounds.bottom - node.bounds.top) * scaleY).clamp(24.0, 300.0);

    final bool isButton = node.className.contains('Button') ||
        (node.isClickable && node.text.length < 30);
    final bool isEditText = node.className.contains('EditText') ||
        node.className.contains('TextInput');

    Widget control;

    if (isEditText) {
      control = TextBox(
        placeholder: node.text.isEmpty ? 'Tap to edit...' : node.text,
        readOnly: true, // Interactions handled via coordinate injection
        onTap: () => _onNodeClicked(node),
        style: const TextStyle(fontSize: 12),
      );
    } else if (isButton) {
      control = FilledButton(
        onPressed: () => _onNodeClicked(node),
        style: ButtonStyle(
          backgroundColor: WidgetStateProperty.all(Colors.blue),
        ),
        child: Center(
          child: Text(
            node.text.isEmpty ? 'Action' : node.text,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      );
    } else {
      // General view or text element
      control = GestureDetector(
        onTap: node.isClickable ? () => _onNodeClicked(node) : null,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
          alignment: Alignment.centerLeft,
          decoration: node.isClickable
              ? BoxDecoration(
                  border: Border.all(color: Colors.grey[140].withValues(alpha: 0.5)),
                  borderRadius: BorderRadius.circular(4),
                )
              : null,
          child: Text(
            node.text,
            style: TextStyle(
              fontSize: 12,
              color: node.isClickable ? Colors.white : Colors.grey[80],
            ),
            overflow: TextOverflow.ellipsis,
            maxLines: 3,
          ),
        ),
      );
    }

    return Positioned(
      left: left,
      top: top,
      width: width,
      height: height,
      child: control,
    );
  }
}
