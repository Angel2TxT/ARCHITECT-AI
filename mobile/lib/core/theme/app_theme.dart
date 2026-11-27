import 'package:flutter/material.dart';
import 'package:movil_architect/core/theme/app_colors.dart';
import 'package:movil_architect/core/theme/architect_theme_tokens.dart';

abstract final class AppTheme {
  static ThemeData get light {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      colorScheme: ColorScheme.fromSeed(
        seedColor: Colors.black,
        brightness: Brightness.light,
        surface: AppColors.dashboardSurface,
      ).copyWith(
        primary: AppColors.ink,
        onPrimary: Colors.white,
        secondary: const Color(0xFF52525B),
        onSecondary: Colors.white,
        surfaceContainerLowest: Colors.white,
        surfaceContainerLow: const Color(0xFFF9F9FB),
        surfaceContainer: const Color(0xFFF3F4F6),
        surfaceContainerHigh: Colors.white,
        surfaceContainerHighest: const Color(0xFFE5E7EB),
        outline: const Color(0xFFD1D5DB),
        outlineVariant: const Color(0xFFE5E7EB),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: Color(0xFFD1D5DB), width: 1.2),
        ),
      ),
      datePickerTheme: const DatePickerThemeData(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: AppColors.ink),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.ink,
          foregroundColor: Colors.white,
        ),
      ),
      fontFamily: ArchitectThemeTokens.textFontFamily,
      fontFamilyFallback: ArchitectThemeTokens.fontFallback,
      textTheme: ArchitectThemeTokens.buildTextTheme(
        primaryColor: ArchitectThemeTokens.light.textPrimary,
        secondaryColor: ArchitectThemeTokens.light.textSecondary,
      ),
      scaffoldBackgroundColor: AppColors.dashboardSurface,
      cardColor: Colors.white,
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.dashboardSurface,
        foregroundColor: AppColors.ink,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? Colors.white
              : AppColors.ink,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? AppColors.ink
              : const Color(0xFFD8D8DC),
        ),
        trackOutlineColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? Colors.transparent
              : const Color(0xFF9A9AA0),
        ),
        overlayColor: WidgetStateProperty.all(
          AppColors.ink.withValues(alpha: 0.08),
        ),
      ),
      extensions: const [ArchitectThemeTokens.light],
    );
  }

  static ThemeData get dark {
    const surface = Color(0xFF0B0B0B);
    const card = Color(0xFF171717);
    const onSurface = Color(0xFFF5F5F5);

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: ColorScheme.fromSeed(
        seedColor: Colors.white,
        brightness: Brightness.dark,
        surface: surface,
        onSurface: onSurface,
      ).copyWith(
        primary: onSurface,
        onPrimary: surface,
        secondary: const Color(0xFFABABB0),
        onSecondary: surface,
        error: const Color(0xFFCF8585),
        surfaceContainerLow: const Color(0xFF121212),
        surfaceContainer: card,
        surfaceContainerHigh: const Color(0xFF1D1D1D),
        surfaceContainerHighest: const Color(0xFF262626),
        outline: const Color(0xFF2A2A2A),
        outlineVariant: const Color(0xFF2A2A2A),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: const Color(0xFF141417),
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: Color(0xFF3F3F46), width: 1.2),
        ),
      ),
      datePickerTheme: const DatePickerThemeData(
        backgroundColor: Color(0xFF141417),
        surfaceTintColor: Colors.transparent,
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: onSurface),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: Colors.white,
          foregroundColor: const Color(0xFF111111),
        ),
      ),
      fontFamily: ArchitectThemeTokens.textFontFamily,
      fontFamilyFallback: ArchitectThemeTokens.fontFallback,
      textTheme: ArchitectThemeTokens.buildTextTheme(
        primaryColor: ArchitectThemeTokens.dark.textPrimary,
        secondaryColor: ArchitectThemeTokens.dark.textSecondary,
      ),
      scaffoldBackgroundColor: surface,
      cardColor: card,
      appBarTheme: const AppBarTheme(
        backgroundColor: surface,
        foregroundColor: onSurface,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
      ),
      dividerColor: const Color(0xFF3A3A3E),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? Colors.white
              : const Color(0xFFF2F2F7),
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? const Color(0xFF8E8E93)
              : const Color(0xFF3A3A3E),
        ),
        trackOutlineColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? Colors.transparent
              : const Color(0xFF6C6C70),
        ),
        overlayColor: WidgetStateProperty.all(
          Colors.white.withValues(alpha: 0.08),
        ),
      ),
      extensions: const [ArchitectThemeTokens.dark],
    );
  }
}
