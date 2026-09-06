import 'package:flutter/material.dart';

/// Semantic color palette for Expense Tracker adhering to Material 3 design principles.
class AppColors {
  // Brand / Primary
  static const Color primary = Color(0xFF0F766E); // Modern Emerald Teal
  static const Color primaryLight = Color(0xFF14B8A6);
  static const Color primaryDark = Color(0xFF115E59);
  static const Color primaryContainerLight = Color(0xFFCCFBF1);
  static const Color primaryContainerDark = Color(0xFF134E4A);

  // Secondary
  static const Color secondary = Color(0xFF475569); // Slate Grey
  static const Color secondaryLight = Color(0xFF64748B);
  static const Color secondaryDark = Color(0xFF334155);

  // Financial Accents (Distinguishable in both Light and Dark themes)
  static const Color income = Color(0xFF10B981); // Emerald Green
  static const Color incomeContainerLight = Color(0xFFD1FAE5);
  static const Color incomeContainerDark = Color(0xFF064E3B);

  static const Color expense = Color(0xFFEF4444); // Crimson Red
  static const Color expenseContainerLight = Color(0xFFFEE2E2);
  static const Color expenseContainerDark = Color(0xFF7F1D1D);

  static const Color transfer = Color(0xFF3B82F6); // Cobalt Blue
  static const Color transferContainerLight = Color(0xFFDBEAFE);
  static const Color transferContainerDark = Color(0xFF1E3A8A);

  static const Color warning = Color(0xFFF59E0B); // Amber
  static const Color warningContainerLight = Color(0xFFFEF3C7);
  static const Color warningContainerDark = Color(0xFF78350F);

  static const Color success = Color(0xFF10B981);
  static const Color disabled = Color(0xFF94A3B8);

  // Backgrounds & Neutrals - Light Theme
  static const Color bgLight = Color(0xFFF8FAFC);
  static const Color surfaceLight = Color(0xFFFFFFFF);
  static const Color surfaceVariantLight = Color(0xFFF1F5F9);
  static const Color cardLight = Color(0xFFFFFFFF);
  static const Color textPrimaryLight = Color(0xFF0F172A);
  static const Color textSecondaryLight = Color(0xFF64748B);
  static const Color textTertiaryLight = Color(0xFF94A3B8);
  static const Color borderLight = Color(0xFFE2E8F0);
  static const Color dividerLight = Color(0xFFE2E8F0);

  // Backgrounds & Neutrals - Dark Theme
  static const Color bgDark = Color(0xFF0F172A);
  static const Color surfaceDark = Color(0xFF1E293B);
  static const Color surfaceVariantDark = Color(0xFF334155);
  static const Color cardDark = Color(0xFF1E293B);
  static const Color textPrimaryDark = Color(0xFFF8FAFC);
  static const Color textSecondaryDark = Color(0xFF94A3B8);
  static const Color textTertiaryDark = Color(0xFF64748B);
  static const Color borderDark = Color(0xFF334155);
  static const Color dividerDark = Color(0xFF334155);

  // High-contrast AMOLED Dark
  static const Color bgAmoled = Color(0xFF000000);
  static const Color surfaceAmoled = Color(0xFF121212);
  static const Color cardAmoled = Color(0xFF181818);
  static const Color borderAmoled = Color(0xFF272727);
}
