import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Small colored dot representing online/offline presence. Used both
/// as an avatar overlay (chat list) and inline next to a name (app bar).
class OnlineStatusDot extends StatelessWidget {
  final bool isOnline;
  final double size;
  final bool withBorder;

  const OnlineStatusDot({
    super.key,
    required this.isOnline,
    this.size = 12,
    this.withBorder = true,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: isOnline ? AppColors.online : AppColors.offline,
        shape: BoxShape.circle,
        border: withBorder ? Border.all(color: Colors.white, width: 2) : null,
      ),
    );
  }
}

/// "Online" / "Offline" text label, e.g. for the chat screen app bar.
class OnlineStatusLabel extends StatelessWidget {
  final bool isOnline;

  const OnlineStatusLabel({super.key, required this.isOnline});

  @override
  Widget build(BuildContext context) {
    return Text(
      isOnline ? 'Online' : 'Offline',
      style: TextStyle(
        fontSize: 12,
        color: isOnline ? Colors.white : Colors.white70,
      ),
    );
  }
}
