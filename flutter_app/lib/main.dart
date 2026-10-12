import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'models/chat_message.dart';
import 'providers/chat_provider.dart';
import 'screens/chat_screen.dart';
import 'screens/login_screen.dart';
import 'theme/app_theme.dart';
import 'utils/app_constants.dart';

final GlobalKey<NavigatorState> navigatorKey =
    GlobalKey<NavigatorState>();

final RouteObserver<PageRoute> routeObserver =
    RouteObserver<PageRoute>();

void main() {
  runApp(const ChatDemoApp());
}

class ChatDemoApp extends StatelessWidget {
  const ChatDemoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => ChatProvider(),
      child: MaterialApp(
        navigatorKey: navigatorKey,
        navigatorObservers: [routeObserver],
        title: 'Chat Demo',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.lightTheme,
        home: const LoginScreen(),
        builder: (context, child) {
          return IncomingMessageBannerHost(
            child: child ?? const SizedBox.shrink(),
          );
        },
      ),
    );
  }
}

class IncomingMessageBannerHost extends StatefulWidget {
  final Widget child;

  const IncomingMessageBannerHost({
    super.key,
    required this.child,
  });

  @override
  State<IncomingMessageBannerHost> createState() =>
      _IncomingMessageBannerHostState();
}

class _IncomingMessageBannerHostState
    extends State<IncomingMessageBannerHost> {
  StreamSubscription<ChatMessage>? _sub;
  ChatMessage? _visibleMessage;
  Timer? _dismissTimer;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    _sub ??= context
        .read<ChatProvider>()
        .bannerMessages
        .listen(_showBanner);
  }

  void _showBanner(ChatMessage message) {
    _dismissTimer?.cancel();

    if (!mounted) return;

    setState(() {
      _visibleMessage = message;
    });

    _dismissTimer = Timer(
      const Duration(seconds: 4),
      () {
        if (!mounted) return;

        setState(() {
          _visibleMessage = null;
        });
      },
    );
  }

  void _dismiss() {
    _dismissTimer?.cancel();

    if (!mounted) return;

    setState(() {
      _visibleMessage = null;
    });
  }

  void _openChat(ChatMessage message) {
    _dismiss();

    final chatProvider = context.read<ChatProvider>();
    if (chatProvider.activePeerId == message.senderId) {
      // Already on ChatScreen with this user
      chatProvider.highlightMessage(message.id);
    } else {
      navigatorKey.currentState?.push(
        MaterialPageRoute(
          builder: (_) => ChatScreen(
            peerId: message.senderId,
            initialTargetMessageId: message.id,
          ),
        ),
      );
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    _dismissTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final message = _visibleMessage;

    return Stack(
      children: [
        widget.child,
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: SafeArea(
            child: IgnorePointer(
              ignoring: message == null,
              child: AnimatedSlide(
                duration: const Duration(
                  milliseconds: 250,
                ),
                curve: Curves.easeOut,
                offset: message == null
                    ? const Offset(0, -1.5)
                    : Offset.zero,
                child: AnimatedOpacity(
                  duration: const Duration(
                    milliseconds: 200,
                  ),
                  opacity: message == null ? 0 : 1,
                  child: message == null
                      ? const SizedBox.shrink()
                      : _TopBanner(
                          message: message,
                          onTap: () {
                            _openChat(message);
                          },
                          onDismiss: _dismiss,
                        ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
class _TopBanner extends StatelessWidget {
  final ChatMessage message;
  final VoidCallback onTap;
  final VoidCallback onDismiss;

  const _TopBanner({
    required this.message,
    required this.onTap,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    final senderName =
        AppConstants.nameForUserId(message.senderId);

    final displayName =
        senderName.isNotEmpty ? senderName : 'New Message';

    return GestureDetector(
      onTap: onTap,
      onVerticalDragEnd: (details) {
        if ((details.primaryVelocity ?? 0) < 0) {
          onDismiss();
        }
      },
      child: Container(
        margin: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 6,
        ),
        padding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 11,
        ),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: AppColors.primary.withOpacity(0.10),
            width: 1,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.10),
              blurRadius: 16,
              offset: const Offset(0, 5),
            ),
          ],
        ),
        child: Row(
          children: [
            CircleAvatar(
              radius: 20,
              backgroundColor:
                  AppColors.primary.withOpacity(0.10),
              child: Text(
                displayName[0].toUpperCase(),
                style: const TextStyle(
                  color: AppColors.primary,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),

            const SizedBox(width: 11),

            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    displayName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                      color: Colors.black87,
                    ),
                  ),

                  const SizedBox(height: 3),

                  Text(
                    message.message,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(width: 6),

            GestureDetector(
              onTap: onDismiss,
              child: Container(
                padding: const EdgeInsets.all(5),
                decoration: BoxDecoration(
                  color: Colors.grey.withOpacity(0.08),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.close_rounded,
                  size: 17,
                  color: Colors.grey,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
