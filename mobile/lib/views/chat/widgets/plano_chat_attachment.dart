import 'dart:io';

import 'package:flutter/material.dart';
import 'package:movil_architect/core/theme/app_colors.dart';
import 'package:movil_architect/views/dashboard/widgets/dashboard_shell.dart';

/// Vista previa del plano en el hilo del chat (encima del texto del usuario).
class PlanoChatAttachment extends StatelessWidget {
  const PlanoChatAttachment({
    super.key,
    required this.fileName,
    this.file,
    this.loadProgress,
    this.onDismiss,
    this.onTap,
  });

  final String fileName;
  final File? file;
  final double? loadProgress;
  final VoidCallback? onDismiss;
  final VoidCallback? onTap;

  bool get _isLoading => loadProgress != null && (loadProgress! < 1 || file == null);

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isImage = isPlanoImageFile(fileName);
    final maxWidth = MediaQuery.sizeOf(context).width * 0.72;

    return Align(
      alignment: Alignment.centerRight,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: Material(
          color: colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(16),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Stack(
                  alignment: Alignment.center,
                  children: [
                    AspectRatio(
                      aspectRatio: 4 / 3,
                      child: file != null && isImage && !_isLoading
                          ? Image.file(file!, fit: BoxFit.cover)
                          : ColoredBox(
                              color: colorScheme.surfaceContainerHigh,
                              child: Icon(
                                Icons.description_outlined,
                                size: 48,
                                color: colorScheme.onSurfaceVariant,
                              ),
                            ),
                    ),
                    if (_isLoading)
                      Container(
                        color: Colors.black26,
                        child: Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              SizedBox(
                                width: 36,
                                height: 36,
                                child: CircularProgressIndicator(
                                  value: loadProgress! > 0 ? loadProgress : null,
                                  strokeWidth: 3,
                                  color: Colors.white,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                '${(loadProgress!.clamp(0, 1) * 100).round()}%',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 13,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _isLoading ? 'Cargando plano…' : 'Tu plano',
                              style: TextStyle(
                                color: colorScheme.onSurface,
                                fontWeight: FontWeight.w800,
                                fontSize: 13,
                              ),
                            ),
                            Text(
                              fileName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: colorScheme.onSurfaceVariant,
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (onDismiss != null)
                        IconButton(
                          onPressed: onDismiss,
                          icon: Icon(
                            Icons.close_rounded,
                            size: 18,
                            color: colorScheme.onSurfaceVariant,
                          ),
                          visualDensity: VisualDensity.compact,
                          tooltip: 'Quitar plano',
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Imagen del plano encima de la burbuja de texto del usuario.
class UserPlanoMessageGroup extends StatelessWidget {
  const UserPlanoMessageGroup({
    super.key,
    required this.fileName,
    required this.text,
    this.file,
    this.loadProgress,
    this.onDismissPlano,
    this.onPlanoTap,
  });

  final String fileName;
  final String text;
  final File? file;
  final double? loadProgress;
  final VoidCallback? onDismissPlano;
  final VoidCallback? onPlanoTap;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        PlanoChatAttachment(
          fileName: fileName,
          file: file,
          loadProgress: loadProgress,
          onDismiss: onDismissPlano,
          onTap: onPlanoTap,
        ),
        if (text.isNotEmpty)
          Align(
            alignment: Alignment.centerRight,
            child: Container(
              margin: const EdgeInsets.only(bottom: 12),
              constraints: BoxConstraints(
                maxWidth: MediaQuery.sizeOf(context).width * 0.82,
              ),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.ink,
                borderRadius: BorderRadius.circular(18),
              ),
              child: Text(
                text,
                style: const TextStyle(
                  color: Colors.white,
                  height: 1.4,
                ),
              ),
            ),
          ),
      ],
    );
  }
}
