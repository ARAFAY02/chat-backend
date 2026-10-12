import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../models/chat_message.dart';
import '../services/websocket_service.dart';
import '../utils/app_constants.dart';

class ChatProvider extends ChangeNotifier {
  ChatProvider() : _socketService = WebSocketService();

  final WebSocketService _socketService;

  String? _currentUserId;
  String? get currentUserId => _currentUserId;

  SocketConnectionState _connectionState =
      SocketConnectionState.disconnected;

  SocketConnectionState get connectionState => _connectionState;

  final Map<String, List<ChatMessage>> _messagesByPeer = {};
  final Map<String, bool> _onlineByPeer = {};
  final Map<String, bool> _typingByPeer = {};

  final Map<String, Timer> _typingExpiryTimers = {};
  final Map<String, Timer> _typingDebounceTimers = {};

  StreamSubscription? _messageSub;
  StreamSubscription? _stateSub;

  final _random = Random();

  String? _activePeerId;

  final StreamController<ChatMessage> _bannerController =
      StreamController<ChatMessage>.broadcast();

  Stream<ChatMessage> get bannerMessages =>
      _bannerController.stream;

  // ------------------------------------------------------------
  // Active chat
  // ------------------------------------------------------------

  void setActivePeer(String? peerId) {
    _activePeerId = peerId;
  }

  String? get activePeerId => _activePeerId;

  String? _highlightedMessageId;
  String? get highlightedMessageId => _highlightedMessageId;
  Timer? _highlightTimer;

  void highlightMessage(String messageId) {
    _highlightTimer?.cancel();
    _highlightedMessageId = messageId;
    notifyListeners();

    _highlightTimer = Timer(const Duration(milliseconds: 2000), () {
      _highlightedMessageId = null;
      notifyListeners();
    });
  }

  // ------------------------------------------------------------
  // Getters
  // ------------------------------------------------------------

  List<ChatMessage> messagesWith(String peerId) {
    return List.unmodifiable(
      _messagesByPeer[peerId] ?? const [],
    );
  }

  bool isOnline(String peerId) {
    return _onlineByPeer[peerId] ?? false;
  }

  bool isTyping(String peerId) {
    return _typingByPeer[peerId] ?? false;
  }

  ChatMessage? lastMessageWith(String peerId) {
    final list = _messagesByPeer[peerId];

    if (list == null || list.isEmpty) {
      return null;
    }

    return list.last;
  }

  int unreadCountWith(String peerId) {
    final list = _messagesByPeer[peerId];

    if (list == null) {
      return 0;
    }

    return list.where((message) {
      return message.senderId == peerId &&
          message.status != MessageStatus.seen;
    }).length;
  }

  // ------------------------------------------------------------
  // Connection
  // ------------------------------------------------------------

  Future<void> connectAs(String userId) async {
    _currentUserId = userId;

    _messageSub?.cancel();
    _stateSub?.cancel();

    _messageSub = _socketService.messages.listen(
      _handleIncoming,
    );

    _stateSub = _socketService.connectionState.listen(
      (state) {
        final previousState = _connectionState;
        _connectionState = state;
        notifyListeners();

        final wasDisconnected =
            previousState == SocketConnectionState.reconnecting ||
                previousState == SocketConnectionState.disconnected ||
                previousState == SocketConnectionState.connecting;

        if (state == SocketConnectionState.connected && wasDisconnected) {
          if (_activePeerId != null) {
            final peerId = _activePeerId!;
            loadHistory(peerId).then((_) {
              if (_activePeerId == peerId) {
                markSeen(peerId);
              }
            });
          }
        }
      },
    );

    await _socketService.connect(userId);
  }

