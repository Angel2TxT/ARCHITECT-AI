import 'package:flutter/material.dart';

/// Tokens semánticos centralizados para superficies, bordes, acentos, estados
/// y tipografía Geist Sans de ARCHITECT, con soporte para modo claro y oscuro.
@immutable
class ArchitectThemeTokens extends ThemeExtension<ArchitectThemeTokens> {
  const ArchitectThemeTokens({
    required this.drawerBackground,
    required this.surfaceSecondary,
    required this.surfaceSelected,
    required this.textPrimary,
    required this.textSecondary,
    required this.borderSubtle,
    required this.borderStrong,
    required this.accent,
    required this.accentSubtle,
    required this.primaryActionBg,
    required this.primaryActionFg,
    required this.interactionOverlay,
    Color? statusPositive,
    Color? statusWarning,
    Color? statusError,
  })  : _statusPositive = statusPositive,
        _statusWarning = statusWarning,
        _statusError = statusError;

  final Color drawerBackground;
  final Color surfaceSecondary;
  final Color surfaceSelected;
  final Color textPrimary;
  final Color textSecondary;
  final Color borderSubtle;
  final Color borderStrong;
  final Color accent;
  final Color accentSubtle;
  final Color primaryActionBg;
  final Color primaryActionFg;
  final Color interactionOverlay;
  final Color? _statusPositive;
  final Color? _statusWarning;
  final Color? _statusError;

  bool get _isDark => drawerBackground.computeLuminance() < 0.2;

  Color get statusPositive =>
      _statusPositive ??
      (_isDark ? const Color(0xFFA3B99D) : const Color(0xFF3F6238));
  Color get statusWarning =>
      _statusWarning ??
      (_isDark ? const Color(0xFFC8A477) : const Color(0xFF8A6434));
  Color get statusError =>
      _statusError ??
      (_isDark ? const Color(0xFFCF8585) : const Color(0xFFA84444));

  static const double radiusSm = 8;
  static const double radiusMd = 12;
  static const double radiusLg = 14;

  /// Familia tipográfica Geist Sans integrada en assets/fonts con fallback limpio.
  static const String displayFontFamily = 'GeistSans';
  static const String textFontFamily = 'GeistSans';
  static const List<String> fontFallback = [
    '.SF Pro Display',
    '.SF Pro Text',
    'sans-serif',
  ];

  static TextTheme buildTextTheme({
    required Color primaryColor,
    required Color secondaryColor,
  }) {
    return TextTheme(
      headlineMedium: appleDisplay(
        color: primaryColor,
        fontSize: 28,
        fontWeight: FontWeight.w500,
        letterSpacing: 0,
        height: 1.18,
      ),
      titleLarge: appleDisplay(
        color: primaryColor,
        fontSize: 18,
        fontWeight: FontWeight.w500,
        letterSpacing: 0,
        height: 1.25,
      ),
      titleMedium: appleText(
        color: primaryColor,
        fontSize: 18,
        fontWeight: FontWeight.w500,
        letterSpacing: 0,
        height: 1.28,
      ),
      titleSmall: appleText(
        color: primaryColor,
        fontSize: 16,
        fontWeight: FontWeight.w500,
        letterSpacing: 0,
        height: 1.3,
      ),
      labelLarge: appleText(
        color: primaryColor,
        fontSize: 15,
        fontWeight: FontWeight.w500,
        letterSpacing: 0,
        height: 1.2,
      ),
      bodyLarge: appleText(
        color: primaryColor,
        fontSize: 16,
        fontWeight: FontWeight.w400,
        letterSpacing: 0,
        height: 1.45,
      ),
      bodyMedium: appleText(
        color: secondaryColor,
        fontSize: 14,
        fontWeight: FontWeight.w400,
        letterSpacing: 0,
        height: 1.4,
      ),
      labelMedium: appleText(
        color: secondaryColor,
        fontSize: 12,
        fontWeight: FontWeight.w500,
        letterSpacing: 0,
        height: 1.25,
      ),
    );
  }

  static TextStyle appleDisplay({
    required Color color,
    double fontSize = 18,
    FontWeight fontWeight = FontWeight.w500,
    double letterSpacing = 0.0,
    double height = 1.2,
  }) {
    return TextStyle(
      fontFamily: displayFontFamily,
      fontFamilyFallback: fontFallback,
      color: color,
      fontSize: fontSize,
      fontWeight: fontWeight,
      letterSpacing: letterSpacing,
      height: height,
    );
  }

  static TextStyle appleText({
    required Color color,
    double fontSize = 15,
    FontWeight fontWeight = FontWeight.w400,
    double? letterSpacing,
    double? height,
    List<FontFeature>? fontFeatures,
  }) {
    final resolvedTracking = letterSpacing ?? 0.0;
    return TextStyle(
      fontFamily: textFontFamily,
      fontFamilyFallback: fontFallback,
      color: color,
      fontSize: fontSize,
      fontWeight: fontWeight,
      letterSpacing: resolvedTracking,
      height: height,
      fontFeatures: fontFeatures,
    );
  }

