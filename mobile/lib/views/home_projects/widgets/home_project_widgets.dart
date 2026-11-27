import 'package:flutter/material.dart';
import 'package:movil_architect/controllers/home_project_controller.dart';
import 'package:movil_architect/core/theme/architect_theme_tokens.dart';
import 'package:movil_architect/core/utils/app_notifications.dart';
import 'package:movil_architect/models/home_project_models.dart';

class HomeStatusChip extends StatelessWidget {
  const HomeStatusChip({super.key, required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    final tokens = ArchitectThemeTokens.of(context);
    final isDone = status == 'completed';
    final isActive = status == 'active' || status == 'in_progress';
    final isWarning = status == 'paused' || status == 'pending';
    final label = homeProjectStatusLabel(status);

    final Color dotColor = (isDone || isActive)
        ? tokens.statusPositive
        : (isWarning ? tokens.statusWarning : tokens.textSecondary);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: isDone
            ? tokens.statusPositive.withValues(alpha: 0.14)
            : tokens.surfaceSelected,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: isDone
              ? tokens.statusPositive.withValues(alpha: 0.4)
              : tokens.borderSubtle,
          width: 1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (isDone)
            Icon(
              Icons.check_rounded,
              size: 13,
              color: tokens.statusPositive,
            )
          else
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: dotColor,
              ),
            ),
          const SizedBox(width: 6),
          Text(
            label,
            style: ArchitectThemeTokens.appleText(
              color: isDone ? tokens.statusPositive : tokens.textPrimary,
              fontSize: 12,
              fontWeight: FontWeight.w500,
              letterSpacing: 0,
            ),
          ),
        ],
      ),
    );
  }
}

class HomeProjectCard extends StatelessWidget {
  const HomeProjectCard({
    super.key,
    required this.project,
    required this.onTap,
    this.pinned = false,
    this.onPin,
    this.onRename,
    this.onDelete,
    this.onLeave,
  });

  final HomeProject project;
  final VoidCallback onTap;
  final bool pinned;
  final VoidCallback? onPin;
  final VoidCallback? onRename;
  final VoidCallback? onDelete;
  final VoidCallback? onLeave;

