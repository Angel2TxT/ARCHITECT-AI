import 'package:flutter/material.dart';
import 'package:movil_architect/controllers/home_project_controller.dart';
import 'package:movil_architect/core/utils/app_notifications.dart';
import 'package:movil_architect/core/utils/date_utils.dart';
import 'package:movil_architect/models/home_project_models.dart';
import 'package:movil_architect/views/home_projects/section_detail_view.dart';
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

  Future<void> _openAssist(BuildContext context, {String? initialGuidance}) async {
    if (!controller.permissions.canEdit) return;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Theme.of(context).brightness == Brightness.dark
          ? const Color(0xFF141417)
          : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) => _StageAssistSheet(
        controller: controller,
        stageNumber: stageNumber,
        initialGuidance: initialGuidance,
      ),
    );
  }

  Future<void> _linkAnalysis(BuildContext context) async {
    if (!controller.permissions.canEdit) return;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final sheetBg = isDark ? const Color(0xFF141417) : Colors.white;
    final primaryBlack = isDark ? Colors.white : const Color(0xFF111111);
    final borderColor = isDark ? const Color(0xFF3F3F46) : const Color(0xFFD1D5DB);

    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => Center(
        child: CircularProgressIndicator(
          color: isDark ? Colors.white : const Color(0xFF111111),
        ),
      ),
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
      backgroundColor: sheetBg,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: ListView(
            shrinkWrap: true,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                child: Text(
                  'Vincular plano / análisis',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: primaryBlack,
                  ),
                ),
              ),
              const Divider(height: 1),
              for (final item in analyses)
                ListTile(
                  leading: Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF222226) : const Color(0xFFF2F2F4),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: borderColor),
                    ),
                    child: Icon(Icons.map_outlined, size: 20, color: primaryBlack),
                  ),
                  title: Text(
                    item.filename,
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: primaryBlack,
                    ),
                  ),
                  subtitle: Text(
                    item.createdAt != null
                        ? formatRelativeTime(item.createdAt)
                        : 'Sin fecha',
                    style: TextStyle(
                      color: isDark ? Colors.white54 : Colors.black45,
                      fontSize: 12,
                    ),
                  ),
                  trailing: Icon(
                    Icons.arrow_forward_ios_rounded,
                    size: 14,
                    color: isDark ? Colors.white38 : Colors.black38,
                  ),
                  onTap: () => Navigator.pop(context, item),
                ),
            ],
          ),
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? const Color(0xFF0C0C0E) : const Color(0xFFF7F7F8);
    final cardBg = isDark ? const Color(0xFF141417) : Colors.white;
    final borderColor = isDark ? const Color(0xFF3F3F46) : const Color(0xFFD1D5DB);
    final primaryBlack = isDark ? Colors.white : const Color(0xFF111111);
    final secondaryText = isDark ? const Color(0xFFA1A1AA) : const Color(0xFF52525B);
    final mutedText = isDark ? const Color(0xFF71717A) : const Color(0xFF8E8E93);
    final tagBg = isDark ? const Color(0xFF1E1E22) : const Color(0xFFF1F1F4);

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
          backgroundColor: bg,
          appBar: AppBar(
            backgroundColor: bg,
            foregroundColor: primaryBlack,
            elevation: 0,
            scrolledUnderElevation: 0,
            title: Text(
              stage == null
                  ? 'Etapa $stageNumber'
                  : '${stage.stageNumber}. ${stage.title}',
              style: TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 17,
                color: primaryBlack,
              ),
            ),
          ),
          body: project == null || stage == null
              ? AppErrorView(
                  message: 'No se encontró la etapa',
                  onRetry: () => controller.load(refresh: true),
                )
              : RefreshIndicator(
                  color: primaryBlack,
                  onRefresh: () => controller.load(refresh: true),
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
                    children: [
                      // 1. HERO CARD: Información principal de la etapa
                      Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: cardBg,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: borderColor, width: 1.4),
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
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                _StageStatusPill(status: stage.status, isDark: isDark, borderColor: borderColor),
                                if (stage.planReview) ...[
                                  const SizedBox(width: 8),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: tagBg,
                                      borderRadius: BorderRadius.circular(999),
                                      border: Border.all(color: borderColor, width: 1.0),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(Icons.layers_outlined, size: 13, color: primaryBlack),
                                        const SizedBox(width: 4),
                                        Text(
                                          'Revisión de planos',
                                          style: TextStyle(
                                            color: primaryBlack,
                                            fontSize: 11,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                                const Spacer(),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: tagBg,
                                    borderRadius: BorderRadius.circular(999),
                                    border: Border.all(color: borderColor, width: 1.0),
                                  ),
                                  child: Text(
                                    'Etapa ${stage.stageNumber} de 9',
                                    style: TextStyle(
                                      color: primaryBlack,
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 14),
                            Text(
                              '${stage.stageNumber}. ${stage.title}',
                              style: TextStyle(
                                color: primaryBlack,
                                fontSize: 22,
                                fontWeight: FontWeight.w800,
                                height: 1.2,
                              ),
                            ),
                            if (stage.summary.isNotEmpty) ...[
                              const SizedBox(height: 8),
                              Text(
                                stage.summary,
                                style: TextStyle(
                                  color: secondaryText,
                                  height: 1.45,
                                  fontSize: 14,
                                ),
                              ),
                            ],
                            if (canEdit) ...[
                              const SizedBox(height: 18),
                              Wrap(
                                spacing: 10,
                                runSpacing: 10,
                                children: [
                                  FilledButton.icon(
                                    onPressed: controller.busy
                                        ? null
                                        : () => _openAssist(
                                              context,
                                              initialGuidance: stage.aiGuidance,
                                            ),
                                    style: FilledButton.styleFrom(
                                      backgroundColor: isDark ? Colors.white : const Color(0xFF111111),
                                      foregroundColor: isDark ? const Color(0xFF111111) : Colors.white,
                                      elevation: 0,
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(999),
                                      ),
                                      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                                    ),
                                    icon: const Icon(Icons.auto_awesome, size: 16),
                                    label: const Text(
                                      'Asistencia IA',
                                      style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                                    ),
                                  ),
                                  if (stage.planReview)
                                    OutlinedButton.icon(
                                      onPressed: controller.busy
                                          ? null
                                          : () => _linkAnalysis(context),
                                      style: OutlinedButton.styleFrom(
                                        foregroundColor: primaryBlack,
                                        side: BorderSide(color: primaryBlack, width: 1.2),
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(999),
                                        ),
                                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                                      ),
                                      icon: const Icon(Icons.link, size: 16),
                                      label: const Text(
                                        'Vincular plano',
                                        style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                                      ),
                                    ),
                                ],
                              ),
                            ],
                          ],
                        ),
                      ),

                      const SizedBox(height: 16),

                      // 2. METRICS CARD: Progreso del expediente
                      Container(
                        padding: const EdgeInsets.all(18),
                        decoration: BoxDecoration(
                          color: cardBg,
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(color: borderColor, width: 1.4),
                          boxShadow: [
                            BoxShadow(
                              color: isDark
                                  ? Colors.black.withValues(alpha: 0.25)
                                  : Colors.black.withValues(alpha: 0.03),
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(6),
                                  decoration: BoxDecoration(
                                    color: tagBg,
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(color: borderColor, width: 1.0),
                                  ),
                                  child: Icon(
                                    Icons.donut_large_rounded,
                                    size: 16,
                                    color: primaryBlack,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  'Progreso de apartados',
                                  style: TextStyle(
                                    color: primaryBlack,
                                    fontSize: 14,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                const Spacer(),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: tagBg,
                                    borderRadius: BorderRadius.circular(999),
                                    border: Border.all(color: borderColor, width: 1.0),
                                  ),
                                  child: Text(
                                    '${stage.sectionsProgress.done} de ${stage.sectionsProgress.total}',
                                    style: TextStyle(
                                      color: primaryBlack,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 14),
                            Container(
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(999),
                                border: Border.all(color: borderColor, width: 1.0),
                              ),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(999),
                                child: LinearProgressIndicator(
                                  value: stage.sectionsProgress.total == 0
                                      ? 0
                                      : stage.sectionsProgress.done / stage.sectionsProgress.total,
                                  minHeight: 8,
                                  backgroundColor: isDark ? const Color(0xFF26262B) : const Color(0xFFEAEAED),
                                  valueColor: AlwaysStoppedAnimation<Color>(
                                    isDark ? Colors.white : const Color(0xFF111111),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 16),
                            Container(
                              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 10),
                              decoration: BoxDecoration(
                                color: tagBg,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: borderColor, width: 1.2),
                              ),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: _MetricColumn(
                                      number: '${stage.sectionsProgress.withFiles}',
                                      label: 'Con archivos',
                                      isDark: isDark,
                                    ),
                                  ),
                                  Container(width: 1.2, height: 28, color: borderColor),
                                  Expanded(
                                    child: _MetricColumn(
                                      number: '${stage.sectionsProgress.needsAction}',
                                      label: 'Por revisar',
                                      isDark: isDark,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),

                      // 3. PLANO VINCULADO (si existe)
                      if (stage.analysis != null || stage.analysisId != null) ...[
                        const SizedBox(height: 16),
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: cardBg,
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(color: borderColor, width: 1.4),
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 42,
                                height: 42,
                                decoration: BoxDecoration(
                                  color: isDark ? const Color(0xFF222226) : const Color(0xFF111111),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(color: borderColor, width: 1.0),
                                ),
                                child: Icon(
                                  Icons.map_outlined,
                                  color: isDark ? Colors.white : Colors.white,
                                  size: 20,
                                ),
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      stage.analysis?.filename ?? 'Análisis #${stage.analysisId}',
                                      style: TextStyle(
                                        color: primaryBlack,
                                        fontWeight: FontWeight.w700,
                                        fontSize: 14,
                                      ),
                                    ),
                                    const SizedBox(height: 3),
                                    Text(
                                      stage.analysis?.createdAt != null
                                          ? 'Vinculado ${formatRelativeTime(stage.analysis!.createdAt)}'
                                          : 'Plano vinculado a esta etapa',
                                      style: TextStyle(color: mutedText, fontSize: 12),
                                    ),
                                  ],
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: tagBg,
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(color: borderColor, width: 1.0),
                                ),
                                child: Text(
                                  'Activo',
                                  style: TextStyle(
                                    color: primaryBlack,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],



                      const SizedBox(height: 24),

                      // 5. ENCABEZADO DE APARTADOS
                      Row(
                        children: [
                          Text(
                            'Apartados',
                            style: TextStyle(
                              color: primaryBlack,
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                            decoration: BoxDecoration(
                              color: tagBg,
                              borderRadius: BorderRadius.circular(999),
                              border: Border.all(color: borderColor, width: 1.0),
                            ),
                            child: Text(
                              '${stage.sections.length}',
                              style: TextStyle(
                                color: primaryBlack,
                                fontSize: 12,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Entregables y documentación requerida para esta etapa',
                        style: TextStyle(color: mutedText, fontSize: 12),
                      ),
                      const SizedBox(height: 14),

                      // 6. LISTA DE APARTADOS
                      if (stage.sections.isEmpty)
                        Container(
                          padding: const EdgeInsets.all(28),
                          decoration: BoxDecoration(
                            color: cardBg,
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(color: borderColor, width: 1.4),
                          ),
                          child: Column(
                            children: [
                              Icon(Icons.folder_open_outlined, size: 36, color: mutedText),
                              const SizedBox(height: 10),
                              Text(
                                'Esta etapa no tiene apartados.',
                                style: TextStyle(
                                  color: secondaryText,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        )
                      else
                        for (final section in stage.sections) ...[
                          _SectionCard(
                            section: section,
                            isDark: isDark,
                            cardBg: cardBg,
                            borderColor: borderColor,
                            primaryBlack: primaryBlack,
                            secondaryText: secondaryText,
                            mutedText: mutedText,
                            tagBg: tagBg,
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
                          ),
                          const SizedBox(height: 12),
                        ],
                    ],
                  ),
                ),
        );
      },
    );
  }
}

class _MetricColumn extends StatelessWidget {
  const _MetricColumn({
    required this.number,
    required this.label,
    required this.isDark,
  });

  final String number;
  final String label;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final primaryBlack = isDark ? Colors.white : const Color(0xFF111111);
    final mutedText = isDark ? const Color(0xFF71717A) : const Color(0xFF8E8E93);

    return Column(
      children: [
        Text(
          number,
          style: TextStyle(
            color: primaryBlack,
            fontSize: 16,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: mutedText,
            fontSize: 11,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.section,
    required this.isDark,
    required this.cardBg,
    required this.borderColor,
    required this.primaryBlack,
    required this.secondaryText,
    required this.mutedText,
    required this.tagBg,
    required this.onTap,
  });

  final HomeProjectSection section;
  final bool isDark;
  final Color cardBg;
  final Color borderColor;
  final Color primaryBlack;
  final Color secondaryText;
  final Color mutedText;
  final Color tagBg;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final filledDeliverables = section.slots
        .where((s) => s.filled || section.documents.any((d) => d.slotKey == s.key))
        .length;

    final sectionBorderColor = isDark
        ? const Color(0xFF3F3F46)
        : const Color(0xFFD1D5DB);

    return Container(
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: sectionBorderColor, width: 1.5),
        boxShadow: [
          BoxShadow(
            color: isDark
                ? Colors.black.withValues(alpha: 0.35)
                : Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          splashColor: primaryBlack.withValues(alpha: 0.05),
          highlightColor: primaryBlack.withValues(alpha: 0.02),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        color: tagBg,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: borderColor, width: 1.0),
                      ),
                      child: Icon(
                        Icons.folder_outlined,
                        size: 20,
                        color: primaryBlack,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            section.title,
                            style: TextStyle(
                              color: primaryBlack,
                              fontWeight: FontWeight.w700,
                              fontSize: 15,
                            ),
                          ),
                          if (section.description.isNotEmpty) ...[
                            const SizedBox(height: 3),
                            Text(
                              section.description,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: mutedText,
                                fontSize: 12,
                                height: 1.3,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        color: tagBg,
                        shape: BoxShape.circle,
                        border: Border.all(color: borderColor, width: 1.0),
                      ),
                      child: Icon(
                        Icons.chevron_right_rounded,
                        size: 18,
                        color: primaryBlack,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Container(
                  height: 1,
                  color: borderColor,
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    _MonoStatusBadge(status: section.status, isDark: isDark),
                    if (section.hasDocuments)
                      _BadgeChip(
                        icon: Icons.attach_file_rounded,
                        label: '${section.documents.length} doc(s)',
                        isDark: isDark,
                        tagBg: tagBg,
                        borderColor: borderColor,
                      ),
                    if (section.slots.isNotEmpty)
                      _BadgeChip(
                        icon: Icons.check_circle_outline_rounded,
                        label: '$filledDeliverables/${section.slots.length} entregas',
                        isDark: isDark,
                        tagBg: tagBg,
                        borderColor: borderColor,
                      ),
                    if (section.commentsCount > 0)
                      _BadgeChip(
                        icon: Icons.chat_bubble_outline_rounded,
                        label: '${section.commentsCount}',
                        isDark: isDark,
                        tagBg: tagBg,
                        borderColor: borderColor,
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

class _StageStatusPill extends StatelessWidget {
  const _StageStatusPill({
    required this.status,
    required this.isDark,
    this.borderColor,
  });

  final String status;
  final bool isDark;
  final Color? borderColor;

  @override
  Widget build(BuildContext context) {
    final label = homeProjectStatusLabel(status);
    final isDone = status == 'completed';
    final effectiveBorder = borderColor ??
        (isDark ? const Color(0xFF3F3F46) : const Color(0xFFD1D5DB));

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
              Icons.check_circle,
              size: 13,
              color: isDark ? const Color(0xFF111111) : Colors.white,
            ),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                color: isDark ? const Color(0xFF111111) : Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF222226) : const Color(0xFFF1F1F4),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: effectiveBorder,
          width: 1.0,
        ),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: isDark ? Colors.white : const Color(0xFF111111),
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _MonoStatusBadge extends StatelessWidget {
  const _MonoStatusBadge({required this.status, required this.isDark});

  final String status;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final label = homeProjectStatusLabel(status);
    final isCompleted = status == 'completed';
    final isInProgress = status == 'in_progress';

    if (isCompleted) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: isDark ? Colors.white : const Color(0xFF111111),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.check,
              size: 11,
              color: isDark ? const Color(0xFF111111) : Colors.white,
            ),
            const SizedBox(width: 3),
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

    if (isInProgress) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF222226) : const Color(0xFFEAEAED),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: isDark ? Colors.white38 : const Color(0xFF111111),
            width: 1,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isDark ? Colors.white : const Color(0xFF111111),
            fontSize: 11,
            fontWeight: FontWeight.w700,
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1E22) : const Color(0xFFF4F4F6),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: isDark ? const Color(0xFF3F3F46) : const Color(0xFFD1D5DB),
          width: 0.8,
        ),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: isDark ? const Color(0xFFA1A1AA) : const Color(0xFF52525B),
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _BadgeChip extends StatelessWidget {
  const _BadgeChip({
    required this.icon,
    required this.label,
    required this.isDark,
    required this.tagBg,
    required this.borderColor,
  });

  final IconData icon;
  final String label;
  final bool isDark;
  final Color tagBg;
  final Color borderColor;

  @override
  Widget build(BuildContext context) {
    final textCol = isDark ? const Color(0xFFA1A1AA) : const Color(0xFF52525B);
    final iconCol = isDark ? const Color(0xFF71717A) : const Color(0xFF71717A);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: tagBg,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: borderColor, width: 1.0),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: iconCol),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              color: textCol,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _StageAssistSheet extends StatefulWidget {
  const _StageAssistSheet({
    required this.controller,
    required this.stageNumber,
    this.initialGuidance,
  });

  final HomeProjectDetailController controller;
  final int stageNumber;
  final String? initialGuidance;

  @override
  State<_StageAssistSheet> createState() => _StageAssistSheetState();
}

class _StageAssistSheetState extends State<_StageAssistSheet> {
  late final TextEditingController _questionController;
  StageAssistResult? _result;
  String? _error;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _questionController = TextEditingController();
    if (widget.initialGuidance != null &&
        widget.initialGuidance!.trim().isNotEmpty) {
      _result = StageAssistResult(
        stageNumber: widget.stageNumber,
        guidance: widget.initialGuidance!.trim(),
        localSources: const [],
        webSources: const [],
        planReviewRecommended: false,
      );
    }
  }

  @override
  void dispose() {
    _questionController.dispose();
    super.dispose();
  }

  Future<void> _run() async {
    FocusScope.of(context).unfocus();
    setState(() {
      _loading = true;
      _error = null;
    });

    final response = await widget.controller.requestAssist(
      stageNumber: widget.stageNumber,
      question: _questionController.text,
    );

    if (!mounted) return;
    setState(() {
      _loading = false;
      _result = response;
      _error = response == null
          ? (widget.controller.actionError ?? 'Sin respuesta')
          : null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primaryBlack = isDark ? Colors.white : const Color(0xFF111111);
    final borderColor = isDark ? const Color(0xFF3F3F46) : const Color(0xFFD1D5DB);
    final maxHeight = MediaQuery.sizeOf(context).height * 0.85;

    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: maxHeight),
      child: Padding(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 14,
          bottom: MediaQuery.viewInsetsOf(context).bottom + 24,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: isDark ? Colors.white24 : Colors.black12,
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: isDark ? Colors.white : const Color(0xFF111111),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    Icons.auto_awesome,
                    size: 18,
                    color: isDark ? const Color(0xFF111111) : Colors.white,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Asistencia IA',
                        style: TextStyle(
                          color: primaryBlack,
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Pregunta sobre normativas y requerimientos de esta etapa',
                        style: TextStyle(
                          color: isDark ? Colors.white60 : Colors.black54,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: Icon(
                    Icons.close_rounded,
                    size: 20,
                    color: isDark ? Colors.white60 : Colors.black54,
                  ),
                  onPressed: () {
                    FocusScope.of(context).unfocus();
                    Navigator.of(context).pop();
                  },
                  splashRadius: 20,
                  tooltip: 'Cerrar',
                ),
              ],
            ),
            const SizedBox(height: 14),
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextField(
                      controller: _questionController,
                      maxLength: 2000,
                      maxLines: 3,
                      style: TextStyle(
                        fontSize: 14,
                        color: primaryBlack,
                      ),
                      decoration: InputDecoration(
                        hintText: 'Ej. ¿Qué documentos se requieren para iniciar esta etapa?',
                        hintStyle: TextStyle(
                          fontSize: 13,
                          color: isDark ? Colors.white38 : Colors.black38,
                        ),
                        filled: true,
                        fillColor: isDark ? const Color(0xFF1C1C20) : const Color(0xFFF7F7F8),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: BorderSide(color: borderColor),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: BorderSide(color: borderColor),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: BorderSide(color: primaryBlack, width: 1.5),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      height: 46,
                      child: FilledButton(
                        onPressed: _loading ? null : _run,
                        style: FilledButton.styleFrom(
                          backgroundColor: isDark ? Colors.white : const Color(0xFF111111),
                          foregroundColor: isDark ? const Color(0xFF111111) : Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: _loading
                            ? SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: isDark ? const Color(0xFF111111) : Colors.white,
                                ),
                              )
                            : const Text(
                                'Consultar con la IA',
                                style: TextStyle(fontWeight: FontWeight.w700),
                              ),
                      ),
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.red.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.red.withValues(alpha: 0.3)),
                        ),
                        child: Text(
                          _error!,
                          style: const TextStyle(
                            color: Colors.redAccent,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                    if (_result != null) ...[
                      const SizedBox(height: 18),
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: isDark ? const Color(0xFF1C1C20) : const Color(0xFFF7F7F8),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: borderColor),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(
                                  Icons.lightbulb_outline,
                                  size: 16,
                                  color: primaryBlack,
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  'Orientación técnica',
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                    color: primaryBlack,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            Text(
                              _result!.guidance.isNotEmpty
                                  ? _result!.guidance
                                  : 'Sin orientación disponible.',
                              style: TextStyle(
                                height: 1.45,
                                fontSize: 13,
                                color: isDark ? Colors.white70 : Colors.black87,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (_result!.planReviewRecommended) ...[
                        const SizedBox(height: 12),
                        Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: isDark ? const Color(0xFF222226) : const Color(0xFFF0F0F2),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: primaryBlack.withValues(alpha: 0.15)),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.layers_outlined, size: 18, color: primaryBlack),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'Se recomienda vincular o revisar un plano en esta etapa.',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 12,
                                    color: primaryBlack,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                      if (_result!.localSources.isNotEmpty) ...[
                        const SizedBox(height: 14),
                        Text(
                          'Fuentes normativas',
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 12,
                            color: primaryBlack,
                          ),
                        ),
                        const SizedBox(height: 6),
                        for (final source in _result!.localSources)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 4),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('• ', style: TextStyle(color: primaryBlack)),
                                Expanded(
                                  child: Text(
                                    source,
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: isDark ? Colors.white60 : Colors.black54,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                      if (_result!.webSources.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        Text(
                          'Fuentes web',
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 12,
                            color: primaryBlack,
                          ),
                        ),
                        const SizedBox(height: 6),
                        for (final source in _result!.webSources)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 4),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('• ', style: TextStyle(color: primaryBlack)),
                                Expanded(
                                  child: Text(
                                    source,
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: isDark ? Colors.white60 : Colors.black54,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

