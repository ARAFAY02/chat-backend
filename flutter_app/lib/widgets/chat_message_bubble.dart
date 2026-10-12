import 'package:flutter/material.dart';

import '../models/chat_message.dart';
import '../theme/app_theme.dart';

class ChatMessageBubble extends StatelessWidget {
  final ChatMessage message;
  final bool isMe;
  final bool isHighlighted;

  const ChatMessageBubble({
    super.key,
    required this.message,
    required this.isMe,
    this.isHighlighted = false,
  });

  @override
  Widget build(BuildContext context) {
    final alignment = isMe ? Alignment.centerRight : Alignment.centerLeft;
    final defaultBubbleColor = isMe ? AppColors.bubbleSent : AppColors.bubbleReceived;
    final bubbleColor = isHighlighted
        ? const Color(0xFFFFF176)
        : defaultBubbleColor;
    final radius = BorderRadius.only(
      topLeft: const Radius.circular(14),
      topRight: const Radius.circular(14),
      bottomLeft: Radius.circular(isMe ? 14 : 2),
      bottomRight: Radius.circular(isMe ? 2 : 14),
    );

    return Align(
      alignment: alignment,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
        margin: const EdgeInsets.symmetric(vertical: 3, horizontal: 10),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.75,
        ),
        decoration: BoxDecoration(
          color: bubbleColor,
          borderRadius: radius,
          border: isHighlighted
              ? Border.all(color: Colors.amber.shade700, width: 1.5)
              : null,
          boxShadow: isHighlighted
              ? [
                  BoxShadow(
                    color: Colors.amber.withOpacity(0.4),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ]
              : const [
                  BoxShadow(
                    color: Color(0x0F000000),
                    blurRadius: 2,
                    offset: Offset(0, 1),
                  ),
                ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              message.message,
              style: const TextStyle(
                fontSize: 15,
                color: AppColors.textPrimary,
                height: 1.3,
              ),
            ),
            const SizedBox(height: 4),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _formatTime(message.timestamp),
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppColors.textSecondary,
                  ),
                ),
                if (isMe) ...[
                  const SizedBox(width: 4),
                  _StatusTicks(status: message.status),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _formatTime(DateTime timestamp) {
    final local = timestamp.toLocal();
    final hour = local.hour % 12 == 0 ? 12 : local.hour % 12;
    final minute = local.minute.toString().padLeft(2, '0');
    final period = local.hour >= 12 ? 'PM' : 'AM';
    return '$hour:$minute $period';
  }
}

class _StatusTicks extends StatelessWidget {
  final MessageStatus status;

  const _StatusTicks({required this.status});

  @override
  Widget build(BuildContext context) {
    switch (status) {
      case MessageStatus.sending:
        return const Icon(Icons.access_time, size: 13, color: AppColors.tickDefault);
      case MessageStatus.sent:
        return const Icon(Icons.check, size: 15, color: AppColors.tickDefault);
      case MessageStatus.delivered:
        return const Icon(Icons.done_all, size: 15, color: AppColors.tickDefault);
      case MessageStatus.seen:
        return const Icon(Icons.done_all, size: 15, color: AppColors.tickSeen);
    }
  }
}
