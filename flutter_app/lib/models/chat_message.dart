/// Delivery/read status of a single message, mirrored from the
/// backend's message payloads.
enum MessageStatus { sending, sent, delivered, seen }

MessageStatus messageStatusFromString(String? value) {
  switch (value) {
    case 'sent':
      return MessageStatus.sent;
    case 'delivered':
      return MessageStatus.delivered;
    case 'seen':
      return MessageStatus.seen;
    case 'sending':
    default:
      return MessageStatus.sending;
  }
}

String messageStatusToString(MessageStatus status) {
  switch (status) {
    case MessageStatus.sending:
      return 'sending';
    case MessageStatus.sent:
      return 'sent';
    case MessageStatus.delivered:
      return 'delivered';
    case MessageStatus.seen:
      return 'seen';
  }
}

class ChatMessage {
  final String id;
  final String chatId;
  final String senderId;
  final String receiverId;
  final String message;
  final DateTime timestamp;
  final MessageStatus status;

  const ChatMessage({
    required this.id,
    required this.chatId,
    required this.senderId,
    required this.receiverId,
    required this.message,
    required this.timestamp,
    this.status = MessageStatus.sending,
  });

  ChatMessage copyWith({
    String? id,
    String? chatId,
    String? senderId,
    String? receiverId,
    String? message,
    DateTime? timestamp,
    MessageStatus? status,
  }) {
    return ChatMessage(
      id: id ?? this.id,
      chatId: chatId ?? this.chatId,
      senderId: senderId ?? this.senderId,
      receiverId: receiverId ?? this.receiverId,
      message: message ?? this.message,
      timestamp: timestamp ?? this.timestamp,
      status: status ?? this.status,
    );
  }

  /// Builds the outbound "type": "message" payload sent over the socket.
  Map<String, dynamic> toJson() {
    return {
      'type': 'message',
      'id': id,
      'chat_id': chatId,
      'sender_id': senderId,
      'receiver_id': receiverId,
      'message': message,
      'timestamp': timestamp.toUtc().toIso8601String(),
      'status': messageStatusToString(status),
    };
  }

  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    return ChatMessage(
      id: json['id'] as String? ?? '',
      chatId: json['chat_id'] as String? ?? '',
      senderId: json['sender_id'] as String? ?? '',
      receiverId: json['receiver_id'] as String? ?? '',
      message: json['message'] as String? ?? '',
      timestamp: DateTime.tryParse(json['timestamp'] as String? ?? '') ??
          DateTime.now(),
      status: messageStatusFromString(json['status'] as String?),
    );
  }
}
