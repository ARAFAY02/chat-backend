import 'package:flutter/material.dart';

/// Central place for colors, typography, and ThemeData so screens and
/// widgets never hardcode a hex value directly.
class AppColors {
  AppColors._();

  static const Color primary = Color(0xFF128C7E); // WhatsApp-esque teal
  static const Color primaryDark = Color(0xFF075E54);
  static const Color accent = Color(0xFF25D366);

  static const Color background = Color(0xFFF7F8FA);
  static const Color chatBackground = Color(0xFFE9EDF0);

  static const Color bubbleSent = Color(0xFFDCF8C6);
  static const Color bubbleReceived = Color(0xFFFFFFFF);

  static const Color textPrimary = Color(0xFF1A1A1A);
  static const Color textSecondary = Color(0xFF6B7280);
  static const Color divider = Color(0xFFE5E7EB);

  static const Color online = Color(0xFF25D366);
  static const Color offline = Color(0xFF9CA3AF);

  static const Color unreadBadge = Color(0xFF25D366);
  static const Color tickSeen = Color(0xFF34B7F1);
  static const Color tickDefault = Color(0xFF9CA3AF);
}

class AppTheme {
  AppTheme._();

  static ThemeData get lightTheme {
    return ThemeData(
      useMaterial3: true,
      scaffoldBackgroundColor: AppColors.background,
      primaryColor: AppColors.primary,
      colorScheme: ColorScheme.fromSeed(
        seedColor: AppColors.primary,
        primary: AppColors.primary,
        brightness: Brightness.light,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        elevation: 0,
        centerTitle: false,
      ),
      textTheme: const TextTheme(
        titleLarge: TextStyle(
          fontWeight: FontWeight.w700,
          color: AppColors.textPrimary,
        ),
        titleMedium: TextStyle(
          fontWeight: FontWeight.w600,
          color: AppColors.textPrimary,
        ),
        bodyLarge: TextStyle(color: AppColors.textPrimary, fontSize: 15),
        bodyMedium: TextStyle(color: AppColors.textSecondary, fontSize: 13),
      ),
      dividerColor: AppColors.divider,
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(24),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }
}