  static const ArchitectThemeTokens light = ArchitectThemeTokens(
    drawerBackground: Color(0xFFF8F8F9),
    surfaceSecondary: Color(0xFFFFFFFF),
    surfaceSelected: Color(0xFFF1F1F3),
    textPrimary: Color(0xFF0B0B0B),
    textSecondary: Color(0xFF55555C),
    borderSubtle: Color(0xFFE4E4E7),
    borderStrong: Color(0xFFD0D0D6),
    accent: Color(0xFF8B6F3E),
    accentSubtle: Color(0x148B6F3E),
    primaryActionBg: Color(0xFF0B0B0B),
    primaryActionFg: Color(0xFFF5F5F5),
    interactionOverlay: Color(0x0D0B0B0B),
    statusPositive: Color(0xFF3F6238),
    statusWarning: Color(0xFF8A6434),
    statusError: Color(0xFFA84444),
  );

  static const ArchitectThemeTokens dark = ArchitectThemeTokens(
    drawerBackground: Color(0xFF0B0B0B),
    surfaceSecondary: Color(0xFF171717),
    surfaceSelected: Color(0xFF202022),
    textPrimary: Color(0xFFF5F5F5),
    textSecondary: Color(0xFFABABB0),
    borderSubtle: Color(0xFF2A2A2A),
    borderStrong: Color(0xFF3A3A3D),
    accent: Color(0xFFC7AC7D),
    accentSubtle: Color(0x1FC7AC7D),
    primaryActionBg: Color(0xFFF5F5F5),
    primaryActionFg: Color(0xFF0B0B0B),
    interactionOverlay: Color(0x12F5F5F5),
    statusPositive: Color(0xFFA3B99D),
    statusWarning: Color(0xFFC8A477),
    statusError: Color(0xFFCF8585),
  );

  static ArchitectThemeTokens of(BuildContext context) {
    final ext = Theme.of(context).extension<ArchitectThemeTokens>();
    if (ext != null) return ext;
    return Theme.of(context).brightness == Brightness.dark ? dark : light;
  }

  @override
  ArchitectThemeTokens copyWith({
    Color? drawerBackground,
    Color? surfaceSecondary,
    Color? surfaceSelected,
    Color? textPrimary,
    Color? textSecondary,
    Color? borderSubtle,
    Color? borderStrong,
    Color? accent,
    Color? accentSubtle,
    Color? primaryActionBg,
    Color? primaryActionFg,
    Color? interactionOverlay,
    Color? statusPositive,
    Color? statusWarning,
    Color? statusError,
  }) {
    return ArchitectThemeTokens(
      drawerBackground: drawerBackground ?? this.drawerBackground,
      surfaceSecondary: surfaceSecondary ?? this.surfaceSecondary,
      surfaceSelected: surfaceSelected ?? this.surfaceSelected,
      textPrimary: textPrimary ?? this.textPrimary,
      textSecondary: textSecondary ?? this.textSecondary,
      borderSubtle: borderSubtle ?? this.borderSubtle,
      borderStrong: borderStrong ?? this.borderStrong,
      accent: accent ?? this.accent,
      accentSubtle: accentSubtle ?? this.accentSubtle,
      primaryActionBg: primaryActionBg ?? this.primaryActionBg,
      primaryActionFg: primaryActionFg ?? this.primaryActionFg,
      interactionOverlay: interactionOverlay ?? this.interactionOverlay,
      statusPositive: statusPositive ?? this.statusPositive,
      statusWarning: statusWarning ?? this.statusWarning,
      statusError: statusError ?? this.statusError,
    );
  }

  @override
  ArchitectThemeTokens lerp(
    covariant ThemeExtension<ArchitectThemeTokens>? other,
    double t,
  ) {
    if (other is! ArchitectThemeTokens) return this;
    return ArchitectThemeTokens(
      drawerBackground: Color.lerp(drawerBackground, other.drawerBackground, t)!,
      surfaceSecondary: Color.lerp(surfaceSecondary, other.surfaceSecondary, t)!,
      surfaceSelected: Color.lerp(surfaceSelected, other.surfaceSelected, t)!,
      textPrimary: Color.lerp(textPrimary, other.textPrimary, t)!,
      textSecondary: Color.lerp(textSecondary, other.textSecondary, t)!,
      borderSubtle: Color.lerp(borderSubtle, other.borderSubtle, t)!,
      borderStrong: Color.lerp(borderStrong, other.borderStrong, t)!,
      accent: Color.lerp(accent, other.accent, t)!,
      accentSubtle: Color.lerp(accentSubtle, other.accentSubtle, t)!,
      primaryActionBg: Color.lerp(primaryActionBg, other.primaryActionBg, t)!,
      primaryActionFg: Color.lerp(primaryActionFg, other.primaryActionFg, t)!,
      interactionOverlay:
          Color.lerp(interactionOverlay, other.interactionOverlay, t)!,
      statusPositive: Color.lerp(statusPositive, other.statusPositive, t)!,
      statusWarning: Color.lerp(statusWarning, other.statusWarning, t)!,
      statusError: Color.lerp(statusError, other.statusError, t)!,
    );
  }
}
