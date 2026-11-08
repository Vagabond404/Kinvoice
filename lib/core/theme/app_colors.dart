import 'package:flutter/material.dart';

/// Design system color tokens for Kinvoice, derived from the Google Stitch specification.
abstract final class AppColors {
  // Brand & Identity Tokens
  static const Color primary = Color(0xFF1E1B4B); // Deep Indigo
  static const Color accent = Color(0xFF6366F1); // Electric Violet

  // Background Tokens
  static const Color backgroundLight = Color(0xFFF8FAFC);
  static const Color backgroundDark = Color(0xFF0B0F19);

  // Surface Tokens
  static const Color surfaceLight = Color(0xFFFFFFFF);
  static const Color surfaceDark = Color(0xFF111827);

  // Surface Container Tokens
  static const Color surfaceContainerLight = Color(0xFFF1F5F9);
  static const Color surfaceContainerDark = Color(0xFF1F2937);

  // Typography Contrast Tokens
  static const Color textPrimaryLight = Color(0xFF0F172A);
  static const Color textPrimaryDark = Color(0xFFF9FAFB);

  static const Color textSecondaryLight = Color(0xFF64748B);
  static const Color textSecondaryDark = Color(0xFF9CA3AF);

  // Semantic Audio & Status Tokens (Stitch MCP Specification)
  static const Color success = Color(0xFF10B981); // Emerald Mint (VAD active / healthy)
  static const Color recording = Color(0xFFEF4444); // Coral Red (Active capture / stop)
  static const Color error = Color(0xFFEF4444); // Error / Alert Red
  static const Color warning = Color(0xFFF59E0B); // Warm Amber (Bookmarks / highlights)

  // Border & Hairline Tokens
  static const Color borderLight = Color(0xFFE2E8F0);
  static const Color borderDark = Color(0xFF374151);

  // Glassmorphic Overlays
  static const Color glassLight = Color(0xB8FFFFFF); // ~72% opacity white
  static const Color glassDark = Color(0xB8111827); // ~72% opacity dark surface
}

/// Custom ThemeExtension allowing easy access to Stitch semantic tokens.
@immutable
class KinvoiceColorsExtension extends ThemeExtension<KinvoiceColorsExtension> {
  const KinvoiceColorsExtension({
    required this.primary,
    required this.accent,
    required this.background,
    required this.surface,
    required this.surfaceContainer,
    required this.textPrimary,
    required this.textSecondary,
    required this.success,
    required this.recording,
    required this.warning,
    required this.border,
  });

  final Color primary;
  final Color accent;
  final Color background;
  final Color surface;
  final Color surfaceContainer;
  final Color textPrimary;
  final Color textSecondary;
  final Color success;
  final Color recording;
  final Color warning;
  final Color border;

  static const KinvoiceColorsExtension light = KinvoiceColorsExtension(
    primary: AppColors.primary,
    accent: AppColors.accent,
    background: AppColors.backgroundLight,
    surface: AppColors.surfaceLight,
    surfaceContainer: AppColors.surfaceContainerLight,
    textPrimary: AppColors.textPrimaryLight,
    textSecondary: AppColors.textSecondaryLight,
    success: AppColors.success,
    recording: AppColors.recording,
    warning: AppColors.warning,
    border: AppColors.borderLight,
  );

  static const KinvoiceColorsExtension dark = KinvoiceColorsExtension(
    primary: AppColors.accent,
    accent: AppColors.accent,
    background: AppColors.backgroundDark,
    surface: AppColors.surfaceDark,
    surfaceContainer: AppColors.surfaceContainerDark,
    textPrimary: AppColors.textPrimaryDark,
    textSecondary: AppColors.textSecondaryDark,
    success: AppColors.success,
    recording: AppColors.recording,
    warning: AppColors.warning,
    border: AppColors.borderDark,
  );

  @override
  KinvoiceColorsExtension copyWith({
    Color? primary,
    Color? accent,
    Color? background,
    Color? surface,
    Color? surfaceContainer,
    Color? textPrimary,
    Color? textSecondary,
    Color? success,
    Color? recording,
    Color? warning,
    Color? border,
  }) {
    return KinvoiceColorsExtension(
      primary: primary ?? this.primary,
      accent: accent ?? this.accent,
      background: background ?? this.background,
      surface: surface ?? this.surface,
      surfaceContainer: surfaceContainer ?? this.surfaceContainer,
      textPrimary: textPrimary ?? this.textPrimary,
      textSecondary: textSecondary ?? this.textSecondary,
      success: success ?? this.success,
      recording: recording ?? this.recording,
      warning: warning ?? this.warning,
      border: border ?? this.border,
    );
  }

  @override
  KinvoiceColorsExtension lerp(
    covariant ThemeExtension<KinvoiceColorsExtension>? other,
    double t,
  ) {
    if (other is! KinvoiceColorsExtension) return this;
    return KinvoiceColorsExtension(
      primary: Color.lerp(primary, other.primary, t) ?? primary,
      accent: Color.lerp(accent, other.accent, t) ?? accent,
      background: Color.lerp(background, other.background, t) ?? background,
      surface: Color.lerp(surface, other.surface, t) ?? surface,
      surfaceContainer:
          Color.lerp(surfaceContainer, other.surfaceContainer, t) ??
          surfaceContainer,
      textPrimary: Color.lerp(textPrimary, other.textPrimary, t) ?? textPrimary,
      textSecondary:
          Color.lerp(textSecondary, other.textSecondary, t) ?? textSecondary,
      success: Color.lerp(success, other.success, t) ?? success,
      recording: Color.lerp(recording, other.recording, t) ?? recording,
      warning: Color.lerp(warning, other.warning, t) ?? warning,
      border: Color.lerp(border, other.border, t) ?? border,
    );
  }
}
