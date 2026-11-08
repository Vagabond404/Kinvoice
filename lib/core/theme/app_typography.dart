import 'package:flutter/material.dart';
import 'app_colors.dart';

/// Semantic typography tokens for Kinvoice, enforcing Inter with weights 400, 500, 600, and 700.
abstract final class AppTypography {
  static const String fontFamily = 'Inter';

  // Font Weights
  static const FontWeight regular = FontWeight.w400;
  static const FontWeight medium = FontWeight.w500;
  static const FontWeight semiBold = FontWeight.w600;
  static const FontWeight bold = FontWeight.w700;

  /// Helper generating an Inter-based [TextStyle].
  static TextStyle interStyle({
    required double fontSize,
    required FontWeight fontWeight,
    required double height,
    required Color color,
    double? letterSpacing,
  }) {
    return TextStyle(
      fontFamily: fontFamily,
      fontFamilyFallback: const ['Roboto', 'sans-serif'],
      fontSize: fontSize,
      fontWeight: fontWeight,
      height: height,
      color: color,
      letterSpacing: letterSpacing,
    );
  }

  /// Generates a standardized Material [TextTheme] for Kinvoice with Inter font styling.
  static TextTheme createTextTheme({
    required Color primaryColor,
    required Color secondaryColor,
  }) {
    return TextTheme(
      // Display Styles
      displayLarge: interStyle(
        fontSize: 40,
        fontWeight: bold,
        height: 1.2,
        color: primaryColor,
        letterSpacing: -0.8,
      ),
      displayMedium: interStyle(
        fontSize: 32,
        fontWeight: bold,
        height: 1.25,
        color: primaryColor,
        letterSpacing: -0.6,
      ),
      displaySmall: interStyle(
        fontSize: 28,
        fontWeight: semiBold,
        height: 1.28,
        color: primaryColor,
        letterSpacing: -0.4,
      ),

      // Headline Styles
      headlineLarge: interStyle(
        fontSize: 24,
        fontWeight: semiBold,
        height: 1.33,
        color: primaryColor,
        letterSpacing: -0.3,
      ),
      headlineMedium: interStyle(
        fontSize: 20,
        fontWeight: semiBold,
        height: 1.4,
        color: primaryColor,
        letterSpacing: -0.2,
      ),
      headlineSmall: interStyle(
        fontSize: 18,
        fontWeight: semiBold,
        height: 1.44,
        color: primaryColor,
      ),

      // Title Styles
      titleLarge: interStyle(
        fontSize: 16,
        fontWeight: semiBold,
        height: 1.5,
        color: primaryColor,
      ),
      titleMedium: interStyle(
        fontSize: 14,
        fontWeight: medium,
        height: 1.43,
        color: primaryColor,
      ),
      titleSmall: interStyle(
        fontSize: 13,
        fontWeight: medium,
        height: 1.38,
        color: secondaryColor,
      ),

      // Body Styles
      bodyLarge: interStyle(
        fontSize: 16,
        fontWeight: regular,
        height: 1.5,
        color: primaryColor,
      ),
      bodyMedium: interStyle(
        fontSize: 14,
        fontWeight: regular,
        height: 1.43,
        color: primaryColor,
      ),
      bodySmall: interStyle(
        fontSize: 12,
        fontWeight: regular,
        height: 1.33,
        color: secondaryColor,
      ),

      // Label Styles
      labelLarge: interStyle(
        fontSize: 14,
        fontWeight: medium,
        height: 1.43,
        color: primaryColor,
      ),
      labelMedium: interStyle(
        fontSize: 12,
        fontWeight: medium,
        height: 1.33,
        color: secondaryColor,
      ),
      labelSmall: interStyle(
        fontSize: 11,
        fontWeight: regular,
        height: 1.27,
        color: secondaryColor,
      ),
    );
  }

  /// Light theme typography snapshot.
  static final TextTheme lightTextTheme = createTextTheme(
    primaryColor: AppColors.textPrimaryLight,
    secondaryColor: AppColors.textSecondaryLight,
  );

  /// Dark theme typography snapshot.
  static final TextTheme darkTextTheme = createTextTheme(
    primaryColor: AppColors.textPrimaryDark,
    secondaryColor: AppColors.textSecondaryDark,
  );
}
