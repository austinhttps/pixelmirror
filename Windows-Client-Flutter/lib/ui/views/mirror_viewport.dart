// lib/ui/views/mirror_viewport.dart
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:fluent_ui/fluent_ui.dart';
import '../../core/constants.dart';
import '../../models/contract_models.dart';
import '../../network/socket_client.dart';
import 'drm_overlay_viewport.dart';

class MirrorViewport extends StatefulWidget {
  final SocketClient socketClient;

  const MirrorViewport({super.key, required this.socketClient});

  @override
  State<MirrorViewport> createState() => _MirrorViewportState();
}

class _MirrorViewportState extends State<MirrorViewport> {
  // Reference phone resolution (Google Pixel 10: 1080 x 2424)
  static const double phoneResWidth = 1080.0;
  static const double phoneResHeight = 2424.0;

  bool _isDraggingOver = false;
  Offset _currentDropOffset = Offset.zero;
  SecureWindowMapData? _activeDrmMap;
  StreamSubscription? _drmSub;

  @override
  void initState() {
    super.initState();
    _drmSub = widget.socketClient.onSecureWindowMap.listen((SecureWindowMapData data) {
      setState(() {
        _activeDrmMap = data;
      });
    });
  }

  @override
  void dispose() {
    _drmSub?.cancel();
    super.dispose();
  }

  void _handleScreenTap(TapDownDetails details, BoxConstraints constraints) {
    if (!widget.socketClient.isAuthorized) return;

    // Convert local tap coordinate to phone screen coordinate
    final double scaleX = phoneResWidth / constraints.maxWidth;
    final double scaleY = phoneResHeight / constraints.maxHeight;

    final int targetX = (details.localPosition.dx * scaleX).round().clamp(0, 1080);
    final int targetY = (details.localPosition.dy * scaleY).round().clamp(0, 2424);

    debugPrint('[Viewport] User tapped phone canvas at ($targetX, $targetY)');
    widget.socketClient.sendRemoteInput(
      targetX: targetX,
      targetY: targetY,
      actionType: ProtocolConstants.actionClickCoordinate,
    );
  }

