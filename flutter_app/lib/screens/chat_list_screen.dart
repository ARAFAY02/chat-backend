import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/chat_provider.dart';
import '../services/websocket_service.dart';
import '../theme/app_theme.dart';
import '../utils/app_constants.dart';
import '../widgets/online_status.dart';
import 'chat_screen.dart';

class ChatListScreen extends StatefulWidget {
  const ChatListScreen({super.key});

  @override
  State<ChatListScreen> createState() => _ChatListScreenState();
}

class _ChatListScreenState extends State<ChatListScreen> {
  final TextEditingController _searchController = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  /// For this demo, the "conversation list" is just the other demo
  /// user(s) besides whoever is currently logged in. Kept generic so
  /// adding more demo users later doesn't require touching this logic.
  List<String> _peerIds(String currentUserId) {
    const allDemoUsers = [AppConstants.demoUser1Id, AppConstants.demoUser2Id];
    return allDemoUsers.where((id) => id != currentUserId).toList();
  }

  @override
  Widget build(BuildContext context) {
    final chatProvider = context.watch<ChatProvider>();
    final currentUserId = chatProvider.currentUserId;

    if (currentUserId == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final peers = _peerIds(currentUserId)
        .where((id) => AppConstants.nameForUserId(id)
            .toLowerCase()
            .contains(_query.toLowerCase()))
        .toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Chats'),
        actions: [
          _ConnectionBadge(state: chatProvider.connectionState),
          const SizedBox(width: 8),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
            child: TextField(
              controller: _searchController,
              onChanged: (value) => setState(() => _query = value),
              decoration: const InputDecoration(
                hintText: 'Search',
                prefixIcon: Icon(Icons.search, color: AppColors.textSecondary),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Signed in as ${AppConstants.nameForUserId(currentUserId)}',
                style: const TextStyle(
                    fontSize: 12, color: AppColors.textSecondary),
              ),
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: peers.isEmpty
                ? const Center(child: Text('No conversations'))
                : ListView.separated(
                    itemCount: peers.length,
                    separatorBuilder: (_, __) =>
                        const Divider(height: 1, indent: 76),
                    itemBuilder: (context, index) {
                      final peerId = peers[index];
                      return _ChatListTile(peerId: peerId);
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _ChatListTile extends StatelessWidget {
  final String peerId;

  const _ChatListTile({required this.peerId});

  @override
  Widget build(BuildContext context) {
    final chatProvider = context.watch<ChatProvider>();
    final name = AppConstants.nameForUserId(peerId);
    final lastMessage = chatProvider.lastMessageWith(peerId);
    final online = chatProvider.isOnline(peerId);
    final unread = chatProvider.unreadCountWith(peerId);

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: Stack(
        children: [
          CircleAvatar(
            radius: 26,
            backgroundColor: AppColors.primary.withOpacity(0.15),
            child: Text(
              name.isNotEmpty ? name[0].toUpperCase() : '?',
              style: const TextStyle(
                color: AppColors.primary,
                fontWeight: FontWeight.bold,
                fontSize: 18,
              ),
            ),
          ),
          Positioned(
            right: 0,
            bottom: 0,
            child: OnlineStatusDot(isOnline: online),
          ),
        ],
      ),
      title: Text(
        name,
        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15.5),
      ),
      subtitle: Text(
        lastMessage?.message ?? 'Say hello 👋',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(color: AppColors.textSecondary, fontSize: 13.5),
      ),
      trailing: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            lastMessage != null ? _formatTime(lastMessage.timestamp) : '',
            style: const TextStyle(fontSize: 11.5, color: AppColors.textSecondary),
          ),
          const SizedBox(height: 6),
          if (unread > 0)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
              decoration: BoxDecoration(
                color: AppColors.unreadBadge,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                '$unread',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
        ],
      ),
      onTap: () {
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => ChatScreen(peerId: peerId)),
        );
      },
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

class _ConnectionBadge extends StatelessWidget {
  final SocketConnectionState state;

  const _ConnectionBadge({required this.state});

  @override
  Widget build(BuildContext context) {
    late final String label;
    late final Color color;
    switch (state) {
      case SocketConnectionState.connected:
        label = 'Connected';
        color = AppColors.online;
        break;
      case SocketConnectionState.connecting:
        label = 'Connecting';
        color = Colors.amber;
        break;
      case SocketConnectionState.reconnecting:
        label = 'Reconnecting';
        color = Colors.amber;
        break;
      case SocketConnectionState.disconnected:
        label = 'Offline';
        color = Colors.redAccent;
        break;
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 4),
        Text(label, style: const TextStyle(color: Colors.white, fontSize: 11)),
      ],
    );
  }
}
