
/// Centralized configuration so the server address, timing constants,
/// and other app-wide values only need to be changed in one place.
class AppConstants {
  AppConstants._();

  // ===========================================================================
  // SERVER CONFIGURATION
  // ===========================================================================

  /// Live Cloudflare Worker public domain.
  ///
  /// HTTP:
  /// https://chat-backend.arain20022.workers.dev
  ///
  /// WebSocket:
  /// wss://chat-backend.arain20022.workers.dev/ws/{userId}
  ///
  /// Set this to null or an empty string to use the local FastAPI backend.
  static const String? publicServerDomain =
      'chat-backend.arain20022.workers.dev';

  /// Local backend host.
  ///
  /// Used only when [publicServerDomain] is null or empty.
  static const String serverHost = '127.0.0.1';

  /// Local FastAPI port.
  static const int serverPort = 8000;

  // ===========================================================================
  // WEBSOCKET
  // ===========================================================================

  /// Returns the WebSocket URL for the given user.
  ///
  /// LIVE:
  /// wss://chat-backend.arain20022.workers.dev/ws/user_1
  ///
  /// LOCAL FALLBACK:
  /// ws://127.0.0.1:8000/ws/user_1
  static String wsUrlFor(String userId) {
    if (publicServerDomain != null &&
        publicServerDomain!.trim().isNotEmpty) {
      return 'wss://$publicServerDomain/ws/$userId';
    }

    return 'ws://$serverHost:$serverPort/ws/$userId';
  }

  // ===========================================================================
  // CHAT HISTORY
  // ===========================================================================

  /// Returns the REST API URL for fetching persisted chat history
  /// between two users.
  ///
  /// LIVE:
  /// https://chat-backend.arain20022.workers.dev/messages/user_1/user_2
  ///
  /// LOCAL FALLBACK:
  /// http://127.0.0.1:8000/messages/user_1/user_2
  static String historyUrlFor(
    String userA,
    String userB,
  ) {
    if (publicServerDomain != null &&
        publicServerDomain!.trim().isNotEmpty) {
      return 'https://$publicServerDomain/messages/$userA/$userB';
    }

    return 'http://$serverHost:$serverPort/messages/$userA/$userB';
  }

  // ===========================================================================
  // RECONNECTION
  // ===========================================================================

  /// Initial delay before attempting to reconnect.
  static const Duration initialReconnectDelay =
      Duration(seconds: 2);

  /// Maximum delay between reconnect attempts.
  static const Duration maxReconnectDelay =
      Duration(seconds: 30);

  // ===========================================================================
  // TYPING INDICATOR
  // ===========================================================================

  /// Delay used to debounce typing events.
  static const Duration typingDebounce =
      Duration(milliseconds: 600);

  /// How long the typing indicator remains visible
  /// if another typing event is not received.
  static const Duration typingExpiry =
      Duration(seconds: 3);

  // ===========================================================================
  // DEMO USERS
  // ===========================================================================

  /// First demo user.
  static const String demoUser1Id = 'user_1';

  static const String demoUser1Name = 'Abdul Rafay';

  /// Second demo user.
  static const String demoUser2Id = 'user_2';

  static const String demoUser2Name = 'Khizar Hussain';

  // ===========================================================================
  // USER NAME HELPER
  // ===========================================================================

  /// Returns the display name for a demo user ID.
  ///
  /// Unknown IDs are returned as-is.
  static String nameForUserId(String userId) {
    switch (userId) {
      case demoUser1Id:
        return demoUser1Name;

      case demoUser2Id:
        return demoUser2Name;

      default:
        return userId;
    }
  }
}