  /// Fetches persisted chat history for [peerId] from the backend's
  /// REST endpoint (GET /messages/{a}/{b}) and merges it into local
  /// state. Existing messages already in memory (e.g. from the current
  /// live session) are kept; only messages not already present (by id)
  /// are added, and the combined list is re-sorted by time. Best-effort:
  /// if the fetch fails (e.g. no connectivity), the chat still works
  /// from whatever arrives live for this session.
  Future<void> loadHistory(String peerId) async {
    if (_currentUserId == null) return;
    HttpClient? client;
    try {
      client = HttpClient();
      final uri = Uri.parse(AppConstants.historyUrlFor(_currentUserId!, peerId));
      final request = await client.getUrl(uri).timeout(const Duration(seconds: 6));
      final response = await request.close();

      if (response.statusCode != 200) return;

      final body = await response.transform(utf8.decoder).join();
      final decoded = jsonDecode(body) as Map<String, dynamic>;
      final rawMessages = decoded['messages'] as List<dynamic>? ?? const [];

      final list = _messagesByPeer.putIfAbsent(peerId, () => []);
      final existingIds = list.map((m) => m.id).toSet();

      for (final raw in rawMessages) {
        final message = ChatMessage.fromJson(raw as Map<String, dynamic>);
        if (existingIds.add(message.id)) {
          list.add(message);
        }
      }
      list.sort((a, b) => a.timestamp.compareTo(b.timestamp));
      notifyListeners();
    } catch (_) {
      // Silently ignore - history is a nice-to-have on top of live chat.
    } finally {
      client?.close();
    }
  }

  /// Loads persisted history for every peer in [peerIds] in parallel.
  ///
  /// Used right after login/connect, before the chat list screen is
  /// shown, so last-message previews and unread counts on that screen
  /// are correct immediately - without this, the list screen only
  /// ever shows data for a chat once the user has actually opened it
  /// in the current app session (loadHistory() above is otherwise only
  /// called from ChatScreen.initState), which made saved history look
  /// like it wasn't persisting at all on a fresh app launch.
  Future<void> loadAllHistory(List<String> peerIds) async {
    await Future.wait(peerIds.map(loadHistory));
  }

  // ------------------------------------------------------------
  // Incoming events
  // ------------------------------------------------------------

  void _handleIncoming(Map<String, dynamic> data) {
    debugPrint('========================================');
    debugPrint('📩 SOCKET INCOMING');
    debugPrint('$data');
    debugPrint('========================================');

    final type = _stringValue(data['type']);

    switch (type) {
      case 'message':
        _onMessageReceived(data);
        break;

      case 'typing':
        _onTypingReceived(data);
        break;

      case 'online':
        _setPeerOnline(
          _stringValue(data['sender_id']),
          true,
        );
        break;

      case 'offline':
        _setPeerOnline(
          _stringValue(data['sender_id']),
          false,
        );
        break;

      case 'sent':
        _updateOutgoingStatus(
          data,
          MessageStatus.sent,
        );
        break;

      case 'delivered':
        _updateOutgoingStatus(
          data,
          MessageStatus.delivered,
        );
        break;

      case 'seen':
        _updateOutgoingStatus(
          data,
          MessageStatus.seen,
        );
        break;
    }
  }

  // ------------------------------------------------------------
  // Find remote user
  // ------------------------------------------------------------

  String? _getRemoteUserId(
    String? senderId,
    String? receiverId,
  ) {
    if (_currentUserId == null) {
      return null;
    }

    if (senderId == null || senderId.isEmpty) {
      return null;
    }

    /*
     * Normal case:
     *
     * sender_id   = user who sent the event
     * receiver_id = logged-in user
     *
     * Example:
     * user_1 sends to user_2
     *
     * sender_id   = user_1
     * receiver_id = user_2
     *
     * Current user = user_2
     *
     * Remote user = user_1
     */

    if (senderId != _currentUserId) {
      return senderId;
    }

    /*
     * If sender_id is our own ID, check receiver_id.
     *
     * This handles a backend payload where the IDs are reversed.
     */

    if (receiverId != null &&
        receiverId.isNotEmpty &&
        receiverId != _currentUserId) {
      return receiverId;
    }

    return null;
  }

  // ------------------------------------------------------------
  // Incoming message
  // ------------------------------------------------------------