  @override
  Widget build(BuildContext context) {
    final tokens = ArchitectThemeTokens.of(context);
    final textScale = MediaQuery.textScalerOf(context).scale(1.0);
    final maxLines = textScale > 1.3 ? 2 : 1;
    final progress = (project.progressPercent / 100).clamp(0.0, 1.0);
    final progressInt = project.progressPercent.round();
    final hasMenu =
        onPin != null ||
        onRename != null ||
        onDelete != null ||
        onLeave != null;

    return Semantics(
      button: true,
      label:
          '${project.name}, ${homeProjectStatusLabel(project.status)}, progreso $progressInt por ciento, etapa ${project.currentStage} de 9',
      child: Material(
        color: tokens.surfaceSecondary,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(ArchitectThemeTokens.radiusLg),
          side: BorderSide(color: tokens.borderSubtle, width: 1),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          hoverColor: tokens.interactionOverlay,
          splashColor: tokens.interactionOverlay,
          borderRadius: BorderRadius.circular(ArchitectThemeTokens.radiusLg),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 12, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Fila superior: Título, Estado y Menú
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    if (pinned) ...[
                      Icon(
                        Icons.push_pin_rounded,
                        size: 15,
                        color: tokens.accent,
                      ),
                      const SizedBox(width: 6),
                    ],
                    Expanded(
                      child: Text(
                        project.name,
                        maxLines: maxLines,
                        overflow: TextOverflow.ellipsis,
                        style: ArchitectThemeTokens.appleText(
                          color: tokens.textPrimary,
                          fontSize: 18,
                          fontWeight: FontWeight.w500,
                          letterSpacing: -0.25,
                          height: 1.25,
                        ),
                      ),
                    ),
                    if (hasMenu) ...[
                      const SizedBox(width: 2),
                      PopupMenuButton<String>(
                        tooltip: 'Opciones del proyecto',
                        color: tokens.surfaceSelected,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(
                            ArchitectThemeTokens.radiusMd,
                          ),
                          side: BorderSide(color: tokens.borderSubtle, width: 1),
                        ),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(
                          minWidth: 44,
                          minHeight: 44,
                        ),
                        offset: const Offset(0, 40),
                        icon: Icon(
                          Icons.more_horiz_rounded,
                          color: tokens.textSecondary,
                          size: 20,
                        ),
                        onSelected: (value) {
                          switch (value) {
                            case 'pin':
                              onPin?.call();
                            case 'rename':
                              onRename?.call();
                            case 'delete':
                              onDelete?.call();
                            case 'leave':
                              onLeave?.call();
                          }
                        },
                        itemBuilder: (context) => [
                          if (onPin != null)
                            PopupMenuItem(
                              value: 'pin',
                              child: Row(
                                children: [
                                  Icon(
                                    pinned
                                        ? Icons.push_pin_rounded
                                        : Icons.push_pin_outlined,
                                    size: 18,
                                    color: pinned
                                        ? tokens.accent
                                        : tokens.textPrimary,
                                  ),
                                  const SizedBox(width: 12),
                                  Text(
                                    pinned ? 'Desfijar' : 'Fijar',
                                    style: ArchitectThemeTokens.appleText(
                                      color: tokens.textPrimary,
                                      fontSize: 15,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          if (onRename != null)
                            PopupMenuItem(
                              value: 'rename',
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.edit_outlined,
                                    size: 18,
                                    color: tokens.textPrimary,
                                  ),
                                  const SizedBox(width: 12),
                                  Text(
                                    'Editar nombre',
                                    style: ArchitectThemeTokens.appleText(
                                      color: tokens.textPrimary,
                                      fontSize: 15,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          if (onDelete != null)
                            PopupMenuItem(
                              value: 'delete',
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.delete_outline_rounded,
                                    size: 18,
                                    color: tokens.statusError,
                                  ),
                                  const SizedBox(width: 12),
                                  Text(
                                    'Eliminar',
                                    style: ArchitectThemeTokens.appleText(
                                      color: tokens.statusError,
                                      fontSize: 15,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          if (onLeave != null)
                            PopupMenuItem(
                              value: 'leave',
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.exit_to_app_rounded,
                                    size: 18,
                                    color: tokens.statusError,
                                  ),
                                  const SizedBox(width: 12),
                                  Text(
                                    'Darse de baja',
                                    style: ArchitectThemeTokens.appleText(
                                      color: tokens.statusError,
                                      fontSize: 15,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ] else
                      const SizedBox(width: 4),
                  ],
                ),

                // Cliente y Ubicación
                if (project.clientName.isNotEmpty ||
                    project.location.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  if (project.clientName.isNotEmpty) ...[
                    Row(
                      children: [
                        Icon(
                          Icons.person_outline_rounded,
                          size: 15,
                          color: tokens.textSecondary,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            project.clientName,
                            maxLines: maxLines,
                            overflow: TextOverflow.ellipsis,
                            style: ArchitectThemeTokens.appleText(
                              color: tokens.textSecondary,
                              fontSize: 14,
                              fontWeight: FontWeight.w400,
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (project.location.isNotEmpty) const SizedBox(height: 4),
                  ],
                  if (project.location.isNotEmpty)
                    Row(
                      children: [
                        Icon(
                          Icons.location_on_outlined,
                          size: 15,
                          color: tokens.textSecondary,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            project.location,
                            maxLines: maxLines,
                            overflow: TextOverflow.ellipsis,
                            style: ArchitectThemeTokens.appleText(
                              color: tokens.textSecondary,
                              fontSize: 14,
                              fontWeight: FontWeight.w400,
                            ),
                          ),
                        ),
                      ],
                    ),
                ],

                const SizedBox(height: 16),

                // Progreso y Etapa
                Padding(
                  padding: const EdgeInsets.only(right: 4),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Text(
                                  'Progreso',
                                  style: ArchitectThemeTokens.appleText(
                                    color: tokens.textSecondary,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  '$progressInt%',
                                  style: ArchitectThemeTokens.appleText(
                                    color: tokens.textPrimary,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w500,
                                    fontFeatures: const [
                                      FontFeature.tabularFigures(),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(999),
                              child: LinearProgressIndicator(
                                value: progress,
                                minHeight: 3.5,
                                backgroundColor: tokens.borderSubtle,
                                valueColor: AlwaysStoppedAnimation<Color>(
                                  progressInt >= 100
                                      ? tokens.statusPositive
                                      : tokens.textPrimary,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 16),
                      Text(
                        'Etapa ${project.currentStage}/9',
                        style: ArchitectThemeTokens.appleText(
                          color: tokens.accent,
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          fontFeatures: const [
                            FontFeature.tabularFigures(),
                          ],
                        ),
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

class NewSectionButton extends StatelessWidget {
  const NewSectionButton({
    super.key,
    required this.onTap,
    this.enabled = true,
  });

  final VoidCallback onTap;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final tokens = ArchitectThemeTokens.of(context);

    return Semantics(
      button: true,
      enabled: enabled,
      label: 'Crear nuevo apartado',
      child: Material(
        color: tokens.surfaceSecondary,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(ArchitectThemeTokens.radiusMd),
          side: BorderSide(color: tokens.borderSubtle, width: 1),
        ),
        child: InkWell(
          onTap: enabled ? onTap : null,
          borderRadius: BorderRadius.circular(ArchitectThemeTokens.radiusMd),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 40),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.add_rounded,
                    size: 16,
                    color: enabled ? tokens.accent : tokens.textSecondary,
                  ),
                  const SizedBox(width: 5),
                  Text(
                    'Nuevo apartado',
                    style: ArchitectThemeTokens.appleText(
                      color:
                          enabled ? tokens.textPrimary : tokens.textSecondary,
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

Future<void> showCreateSectionDialog({
  required BuildContext context,
  required HomeProjectDetailController controller,
  required int stageNumber,
}) async {
  final tokens = ArchitectThemeTokens.of(context);
  final isDark = Theme.of(context).brightness == Brightness.dark;
  final titleController = TextEditingController();
  final descController = TextEditingController();
  final formKey = GlobalKey<FormState>();

  final result = await showDialog<({String title, String? description})>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text('Nuevo apartado · Etapa $stageNumber'),
      content: Form(
        key: formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              controller: titleController,
              autofocus: true,
              maxLength: 160,
              textCapitalization: TextCapitalization.sentences,
              autovalidateMode: AutovalidateMode.onUserInteraction,
              decoration: const InputDecoration(
                labelText: 'Nombre del apartado',
                hintText: 'Ej. Estudio de mecánica de suelos',
              ),
              validator: (value) {
                final trimmed = (value ?? '').trim();
                if (trimmed.isEmpty) {
                  return 'Ingresa el nombre del apartado';
                }
                if (trimmed.length < 2) {
                  return 'Debe tener al menos 2 caracteres';
                }
                return null;
              },
            ),
            const SizedBox(height: 8),
            TextFormField(
              controller: descController,
              maxLines: 3,
              maxLength: 400,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Descripción (opcional)',
                hintText: 'Detalles o alcance del apartado',
              ),
            ),
          ],
        ),
      ),
      actions: [
        FilledButton(
          onPressed: () => Navigator.pop(dialogContext),
          style: FilledButton.styleFrom(
            foregroundColor: Colors.white,
            backgroundColor:
                isDark ? const Color(0xFF3E3E44) : const Color(0xFF6B6B73),
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
            minimumSize: const Size(0, 42),
          ),
          child: Text(
            'Cancelar',
            style: ArchitectThemeTokens.appleText(
              color: Colors.white,
              fontSize: 14.5,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        const SizedBox(width: 4),
        FilledButton(
          onPressed: () {
            if (formKey.currentState?.validate() == true) {
              final desc = descController.text.trim();
              Navigator.pop(dialogContext, (
                title: titleController.text.trim(),
                description: desc.isEmpty ? null : desc,
              ));
            }
          },
          style: FilledButton.styleFrom(
            foregroundColor: tokens.primaryActionFg,
            backgroundColor: tokens.primaryActionBg,
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
            minimumSize: const Size(0, 42),
          ),
          child: Text(
            'Crear',
            style: ArchitectThemeTokens.appleText(
              color: tokens.primaryActionFg,
              fontSize: 14.5,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ],
    ),
  );

  titleController.dispose();
  descController.dispose();

  if (result == null || !context.mounted) return;

  final ok = await controller.createSection(
    stageNumber: stageNumber,
    title: result.title,
    description: result.description,
  );
  if (!context.mounted) return;
  AppNotifications.result(
    context,
    ok: ok,
    successMessage: 'Apartado creado',
    errorMessage: controller.actionError,
  );
}
