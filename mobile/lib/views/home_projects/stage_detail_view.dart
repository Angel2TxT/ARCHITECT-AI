import 'package:flutter/material.dart';
import 'package:movil_architect/controllers/home_project_controller.dart';
import 'package:movil_architect/core/utils/app_notifications.dart';
import 'package:movil_architect/core/utils/date_utils.dart';
import 'package:movil_architect/models/home_project_models.dart';
import 'package:movil_architect/views/home_projects/section_detail_view.dart';
import 'package:movil_architect/views/home_projects/widgets/home_project_widgets.dart';
import 'package:movil_architect/views/shared/app_states.dart';

class StageDetailView extends StatelessWidget {
  const StageDetailView({
    super.key,
    required this.projectId,
    required this.stageNumber,
    required this.controller,
  });

  final String projectId;
  final int stageNumber;
  final HomeProjectDetailController controller;

  Future<void> _openAssist(BuildContext context) async {
    if (!controller.permissions.canEdit) return;
    final questionController = TextEditingController();
    StageAssistResult? result;
    String? error;
    var loading = false;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setLocal) {
            Future<void> run() async {
              setLocal(() {
                loading = true;
                error = null;
              });
              final response = await controller.requestAssist(
                stageNumber: stageNumber,
                question: questionController.text,
              );
              setLocal(() {
                loading = false;
                result = response;
                error = response == null
                    ? (controller.actionError ?? 'Sin respuesta')
                    : null;
              });
            }

            return Padding(
              padding: EdgeInsets.only(
                left: 20,
                right: 20,
                top: 20,
                bottom: MediaQuery.viewInsetsOf(context).bottom + 20,
              ),
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'Asistencia IA',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: questionController,
                      maxLength: 2000,
                      maxLines: 3,
                      decoration: const InputDecoration(
                        labelText: 'Pregunta (opcional)',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 8),
                    FilledButton(
                      onPressed: loading ? null : run,
                      child: loading
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('Consultar'),
                    ),
                    if (error != null) ...[
                      const SizedBox(height: 12),
                      Text(error!, style: const TextStyle(color: Colors.redAccent)),
                    ],
                    if (result != null) ...[
                      const SizedBox(height: 16),
                      Text(
                        result!.guidance.isNotEmpty
                            ? result!.guidance
                            : 'Sin orientación disponible.',
                        style: const TextStyle(height: 1.4),
                      ),
                      if (result!.planReviewRecommended) ...[
                        const SizedBox(height: 12),
                        const Material(
                          color: Color(0xFFFFF4D6),
                          borderRadius: BorderRadius.all(Radius.circular(12)),
                          child: Padding(
                            padding: EdgeInsets.all(12),
                            child: Text(
                              'Se recomienda vincular o revisar un plano en esta etapa.',
                              style: TextStyle(fontWeight: FontWeight.w600),
                            ),
                          ),
                        ),
                      ],
                      if (result!.localSources.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        const Text(
                          'Fuentes locales',
                          style: TextStyle(fontWeight: FontWeight.w800),
                        ),
                        for (final source in result!.localSources)
                          Text('• $source'),
                      ],
                      if (result!.webSources.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        const Text(
                          'Fuentes web',
                          style: TextStyle(fontWeight: FontWeight.w800),
                        ),
                        for (final source in result!.webSources)
                          Text('• $source'),
                      ],
                    ],
                  ],
                ),
              ),
            );
          },
        );
      },
    );
    questionController.dispose();
  }

  Future<void> _linkAnalysis(BuildContext context) async {
    if (!controller.permissions.canEdit) return;
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );
    final analyses = await controller.loadAnalysesPicker();
    if (!context.mounted) return;
    Navigator.pop(context);

    if (analyses.isEmpty) {
      AppNotifications.error(
        context,
        controller.actionError ?? 'No hay análisis disponibles',
      );
      return;
    }

    final selected = await showModalBottomSheet<LinkedAnalysisSummary>(
      context: context,
      builder: (context) => SafeArea(
        child: ListView(
          children: [
            const ListTile(
              title: Text(
                'Vincular plano / análisis',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
            for (final item in analyses)
              ListTile(
                title: Text(item.filename),
                subtitle: Text(
                  item.createdAt != null
                      ? formatRelativeTime(item.createdAt)
                      : 'Sin fecha',
                ),
                onTap: () => Navigator.pop(context, item),
              ),
          ],
        ),
      ),
    );
    if (selected == null || !context.mounted) return;

    final ok = await controller.linkStageAnalysis(
      stageNumber: stageNumber,
      analysisId: selected.id,
    );
    if (!context.mounted) return;
    AppNotifications.result(
      context,
      ok: ok,
      successMessage: 'Plano vinculado',
      errorMessage: controller.actionError,
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        if (controller.isDisposed) {
          return const Scaffold(body: SizedBox.shrink());
        }
        final project = controller.project;
        final stage = project?.stageByNumber(stageNumber);
        final canEdit = controller.permissions.canEdit;

        return Scaffold(
          backgroundColor: Theme.of(context).scaffoldBackgroundColor,
          appBar: AppBar(
            title: Text(
              stage == null
                  ? 'Etapa $stageNumber'
                  : '${stage.stageNumber}. ${stage.title}',
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
            backgroundColor: Theme.of(context).scaffoldBackgroundColor,
            elevation: 0,
          ),
          body: project == null || stage == null
              ? AppErrorView(
                  message: 'No se encontró la etapa',
                  onRetry: () => controller.load(refresh: true),
                )
              : RefreshIndicator(
                  onRefresh: () => controller.load(refresh: true),
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
                    children: [
                      Row(
                        children: [
                          HomeStatusChip(status: stage.status),
                          if (stage.planReview) ...[
                            const SizedBox(width: 8),
                            Chip(
                              label: const Text('Revisión de planos'),
                              visualDensity: VisualDensity.compact,
                              backgroundColor: scheme.surfaceContainerHighest,
                            ),
                          ],
                        ],
                      ),
                      if (stage.summary.isNotEmpty) ...[
                        const SizedBox(height: 14),
                        Text(
                          stage.summary,
                          style: TextStyle(
                            color: scheme.onSurfaceVariant,
                            height: 1.4,
                            fontSize: 15,
                          ),
                        ),
                      ],
                      if (canEdit) ...[
                        const SizedBox(height: 14),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            OutlinedButton.icon(
                              onPressed: controller.busy
                                  ? null
                                  : () => _openAssist(context),
                              icon: const Icon(Icons.auto_awesome),
                              label: const Text('Asistencia IA'),
                            ),
                            if (stage.planReview)
                              FilledButton.icon(
                                onPressed: controller.busy
                                    ? null
                                    : () => _linkAnalysis(context),
                                icon: const Icon(Icons.link),
                                label: const Text('Vincular plano'),
                              ),
                          ],
                        ),
                      ],
                      if (stage.aiGuidance.isNotEmpty) ...[
                        const SizedBox(height: 16),
                        Text(
                          'Orientación IA guardada',
                          style: TextStyle(
                            color: scheme.onSurface,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          stage.aiGuidance,
                          style: TextStyle(
                            color: scheme.onSurfaceVariant,
                            height: 1.4,
                          ),
                        ),
                      ],
                      if (stage.analysis != null || stage.analysisId != null) ...[
                        const SizedBox(height: 16),
                        Material(
                          color: Theme.of(context).cardColor,
                          borderRadius: BorderRadius.circular(16),
                          child: ListTile(
                            leading: const Icon(Icons.map_outlined),
                            title: Text(
                              stage.analysis?.filename ??
                                  'Análisis #${stage.analysisId}',
                              style: const TextStyle(fontWeight: FontWeight.w700),
                            ),
                            subtitle: Text(
                              stage.analysis?.createdAt != null
                                  ? formatRelativeTime(stage.analysis!.createdAt)
                                  : 'Plano vinculado a esta etapa',
                            ),
                          ),
                        ),
                      ],
                      const SizedBox(height: 16),
                      Text(
                        'Progreso de apartados: '
                        '${stage.sectionsProgress.done}/${stage.sectionsProgress.total}',
                        style: TextStyle(
                          color: scheme.onSurface,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 8),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(999),
                        child: LinearProgressIndicator(
                          value: stage.sectionsProgress.total == 0
                              ? 0
                              : stage.sectionsProgress.done /
                                  stage.sectionsProgress.total,
                          minHeight: 7,
                          backgroundColor: scheme.surfaceContainerHighest,
                          color: scheme.onSurface,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Con archivos: ${stage.sectionsProgress.withFiles} · '
                        'Sin docs: ${stage.sectionsProgress.withoutDocs} · '
                        'Requieren acción: ${stage.sectionsProgress.needsAction}',
                        style: TextStyle(
                          color: scheme.onSurfaceVariant,
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(height: 22),
                      Text(
                        'Apartados',
                        style: TextStyle(
                          color: scheme.onSurface,
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 10),
                      if (stage.sections.isEmpty)
                        Text(
                          'Esta etapa no tiene apartados.',
                          style: TextStyle(color: scheme.onSurfaceVariant),
                        )
                      else
                        for (final section in stage.sections) ...[
                          Material(
                            color: Theme.of(context).cardColor,
                            borderRadius: BorderRadius.circular(16),
                            child: ListTile(
                              onTap: () async {
                                await Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (_) => SectionDetailView(
                                      projectId: projectId,
                                      stageNumber: stageNumber,
                                      sectionId: section.id,
                                      controller: controller,
                                    ),
                                  ),
                                );
                                if (!controller.isDisposed) {
                                  await controller.load(refresh: true);
                                }
                              },
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 8,
                              ),
                              title: Text(
                                section.title,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              subtitle: Padding(
                                padding: const EdgeInsets.only(top: 8),
                                child: Row(
                                  children: [
                                    HomeStatusChip(status: section.status),
                                    const SizedBox(width: 8),
                                    Icon(
                                      section.hasDocuments
                                          ? Icons.attach_file
                                          : Icons.insert_drive_file_outlined,
                                      size: 16,
                                      color: scheme.onSurfaceVariant,
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      section.hasDocuments
                                          ? '${section.documents.length} doc(s)'
                                          : 'Sin docs',
                                      style: TextStyle(
                                        color: scheme.onSurfaceVariant,
                                        fontSize: 12,
                                      ),
                                    ),
                                    if (section.slots.isNotEmpty) ...[
                                      const SizedBox(width: 8),
                                      Icon(
                                        Icons.task_alt,
                                        size: 16,
                                        color: scheme.onSurfaceVariant,
                                      ),
                                      const SizedBox(width: 4),
                                      Text(
                                        '${section.slots.where((s) => s.filled || section.documents.any((d) => d.slotKey == s.key)).length}/${section.slots.length} entregas',
                                        style: TextStyle(
                                          color: scheme.onSurfaceVariant,
                                          fontSize: 12,
                                        ),
                                      ),
                                    ],
                                    if (section.commentsCount > 0) ...[
                                      const SizedBox(width: 8),
                                      Icon(
                                        Icons.chat_bubble_outline,
                                        size: 16,
                                        color: scheme.onSurfaceVariant,
                                      ),
                                      const SizedBox(width: 2),
                                      Text(
                                        '${section.commentsCount}',
                                        style: TextStyle(
                                          color: scheme.onSurfaceVariant,
                                          fontSize: 12,
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                              trailing: const Icon(Icons.chevron_right),
                            ),
                          ),
                          const SizedBox(height: 10),
                        ],
                    ],
                  ),
                ),
        );
      },
    );
  }
}
