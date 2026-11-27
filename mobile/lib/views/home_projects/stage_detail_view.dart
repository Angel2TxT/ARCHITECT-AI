import 'package:flutter/material.dart';
import 'package:movil_architect/controllers/home_project_controller.dart';
import 'package:movil_architect/core/theme/architect_theme_tokens.dart';
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

  Future<void> _openAssist(
    BuildContext context, {
    String? initialGuidance,
  }) async {
    if (!controller.permissions.canEdit) return;
    final tokens = ArchitectThemeTokens.of(context);

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: tokens.surfaceSecondary,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
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
    final tokens = ArchitectThemeTokens.of(context);

    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => Center(
        child: CircularProgressIndicator(color: tokens.accent),
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
      backgroundColor: tokens.surfaceSecondary,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (sheetContext) => SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: ListView(
            shrinkWrap: true,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: tokens.borderStrong,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 14, 20, 10),
                child: Text(
                  'Vincular plano / análisis',
                  style: ArchitectThemeTokens.appleDisplay(
                    color: tokens.textPrimary,
                    fontSize: 18,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              Divider(height: 1, thickness: 1, color: tokens.borderSubtle),
              for (final item in analyses)
                ListTile(
                  leading: Icon(
                    Icons.map_outlined,
                    size: 20,
                    color: tokens.accent,
                  ),
                  title: Text(
                    item.filename,
                    style: ArchitectThemeTokens.appleText(
                      color: tokens.textPrimary,
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  subtitle: Text(
                    item.createdAt != null
                        ? formatRelativeTime(item.createdAt)
                        : 'Sin fecha',
                    style: ArchitectThemeTokens.appleText(
                      color: tokens.textSecondary,
                      fontSize: 12,
                    ),
                  ),
                  trailing: Icon(
                    Icons.chevron_right_rounded,
                    size: 18,
                    color: tokens.textSecondary,
                  ),
                  onTap: () => Navigator.pop(sheetContext, item),
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
    final tokens = ArchitectThemeTokens.of(context);
    final reduceMotion = MediaQuery.disableAnimationsOf(context);

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
          backgroundColor: tokens.drawerBackground,
          appBar: AppBar(
            backgroundColor: tokens.drawerBackground,
            foregroundColor: tokens.textPrimary,
            elevation: 0,
            scrolledUnderElevation: 0,
            centerTitle: true,
            leading: Semantics(
              button: true,
              label: 'Regresar',
              child: IconButton(
                icon: Icon(
                  Icons.arrow_back_rounded,
                  size: 22,
                  color: tokens.textPrimary,
                ),
                tooltip: 'Regresar',
                constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
                onPressed: () => Navigator.of(context).maybePop(),
              ),
            ),
            title: Semantics(
              header: true,
              child: Text(
                stage == null
                    ? 'Etapa $stageNumber'
                    : '${stage.stageNumber}. ${stage.title}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: ArchitectThemeTokens.appleDisplay(
                  color: tokens.textPrimary,
                  fontSize: 19,
                  fontWeight: FontWeight.w500,
                  letterSpacing: -0.3,
                ),
              ),
            ),
          ),
          body: SafeArea(
            top: false,
            child: project == null || stage == null
                ? AppErrorView(
                    message: 'No se encontró la etapa',
                    onRetry: () => controller.load(refresh: true),
                  )
                : RefreshIndicator(
                    color: tokens.accent,
                    onRefresh: () => controller.load(refresh: true),
                    child: ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.fromLTRB(20, 12, 20, 36),
                      children: [
                        // 1. TARJETA PRINCIPAL DE LA ETAPA
                        _StageOverviewCard(
                          stage: stage,
                          canEdit: canEdit,
                          busy: controller.busy,
                          reduceMotion: reduceMotion,
                          onAssist: () => _openAssist(
                            context,
                            initialGuidance: stage.aiGuidance,
                          ),
                          onLinkPlan: () => _linkAnalysis(context),
                        ),

                        const SizedBox(height: 16),

                        // 2. PROGRESO DE APARTADOS
                        _StageProgressCard(progress: stage.sectionsProgress),

                        // 3. PLANO VINCULADO (si existe)
                        if (stage.analysis != null ||
                            stage.analysisId != null) ...[
                          const SizedBox(height: 16),
                          _LinkedAnalysisCard(stage: stage),
                        ],

                        const SizedBox(height: 28),

                        // 4. ENCABEZADO DE APARTADOS
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Expanded(
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.baseline,
                                textBaseline: TextBaseline.alphabetic,
                                children: [
                                  Text(
                                    'Apartados',
                                    style: ArchitectThemeTokens.appleDisplay(
                                      color: tokens.textPrimary,
                                      fontSize: 18,
                                      fontWeight: FontWeight.w500,
                                      letterSpacing: -0.25,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    '${stage.sections.length}',
                                    style: ArchitectThemeTokens.appleText(
                                      color: tokens.textSecondary,
                                      fontSize: 14,
                                      fontWeight: FontWeight.w500,
                                      fontFeatures: const [
                                        FontFeature.tabularFigures(),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            if (controller.permissions.canCreateSection) ...[
                              const SizedBox(width: 12),
                              NewSectionButton(
                                enabled: !controller.busy,
                                onTap: () => showCreateSectionDialog(
                                  context: context,
                                  controller: controller,
                                  stageNumber: stage.stageNumber,
                                ),
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Entregables y documentación requerida para esta etapa',
                          style: ArchitectThemeTokens.appleText(
                            color: tokens.textSecondary,
                            fontSize: 14,
                            fontWeight: FontWeight.w400,
                          ),
                        ),
                        const SizedBox(height: 14),

                        // 5. LISTA DE APARTADOS
                        if (stage.sections.isEmpty)
                          Container(
                            padding: const EdgeInsets.all(24),
                            decoration: BoxDecoration(
                              color: tokens.surfaceSecondary,
                              borderRadius: BorderRadius.circular(
                                ArchitectThemeTokens.radiusLg,
                              ),
                              border: Border.all(
                                color: tokens.borderSubtle,
                                width: 1,
                              ),
                            ),
                            child: Column(
                              children: [
                                Icon(
                                  Icons.folder_outlined,
                                  size: 32,
                                  color: tokens.textSecondary,
                                ),
                                const SizedBox(height: 10),
                                Text(
                                  'Esta etapa no tiene apartados.',
                                  style: ArchitectThemeTokens.appleText(
                                    color: tokens.textSecondary,
                                    fontSize: 14,
                                    fontWeight: FontWeight.w400,
                                  ),
                                ),
                              ],
                            ),
                          )
                        else
                          for (final section in stage.sections) ...[
                            _SectionCard(
                              section: section,
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
                            const SizedBox(height: 10),
                          ],
                      ],
                    ),
                  ),
          ),
        );
      },
    );
  }
}

class _StageOverviewCard extends StatelessWidget {
  const _StageOverviewCard({
    required this.stage,
    required this.canEdit,
    required this.busy,
    required this.reduceMotion,
    required this.onAssist,
    required this.onLinkPlan,
  });

  final HomeProjectStage stage;
  final bool canEdit;
  final bool busy;
  final bool reduceMotion;
  final VoidCallback onAssist;
  final VoidCallback onLinkPlan;

  @override
  Widget build(BuildContext context) {
    final tokens = ArchitectThemeTokens.of(context);
    final stageLabel =
        'Etapa ${stage.stageNumber.toString().padLeft(2, '0')} de 09';

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: tokens.surfaceSecondary,
        borderRadius: BorderRadius.circular(ArchitectThemeTokens.radiusLg),
        border: Border.all(color: tokens.borderSubtle, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _SemanticStatusIndicator(status: stage.status),
              const Spacer(),
              Text(
                stageLabel,
                style: ArchitectThemeTokens.appleText(
                  color: tokens.textSecondary,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
          if (stage.planReview) ...[
            const SizedBox(height: 8),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.layers_outlined,
                  size: 14,
                  color: tokens.accent,
                ),
                const SizedBox(width: 6),
                Text(
                  'Revisión de planos',
                  style: ArchitectThemeTokens.appleText(
                    color: tokens.accent,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ],
          if (stage.summary.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              stage.summary,
              style: ArchitectThemeTokens.appleText(
                color: tokens.textSecondary,
                fontSize: 14,
                fontWeight: FontWeight.w400,
                height: 1.45,
              ),
            ),
          ],
          if (canEdit) ...[
            const SizedBox(height: 18),
            _AssistAiButton(
              busy: busy,
              reduceMotion: reduceMotion,
              onPressed: onAssist,
            ),
            if (stage.planReview) ...[
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: busy ? null : onLinkPlan,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: tokens.textPrimary,
                    side: BorderSide(color: tokens.borderStrong, width: 1),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(
                        ArchitectThemeTokens.radiusMd,
                      ),
                    ),
                    minimumSize: const Size(double.infinity, 44),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 10,
                    ),
                  ),
                  icon: Icon(
                    Icons.link_rounded,
                    size: 18,
                    color: tokens.textPrimary,
                  ),
                  label: Text(
                    'Vincular plano',
                    style: ArchitectThemeTokens.appleText(
                      color: tokens.textPrimary,
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }
}

class _AssistAiButton extends StatefulWidget {
  const _AssistAiButton({
    required this.busy,
    required this.reduceMotion,
    required this.onPressed,
  });

  final bool busy;
  final bool reduceMotion;
  final VoidCallback onPressed;

  @override
  State<_AssistAiButton> createState() => _AssistAiButtonState();
}

class _AssistAiButtonState extends State<_AssistAiButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final tokens = ArchitectThemeTokens.of(context);
    final disabled = widget.busy;

    return Semantics(
      button: true,
      enabled: !disabled,
      label: 'Abrir Asistencia IA para esta etapa',
      child: AnimatedScale(
        scale: (_pressed && !disabled && !widget.reduceMotion) ? 0.98 : 1.0,
        duration: widget.reduceMotion
            ? Duration.zero
            : const Duration(milliseconds: 110),
        curve: Curves.easeOutCubic,
        child: Material(
          color: disabled
              ? tokens.primaryActionBg.withValues(alpha: 0.45)
              : tokens.primaryActionBg,
          borderRadius: BorderRadius.circular(ArchitectThemeTokens.radiusMd),
          child: InkWell(
            onTap: disabled ? null : widget.onPressed,
            onHighlightChanged: (value) {
              if (mounted) setState(() => _pressed = value);
            },
            borderRadius: BorderRadius.circular(ArchitectThemeTokens.radiusMd),
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                minWidth: double.infinity,
                minHeight: 48,
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.auto_awesome_outlined,
                      size: 18,
                      color: tokens.primaryActionFg,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Asistencia IA',
                      style: ArchitectThemeTokens.appleText(
                        color: tokens.primaryActionFg,
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _StageProgressCard extends StatelessWidget {
  const _StageProgressCard({required this.progress});

  final SectionsProgress progress;

  @override
  Widget build(BuildContext context) {
    final tokens = ArchitectThemeTokens.of(context);
    final ratio = progress.total == 0
        ? 0.0
        : (progress.done / progress.total).clamp(0.0, 1.0);
    final percent = (ratio * 100).round();
    final isComplete = progress.total > 0 && progress.done >= progress.total;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: tokens.surfaceSecondary,
        borderRadius: BorderRadius.circular(ArchitectThemeTokens.radiusLg),
        border: Border.all(color: tokens.borderSubtle, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Icon(
                Icons.donut_large_rounded,
                size: 18,
                color: tokens.accent,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Progreso de apartados',
                  style: ArchitectThemeTokens.appleText(
                    color: tokens.textPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              Text(
                '${progress.done} de ${progress.total}',
                style: ArchitectThemeTokens.appleText(
                  color: tokens.textSecondary,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Text(
                '$percent%',
                style: ArchitectThemeTokens.appleDisplay(
                  color: tokens.textPrimary,
                  fontSize: 26,
                  fontWeight: FontWeight.w500,
                  letterSpacing: -0.4,
                ).copyWith(
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Semantics(
                  label:
                      'Progreso de apartados: $percent por ciento, ${progress.done} de ${progress.total}',
                  value: '$percent%',
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(999),
                    child: LinearProgressIndicator(
                      value: ratio,
                      minHeight: 5,
                      backgroundColor: tokens.borderSubtle,
                      valueColor: AlwaysStoppedAnimation<Color>(
                        isComplete ? tokens.statusPositive : tokens.accent,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Divider(height: 1, thickness: 1, color: tokens.borderSubtle),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _MetricColumn(
                  number: '${progress.withFiles}',
                  label: 'Con archivos',
                ),
              ),
              Container(width: 1, height: 32, color: tokens.borderSubtle),
              Expanded(
                child: _MetricColumn(
                  number: '${progress.needsAction}',
                  label: 'Por revisar',
                  highlightWarning: progress.needsAction > 0,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MetricColumn extends StatelessWidget {
  const _MetricColumn({
    required this.number,
    required this.label,
    this.highlightWarning = false,
  });

  final String number;
  final String label;
  final bool highlightWarning;

  @override
  Widget build(BuildContext context) {
    final tokens = ArchitectThemeTokens.of(context);

    return Column(
      children: [
        Text(
          number,
          style: ArchitectThemeTokens.appleDisplay(
            color: highlightWarning ? tokens.statusWarning : tokens.textPrimary,
            fontSize: 24,
            fontWeight: FontWeight.w500,
            letterSpacing: -0.3,
          ).copyWith(
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          textAlign: TextAlign.center,
          style: ArchitectThemeTokens.appleText(
            color: tokens.textSecondary,
            fontSize: 12,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}

class _LinkedAnalysisCard extends StatelessWidget {
  const _LinkedAnalysisCard({required this.stage});

  final HomeProjectStage stage;

  @override
  Widget build(BuildContext context) {
    final tokens = ArchitectThemeTokens.of(context);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: tokens.surfaceSecondary,
        borderRadius: BorderRadius.circular(ArchitectThemeTokens.radiusLg),
        border: Border.all(color: tokens.borderSubtle, width: 1),
      ),
      child: Row(
        children: [
          Icon(
            Icons.map_outlined,
            color: tokens.accent,
            size: 20,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  stage.analysis?.filename ?? 'Análisis #${stage.analysisId}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: ArchitectThemeTokens.appleText(
                    color: tokens.textPrimary,
                    fontWeight: FontWeight.w500,
                    fontSize: 15,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  stage.analysis?.createdAt != null
                      ? 'Vinculado ${formatRelativeTime(stage.analysis!.createdAt)}'
                      : 'Plano vinculado a esta etapa',
                  style: ArchitectThemeTokens.appleText(
                    color: tokens.textSecondary,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: tokens.statusPositive,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                'Activo',
                style: ArchitectThemeTokens.appleText(
                  color: tokens.statusPositive,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.section,
    required this.onTap,
  });

  final HomeProjectSection section;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = ArchitectThemeTokens.of(context);
    final textScale = MediaQuery.textScalerOf(context).scale(1.0);
    final filledDeliverables = section.slots
        .where(
          (s) => s.filled || section.documents.any((d) => d.slotKey == s.key),
        )
        .length;
    final isDone = section.status == 'completed';
    final isInProgress =
        section.status == 'in_progress' || section.status == 'active';
    final iconColor = isDone
        ? tokens.statusPositive
        : (isInProgress ? tokens.accent : tokens.textSecondary);

    return Semantics(
      button: true,
      label:
          '${section.title}, ${homeProjectStatusLabel(section.status)}${section.slots.isNotEmpty ? ', $filledDeliverables de ${section.slots.length} entregas' : ''}',
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
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Icon(
                        Icons.folder_outlined,
                        size: 20,
                        color: iconColor,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            section.title,
                            maxLines: textScale > 1.3 ? 3 : 2,
                            overflow: TextOverflow.ellipsis,
                            style: ArchitectThemeTokens.appleText(
                              color: tokens.textPrimary,
                              fontWeight: FontWeight.w500,
                              fontSize: 16,
                              height: 1.25,
                            ),
                          ),
                          if (section.description.isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Text(
                              section.description,
                              maxLines: textScale > 1.3 ? 3 : 2,
                              overflow: TextOverflow.ellipsis,
                              style: ArchitectThemeTokens.appleText(
                                color: tokens.textSecondary,
                                fontSize: 14,
                                fontWeight: FontWeight.w400,
                                height: 1.38,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Icon(
                        Icons.chevron_right_rounded,
                        size: 20,
                        color: tokens.textSecondary,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    _SemanticStatusIndicator(status: section.status),
                    const Spacer(),
                    if (section.commentsCount > 0) ...[
                      Icon(
                        Icons.chat_bubble_outline_rounded,
                        size: 13,
                        color: tokens.textSecondary,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '${section.commentsCount}',
                        style: ArchitectThemeTokens.appleText(
                          color: tokens.textSecondary,
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                      if (section.slots.isNotEmpty) const SizedBox(width: 12),
                    ],
                    if (section.slots.isNotEmpty)
                      Text(
                        '$filledDeliverables/${section.slots.length} entregas',
                        style: ArchitectThemeTokens.appleText(
                          color: tokens.textSecondary,
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      )
                    else if (section.hasDocuments)
                      Text(
                        '${section.documents.length} doc(s)',
                        style: ArchitectThemeTokens.appleText(
                          color: tokens.textSecondary,
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          fontFeatures: const [FontFeature.tabularFigures()],
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

class _SemanticStatusIndicator extends StatelessWidget {
  const _SemanticStatusIndicator({required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    final tokens = ArchitectThemeTokens.of(context);
    final label = homeProjectStatusLabel(status);

    final bool isCompleted = status == 'completed';
    final bool isInProgress = status == 'in_progress' || status == 'active';
    final bool isReview =
        status == 'needs_review' || status == 'in_review' || status == 'review';
    final bool isRejected = status == 'rejected' || status == 'error';

    final Color color = isCompleted
        ? tokens.statusPositive
        : (isInProgress
            ? tokens.accent
            : (isReview
                ? tokens.statusWarning
                : (isRejected ? tokens.statusError : tokens.textSecondary)));

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (isCompleted)
          Icon(Icons.check_circle_outline_rounded, size: 14, color: color)
        else if (isRejected)
          Icon(Icons.error_outline_rounded, size: 14, color: color)
        else
          Container(
            width: 6.5,
            height: 6.5,
            decoration: BoxDecoration(shape: BoxShape.circle, color: color),
          ),
        const SizedBox(width: 6),
        Text(
          label,
          style: ArchitectThemeTokens.appleText(
            color: color,
            fontSize: 12,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
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
    final tokens = ArchitectThemeTokens.of(context);
    final maxHeight = MediaQuery.sizeOf(context).height * 0.85;

    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: maxHeight),
      child: Padding(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 12,
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
                  color: tokens.borderStrong,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Icon(
                  Icons.auto_awesome_outlined,
                  size: 20,
                  color: tokens.accent,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Asistencia IA',
                        style: ArchitectThemeTokens.appleDisplay(
                          color: tokens.textPrimary,
                          fontSize: 18,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Normativas y requerimientos de esta etapa',
                        style: ArchitectThemeTokens.appleText(
                          color: tokens.textSecondary,
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
                    color: tokens.textSecondary,
                  ),
                  constraints: const BoxConstraints(
                    minWidth: 44,
                    minHeight: 44,
                  ),
                  onPressed: () {
                    FocusScope.of(context).unfocus();
                    Navigator.of(context).pop();
                  },
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
                      style: ArchitectThemeTokens.appleText(
                        fontSize: 14,
                        color: tokens.textPrimary,
                      ),
                      decoration: InputDecoration(
                        hintText:
                            'Ej. ¿Qué documentos se requieren para iniciar esta etapa?',
                        hintStyle: ArchitectThemeTokens.appleText(
                          fontSize: 13,
                          color: tokens.textSecondary,
                        ),
                        filled: true,
                        fillColor: tokens.drawerBackground,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(
                            ArchitectThemeTokens.radiusMd,
                          ),
                          borderSide: BorderSide(color: tokens.borderSubtle),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(
                            ArchitectThemeTokens.radiusMd,
                          ),
                          borderSide: BorderSide(color: tokens.borderSubtle),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(
                            ArchitectThemeTokens.radiusMd,
                          ),
                          borderSide: BorderSide(
                            color: tokens.accent,
                            width: 1.2,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      height: 48,
                      child: FilledButton(
                        onPressed: _loading ? null : _run,
                        style: FilledButton.styleFrom(
                          backgroundColor: tokens.primaryActionBg,
                          foregroundColor: tokens.primaryActionFg,
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(
                              ArchitectThemeTokens.radiusMd,
                            ),
                          ),
                        ),
                        child: _loading
                            ? SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: tokens.primaryActionFg,
                                ),
                              )
                            : Text(
                                'Consultar con la IA',
                                style: ArchitectThemeTokens.appleText(
                                  color: tokens.primaryActionFg,
                                  fontSize: 15,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                      ),
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: tokens.statusError.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(
                            ArchitectThemeTokens.radiusMd,
                          ),
                          border: Border.all(
                            color: tokens.statusError.withValues(alpha: 0.35),
                          ),
                        ),
                        child: Text(
                          _error!,
                          style: ArchitectThemeTokens.appleText(
                            color: tokens.statusError,
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                    if (_result != null) ...[
                      const SizedBox(height: 18),
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: tokens.drawerBackground,
                          borderRadius: BorderRadius.circular(
                            ArchitectThemeTokens.radiusLg,
                          ),
                          border: Border.all(color: tokens.borderSubtle),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(
                                  Icons.lightbulb_outline,
                                  size: 16,
                                  color: tokens.accent,
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  'Orientación técnica',
                                  style: ArchitectThemeTokens.appleText(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: tokens.textPrimary,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            Text(
                              _result!.guidance.isNotEmpty
                                  ? _result!.guidance
                                  : 'Sin orientación disponible.',
                              style: ArchitectThemeTokens.appleText(
                                height: 1.45,
                                fontSize: 14,
                                color: tokens.textSecondary,
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
                            color: tokens.accentSubtle,
                            borderRadius: BorderRadius.circular(
                              ArchitectThemeTokens.radiusMd,
                            ),
                            border: Border.all(
                              color: tokens.accent.withValues(alpha: 0.35),
                            ),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                Icons.layers_outlined,
                                size: 18,
                                color: tokens.accent,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'Se recomienda vincular o revisar un plano en esta etapa.',
                                  style: ArchitectThemeTokens.appleText(
                                    fontWeight: FontWeight.w500,
                                    fontSize: 12,
                                    color: tokens.accent,
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
                          style: ArchitectThemeTokens.appleText(
                            fontWeight: FontWeight.w600,
                            fontSize: 12,
                            color: tokens.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 6),
                        for (final source in _result!.localSources)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 4),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '• ',
                                  style: TextStyle(color: tokens.accent),
                                ),
                                Expanded(
                                  child: Text(
                                    source,
                                    style: ArchitectThemeTokens.appleText(
                                      fontSize: 12,
                                      color: tokens.textSecondary,
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
                          style: ArchitectThemeTokens.appleText(
                            fontWeight: FontWeight.w600,
                            fontSize: 12,
                            color: tokens.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 6),
                        for (final source in _result!.webSources)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 4),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '• ',
                                  style: TextStyle(color: tokens.accent),
                                ),
                                Expanded(
                                  child: Text(
                                    source,
                                    style: ArchitectThemeTokens.appleText(
                                      fontSize: 12,
                                      color: tokens.textSecondary,
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
