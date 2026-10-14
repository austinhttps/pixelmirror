// lib/ui/widgets/quick_reply_dialog.dart
import 'dart:convert';
import 'package:fluent_ui/fluent_ui.dart';
import '../../models/contract_models.dart';

class QuickReplyDialog extends StatefulWidget {
  final NotificationEnqueueData notification;
  final Function(String replyText) onSend;

  const QuickReplyDialog({
    super.key,
    required this.notification,
    required this.onSend,
  });

  @override
  State<QuickReplyDialog> createState() => _QuickReplyDialogState();
}

class _QuickReplyDialogState extends State<QuickReplyDialog> {
  final TextEditingController _textController = TextEditingController();
  bool _isSending = false;

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  void _submit() {
    final text = _textController.text.trim();
    if (text.isEmpty) return;

    setState(() => _isSending = true);
    widget.onSend(text);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    Widget? iconWidget;
    if (widget.notification.iconBase64.isNotEmpty) {
      try {
        final bytes = base64Decode(widget.notification.iconBase64);
        iconWidget = Image.memory(bytes, width: 36, height: 36);
      } catch (_) {}
    }

    return ContentDialog(
      title: Row(
        children: [
          if (iconWidget != null) ...[
            iconWidget,
            const SizedBox(width: 10),
          ],
          Expanded(
            child: Text(
              'Reply to ${widget.notification.appLabel}',
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.notification.title,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
          ),
          const SizedBox(height: 4),
          Text(
            widget.notification.body,
            style: TextStyle(color: Colors.grey[120], fontSize: 13),
          ),
          const SizedBox(height: 16),
          TextBox(
            controller: _textController,
            placeholder: 'Type a reply...',
            maxLines: 3,
            autofocus: true,
            onSubmitted: (_) => _submit(),
          ),
        ],
      ),
      actions: [
        Button(
          child: const Text('Cancel'),
          onPressed: () => Navigator.of(context).pop(),
        ),
        FilledButton(
          onPressed: _isSending ? null : _submit,
          child: _isSending
              ? const ProgressRing(strokeWidth: 2, activeColor: Colors.white)
              : const Text('Send Reply'),
        ),
      ],
    );
  }
}
