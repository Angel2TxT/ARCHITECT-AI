import 'package:flutter/material.dart';
import 'package:movil_architect/models/home_project_models.dart';

class HomeStatusChip extends StatelessWidget {
  const HomeStatusChip({super.key, required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primaryBlack = isDark ? Colors.white : const Color(0xFF111111);
    final borderColor = isDark ? const Color(0xFF3F3F46) : const Color(0xFFD1D5DB);
    final tagBg = isDark ? const Color(0xFF1E1E22) : const Color(0xFFF1F1F4);
    final isDone = status == 'completed';
    final isActive = status == 'active' || status == 'in_progress';
    final label = homeProjectStatusLabel(status);

    if (isDone) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: isDark ? Colors.white : const Color(0xFF111111),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.check_circle_rounded,
              size: 12,
              color: isDark ? const Color(0xFF111111) : Colors.white,
            ),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                color: isDark ? const Color(0xFF111111) : Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: tagBg,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: borderColor, width: 1.0),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isActive
                  ? primaryBlack
                  : (isDark ? Colors.white54 : Colors.black38),
            ),
          ),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              color: primaryBlack,
              fontSize: 11,
              fontWeight: FontWeight.w600,
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
  });

  final HomeProject project;
  final VoidCallback onTap;
  final bool pinned;
  final VoidCallback? onPin;
  final VoidCallback? onRename;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardBg = isDark ? const Color(0xFF141417) : Colors.white;
    final borderColor = isDark ? const Color(0xFF3F3F46) : const Color(0xFFD1D5DB);
    final primaryBlack = isDark ? Colors.white : const Color(0xFF111111);
    final secondaryText = isDark ? const Color(0xFFA1A1AA) : const Color(0xFF52525B);
    final mutedText = isDark ? const Color(0xFF71717A) : const Color(0xFF8E8E93);
    final tagBg = isDark ? const Color(0xFF1E1E22) : const Color(0xFFF1F1F4);
    final hasMenu = onPin != null || onRename != null || onDelete != null;

    return Container(
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: borderColor,
          width: 1.4,
        ),
        boxShadow: [
          BoxShadow(
            color: isDark
                ? Colors.black.withValues(alpha: 0.3)
                : Colors.black.withValues(alpha: 0.04),
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
            padding: const EdgeInsets.all(16),
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
                        size: 16,
                        color: primaryBlack,
                      ),
                      const SizedBox(width: 6),
                    ],
                    Expanded(
                      child: Text(
                        project.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: primaryBlack,
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
                          Icons.more_vert_rounded,
                          color: secondaryText,
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
                                    color: primaryBlack,
                                  ),
                                  const SizedBox(width: 12),
                                  Text(
                                    pinned ? 'Desfijar' : 'Fijar',
                                    style: TextStyle(
                                      color: primaryBlack,
                                      fontWeight: FontWeight.w600,
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
                                    color: primaryBlack,
                                  ),
                                  const SizedBox(width: 12),
                                  Text(
                                    'Editar nombre',
                                    style: TextStyle(
                                      color: primaryBlack,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          if (onDelete != null)
                            const PopupMenuItem(
                              value: 'delete',
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.delete_outline_rounded,
                                    size: 18,
                                    color: Colors.red,
                                  ),
                                  SizedBox(width: 12),
                                  Text(
                                    'Eliminar',
                                    style: TextStyle(
                                      color: Colors.red,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ],
                  ],
                ),

                // Cliente y Ubicación
                if (project.clientName.isNotEmpty || project.location.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  if (project.clientName.isNotEmpty) ...[
                    Row(
                      children: [
                        Icon(
                          Icons.person_outline_rounded,
                          size: 14,
                          color: mutedText,
                        ),
                        const SizedBox(width: 5),
                        Expanded(
                          child: Text(
                            project.clientName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: secondaryText,
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 3),
                  ],
                  if (project.location.isNotEmpty) ...[
                    Row(
                      children: [
                        Icon(
                          Icons.place_outlined,
                          size: 14,
                          color: mutedText,
                        ),
                        const SizedBox(width: 5),
                        Expanded(
                          child: Text(
                            project.location,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: mutedText,
                              fontSize: 12.5,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ],

                const SizedBox(height: 12),
                Container(
                  height: 1,
                  color: borderColor.withValues(alpha: 0.6),
                ),
                const SizedBox(height: 12),

                // Progreso y Etapa
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(
                                'Progreso',
                                style: TextStyle(
                                  color: secondaryText,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(width: 6),
                              Text(
                                '${project.progressPercent.round()}%',
                                style: TextStyle(
                                  color: primaryBlack,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(999),
                            child: LinearProgressIndicator(
                              value: (project.progressPercent / 100).clamp(0.0, 1.0),
                              minHeight: 5,
                              backgroundColor: isDark
                                  ? const Color(0xFF27272A)
                                  : const Color(0xFFE4E4E7),
                              valueColor: AlwaysStoppedAnimation<Color>(primaryBlack),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 16),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: tagBg,
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(color: borderColor, width: 1),
                      ),
                      child: Text(
                        'Etapa ${project.currentStage}/9',
                        style: TextStyle(
                          color: primaryBlack,
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
