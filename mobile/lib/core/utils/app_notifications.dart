import 'dart:async';

import 'package:flutter/material.dart';

abstract final class AppNotifications {
  static const duration = Duration(seconds: 3);

  static const successColor = Color(0xFF1B8A5A);
  static const errorColor = Color(0xFFD64545);
  static const infoColor = Color(0xFF2563EB);

  static OverlayEntry? _activeEntry;
  static Timer? _dismissTimer;

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

  static void _dismissActive() {
    _dismissTimer?.cancel();
    _dismissTimer = null;
    _activeEntry?.remove();
    _activeEntry = null;
  }

  static void _show(
    BuildContext context,
    String message,
    Color backgroundColor,
  ) {
    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    if (overlay == null) {
      final messenger = ScaffoldMessenger.maybeOf(context);
      messenger?.hideCurrentSnackBar();
      messenger?.showSnackBar(
        SnackBar(
          content: Text(message, textAlign: TextAlign.center),
          backgroundColor: backgroundColor,
          duration: duration,
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
      );
      return;
    }

    _dismissActive();

    late OverlayEntry entry;
    entry = OverlayEntry(
      builder: (overlayContext) {
        return Positioned(
          top: 0,
          left: 16,
          right: 16,
          child: SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Material(
                color: Colors.transparent,
                child: Dismissible(
                  key: ValueKey('app_notif_${message.hashCode}'),
                  direction: DismissDirection.up,
                  onDismissed: (_) {
                    if (_activeEntry == entry) {
                      _dismissActive();
                    }
                  },
                  child: GestureDetector(
                    onTap: () {
                      if (_activeEntry == entry) {
                        _dismissActive();
                      }
                    },
                    child: Center(
                      child: Container(
                        constraints: const BoxConstraints(maxWidth: 340),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 11,
                        ),
                        decoration: BoxDecoration(
                          color: backgroundColor,
                          borderRadius: BorderRadius.circular(24),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.18),
                              blurRadius: 12,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Text(
                          message,
                          textAlign: TextAlign.center,
                          softWrap: true,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                            height: 1.3,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );

    _activeEntry = entry;
    overlay.insert(entry);
    _dismissTimer = Timer(duration, () {
      if (_activeEntry == entry) {
        _dismissActive();
      }
    });
  }
}
