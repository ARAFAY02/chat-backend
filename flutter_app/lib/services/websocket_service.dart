import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../utils/app_constants.dart';

enum SocketConnectionState { disconnected, connecting, connected, reconnecting }

/// Thin wrapper around `dart:io`'s [WebSocket] that adds:
///  - a clean connect/disconnect API
///  - a broadcast stream of decoded JSON messages
///  - a stream of connection-state changes
///  - automatic reconnection with exponential backoff
///
/// The UI/provider layer never touches [WebSocket] directly — it only
/// sees streams and a couple of methods, so raw socket handling stays
/// fully out of widgets and providers.
class WebSocketService {
  WebSocket? _socket;
  StreamSubscription? _socketSubscription;

  String? _userId;
  bool _manuallyDisconnected = false;
  Duration _currentReconnectDelay = AppConstants.initialReconnectDelay;
  Timer? _reconnectTimer;

  final StreamController<Map<String, dynamic>> _messageController =
      StreamController<Map<String, dynamic>>.broadcast();
  final StreamController<SocketConnectionState> _stateController =
      StreamController<SocketConnectionState>.broadcast();

  SocketConnectionState _state = SocketConnectionState.disconnected;

  Stream<Map<String, dynamic>> get messages => _messageController.stream;
  Stream<SocketConnectionState> get connectionState => _stateController.stream;
  SocketConnectionState get state => _state;

  bool get isConnected => _state == SocketConnectionState.connected;

  /// Connects (or reconnects) as [userId]. Safe to call once; internal
  /// reconnection logic re-uses the same userId automatically.
  Future<void> connect(String userId) async {
    _userId = userId;
    _manuallyDisconnected = false;
    await _openSocket();
  }

  Future<void> _openSocket() async {
    if (_userId == null) return;

    _setState(
      _state == SocketConnectionState.disconnected
          ? SocketConnectionState.connecting
          : SocketConnectionState.reconnecting,
    );

    try {
      final url = AppConstants.wsUrlFor(_userId!);
      final socket = await WebSocket.connect(url).timeout(
        const Duration(seconds: 8),
      );
      _socket = socket;
      _currentReconnectDelay = AppConstants.initialReconnectDelay;
      _setState(SocketConnectionState.connected);

      _socketSubscription = socket.listen(
        _onRawData,
        onDone: _onSocketClosed,
        onError: (_) => _onSocketClosed(),
        cancelOnError: true,
      );
    } catch (_) {
      _scheduleReconnect();
    }
  }

  void _onRawData(dynamic raw) {
    if (raw is! String) return;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        _messageController.add(decoded);
      }
    } catch (_) {
      // Ignore malformed frames rather than crashing the stream.
    }
  }

  void _onSocketClosed() {
    _socketSubscription?.cancel();
    _socketSubscription = null;
    _socket = null;

    if (_manuallyDisconnected) {
      _setState(SocketConnectionState.disconnected);
      return;
    }
    _scheduleReconnect();
  }

  void _scheduleReconnect() {
    _setState(SocketConnectionState.reconnecting);
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(_currentReconnectDelay, () {
      if (_manuallyDisconnected) return;
      _openSocket();
    });

    // Exponential backoff, capped at maxReconnectDelay.
    final nextMillis = (_currentReconnectDelay.inMilliseconds * 2)
        .clamp(0, AppConstants.maxReconnectDelay.inMilliseconds);
    _currentReconnectDelay = Duration(milliseconds: nextMillis);
  }

  /// Sends a JSON-encodable payload. No-op (silently) if not connected —
  /// callers that need delivery guarantees should check [isConnected] or
  /// handle it via message status in the provider.
  void send(Map<String, dynamic> payload) {
    final socket = _socket;
    if (socket == null || _state != SocketConnectionState.connected) return;
    socket.add(jsonEncode(payload));
  }

  void disconnect() {
    _manuallyDisconnected = true;
    _reconnectTimer?.cancel();
    _socketSubscription?.cancel();
    _socket?.close();
    _socket = null;
    _setState(SocketConnectionState.disconnected);
  }

  void dispose() {
    disconnect();
    _messageController.close();
    _stateController.close();
  }

  void _setState(SocketConnectionState newState) {
    _state = newState;
    _stateController.add(newState);
  }
}
