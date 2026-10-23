import 'package:flutter/material.dart';
import 'package:movil_architect/core/theme/app_colors.dart';

abstract final class AppTheme {
  static ThemeData get light {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      colorScheme: ColorScheme.fromSeed(
        seedColor: Colors.black,
        brightness: Brightness.light,
        surface: AppColors.dashboardSurface,
      ),
      fontFamily: 'Roboto',
      textTheme: ThemeData(brightness: Brightness.light).textTheme.apply(
            fontFamily: 'Roboto',
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
    );
  }

  static ThemeData get dark {
    const surface = Color(0xFF121214);
    const card = Color(0xFF1C1C1F);
    const onSurface = Color(0xFFF2F2F7);

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: ColorScheme.fromSeed(
        seedColor: Colors.white,
        brightness: Brightness.dark,
        surface: surface,
        onSurface: onSurface,
      ).copyWith(
        surfaceContainerHighest: const Color(0xFF2A2A2E),
        outlineVariant: const Color(0xFF3A3A3E),
      ),
      fontFamily: 'Roboto',
      textTheme: ThemeData(brightness: Brightness.dark).textTheme.apply(
            fontFamily: 'Roboto',
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
    );
  }
}