  void _onMessageReceived(
    Map<String, dynamic> data,
  ) {
    final senderId = _stringValue(
      data['sender_id'],
    );

    final receiverId = _stringValue(
      data['receiver_id'],
    );

    debugPrint('📨 MESSAGE EVENT');
    debugPrint('sender_id   = $senderId');
    debugPrint('receiver_id = $receiverId');
    debugPrint('my user id  = $_currentUserId');

    final remoteUserId = _getRemoteUserId(
      senderId,
      receiverId,
    );

    if (remoteUserId == null) {
      debugPrint(
        '⚠️ Could not determine remote sender.',
      );
      return;
    }

    debugPrint(
      '✅ ACTUAL REMOTE USER = $remoteUserId',
    );

    /*
     * IMPORTANT:
     *
     * ChatMessage.senderId must contain the actual
     * remote user's ID for an incoming message.
     *
     * ChatMessage.receiverId must contain our ID.
     */

    final message = ChatMessage(
      id: _stringValue(data['id']) ?? '',
      chatId: _stringValue(data['chat_id']) ?? '',
      senderId: remoteUserId,
      receiverId: _currentUserId!,
      message: _stringValue(data['message']) ?? '',
      timestamp: DateTime.tryParse(
            _stringValue(data['timestamp']) ?? '',
          ) ??
          DateTime.now(),
      status: messageStatusFromString(
        _stringValue(data['status']),
      ),
    );

    final peerId = remoteUserId;

    final list = _messagesByPeer.putIfAbsent(
      peerId,
      () => [],
    );

    list.add(message);

    // Stop typing indicator.
    _typingByPeer[peerId] = false;

    _typingExpiryTimers[peerId]?.cancel();
    _typingExpiryTimers.remove(peerId);

    // Show top notification banner
    _bannerController.add(message);

    // If this chat is currently open on screen, mark seen immediately
    // so the sender gets the blue ticks in real time without reopening.
    if (peerId == _activePeerId) {
      markSeen(peerId);
    }

    notifyListeners();
  }

  // ------------------------------------------------------------
  // Incoming typing
  // ------------------------------------------------------------

void _onTypingReceived(
  Map<String, dynamic> data,
) {
  final senderId = _stringValue(data['sender_id']);
  final receiverId = _stringValue(data['receiver_id']);

  debugPrint('⌨️ TYPING EVENT');
  debugPrint('sender_id   = $senderId');
  debugPrint('receiver_id = $receiverId');
  debugPrint('my user id  = $_currentUserId');

  // 👇 Jo user type kar raha hai uski ID
  final typingUserId = senderId;

  if (typingUserId == null ||
      typingUserId.isEmpty ||
      typingUserId == _currentUserId) {
    return;
  }

  debugPrint('✅ TYPING USER ID = $typingUserId');

  final isTypingNow =
      data['is_typing'] as bool? ?? true;

  _typingByPeer[typingUserId] = isTypingNow;

  _typingExpiryTimers[typingUserId]?.cancel();
  _typingExpiryTimers.remove(typingUserId);

  if (isTypingNow) {
    _typingExpiryTimers[typingUserId] = Timer(
      AppConstants.typingExpiry,
      () {
        _typingByPeer[typingUserId] = false;
        _typingExpiryTimers.remove(typingUserId);
        notifyListeners();
      },
    );
  }

  notifyListeners();
}

  // ------------------------------------------------------------
  // Online / Offline
  // ------------------------------------------------------------

  void _setPeerOnline(
    String? peerId,
    bool online,
  ) {
    if (peerId == null || peerId.isEmpty) {
      return;
    }

    if (peerId == _currentUserId) {
      return;
    }

    _onlineByPeer[peerId] = online;

    notifyListeners();
  }

  // ------------------------------------------------------------
  // Message status
  // ------------------------------------------------------------

  void _updateOutgoingStatus(
    Map<String, dynamic> data,
    MessageStatus status,
  ) {
    final id = _stringValue(data['id']);

    if (id == null || id.isEmpty) {
      return;
    }

    String? peerId;

    final receiverId = _stringValue(
      data['receiver_id'],
    );

    if (receiverId != null &&
        receiverId.isNotEmpty &&
        receiverId != _currentUserId) {
      peerId = receiverId;
    }

    peerId ??= _findPeerForMessage(id);

    if (peerId == null) {
      return;
    }

    final list = _messagesByPeer[peerId];

    if (list == null) {
      return;
    }

    final index = list.indexWhere(
      (message) => message.id == id,
    );

    if (index == -1) {
      return;
    }

    if (_statusRank(list[index].status) >=
        _statusRank(status)) {
      return;
    }

    list[index] = list[index].copyWith(
      status: status,
    );

    notifyListeners();
  }

