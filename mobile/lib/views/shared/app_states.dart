import 'package:flutter/material.dart';
import 'package:movil_architect/core/theme/app_colors.dart';
import 'package:movil_architect/models/analysis_models.dart';

Color verdictColor(String tone) {
  switch (tone) {
    case 'ok':
      return const Color(0xFF1B8A5A);
    case 'warning':
      return const Color(0xFFD9A406);
    case 'error':
      return const Color(0xFFD64545);
    default:
      return AppColors.muted;
  }
}

IconData verdictIcon(String tone) {
  switch (tone) {
    case 'ok':
      return Icons.check_circle_outline;
    case 'warning':
      return Icons.warning_amber_rounded;
    case 'error':
      return Icons.error_outline;
    default:
      return Icons.info_outline;
  }
}

class AppLoadingView extends StatelessWidget {
  const AppLoadingView({super.key, this.message});

  final String? message;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircularProgressIndicator(color: colorScheme.onSurface),
          if (message != null) ...[
            const SizedBox(height: 16),
            Text(
              message!,
              textAlign: TextAlign.center,
              style: TextStyle(color: colorScheme.onSurfaceVariant),
            ),
          ],
        ],
      ),
    );
  }
}

class AppErrorView extends StatelessWidget {
  const AppErrorView({
    super.key,
    required this.message,
    this.onRetry,
    this.retryLabel = 'Reintentar',
  });

  final String message;
  final VoidCallback? onRetry;
  final String retryLabel;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final displayMessage = _displayMessage(message);

    return SafeArea(
      child: LayoutBuilder(
        builder: (context, constraints) {
          return SingleChildScrollView(
            padding: const EdgeInsets.all(28),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                minHeight: constraints.maxHeight - 56,
                maxWidth: 420,
              ),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.cloud_off,
                      size: 56,
                      color: colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      displayMessage,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: colorScheme.onSurface,
                        fontSize: 16,
                        height: 1.4,
                      ),
                    ),
                    if (onRetry != null) ...[
                      const SizedBox(height: 20),
                      FilledButton(
                        onPressed: onRetry,
                        child: Text(retryLabel),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  static String _displayMessage(String raw) {
    final value = raw.trim();
    if (value.isEmpty) return 'No se pudo conectar al servidor.';
    final lower = value.toLowerCase();
    if (lower.contains('<html') ||
        lower.contains('<!doctype') ||
        lower.contains('<script') ||
        lower.contains('cloudflare tunnel error')) {
      return 'El servidor no está disponible. '
          'Revisa la URL en Ajustes o reinicia el túnel.';
    }
    if (value.length > 320) {
      return '${value.substring(0, 317).trimRight()}…';
    }
    return value;
  }
}

class CountBadge extends StatelessWidget {
  const CountBadge({
    super.key,
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final int value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        '$label: $value',
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class AnalysisCountsRow extends StatelessWidget {
  const AnalysisCountsRow({super.key, required this.counts});

  final AnalysisCounts counts;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        CountBadge(
          label: 'Errores',
          value: counts.errors,
          color: const Color(0xFFD64545),
        ),
        CountBadge(
          label: 'Avisos',
          value: counts.warnings,
          color: const Color(0xFFD9A406),
        ),
        CountBadge(
          label: 'Detecciones',
          value: counts.detections,
          color: const Color(0xFF1B4D8A),
        ),
      ],
    );
  }
}