  Future<void> _handleFileDrop(DropDoneDetails details, BoxConstraints constraints) async {
    if (!widget.socketClient.isAuthorized) {
      debugPrint('[Viewport] Cannot drop file: Device not connected.');
      return;
    }

    final double scaleX = phoneResWidth / constraints.maxWidth;
    final double scaleY = phoneResHeight / constraints.maxHeight;

    final int targetX = (_currentDropOffset.dx * scaleX).round().clamp(0, 1080);
    final int targetY = (_currentDropOffset.dy * scaleY).round().clamp(0, 2424);

    for (final file in details.files) {
      try {
        final Uint8List bytes = await file.readAsBytes();
        final String filename = file.name;

        debugPrint('[Viewport] Uploading dropped file to canvas: $filename ($targetX, $targetY)...');

        // Transmit Section 3.3 FileDropData to trigger Android FileDropHelper & A11y macro
        await widget.socketClient.sendFileDrop(
          filename: filename,
          fileBytes: bytes,
          targetX: targetX,
          targetY: targetY,
          isCanvasPaste: true,
        );
      } catch (e) {
        debugPrint('[Viewport] Error reading dropped file: $e');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_activeDrmMap != null) {
      return DrmOverlayViewport(
        mapData: _activeDrmMap!,
        socketClient: widget.socketClient,
        onDismiss: () {
          setState(() {
            _activeDrmMap = null;
          });
        },
      );
    }

    final bool isConnected = widget.socketClient.isAuthorized;

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Main Mirror Viewport Phone Frame
          Expanded(
            child: AspectRatio(
              aspectRatio: 9 / 19.5, // Pixel 10 aspect ratio
              child: Container(
                margin: const EdgeInsets.symmetric(vertical: 16),
                decoration: BoxDecoration(
                  color: Colors.black,
                  borderRadius: BorderRadius.circular(32),
                  border: Border.all(
                    color: _isDraggingOver ? Colors.blue : Colors.grey[140],
                    width: _isDraggingOver ? 3 : 2,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.35),
                      blurRadius: 24,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(30),
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      return DropTarget(
                        onDragEntered: (details) {
                          setState(() {
                            _isDraggingOver = true;
                          });
                        },
                        onDragUpdated: (details) {
                          setState(() {
                            _currentDropOffset = details.localPosition;
                          });
                        },
                        onDragExited: (details) {
                          setState(() {
                            _isDraggingOver = false;
                          });
                        },
                        onDragDone: (details) async {
                          setState(() {
                            _isDraggingOver = false;
                          });
                          await _handleFileDrop(details, constraints);
                        },
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTapDown: (details) => _handleScreenTap(details, constraints),
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              // Mirrored Video Stream / Canvas Simulation
                              if (isConnected) ...[
                                Container(
                                  decoration: const BoxDecoration(
                                    gradient: LinearGradient(
                                      begin: Alignment.topCenter,
                                      end: Alignment.bottomCenter,
                                      colors: [
                                        Color(0xFF1E293B),
                                        Color(0xFF0F172A),
                                      ],
                                    ),
                                  ),
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      const Icon(
                                        FluentIcons.cell_phone,
                                        size: 64,
                                        color: Colors.blue,
                                      ),
                                      const SizedBox(height: 12),
                                      Text(
                                        widget.socketClient.connectedDeviceName,
                                        style: const TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.white,
                                        ),
                                      ),
                                      const SizedBox(height: 6),
                                      const Text(
                                        'Low-Latency Wi-Fi Mirroring Active',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: Colors.grey,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ] else ...[
                                Container(
                                  color: const Color(0xFF151515),
                                  child: Center(
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(
                                          FluentIcons.plug_disconnected,
                                          size: 48,
                                          color: Colors.grey[100],
                                        ),
                                        const SizedBox(height: 16),
                                        const Text(
                                          'Pixel 10 Disconnected',
                                          style: TextStyle(
                                            fontSize: 15,
                                            fontWeight: FontWeight.w600,
                                            color: Colors.grey,
                                          ),
                                        ),
                                        const SizedBox(height: 8),
                                        const Text(
                                          'Connect via USB or local Wi-Fi mDNS to begin mirroring',
                                          textAlign: TextAlign.center,
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: Colors.grey,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ],

                              // Drag & Drop Canvas Pasting Target Overlay
                              if (_isDraggingOver)
                                Container(
                                  color: Colors.blue.withOpacity(0.3),
                                  child: Center(
                                    child: Container(
                                      padding: const EdgeInsets.all(16),
                                      decoration: BoxDecoration(
                                        color: Colors.black.withOpacity(0.8),
                                        borderRadius: BorderRadius.circular(16),
                                        border: Border.all(color: Colors.blue),
                                      ),
                                      child: Column(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          const Icon(
                                            FluentIcons.cloud_upload,
                                            size: 40,
                                            color: Colors.blue,
                                          ),
                                          const SizedBox(height: 8),
                                          const Text(
                                            'Drop to Paste at Location',
                                            style: TextStyle(
                                              fontWeight: FontWeight.bold,
                                              color: Colors.white,
                                            ),
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            'Target: (${((_currentDropOffset.dx * (phoneResWidth / constraints.maxWidth))).round()}, ${((_currentDropOffset.dy * (phoneResHeight / constraints.maxHeight))).round()})',
                                            style: const TextStyle(
                                              fontSize: 11,
                                              color: Colors.grey,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
            ),
          ),

          // Android Navigation Bar (Back, Home, Recents)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.4),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: Colors.grey[140].withOpacity(0.3)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: const Icon(FluentIcons.back, size: 16),
                  onPressed: isConnected
                      ? () => widget.socketClient.sendRemoteInput(
                            targetX: 0,
                            targetY: 0,
                            actionType: ProtocolConstants.actionGlobalBack,
                          )
                      : null,
                ),
                const SizedBox(width: 24),
                IconButton(
                  icon: const Icon(FluentIcons.circle_shape_solid, size: 14),
                  onPressed: isConnected
                      ? () => widget.socketClient.sendRemoteInput(
                            targetX: 0,
                            targetY: 0,
                            actionType: ProtocolConstants.actionGlobalHome,
                          )
                      : null,
                ),
                const SizedBox(width: 24),
                IconButton(
                  icon: const Icon(FluentIcons.stop_solid, size: 14),
                  onPressed: isConnected
                      ? () => widget.socketClient.sendRemoteInput(
                            targetX: 0,
                            targetY: 0,
                            actionType: ProtocolConstants.actionGlobalRecents,
                          )
                      : null,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
