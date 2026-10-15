// lib/ui/views/quick_share_box.dart
import 'dart:typed_data';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:fluent_ui/fluent_ui.dart';
import '../../network/socket_client.dart';

class QuickShareBox extends StatefulWidget {
  final SocketClient socketClient;

  const QuickShareBox({super.key, required this.socketClient});

  @override
  State<QuickShareBox> createState() => _QuickShareBoxState();
}

class _QuickShareBoxState extends State<QuickShareBox> {
  bool _isDragging = false;
  bool _isUploading = false;
  String _uploadStatus = '';
  final List<String> _sharedHistory = [];

  Future<void> _handleFileShare(List<DropItem> files) async {
    if (!widget.socketClient.isAuthorized) {
      displayInfoBar(
        context,
        builder: (context, close) => InfoBar(
          title: const Text('Not Connected'),
          content: const Text('Connect to your Pixel 10 to share files.'),
          severity: InfoBarSeverity.warning,
          onClose: close,
        ),
      );
      return;
    }

    setState(() {
      _isUploading = true;
      _uploadStatus = 'Uploading ${files.length} file(s) to phone...';
    });

    for (final file in files) {
      try {
        final Uint8List bytes = await file.readAsBytes();
        final String filename = file.name;

        // Determine simple MIME type
        String mime = 'application/octet-stream';
        final lower = filename.toLowerCase();
        if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) mime = 'image/jpeg';
        if (lower.endsWith('.png')) mime = 'image/png';
        if (lower.endsWith('.pdf')) mime = 'application/pdf';
        if (lower.endsWith('.mp4')) mime = 'video/mp4';

        // Section 3.5: Send with isCanvasPaste = false to deploy native Android Quick Share sheet
        await widget.socketClient.sendFileDrop(
          filename: filename,
          fileBytes: bytes,
          targetX: -1,
          targetY: -1,
          isCanvasPaste: false,
          mimeType: mime,
        );

        _sharedHistory.insert(0, '$filename (${(bytes.length / 1024).toStringAsFixed(1)} KB)');
      } catch (e) {
        debugPrint('[QuickShare] Error uploading file: $e');
      }
    }

    if (mounted) {
      setState(() {
        _isUploading = false;
        _uploadStatus = 'Files deployed to Pixel 10 Quick Share!';
      });

      displayInfoBar(
        context,
        builder: (context, close) => InfoBar(
          title: const Text('Quick Share Deployed'),
          content: const Text('Native Android share sheet opened in stream.'),
          severity: InfoBarSeverity.success,
          onClose: close,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return ScaffoldPage(
      header: const PageHeader(
        title: Text('Quick Share Bridge'),
      ),
      content: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Dedicated Drag-and-Drop Quick Share Target Tile
            DropTarget(
              onDragEntered: (_) => setState(() => _isDragging = true),
              onDragExited: (_) => setState(() => _isDragging = false),
              onDragDone: (details) async {
                setState(() => _isDragging = false);
                await _handleFileShare(details.files);
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                height: 240,
                decoration: BoxDecoration(
                  color: _isDragging
                      ? Colors.blue.withValues(alpha: 0.15)
                      : FluentTheme.of(context).cardColor,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: _isDragging ? Colors.blue : Colors.grey[120].withValues(alpha: 0.4),
                    width: _isDragging ? 2.5 : 1.5,
                  ),
                ),
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.blue.withValues(alpha: 0.12),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          FluentIcons.share,
                          color: Colors.blue,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        _isDragging
                            ? 'Drop files to launch Quick Share'
                            : 'Drag & Drop files here for Quick Share',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Files are transferred securely and open the Pixel 10 native system share sheet directly inside the stream',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 12, color: Colors.grey[100]),
                      ),
                      if (_isUploading) ...[
                        const SizedBox(height: 16),
                        const SizedBox(
                          width: 20,
                          height: 20,
                          child: ProgressRing(strokeWidth: 2),
                        ),
                        const SizedBox(height: 8),
                        Text(_uploadStatus, style: const TextStyle(fontSize: 12)),
                      ],
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 24),

            // Share History & Status
            const Text(
              'Recent Shared Transfers',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: _sharedHistory.isEmpty
                  ? Center(
                      child: Text(
                        'No files shared yet in this session',
                        style: TextStyle(color: Colors.grey[100]),
                      ),
                    )
                  : ListView.separated(
                      itemCount: _sharedHistory.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (context, index) {
                        return Card(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                          child: Row(
                            children: [
                              Icon(FluentIcons.page, color: Colors.blue),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  _sharedHistory[index],
                                  style: const TextStyle(fontSize: 13),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              Icon(FluentIcons.check_mark, color: Colors.green),
                            ],
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
