import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/chat_provider.dart';
import '../theme/app_theme.dart';
import '../utils/app_constants.dart';
import 'chat_list_screen.dart';

/// Simple dev-only "login" screen: pick which demo user this device/
/// emulator instance represents, then connect to the backend as them.
/// Not a real auth flow — just enough to run two clients side by side.
class LoginScreen extends StatelessWidget {
  const LoginScreen({super.key});

  Future<void> _selectUser(BuildContext context, String userId) async {
    final chatProvider = context.read<ChatProvider>();
    await chatProvider.connectAs(userId);

    // Load saved history for every other demo user right away, so the
    // chat list screen's last-message previews and unread badges are
    // correct from the very first frame - not just after the user has
    // opened each chat at least once in this app session.
    final otherUserIds = [AppConstants.demoUser1Id, AppConstants.demoUser2Id]
        .where((id) => id != userId)
        .toList();
    await chatProvider.loadAllHistory(otherUserIds);

    if (!context.mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const ChatListScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.primary,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Icon(Icons.chat_bubble_rounded, color: Colors.white, size: 64),
              const SizedBox(height: 16),
              const Text(
                'Chat Demo',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 26,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                'Pick a demo user for this device',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white70, fontSize: 14),
              ),
              const SizedBox(height: 40),
              _UserButton(
                name: AppConstants.demoUser1Name,
                onTap: () => _selectUser(context, AppConstants.demoUser1Id),
              ),
              const SizedBox(height: 16),
              _UserButton(
                name: AppConstants.demoUser2Name,
                onTap: () => _selectUser(context, AppConstants.demoUser2Id),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _UserButton extends StatelessWidget {
  final String name;
  final VoidCallback onTap;

  const _UserButton({required this.name, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
          child: Row(
            children: [
              CircleAvatar(
                backgroundColor: AppColors.primary.withOpacity(0.12),
                child: Text(
                  name[0].toUpperCase(),
                  style: const TextStyle(
                    color: AppColors.primary,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Text(
                name,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
              ),
              const Spacer(),
              const Icon(Icons.arrow_forward_ios, size: 16, color: AppColors.textSecondary),
            ],
          ),
        ),
      ),
    );
  }
}
