import 'package:flutter/material.dart';

abstract final class AppNotifications {
  static const duration = Duration(seconds: 3);

  static const successColor = Color(0xFF1B8A5A);
  static const errorColor = Color(0xFFD64545);
  static const infoColor = Color(0xFF2563EB);

  static void success(BuildContext context, String message) {
    _show(context, message, successColor);
  }

  static void error(BuildContext context, String message) {
    _show(context, message, errorColor);
  }

  static void info(BuildContext context, String message) {
    _show(context, message, infoColor);
  }

  static void result(
    BuildContext context, {
    required bool ok,
    required String successMessage,
    String? errorMessage,
    String fallbackError = 'No se pudo completar la acción.',
  }) {
    if (ok) {
      success(context, successMessage);
      return;
    }
    error(context, errorMessage ?? fallbackError);
  }

  static void _show(
    BuildContext context,
    String message,
    Color backgroundColor,
  ) {
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();

    final media = MediaQuery.of(context);
    const snackbarHeight = 48.0;
    final top = media.padding.top + kToolbarHeight + 8;

    messenger.showSnackBar(
      SnackBar(
        content: Text(
          message,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w600,
            fontSize: 14,
          ),
        ),
        backgroundColor: backgroundColor,
        duration: duration,
        behavior: SnackBarBehavior.floating,
        dismissDirection: DismissDirection.up,
        margin: EdgeInsets.only(
          left: 56,
          right: 56,
          bottom: media.size.height - top - snackbarHeight,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
        elevation: 6,
      ),
    );
  }
}
