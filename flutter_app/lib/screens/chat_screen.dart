import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../main.dart' show routeObserver;
import '../providers/chat_provider.dart';
import '../theme/app_theme.dart';
import '../utils/app_constants.dart';
import '../widgets/chat_input.dart';
import '../widgets/chat_message_bubble.dart';
import '../widgets/online_status.dart';
import '../widgets/typing_indicator.dart';

class ChatScreen extends StatefulWidget {
  final String peerId;
  final String? initialTargetMessageId;

  const ChatScreen({
    super.key,
    required this.peerId,
    this.initialTargetMessageId,
  });

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> with RouteAware {
  final ScrollController _scrollController = ScrollController();
  final Map<String, GlobalKey> _messageKeys = {};

  // Cached here (not looked up in dispose()) because by the time
  // dispose() runs, this widget may already be deactivated and its
  // context is no longer safe to use for an inherited-widget lookup.
  ChatProvider? _chatProvider;

  bool _routeSubscribed = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      final provider = context.read<ChatProvider>();
      // Load any persisted history first so it's visible before we
      // mark things seen (harmless either order, but feels right).
      await provider.loadHistory(widget.peerId);
      if (!mounted) return;
      provider.markSeen(widget.peerId);

      if (widget.initialTargetMessageId != null) {
        provider.highlightMessage(widget.initialTargetMessageId!);
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _chatProvider = context.read<ChatProvider>();

    if (!_routeSubscribed) {
      final route = ModalRoute.of(context);
      if (route is PageRoute) {
        routeObserver.subscribe(this, route);
        _routeSubscribed = true;
      }
    }

    // This screen is being built, so it's the one currently on top -
    // mark it active right away (RouteAware callbacks below handle
    // every transition after this initial one).
    _chatProvider?.setActivePeer(widget.peerId);
  }

  // Called when the user navigates back to this screen (e.g. pops a
  // route that was covering it) - it's visible again.
  @override
  void didPopNext() {
    _chatProvider?.setActivePeer(widget.peerId);
    _chatProvider?.markSeen(widget.peerId);
  }

  // Called when another route is pushed on top of this one - this
  // chat is no longer the one visible on screen.
  @override
  void didPushNext() {
    _chatProvider?.setActivePeer(null);
  }

  @override
  void dispose() {
    routeObserver.unsubscribe(this);
    _chatProvider?.setActivePeer(null);
    _chatProvider?.notifyStoppedTyping(widget.peerId);
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    if (!_scrollController.hasClients) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    });
  }

  void _scrollToMessage(String messageId) {
    if (!_scrollController.hasClients) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;
      final key = _messageKeys[messageId];
      if (key?.currentContext != null) {
        Scrollable.ensureVisible(
          key!.currentContext!,
          duration: const Duration(milliseconds: 350),
          curve: Curves.easeInOut,
          alignment: 0.5,
        );
      } else {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        ).then((_) {
          if (!mounted) return;
          final lateKey = _messageKeys[messageId];
          if (lateKey?.currentContext != null) {
            Scrollable.ensureVisible(
              lateKey!.currentContext!,
              duration: const Duration(milliseconds: 250),
              curve: Curves.easeInOut,
              alignment: 0.5,
            );
          }
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final chatProvider = context.watch<ChatProvider>();
    final peerName = AppConstants.nameForUserId(widget.peerId);
    final peerOnline = chatProvider.isOnline(widget.peerId);
    final peerTyping = chatProvider.isTyping(widget.peerId);
    final messages = chatProvider.messagesWith(widget.peerId);
    final currentUserId = chatProvider.currentUserId;
    final highlightedId = chatProvider.highlightedMessageId;

    if (highlightedId != null) {
      _scrollToMessage(highlightedId);
    } else {
      _scrollToBottom();
    }

    return Scaffold(
      backgroundColor: AppColors.chatBackground,
      appBar: AppBar(
        titleSpacing: 0,
        title: Row(
          children: [
            Stack(
              children: [
                CircleAvatar(
                  radius: 18,
                  backgroundColor: Colors.white24,
                  child: Text(
                    peerName.isNotEmpty ? peerName[0].toUpperCase() : '?',
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                  ),
                ),
                Positioned(
                  right: 0,
                  bottom: 0,
                  child: OnlineStatusDot(isOnline: peerOnline, size: 10),
                ),
              ],
            ),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  peerName,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                peerTyping
                    ? const Text(
                        'typing...',
                        style: TextStyle(color: Colors.white70, fontSize: 12),
                      )
                    : OnlineStatusLabel(isOnline: peerOnline),
              ],
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: messages.isEmpty
                ? const Center(
                    child: Text(
                      'No messages yet. Say hello!',
                      style: TextStyle(color: AppColors.textSecondary),
                    ),
                  )
                : ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    itemCount: messages.length,
                    itemBuilder: (context, index) {
                      final message = messages[index];
                      final isMe = message.senderId == currentUserId;
                      final isHighlighted = highlightedId == message.id;
                      final key = _messageKeys.putIfAbsent(
                        message.id,
                        () => GlobalKey(),
                      );
                      return Container(
                        key: key,
                        child: ChatMessageBubble(
                          message: message,
                          isMe: isMe,
                          isHighlighted: isHighlighted,
                        ),
                      );
                    },
                  ),
          ),
          if (peerTyping) TypingIndicator(userName: peerName),
          ChatInput(
            onSend: (text) =>
                context.read<ChatProvider>().sendMessage(widget.peerId, text),
            onTyping: () =>
                context.read<ChatProvider>().notifyTyping(widget.peerId),
            onStoppedTyping: () =>
                context.read<ChatProvider>().notifyStoppedTyping(widget.peerId),
          ),
        ],
      ),
    );
  }
}