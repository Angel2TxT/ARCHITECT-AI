import 'package:flutter/material.dart';
import 'package:movil_architect/models/home_project_models.dart';

class HomeStatusChip extends StatelessWidget {
  const HomeStatusChip({super.key, required this.status});

  final String status;

  Color _bg(ColorScheme scheme) {
    switch (status) {
      case 'completed':
      case 'active':
        return const Color(0xFF1B8A5A).withValues(alpha: 0.14);
      case 'in_progress':
        return const Color(0xFF1B4D8A).withValues(alpha: 0.14);
      case 'blocked':
      case 'canceled':
      case 'needs_correction':
        return const Color(0xFFD64545).withValues(alpha: 0.14);
      case 'needs_details':
      case 'on_hold':
        return const Color(0xFFD9A406).withValues(alpha: 0.16);
      default:
        return scheme.surfaceContainerHighest;
    }
  }

  Color _fg(ColorScheme scheme) {
    switch (status) {
      case 'completed':
      case 'active':
        return const Color(0xFF1B8A5A);
      case 'in_progress':
        return const Color(0xFF1B4D8A);
      case 'blocked':
      case 'canceled':
      case 'needs_correction':
        return const Color(0xFFD64545);
      case 'needs_details':
      case 'on_hold':
        return const Color(0xFFB07A00);
      default:
        return scheme.onSurfaceVariant;
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: _bg(scheme),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        homeProjectStatusLabel(status),
        style: TextStyle(
          color: _fg(scheme),
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
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
    this.onDelete,
  });

  final HomeProject project;
  final VoidCallback onTap;
  final bool pinned;
  final VoidCallback? onPin;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = scheme.brightness == Brightness.dark;
    final hasMenu = onPin != null || onDelete != null;
    final borderColor = isDark
        ? const Color(0xFF2E2E34)
        : const Color(0xFFD0D5DD);

    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: borderColor,
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: isDark
                ? Colors.black.withValues(alpha: 0.3)
                : Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(18),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(18),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  if (pinned) ...[
                    Icon(
                      Icons.push_pin,
                      size: 16,
                      color: scheme.primary,
                    ),
                    const SizedBox(width: 6),
                  ],
                  Expanded(
                    child: Text(
                      project.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: scheme.onSurface,
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.2,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  HomeStatusChip(status: project.status),
                  if (hasMenu) ...[
                    const SizedBox(width: 2),
                    PopupMenuButton<String>(
                      tooltip: 'Opciones',
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      offset: const Offset(0, 36),
                      icon: Icon(
                        Icons.more_vert,
                        color: scheme.onSurfaceVariant,
                        size: 20,
                      ),
                      onSelected: (value) {
                        switch (value) {
                          case 'pin':
                            onPin?.call();
                          case 'delete':
                            onDelete?.call();
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
                                      ? Icons.push_pin
                                      : Icons.push_pin_outlined,
                                  size: 20,
                                  color: scheme.onSurface,
                                ),
                                const SizedBox(width: 12),
                                Text(pinned ? 'Desfijar' : 'Fijar'),
                              ],
                            ),
                          ),
                        if (onDelete != null)
                          const PopupMenuItem(
                            value: 'delete',
                            child: Row(
                              children: [
                                Icon(
                                  Icons.delete_outline,
                                  size: 20,
                                  color: Colors.red,
                                ),
                                SizedBox(width: 12),
                                Text(
                                  'Eliminar',
                                  style: TextStyle(color: Colors.red),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 10),
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Icon(
                    Icons.place_outlined,
                    size: 15,
                    color: scheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      project.location.isNotEmpty
                          ? project.location
                          : 'Sin ubicación',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: scheme.onSurfaceVariant,
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3.5,
                    ),
                    decoration: BoxDecoration(
                      color: scheme.surfaceContainerHighest
                          .withValues(alpha: isDark ? 0.6 : 0.8),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      'Etapa ${project.currentStage}/9',
                      style: TextStyle(
                        color: scheme.onSurface,
                        fontWeight: FontWeight.w700,
                        fontSize: 11.5,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
}
