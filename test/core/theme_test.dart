import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kinvoice/core/theme/app_colors.dart';
import 'package:kinvoice/core/theme/app_theme.dart';
import 'package:kinvoice/core/theme/app_typography.dart';

void main() {
  group('Design System Theme Tokens Verification', () {
    test('Verifies required brand color tokens', () {
      expect(AppColors.primary, const Color(0xFF1E1B4B));
      expect(AppColors.accent, const Color(0xFF6366F1));
    });

    test('Verifies light & dark background tokens', () {
      expect(AppColors.backgroundLight, const Color(0xFFF8FAFC));
      expect(AppColors.backgroundDark, const Color(0xFF0B0F19));
    });

    test('Verifies light & dark surface tokens', () {
      expect(AppColors.surfaceLight, const Color(0xFFFFFFFF));
      expect(AppColors.surfaceDark, const Color(0xFF111827));
    });

    test('Verifies light & dark surface container tokens', () {
      expect(AppColors.surfaceContainerLight, const Color(0xFFF1F5F9));
      expect(AppColors.surfaceContainerDark, const Color(0xFF1F2937));
    });

    test('Verifies light & dark text primary contrast tokens', () {
      expect(AppColors.textPrimaryLight, const Color(0xFF0F172A));
      expect(AppColors.textPrimaryDark, const Color(0xFFF9FAFB));
    });

    test('Verifies light & dark text secondary contrast tokens', () {
      expect(AppColors.textSecondaryLight, const Color(0xFF64748B));
      expect(AppColors.textSecondaryDark, const Color(0xFF9CA3AF));
    });

    test('Verifies semantic Stitch tokens', () {
      expect(AppColors.success, const Color(0xFF10B981));
      expect(AppColors.recording, const Color(0xFFEF4444));
      expect(AppColors.warning, const Color(0xFFF59E0B));
      expect(AppColors.borderLight, const Color(0xFFE2E8F0));
      expect(AppColors.borderDark, const Color(0xFF374151));
    });
  });

  group('Material 3 ThemeData Brightness & Structure', () {
    test('Light theme is correctly configured for Material 3 and Light Brightness', () {
      final theme = AppTheme.lightTheme;

      expect(theme.useMaterial3, isTrue);
      expect(theme.brightness, Brightness.light);
      expect(theme.colorScheme.brightness, Brightness.light);
      expect(theme.scaffoldBackgroundColor, AppColors.backgroundLight);
      expect(theme.colorScheme.primary, AppColors.primary);
      expect(theme.colorScheme.secondary, AppColors.accent);
      expect(theme.colorScheme.surface, AppColors.surfaceLight);
      expect(theme.colorScheme.surfaceContainer, AppColors.surfaceContainerLight);
      expect(theme.colorScheme.onSurface, AppColors.textPrimaryLight);
      expect(theme.colorScheme.onSurfaceVariant, AppColors.textSecondaryLight);

      final ext = theme.extension<KinvoiceColorsExtension>();
      expect(ext, isNotNull);
      expect(ext?.primary, AppColors.primary);
      expect(ext?.background, AppColors.backgroundLight);
    });

    test('Dark theme is correctly configured for Material 3 and Dark Brightness', () {
      final theme = AppTheme.darkTheme;

      expect(theme.useMaterial3, isTrue);
      expect(theme.brightness, Brightness.dark);
      expect(theme.colorScheme.brightness, Brightness.dark);
      expect(theme.scaffoldBackgroundColor, AppColors.backgroundDark);
      expect(theme.colorScheme.surface, AppColors.surfaceDark);
      expect(theme.colorScheme.surfaceContainer, AppColors.surfaceContainerDark);
      expect(theme.colorScheme.onSurface, AppColors.textPrimaryDark);
      expect(theme.colorScheme.onSurfaceVariant, AppColors.textSecondaryDark);

      final ext = theme.extension<KinvoiceColorsExtension>();
      expect(ext, isNotNull);
      expect(ext?.background, AppColors.backgroundDark);
      expect(ext?.surface, AppColors.surfaceDark);
    });
  });

  group('AppTypography Tokens Verification', () {
    test('Verifies font family and standard weight constants', () {
      expect(AppTypography.fontFamily, 'Inter');
      expect(AppTypography.regular, FontWeight.w400);
      expect(AppTypography.medium, FontWeight.w500);
      expect(AppTypography.semiBold, FontWeight.w600);
      expect(AppTypography.bold, FontWeight.w700);
    });

    test('Verifies Light and Dark TextThemes define expected typography scales', () {
      expect(AppTypography.lightTextTheme.displayLarge?.fontWeight, FontWeight.w700);
      expect(AppTypography.lightTextTheme.headlineLarge?.fontWeight, FontWeight.w600);
      expect(AppTypography.lightTextTheme.bodyLarge?.fontWeight, FontWeight.w400);
      expect(AppTypography.lightTextTheme.labelMedium?.fontWeight, FontWeight.w500);

      expect(AppTypography.darkTextTheme.displayLarge?.fontWeight, FontWeight.w700);
      expect(AppTypography.darkTextTheme.headlineLarge?.fontWeight, FontWeight.w600);
      expect(AppTypography.darkTextTheme.bodyLarge?.fontWeight, FontWeight.w400);
      expect(AppTypography.darkTextTheme.labelMedium?.fontWeight, FontWeight.w500);
    });
  });
}