  String? _findPeerForMessage(String id) {
    for (final entry in _messagesByPeer.entries) {
      final exists = entry.value.any(
        (message) => message.id == id,
      );

      if (exists) {
        return entry.key;
      }
    }

    return null;
  }

  int _statusRank(MessageStatus status) {
    switch (status) {
      case MessageStatus.sending:
        return 0;

      case MessageStatus.sent:
        return 1;

      case MessageStatus.delivered:
        return 2;

      case MessageStatus.seen:
        return 3;
    }
  }

  // ------------------------------------------------------------
  // Send message
  // ------------------------------------------------------------

  void sendMessage(
    String peerId,
    String text,
  ) {
    final trimmed = text.trim();

    if (trimmed.isEmpty ||
        _currentUserId == null) {
      return;
    }

    final message = ChatMessage(
      id: _generateId(),
      chatId: _chatIdFor(
        _currentUserId!,
        peerId,
      ),
      senderId: _currentUserId!,
      receiverId: peerId,
      message: trimmed,
      timestamp: DateTime.now(),
      status: MessageStatus.sending,
    );

    final list = _messagesByPeer.putIfAbsent(
      peerId,
      () => [],
    );

    list.add(message);

    notifyListeners();

    _socketService.send(
      message.toJson(),
    );
  }

  // ------------------------------------------------------------
  // Typing
  // ------------------------------------------------------------

  void notifyTyping(String peerId) {
    _typingDebounceTimers[peerId]?.cancel();

    _sendTypingEvent(
      peerId,
      true,
    );

    _typingDebounceTimers[peerId] = Timer(
      AppConstants.typingDebounce,
      () {
        _typingDebounceTimers.remove(peerId);
      },
    );
  }

  void notifyStoppedTyping(String peerId) {
    _typingDebounceTimers[peerId]?.cancel();
    _typingDebounceTimers.remove(peerId);

    _sendTypingEvent(
      peerId,
      false,
    );
  }

  void _sendTypingEvent(
    String peerId,
    bool isTyping,
  ) {
    if (_currentUserId == null) {
      return;
    }

    _socketService.send({
      'type': 'typing',
      'chat_id': _chatIdFor(
        _currentUserId!,
        peerId,
      ),
      'sender_id': _currentUserId!,
      'receiver_id': peerId,
      'is_typing': isTyping,
    });
  }

  // ------------------------------------------------------------
  // Mark seen
  // ------------------------------------------------------------

  void markSeen(String peerId) {
    final list = _messagesByPeer[peerId];

    if (list == null ||
        _currentUserId == null) {
      return;
    }

    var changed = false;

    for (var i = 0; i < list.length; i++) {
      final message = list[i];

      if (message.senderId == peerId &&
          message.status != MessageStatus.seen) {
        list[i] = message.copyWith(
          status: MessageStatus.seen,
        );

        _socketService.send({
          'type': 'seen',
          'id': message.id,
          'chat_id': message.chatId,
          'receiver_id': peerId,
        });

        changed = true;
      }
    }

    if (changed) {
      notifyListeners();
    }
  }

  // ------------------------------------------------------------
  // Helpers
  // ------------------------------------------------------------

  String _chatIdFor(
    String a,
    String b,
  ) {
    final ids = [a, b]..sort();

    return 'chat_${ids.join('_')}';
  }

  String _generateId() {
    return 'msg_${DateTime.now().microsecondsSinceEpoch}_'
        '${_random.nextInt(99999)}';
  }

  String? _stringValue(dynamic value) {
    if (value == null) {
      return null;
    }

    return value.toString();
  }

  // ------------------------------------------------------------
  // Dispose
  // ------------------------------------------------------------

  @override
  void dispose() {
    _messageSub?.cancel();
    _stateSub?.cancel();
    _highlightTimer?.cancel();

    for (final timer in _typingExpiryTimers.values) {
      timer.cancel();
    }

    for (final timer in _typingDebounceTimers.values) {
      timer.cancel();
    }

    _typingExpiryTimers.clear();
    _typingDebounceTimers.clear();

    _bannerController.close();

    _socketService.dispose();

    super.dispose();
  }
}