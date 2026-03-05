import 'package:flutter/material.dart';

/// Centralized color constants for the entire app.
class AppColors {
  AppColors._();

  // Primary green palette
  static const Color primary = Color(0xFF2E7D32);
  static const Color primaryLight = Color(0xFF4CAF50);
  static const Color primaryDark = Color(0xFF1B5E20);
  static const Color primarySurface = Color(0xFFE8F5E9);

  // Pengawas blue accent
  static const Color pengawas = Color(0xFF1565C0);
  static const Color pengawasLight = Color(0xFF42A5F5);
  static const Color pengawasSurface = Color(0xFFE3F2FD);

  // Security green accent
  static const Color security = Color(0xFF2E7D32);
  static const Color securityLight = Color(0xFF66BB6A);
  static const Color securitySurface = Color(0xFFE8F5E9);

  // Status colors
  static const Color success = Color(0xFF2E7D32);
  static const Color warning = Color(0xFFF9A825);
  static const Color error = Color(0xFFC62828);
  static const Color info = Color(0xFF1565C0);

  // Neutral palette
  static const Color background = Color(0xFFF5F7FA);
  static const Color surface = Color(0xFFFFFFFF);
  static const Color cardBorder = Color(0xFFE0E0E0);
  static const Color textPrimary = Color(0xFF1A1A2E);
  static const Color textSecondary = Color(0xFF6B7280);
  static const Color textHint = Color(0xFF9CA3AF);
  static const Color divider = Color(0xFFE5E7EB);

  // Navigation
  static const Color navActive = Color(0xFF2E7D32);
  static const Color navInactive = Color(0xFF9CA3AF);
  static const Color navIndicator = Color(0xFFE8F5E9);

  // Gradient helpers
  static List<Color> primaryGradient = [
    const Color(0xFF2E7D32),
    const Color(0xFF43A047),
  ];

  static List<Color> pengawasGradient = [
    const Color(0xFF1565C0),
    const Color(0xFF1E88E5),
  ];
}
